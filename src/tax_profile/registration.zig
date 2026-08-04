//! Repeatable, effective-dated taxpayer registration aggregate.
//!
//! This module owns taxpayer-registration truth only. It deliberately does
//! not contain form transactions, filing-period choices, amounts, schedules,
//! or other form-owned facts. Stable profile-scoped anchors let annual form
//! profiles bind to a business activity or registration obligation without
//! copying the current text into a second source of truth.
//!
//! Unreviewed imports, migrations, and manual proposals remain visible in the
//! aggregate, but resolvers never let them replace a confirmed decision.

const std = @import("std");
const date = @import("../domain/date.zig");
const field = @import("field.zig");
const model = @import("model.zig");

pub const Date = date.Date;
pub const EffectivePeriod = date.EffectivePeriod;
pub const ProfileId = model.ProfileId;

pub const Error = error{
    EmptyIdentifier,
    IdentifierTooLong,
    InvalidIdentifier,
    InvalidSequence,
    WrongOwner,
    DuplicateActivityAnchor,
    DuplicateObligationAnchor,
    MissingActivityAnchor,
    MissingObligationAnchor,
    DuplicateRevisionId,
    DuplicateRevisionSequence,
    ActivityConfirmedPeriodOverlap,
    ObligationConfirmedPeriodOverlap,
    FactConfirmedPeriodOverlap,
    ObligationAnchorKindConflict,
    DuplicateConfirmedObligation,
    VatPercentageConflict,
    UnknownValueMustRequireReview,
};

const IdentifierKind = enum {
    activity_anchor,
    obligation_anchor,
    component_revision,
};

fn Identifier(comptime kind: IdentifierKind, comptime capacity: usize) type {
    _ = kind;
    return struct {
        const Self = @This();

        bytes: [capacity]u8 = undefined,
        len: u8 = 0,

        pub fn parse(raw: []const u8) Error!Self {
            const value = std.mem.trim(u8, raw, " \t\r\n");
            if (value.len == 0) return error.EmptyIdentifier;
            if (value.len > capacity or value.len > std.math.maxInt(u8)) {
                return error.IdentifierTooLong;
            }
            for (value) |byte| {
                if (!std.ascii.isAlphanumeric(byte) and
                    byte != '-' and byte != '_' and byte != '.' and
                    byte != ':' and byte != '/')
                {
                    return error.InvalidIdentifier;
                }
            }
            var result: Self = .{};
            @memcpy(result.bytes[0..value.len], value);
            result.len = @intCast(value.len);
            return result;
        }

        pub fn asSlice(self: *const Self) []const u8 {
            return self.bytes[0..self.len];
        }

        pub fn eql(self: *const Self, other: *const Self) bool {
            return std.mem.eql(u8, self.asSlice(), other.asSlice());
        }
    };
}

/// Stable identity of one business activity inside one taxpayer profile.
pub const ActivityAnchorId = Identifier(.activity_anchor, 64);
/// Stable identity of one registration obligation inside one profile.
pub const ObligationAnchorId = Identifier(.obligation_anchor, 64);
/// Immutable row identity. Sequences are scoped to the component history.
pub const ComponentRevisionId = Identifier(.component_revision, 64);

pub const ActivityAnchor = struct {
    owner_profile_id: ProfileId,
    id: ActivityAnchorId,
};

pub const ObligationAnchor = struct {
    owner_profile_id: ProfileId,
    id: ObligationAnchorId,
};

pub const RecordSource = union(enum) {
    manual_entry,
    documented: field.SourceReference,
    imported: field.SourceReference,
    migrated: field.SourceReference,
};

pub const ReviewReason = enum {
    evidence_missing,
    specificity_unknown,
    migrated_without_confirmation,
    manual_proposal,
};

/// A proposal has no implicit precedence over a confirmed decision, even
/// when the proposal has the larger sequence number.
pub const ReviewState = union(enum) {
    requires_review: ReviewReason,
    confirmed: struct {
        confirmed_at_unix_seconds: i64,
    },

    pub fn isConfirmed(self: ReviewState) bool {
        return switch (self) {
            .requires_review => false,
            .confirmed => true,
        };
    }
};

pub const RevisionMetadata = struct {
    owner_profile_id: ProfileId,
    revision_id: ComponentRevisionId,
    sequence: u32,
    effective: EffectivePeriod,
    source: RecordSource,
    review: ReviewState,

    pub fn isEffective(self: *const RevisionMetadata, on: Date) bool {
        return self.effective.contains(on);
    }

    /// Registration & Forms is selected by tax year. A finite component is
    /// part of that workspace whenever its exact interval intersects any day
    /// of the year; it does not have to remain active on December 31.
    pub fn intersectsTaxYear(
        self: *const RevisionMetadata,
        tax_year: u16,
    ) date.Error!bool {
        return self.effective.overlaps(try taxYearPeriod(tax_year));
    }
};

pub fn taxYearPeriod(tax_year: u16) date.Error!EffectivePeriod {
    const first = try Date.init(tax_year, 1, 1);
    const last = try Date.init(tax_year, 12, 31);
    return EffectivePeriod.init(first, last) catch unreachable;
}

/// One version of a repeatable activity. `anchor_id` is stable while LOB,
/// ATC, source, review status, and effectivity may change by revision.
pub const BusinessActivity = struct {
    anchor_id: ActivityAnchorId,
    metadata: RevisionMetadata,
    line_of_business: field.LineOfBusiness,
    atc: ?field.Atc = null,
};

pub const WithholdingObligation = union(enum) {
    compensation: void,
    expanded: void,
    final: void,
    other: field.TaxType,
    unspecified_requires_review: field.TaxType,

    fn requiresSpecificityReview(self: *const WithholdingObligation) bool {
        return self.* == .unspecified_requires_review;
    }
};

/// Registration obligations are positive registrations, not a nullable bag
/// of duplicated tax-type booleans. Absence means "not recorded here", not a
/// guessed negative. Ambiguous legacy text remains an explicit proposal.
pub const RegistrationObligationKind = union(enum) {
    registered_income_tax: void,
    vat: void,
    percentage_tax: void,
    withholding: WithholdingObligation,
    unknown_requires_review: field.TaxType,

    fn requiresSpecificityReview(self: *const RegistrationObligationKind) bool {
        return switch (self.*) {
            .unknown_requires_review => true,
            .withholding => |*value| value.requiresSpecificityReview(),
            else => false,
        };
    }
};

pub const RegistrationObligation = struct {
    anchor_id: ObligationAnchorId,
    metadata: RevisionMetadata,
    kind: RegistrationObligationKind,
};

/// Withholding-agent designation is distinct from the taxpayer's registered
/// withholding return obligations.
pub const AgentDesignation = enum {
    not_designated,
    government_withholding_agent,
    top_withholding_agent,
    government_and_top_withholding_agent,
    unknown_requires_review,
};

/// EOPT size classification is recorded, never inferred from a form amount.
pub const EoptTier = enum {
    not_applicable,
    micro,
    small,
    medium,
    large,
    unknown_requires_review,
};

/// Overall registration activity status. Activity revision effectivity is
/// still authoritative for each individual business activity.
pub const RegistrationActivityStatus = enum {
    active,
    inactive,
    unknown_requires_review,
};

pub const SpecialLawOrTreatyBasis = union(enum) {
    special_law: field.SpecialRateBasis,
    treaty: field.SpecialRateBasis,
    unknown_requires_review: field.SpecialRateBasis,
};

fn EffectiveFact(comptime Value: type) type {
    return struct {
        metadata: RevisionMetadata,
        value: Value,
    };
}

pub const AgentDesignationRevision = EffectiveFact(AgentDesignation);
pub const EoptTierRevision = EffectiveFact(EoptTier);
pub const RegistrationActivityStatusRevision =
    EffectiveFact(RegistrationActivityStatus);
pub const SpecialLawOrTreatyBasisRevision =
    EffectiveFact(SpecialLawOrTreatyBasis);

fn ComponentResolution(comptime T: type) type {
    return struct {
        /// Confirmed filing-relevant truth, when one is active.
        confirmed: ?*const T = null,
        /// Highest-sequence active proposal, retained for review UI.
        latest_proposal: ?*const T = null,
        /// All active proposals remain in the aggregate; this count prevents
        /// callers from mistaking `latest_proposal` for the only proposal.
        proposal_count: u32 = 0,
    };
}

pub const ActivityResolution = ComponentResolution(BusinessActivity);
pub const ObligationResolution = ComponentResolution(RegistrationObligation);
pub const AgentDesignationResolution =
    ComponentResolution(AgentDesignationRevision);
pub const EoptTierResolution = ComponentResolution(EoptTierRevision);
pub const RegistrationActivityStatusResolution =
    ComponentResolution(RegistrationActivityStatusRevision);
pub const SpecialLawOrTreatyBasisResolution =
    ComponentResolution(SpecialLawOrTreatyBasisRevision);

pub const DerivedRegistration = struct {
    confirmed_registered: bool = false,
    unreviewed_proposal_count: u32 = 0,
};

pub const ConfirmedWithholdingKind = enum {
    compensation,
    expanded,
    final,
};

pub const WithholdingSummary = struct {
    confirmed_kinds: std.EnumSet(ConfirmedWithholdingKind) = .{},
    confirmed_other_count: u32 = 0,
    unreviewed_proposal_count: u32 = 0,
    unspecified_proposal_count: u32 = 0,
};

/// Derived on demand from obligations. These values are never persisted as a
/// second registration truth.
pub const RegistrationSummary = struct {
    income_tax: DerivedRegistration = .{},
    vat: DerivedRegistration = .{},
    percentage_tax: DerivedRegistration = .{},
    withholding: WithholdingSummary = .{},
    unknown_obligation_proposal_count: u32 = 0,
};

pub const RegistrationAggregate = struct {
    profile_id: ProfileId,
    activity_anchors: []const ActivityAnchor = &.{},
    obligation_anchors: []const ObligationAnchor = &.{},
    business_activities: []const BusinessActivity = &.{},
    obligations: []const RegistrationObligation = &.{},
    agent_designations: []const AgentDesignationRevision = &.{},
    eopt_tiers: []const EoptTierRevision = &.{},
    registration_activity_statuses: []const RegistrationActivityStatusRevision = &.{},
    special_law_or_treaty_bases: []const SpecialLawOrTreatyBasisRevision = &.{},

    pub fn validate(self: *const RegistrationAggregate) Error!void {
        try self.validateAnchors();
        try self.validateGlobalRevisionIds();
        try self.validateActivities();
        try self.validateObligations();
        try validateEffectiveFacts(
            self.profile_id,
            self.agent_designations,
            agentDesignationRequiresReview,
        );
        try validateEffectiveFacts(
            self.profile_id,
            self.eopt_tiers,
            eoptTierRequiresReview,
        );
        try validateEffectiveFacts(
            self.profile_id,
            self.registration_activity_statuses,
            registrationStatusRequiresReview,
        );
        try validateEffectiveFacts(
            self.profile_id,
            self.special_law_or_treaty_bases,
            specialBasisRequiresReview,
        );
    }

    fn validateAnchors(self: *const RegistrationAggregate) Error!void {
        for (self.activity_anchors, 0..) |*anchor, index| {
            if (!anchor.owner_profile_id.eql(&self.profile_id)) {
                return error.WrongOwner;
            }
            for (self.activity_anchors[index + 1 ..]) |*other| {
                if (anchor.id.eql(&other.id)) {
                    return error.DuplicateActivityAnchor;
                }
            }
        }
        for (self.obligation_anchors, 0..) |*anchor, index| {
            if (!anchor.owner_profile_id.eql(&self.profile_id)) {
                return error.WrongOwner;
            }
            for (self.obligation_anchors[index + 1 ..]) |*other| {
                if (anchor.id.eql(&other.id)) {
                    return error.DuplicateObligationAnchor;
                }
            }
        }
    }

    fn validateActivities(self: *const RegistrationAggregate) Error!void {
        for (self.business_activities, 0..) |*activity, index| {
            try validateMetadataOwner(&activity.metadata, &self.profile_id);
            if (!self.hasActivityAnchor(&activity.anchor_id)) {
                return error.MissingActivityAnchor;
            }
            for (self.business_activities[index + 1 ..]) |*other| {
                if (!activity.anchor_id.eql(&other.anchor_id)) continue;
                if (activity.metadata.sequence == other.metadata.sequence) {
                    return error.DuplicateRevisionSequence;
                }
                if (activity.metadata.review.isConfirmed() and
                    other.metadata.review.isConfirmed() and
                    activity.metadata.effective.overlaps(
                        other.metadata.effective,
                    ))
                {
                    return error.ActivityConfirmedPeriodOverlap;
                }
            }
        }
    }

    fn validateObligations(self: *const RegistrationAggregate) Error!void {
        for (self.obligations, 0..) |*obligation, index| {
            try validateMetadataOwner(&obligation.metadata, &self.profile_id);
            if (!self.hasObligationAnchor(&obligation.anchor_id)) {
                return error.MissingObligationAnchor;
            }
            if (obligation.kind.requiresSpecificityReview() and
                obligation.metadata.review.isConfirmed())
            {
                return error.UnknownValueMustRequireReview;
            }

            for (self.obligations[index + 1 ..]) |*other| {
                if (obligation.anchor_id.eql(&other.anchor_id)) {
                    if (obligation.metadata.sequence == other.metadata.sequence) {
                        return error.DuplicateRevisionSequence;
                    }
                    if (!obligationKindsCompatible(
                        &obligation.kind,
                        &other.kind,
                    )) return error.ObligationAnchorKindConflict;
                    if (obligation.metadata.review.isConfirmed() and
                        other.metadata.review.isConfirmed() and
                        obligation.metadata.effective.overlaps(
                            other.metadata.effective,
                        ))
                    {
                        return error.ObligationConfirmedPeriodOverlap;
                    }
                }

                if (!obligation.metadata.review.isConfirmed() or
                    !other.metadata.review.isConfirmed() or
                    !obligation.metadata.effective.overlaps(
                        other.metadata.effective,
                    )) continue;

                if (isVat(&obligation.kind) and
                    isPercentageTax(&other.kind) or
                    isPercentageTax(&obligation.kind) and
                        isVat(&other.kind))
                {
                    return error.VatPercentageConflict;
                }
                if (obligationKindsEqual(&obligation.kind, &other.kind)) {
                    return error.DuplicateConfirmedObligation;
                }
            }
        }
    }

    pub fn resolveActivity(
        self: *const RegistrationAggregate,
        anchor_id: ActivityAnchorId,
        on: Date,
    ) Error!ActivityResolution {
        try self.validate();
        if (!self.hasActivityAnchor(&anchor_id)) {
            return error.MissingActivityAnchor;
        }
        var result: ActivityResolution = .{};
        for (self.business_activities) |*activity| {
            if (!activity.anchor_id.eql(&anchor_id) or
                !activity.metadata.isEffective(on)) continue;
            updateResolution(BusinessActivity, &result, activity);
        }
        return result;
    }

    pub fn resolveObligation(
        self: *const RegistrationAggregate,
        anchor_id: ObligationAnchorId,
        on: Date,
    ) Error!ObligationResolution {
        try self.validate();
        if (!self.hasObligationAnchor(&anchor_id)) {
            return error.MissingObligationAnchor;
        }
        var result: ObligationResolution = .{};
        for (self.obligations) |*obligation| {
            if (!obligation.anchor_id.eql(&anchor_id) or
                !obligation.metadata.isEffective(on)) continue;
            updateResolution(RegistrationObligation, &result, obligation);
        }
        return result;
    }

    pub fn resolveAgentDesignation(
        self: *const RegistrationAggregate,
        on: Date,
    ) Error!AgentDesignationResolution {
        try self.validate();
        return resolveEffectiveFacts(AgentDesignationRevision, self.agent_designations, on);
    }

    pub fn resolveEoptTier(
        self: *const RegistrationAggregate,
        on: Date,
    ) Error!EoptTierResolution {
        try self.validate();
        return resolveEffectiveFacts(EoptTierRevision, self.eopt_tiers, on);
    }

    pub fn resolveRegistrationActivityStatus(
        self: *const RegistrationAggregate,
        on: Date,
    ) Error!RegistrationActivityStatusResolution {
        try self.validate();
        return resolveEffectiveFacts(
            RegistrationActivityStatusRevision,
            self.registration_activity_statuses,
            on,
        );
    }

    pub fn resolveSpecialLawOrTreatyBasis(
        self: *const RegistrationAggregate,
        on: Date,
    ) Error!SpecialLawOrTreatyBasisResolution {
        try self.validate();
        return resolveEffectiveFacts(
            SpecialLawOrTreatyBasisRevision,
            self.special_law_or_treaty_bases,
            on,
        );
    }

    pub fn derivedSummary(
        self: *const RegistrationAggregate,
        on: Date,
    ) Error!RegistrationSummary {
        try self.validate();
        var result: RegistrationSummary = .{};
        for (self.obligations) |*obligation| {
            if (!obligation.metadata.isEffective(on)) continue;
            const is_confirmed = obligation.metadata.review.isConfirmed();
            switch (obligation.kind) {
                .registered_income_tax => if (is_confirmed) {
                    result.income_tax.confirmed_registered = true;
                } else {
                    result.income_tax.unreviewed_proposal_count += 1;
                },
                .vat => if (is_confirmed) {
                    result.vat.confirmed_registered = true;
                } else {
                    result.vat.unreviewed_proposal_count += 1;
                },
                .percentage_tax => if (is_confirmed) {
                    result.percentage_tax.confirmed_registered = true;
                } else {
                    result.percentage_tax.unreviewed_proposal_count += 1;
                },
                .withholding => |withholding| {
                    if (!is_confirmed) {
                        result.withholding.unreviewed_proposal_count += 1;
                        if (withholding == .unspecified_requires_review) {
                            result.withholding.unspecified_proposal_count += 1;
                        }
                        continue;
                    }
                    switch (withholding) {
                        .compensation => result.withholding.confirmed_kinds.insert(
                            .compensation,
                        ),
                        .expanded => result.withholding.confirmed_kinds.insert(
                            .expanded,
                        ),
                        .final => result.withholding.confirmed_kinds.insert(
                            .final,
                        ),
                        .other => result.withholding.confirmed_other_count += 1,
                        .unspecified_requires_review => unreachable,
                    }
                },
                .unknown_requires_review => {
                    result.unknown_obligation_proposal_count += 1;
                },
            }
        }
        return result;
    }

    fn hasActivityAnchor(
        self: *const RegistrationAggregate,
        id: *const ActivityAnchorId,
    ) bool {
        for (self.activity_anchors) |*anchor| {
            if (anchor.id.eql(id)) return true;
        }
        return false;
    }

    fn hasObligationAnchor(
        self: *const RegistrationAggregate,
        id: *const ObligationAnchorId,
    ) bool {
        for (self.obligation_anchors) |*anchor| {
            if (anchor.id.eql(id)) return true;
        }
        return false;
    }

    fn validateGlobalRevisionIds(
        self: *const RegistrationAggregate,
    ) Error!void {
        for (self.business_activities) |*item| {
            if (self.revisionIdOccurrenceCount(&item.metadata.revision_id) != 1) {
                return error.DuplicateRevisionId;
            }
        }
        for (self.obligations) |*item| {
            if (self.revisionIdOccurrenceCount(&item.metadata.revision_id) != 1) {
                return error.DuplicateRevisionId;
            }
        }
        inline for (.{
            self.agent_designations,
            self.eopt_tiers,
            self.registration_activity_statuses,
            self.special_law_or_treaty_bases,
        }) |items| {
            for (items) |*item| {
                if (self.revisionIdOccurrenceCount(
                    &item.metadata.revision_id,
                ) != 1) return error.DuplicateRevisionId;
            }
        }
    }

    fn revisionIdOccurrenceCount(
        self: *const RegistrationAggregate,
        id: *const ComponentRevisionId,
    ) usize {
        var count: usize = 0;
        for (self.business_activities) |*item| {
            count += @intFromBool(item.metadata.revision_id.eql(id));
        }
        for (self.obligations) |*item| {
            count += @intFromBool(item.metadata.revision_id.eql(id));
        }
        inline for (.{
            self.agent_designations,
            self.eopt_tiers,
            self.registration_activity_statuses,
            self.special_law_or_treaty_bases,
        }) |items| {
            for (items) |*item| {
                count += @intFromBool(item.metadata.revision_id.eql(id));
            }
        }
        return count;
    }
};

pub const Aggregate = RegistrationAggregate;

fn validateMetadataOwner(
    metadata: *const RevisionMetadata,
    profile_id: *const ProfileId,
) Error!void {
    if (!metadata.owner_profile_id.eql(profile_id)) return error.WrongOwner;
    if (metadata.sequence == 0) return error.InvalidSequence;
}

fn validateEffectiveFacts(
    profile_id: ProfileId,
    items: anytype,
    comptime valueRequiresReview: anytype,
) Error!void {
    for (items, 0..) |*item, index| {
        try validateMetadataOwner(&item.metadata, &profile_id);
        if (valueRequiresReview(&item.value) and
            item.metadata.review.isConfirmed())
        {
            return error.UnknownValueMustRequireReview;
        }
        for (items[index + 1 ..]) |*other| {
            if (item.metadata.sequence == other.metadata.sequence) {
                return error.DuplicateRevisionSequence;
            }
            if (item.metadata.review.isConfirmed() and
                other.metadata.review.isConfirmed() and
                item.metadata.effective.overlaps(other.metadata.effective))
            {
                return error.FactConfirmedPeriodOverlap;
            }
        }
    }
}

fn resolveEffectiveFacts(
    comptime T: type,
    items: []const T,
    on: Date,
) ComponentResolution(T) {
    var result: ComponentResolution(T) = .{};
    for (items) |*item| {
        if (!item.metadata.isEffective(on)) continue;
        updateResolution(T, &result, item);
    }
    return result;
}

fn updateResolution(
    comptime T: type,
    result: *ComponentResolution(T),
    item: *const T,
) void {
    if (item.metadata.review.isConfirmed()) {
        if (result.confirmed == null or
            item.metadata.sequence > result.confirmed.?.metadata.sequence)
        {
            result.confirmed = item;
        }
        return;
    }
    result.proposal_count += 1;
    if (result.latest_proposal == null or
        item.metadata.sequence > result.latest_proposal.?.metadata.sequence)
    {
        result.latest_proposal = item;
    }
}

const ObligationFamily = enum {
    unknown,
    income_tax,
    vat,
    percentage_tax,
    withholding,
};

fn obligationFamily(kind: *const RegistrationObligationKind) ObligationFamily {
    return switch (kind.*) {
        .registered_income_tax => .income_tax,
        .vat => .vat,
        .percentage_tax => .percentage_tax,
        .withholding => .withholding,
        .unknown_requires_review => .unknown,
    };
}

fn obligationKindsCompatible(
    left: *const RegistrationObligationKind,
    right: *const RegistrationObligationKind,
) bool {
    const left_family = obligationFamily(left);
    const right_family = obligationFamily(right);
    return left_family == .unknown or right_family == .unknown or
        left_family == right_family;
}

fn obligationKindsEqual(
    left: *const RegistrationObligationKind,
    right: *const RegistrationObligationKind,
) bool {
    if (std.meta.activeTag(left.*) != std.meta.activeTag(right.*)) return false;
    return switch (left.*) {
        .registered_income_tax, .vat, .percentage_tax => true,
        .unknown_requires_review => false,
        .withholding => |*left_value| switch (right.*) {
            .withholding => |*right_value| withholdingKindsEqual(
                left_value,
                right_value,
            ),
            else => unreachable,
        },
    };
}

fn withholdingKindsEqual(
    left: *const WithholdingObligation,
    right: *const WithholdingObligation,
) bool {
    if (std.meta.activeTag(left.*) != std.meta.activeTag(right.*)) return false;
    return switch (left.*) {
        .compensation, .expanded, .final => true,
        .other => |*left_text| switch (right.*) {
            .other => |*right_text| left_text.eql(right_text),
            else => unreachable,
        },
        .unspecified_requires_review => false,
    };
}

fn isVat(kind: *const RegistrationObligationKind) bool {
    return kind.* == .vat;
}

fn isPercentageTax(kind: *const RegistrationObligationKind) bool {
    return kind.* == .percentage_tax;
}

fn agentDesignationRequiresReview(value: *const AgentDesignation) bool {
    return value.* == .unknown_requires_review;
}

fn eoptTierRequiresReview(value: *const EoptTier) bool {
    return value.* == .unknown_requires_review;
}

fn registrationStatusRequiresReview(
    value: *const RegistrationActivityStatus,
) bool {
    return value.* == .unknown_requires_review;
}

fn specialBasisRequiresReview(value: *const SpecialLawOrTreatyBasis) bool {
    return value.* == .unknown_requires_review;
}

fn testProfile(raw: []const u8) !ProfileId {
    return ProfileId.parse(raw);
}

fn testMetadata(
    profile_id: ProfileId,
    revision_id: []const u8,
    sequence: u32,
    from: []const u8,
    until: ?[]const u8,
    source: RecordSource,
    review: ReviewState,
) !RevisionMetadata {
    return .{
        .owner_profile_id = profile_id,
        .revision_id = try ComponentRevisionId.parse(revision_id),
        .sequence = sequence,
        .effective = try EffectivePeriod.init(
            try Date.parseIso(from),
            if (until) |last| try Date.parseIso(last) else null,
        ),
        .source = source,
        .review = review,
    };
}

fn confirmed(at: i64) ReviewState {
    return .{ .confirmed = .{ .confirmed_at_unix_seconds = at } };
}

fn proposal(reason: ReviewReason) ReviewState {
    return .{ .requires_review = reason };
}

test "finite registration activity belongs to its selected tax year" {
    const profile_id = try testProfile("part-year-profile");
    const anchor_id = try ActivityAnchorId.parse("part-year-activity");
    const metadata = try testMetadata(
        profile_id,
        "part-year-activity-r1",
        1,
        "2026-01-01",
        "2026-06-30",
        .manual_entry,
        confirmed(1),
    );
    const activity: BusinessActivity = .{
        .anchor_id = anchor_id,
        .metadata = metadata,
        .line_of_business = try field.LineOfBusiness.parse(
            "Seasonal consulting",
        ),
        .atc = try field.Atc.parse("PT010"),
    };

    try std.testing.expect(!activity.metadata.isEffective(
        try Date.parseIso("2026-12-31"),
    ));
    try std.testing.expect(try activity.metadata.intersectsTaxYear(2026));
    try std.testing.expect(!(try activity.metadata.intersectsTaxYear(2027)));
    try std.testing.expectEqualStrings(
        "part-year-activity",
        activity.anchor_id.asSlice(),
    );
    try std.testing.expect(activity.metadata.effective.eql(
        try EffectivePeriod.init(
            try Date.parseIso("2026-01-01"),
            try Date.parseIso("2026-06-30"),
        ),
    ));
}

test "multiple activities and obligations validate and derive one truth" {
    const profile_id = try testProfile("profile-one");
    const activity_anchors = [_]ActivityAnchor{
        .{ .owner_profile_id = profile_id, .id = try ActivityAnchorId.parse("consulting") },
        .{ .owner_profile_id = profile_id, .id = try ActivityAnchorId.parse("retail") },
    };
    const obligation_anchors = [_]ObligationAnchor{
        .{ .owner_profile_id = profile_id, .id = try ObligationAnchorId.parse("income") },
        .{ .owner_profile_id = profile_id, .id = try ObligationAnchorId.parse("vat") },
        .{ .owner_profile_id = profile_id, .id = try ObligationAnchorId.parse("expanded") },
    };
    const activities = [_]BusinessActivity{
        .{
            .anchor_id = activity_anchors[0].id,
            .metadata = try testMetadata(profile_id, "activity-1", 1, "2026-01-01", null, .manual_entry, confirmed(1)),
            .line_of_business = try field.LineOfBusiness.parse("Software consulting"),
            .atc = try field.Atc.parse("IT010"),
        },
        .{
            .anchor_id = activity_anchors[1].id,
            .metadata = try testMetadata(profile_id, "activity-2", 1, "2026-02-01", null, .manual_entry, confirmed(2)),
            .line_of_business = try field.LineOfBusiness.parse("Retail trade"),
        },
    };
    const obligations = [_]RegistrationObligation{
        .{
            .anchor_id = obligation_anchors[0].id,
            .metadata = try testMetadata(profile_id, "obligation-1", 1, "2026-01-01", null, .manual_entry, confirmed(3)),
            .kind = .{ .registered_income_tax = {} },
        },
        .{
            .anchor_id = obligation_anchors[1].id,
            .metadata = try testMetadata(profile_id, "obligation-2", 1, "2026-01-01", null, .manual_entry, confirmed(4)),
            .kind = .{ .vat = {} },
        },
        .{
            .anchor_id = obligation_anchors[2].id,
            .metadata = try testMetadata(profile_id, "obligation-3", 1, "2026-01-01", null, .manual_entry, confirmed(5)),
            .kind = .{ .withholding = .{ .expanded = {} } },
        },
    };
    const aggregate = RegistrationAggregate{
        .profile_id = profile_id,
        .activity_anchors = &activity_anchors,
        .obligation_anchors = &obligation_anchors,
        .business_activities = &activities,
        .obligations = &obligations,
    };
    try aggregate.validate();
    const summary = try aggregate.derivedSummary(
        try Date.parseIso("2026-03-31"),
    );
    try std.testing.expect(summary.income_tax.confirmed_registered);
    try std.testing.expect(summary.vat.confirmed_registered);
    try std.testing.expect(!summary.percentage_tax.confirmed_registered);
    try std.testing.expect(
        summary.withholding.confirmed_kinds.contains(.expanded),
    );
}

test "same activity anchor revisions resolve by effectivity" {
    const profile_id = try testProfile("profile-one");
    const anchor = ActivityAnchor{
        .owner_profile_id = profile_id,
        .id = try ActivityAnchorId.parse("primary"),
    };
    const revisions = [_]BusinessActivity{
        .{
            .anchor_id = anchor.id,
            .metadata = try testMetadata(profile_id, "activity-old", 1, "2026-01-01", "2026-06-30", .manual_entry, confirmed(1)),
            .line_of_business = try field.LineOfBusiness.parse("Old activity"),
        },
        .{
            .anchor_id = anchor.id,
            .metadata = try testMetadata(profile_id, "activity-new", 2, "2026-07-01", null, .manual_entry, confirmed(2)),
            .line_of_business = try field.LineOfBusiness.parse("Updated activity"),
        },
    };
    const aggregate = RegistrationAggregate{
        .profile_id = profile_id,
        .activity_anchors = &.{anchor},
        .business_activities = &revisions,
    };
    const old = try aggregate.resolveActivity(
        anchor.id,
        try Date.parseIso("2026-06-30"),
    );
    const new = try aggregate.resolveActivity(
        anchor.id,
        try Date.parseIso("2026-07-01"),
    );
    try std.testing.expectEqualStrings(
        "Old activity",
        old.confirmed.?.line_of_business.asSlice(),
    );
    try std.testing.expectEqualStrings(
        "Updated activity",
        new.confirmed.?.line_of_business.asSlice(),
    );
}

test "duplicate anchor declarations and wrong owners are rejected" {
    const profile_id = try testProfile("profile-one");
    const wrong_profile = try testProfile("profile-two");
    const same = try ActivityAnchorId.parse("duplicate");
    const duplicate = [_]ActivityAnchor{
        .{ .owner_profile_id = profile_id, .id = same },
        .{ .owner_profile_id = profile_id, .id = same },
    };
    var aggregate = RegistrationAggregate{
        .profile_id = profile_id,
        .activity_anchors = &duplicate,
    };
    try std.testing.expectError(error.DuplicateActivityAnchor, aggregate.validate());

    const same_obligation = try ObligationAnchorId.parse("duplicate");
    aggregate.activity_anchors = &.{};
    aggregate.obligation_anchors = &.{
        .{ .owner_profile_id = profile_id, .id = same_obligation },
        .{ .owner_profile_id = profile_id, .id = same_obligation },
    };
    try std.testing.expectError(
        error.DuplicateObligationAnchor,
        aggregate.validate(),
    );

    aggregate.obligation_anchors = &.{};
    aggregate.activity_anchors = &.{.{
        .owner_profile_id = wrong_profile,
        .id = try ActivityAnchorId.parse("wrong-owner"),
    }};
    try std.testing.expectError(error.WrongOwner, aggregate.validate());
}

test "confirmed VAT and percentage tax cannot overlap" {
    const profile_id = try testProfile("profile-one");
    const anchors = [_]ObligationAnchor{
        .{ .owner_profile_id = profile_id, .id = try ObligationAnchorId.parse("vat") },
        .{ .owner_profile_id = profile_id, .id = try ObligationAnchorId.parse("percentage") },
    };
    const obligations = [_]RegistrationObligation{
        .{
            .anchor_id = anchors[0].id,
            .metadata = try testMetadata(profile_id, "vat-1", 1, "2026-01-01", null, .manual_entry, confirmed(1)),
            .kind = .{ .vat = {} },
        },
        .{
            .anchor_id = anchors[1].id,
            .metadata = try testMetadata(profile_id, "percentage-1", 1, "2026-03-01", null, .manual_entry, confirmed(2)),
            .kind = .{ .percentage_tax = {} },
        },
    };
    const aggregate = RegistrationAggregate{
        .profile_id = profile_id,
        .obligation_anchors = &anchors,
        .obligations = &obligations,
    };
    try std.testing.expectError(error.VatPercentageConflict, aggregate.validate());
}

test "manual confirmed decision outranks later migrated proposal" {
    const profile_id = try testProfile("profile-one");
    const anchor = ObligationAnchor{
        .owner_profile_id = profile_id,
        .id = try ObligationAnchorId.parse("indirect-tax"),
    };
    const migration_ref = try field.SourceReference.parse("legacy tax type text");
    const obligations = [_]RegistrationObligation{
        .{
            .anchor_id = anchor.id,
            .metadata = try testMetadata(profile_id, "manual-vat", 2, "2026-01-01", null, .manual_entry, confirmed(10)),
            .kind = .{ .vat = {} },
        },
        .{
            .anchor_id = anchor.id,
            .metadata = try testMetadata(profile_id, "migrated-guess", 3, "2026-01-01", null, .{ .migrated = migration_ref }, proposal(.migrated_without_confirmation)),
            .kind = .{ .unknown_requires_review = try field.TaxType.parse("VAT or percentage tax") },
        },
    };
    const aggregate = RegistrationAggregate{
        .profile_id = profile_id,
        .obligation_anchors = &.{anchor},
        .obligations = &obligations,
    };
    const resolution = try aggregate.resolveObligation(
        anchor.id,
        try Date.parseIso("2026-06-30"),
    );
    try std.testing.expect(resolution.confirmed != null);
    try std.testing.expect(resolution.confirmed.?.kind == .vat);
    try std.testing.expectEqual(@as(u32, 1), resolution.proposal_count);
    try std.testing.expectEqual(
        @as(u32, 3),
        resolution.latest_proposal.?.metadata.sequence,
    );

    const summary = try aggregate.derivedSummary(
        try Date.parseIso("2026-06-30"),
    );
    try std.testing.expect(summary.vat.confirmed_registered);
    try std.testing.expect(!summary.percentage_tax.confirmed_registered);
    try std.testing.expectEqual(
        @as(u32, 1),
        summary.unknown_obligation_proposal_count,
    );

    const reversed = [_]RegistrationObligation{
        obligations[1],
        obligations[0],
    };
    const reversed_aggregate = RegistrationAggregate{
        .profile_id = profile_id,
        .obligation_anchors = &.{anchor},
        .obligations = &reversed,
    };
    const reversed_summary = try reversed_aggregate.derivedSummary(
        try Date.parseIso("2026-06-30"),
    );
    try std.testing.expectEqual(
        summary.vat.confirmed_registered,
        reversed_summary.vat.confirmed_registered,
    );
    try std.testing.expectEqual(
        summary.unknown_obligation_proposal_count,
        reversed_summary.unknown_obligation_proposal_count,
    );
}

test "unknown obligation and withholding specificity remain review-only" {
    const profile_id = try testProfile("profile-one");
    const anchors = [_]ObligationAnchor{
        .{ .owner_profile_id = profile_id, .id = try ObligationAnchorId.parse("unknown") },
        .{ .owner_profile_id = profile_id, .id = try ObligationAnchorId.parse("withholding") },
    };
    var obligations = [_]RegistrationObligation{
        .{
            .anchor_id = anchors[0].id,
            .metadata = try testMetadata(profile_id, "unknown-1", 1, "2026-01-01", null, .manual_entry, confirmed(1)),
            .kind = .{ .unknown_requires_review = try field.TaxType.parse("Unclear registration") },
        },
        .{
            .anchor_id = anchors[1].id,
            .metadata = try testMetadata(profile_id, "withholding-1", 1, "2026-01-01", null, .manual_entry, proposal(.specificity_unknown)),
            .kind = .{ .withholding = .{ .unspecified_requires_review = try field.TaxType.parse("Withholding tax") } },
        },
    };
    var aggregate = RegistrationAggregate{
        .profile_id = profile_id,
        .obligation_anchors = &anchors,
        .obligations = &obligations,
    };
    try std.testing.expectError(
        error.UnknownValueMustRequireReview,
        aggregate.validate(),
    );
    obligations[0].metadata.review = proposal(.specificity_unknown);
    try aggregate.validate();
    const summary = try aggregate.derivedSummary(
        try Date.parseIso("2026-01-31"),
    );
    try std.testing.expectEqual(
        @as(u32, 1),
        summary.withholding.unspecified_proposal_count,
    );
}

test "auxiliary registration facts resolve independently by date" {
    const profile_id = try testProfile("profile-one");
    const designations = [_]AgentDesignationRevision{
        .{
            .metadata = try testMetadata(profile_id, "agent-old", 1, "2026-01-01", "2026-03-31", .manual_entry, confirmed(1)),
            .value = .not_designated,
        },
        .{
            .metadata = try testMetadata(profile_id, "agent-new", 2, "2026-04-01", null, .manual_entry, confirmed(2)),
            .value = .government_withholding_agent,
        },
        .{
            .metadata = try testMetadata(profile_id, "agent-proposal", 3, "2026-04-01", null, .manual_entry, proposal(.manual_proposal)),
            .value = .top_withholding_agent,
        },
    };
    const tiers = [_]EoptTierRevision{.{
        .metadata = try testMetadata(profile_id, "tier-1", 1, "2026-01-01", null, .manual_entry, confirmed(3)),
        .value = .small,
    }};
    const statuses = [_]RegistrationActivityStatusRevision{.{
        .metadata = try testMetadata(profile_id, "status-1", 1, "2026-01-01", null, .manual_entry, confirmed(4)),
        .value = .active,
    }};
    const bases = [_]SpecialLawOrTreatyBasisRevision{.{
        .metadata = try testMetadata(profile_id, "basis-1", 1, "2026-01-01", null, .manual_entry, confirmed(5)),
        .value = .{ .treaty = try field.SpecialRateBasis.parse("PH treaty basis") },
    }};
    const aggregate = RegistrationAggregate{
        .profile_id = profile_id,
        .agent_designations = &designations,
        .eopt_tiers = &tiers,
        .registration_activity_statuses = &statuses,
        .special_law_or_treaty_bases = &bases,
    };
    const on = try Date.parseIso("2026-06-30");
    const designation = try aggregate.resolveAgentDesignation(on);
    try std.testing.expectEqual(
        AgentDesignation.government_withholding_agent,
        designation.confirmed.?.value,
    );
    try std.testing.expectEqual(@as(u32, 1), designation.proposal_count);
    try std.testing.expectEqual(EoptTier.small, (try aggregate.resolveEoptTier(on)).confirmed.?.value);
    try std.testing.expectEqual(
        RegistrationActivityStatus.active,
        (try aggregate.resolveRegistrationActivityStatus(on)).confirmed.?.value,
    );
    try std.testing.expect(
        (try aggregate.resolveSpecialLawOrTreatyBasis(on)).confirmed != null,
    );
}

test "missing anchors, duplicate sequences, and confirmed overlaps reject" {
    const profile_id = try testProfile("profile-one");
    const anchor = ActivityAnchor{
        .owner_profile_id = profile_id,
        .id = try ActivityAnchorId.parse("primary"),
    };
    var activities = [_]BusinessActivity{
        .{
            .anchor_id = anchor.id,
            .metadata = try testMetadata(profile_id, "activity-1", 1, "2026-01-01", null, .manual_entry, confirmed(1)),
            .line_of_business = try field.LineOfBusiness.parse("Consulting"),
        },
        .{
            .anchor_id = anchor.id,
            .metadata = try testMetadata(profile_id, "activity-2", 1, "2026-02-01", null, .manual_entry, confirmed(2)),
            .line_of_business = try field.LineOfBusiness.parse("Consulting two"),
        },
    };
    var aggregate = RegistrationAggregate{
        .profile_id = profile_id,
        .activity_anchors = &.{anchor},
        .business_activities = &activities,
    };
    try std.testing.expectError(
        error.DuplicateRevisionSequence,
        aggregate.validate(),
    );
    activities[1].metadata.sequence = 2;
    try std.testing.expectError(
        error.ActivityConfirmedPeriodOverlap,
        aggregate.validate(),
    );
    aggregate.activity_anchors = &.{};
    try std.testing.expectError(error.MissingActivityAnchor, aggregate.validate());
}

test "component revision ids are unique across the aggregate" {
    const profile_id = try testProfile("profile-one");
    const anchor = ActivityAnchor{
        .owner_profile_id = profile_id,
        .id = try ActivityAnchorId.parse("primary"),
    };
    const activity = BusinessActivity{
        .anchor_id = anchor.id,
        .metadata = try testMetadata(profile_id, "same-revision", 1, "2026-01-01", null, .manual_entry, confirmed(1)),
        .line_of_business = try field.LineOfBusiness.parse("Consulting"),
    };
    const designation = AgentDesignationRevision{
        .metadata = try testMetadata(profile_id, "same-revision", 1, "2026-01-01", null, .manual_entry, confirmed(2)),
        .value = .not_designated,
    };
    const aggregate = RegistrationAggregate{
        .profile_id = profile_id,
        .activity_anchors = &.{anchor},
        .business_activities = &.{activity},
        .agent_designations = &.{designation},
    };
    try std.testing.expectError(error.DuplicateRevisionId, aggregate.validate());
}

test "stable obligation anchor permits unknown proposal then known decision" {
    const profile_id = try testProfile("profile-one");
    const anchor = ObligationAnchor{
        .owner_profile_id = profile_id,
        .id = try ObligationAnchorId.parse("withholding-stable"),
    };
    const obligations = [_]RegistrationObligation{
        .{
            .anchor_id = anchor.id,
            .metadata = try testMetadata(profile_id, "withholding-unknown", 1, "2026-01-01", null, .manual_entry, proposal(.specificity_unknown)),
            .kind = .{ .withholding = .{ .unspecified_requires_review = try field.TaxType.parse("Withholding") } },
        },
        .{
            .anchor_id = anchor.id,
            .metadata = try testMetadata(profile_id, "withholding-confirmed", 2, "2026-01-01", null, .manual_entry, confirmed(2)),
            .kind = .{ .withholding = .{ .compensation = {} } },
        },
    };
    const aggregate = RegistrationAggregate{
        .profile_id = profile_id,
        .obligation_anchors = &.{anchor},
        .obligations = &obligations,
    };
    const resolved = try aggregate.resolveObligation(
        anchor.id,
        try Date.parseIso("2026-12-31"),
    );
    try std.testing.expect(resolved.confirmed != null);
    try std.testing.expectEqual(@as(u32, 1), resolved.proposal_count);
    const summary = try aggregate.derivedSummary(
        try Date.parseIso("2026-12-31"),
    );
    try std.testing.expect(
        summary.withholding.confirmed_kinds.contains(.compensation),
    );
    try std.testing.expectEqual(
        @as(u32, 1),
        summary.withholding.unspecified_proposal_count,
    );
}
