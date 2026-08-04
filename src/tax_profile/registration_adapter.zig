//! Lossless bridge from legacy profile components to `registration.zig`.
//!
//! `model.ProfileRevision` does not carry the persistence layer's separate
//! component `anchor_id`. Consequently this adapter requires explicit
//! identity bindings. It never guesses that a revision-row ID is a stable
//! anchor, and it never infers VAT, percentage-tax, withholding, special-law,
//! or treaty meaning from legacy free text.

const std = @import("std");
const field = @import("field.zig");
const model = @import("model.zig");
const registration = @import("registration.zig");

pub const Error = registration.Error || model.RevisionError || error{
    EmptyInput,
    WrongProfile,
    MissingActivityIdentity,
    MissingRegistrationFactIdentity,
    DuplicateActivityIdentity,
    DuplicateRegistrationFactIdentity,
    ExtraActivityIdentity,
    ExtraRegistrationFactIdentity,
    LegacyFactAnchorKindConflict,
};

/// Supplies identity discarded by the current domain projection. The target
/// revision ID must identify this one activity row, while `anchor_id` remains
/// stable across later revisions of the same activity.
pub const ActivityIdentity = struct {
    source_component_id: model.BusinessActivityId,
    anchor_id: registration.ActivityAnchorId,
    target_revision_id: registration.ComponentRevisionId,
    /// Null uses the owning profile revision's sequence. Callers may provide
    /// an explicit component-history sequence when importing another scheme.
    target_sequence: ?u32 = null,
};

/// Preserves the stable legacy registration-fact anchor even when the value
/// routes into an auxiliary history rather than an obligation history.
pub const RegistrationFactIdentity = struct {
    source_fact_id: model.RegistrationFactId,
    legacy_anchor_id: model.RegistrationFactId,
    target_revision_id: registration.ComponentRevisionId,
    target_sequence: ?u32 = null,
};

pub const RevisionInput = struct {
    revision: *const model.ProfileRevision,
    activity_identities: []const ActivityIdentity = &.{},
    registration_fact_identities: []const RegistrationFactIdentity = &.{},
    /// Existing activity values are copied exactly, but their review status
    /// remains an explicit caller decision. The safe default is unreviewed.
    activity_review: registration.ReviewState = .{
        .requires_review = .migrated_without_confirmation,
    },
};

pub const LegacyFactRoute = union(enum) {
    registration_obligation: registration.ObligationAnchorId,
    agent_designation: void,
    special_law_or_treaty_basis: void,
};

/// Audit mapping retained outside the normalized aggregate. GWA and special
/// basis are deliberately separate histories in the new domain, so this row
/// is where their old stable anchor remains recoverable.
pub const LegacyFactAnchorTrace = struct {
    profile_revision_id: model.RevisionId,
    source_fact_id: model.RegistrationFactId,
    legacy_anchor_id: model.RegistrationFactId,
    target_revision_id: registration.ComponentRevisionId,
    target_sequence: u32,
    route: LegacyFactRoute,
};

pub const ActivityAnchorTrace = struct {
    profile_revision_id: model.RevisionId,
    source_component_id: model.BusinessActivityId,
    anchor_id: registration.ActivityAnchorId,
    target_revision_id: registration.ComponentRevisionId,
    target_sequence: u32,
};

pub const OwnedComposition = struct {
    aggregate: registration.RegistrationAggregate,
    activity_anchor_traces: []const ActivityAnchorTrace,
    legacy_fact_anchor_traces: []const LegacyFactAnchorTrace,

    activity_anchor_storage: []registration.ActivityAnchor,
    obligation_anchor_storage: []registration.ObligationAnchor,
    business_activity_storage: []registration.BusinessActivity,
    obligation_storage: []registration.RegistrationObligation,
    agent_designation_storage: []registration.AgentDesignationRevision,
    special_basis_storage: []registration.SpecialLawOrTreatyBasisRevision,
    activity_trace_storage: []ActivityAnchorTrace,
    trace_storage: []LegacyFactAnchorTrace,

    pub fn deinit(
        self: *OwnedComposition,
        allocator: std.mem.Allocator,
    ) void {
        allocator.free(self.activity_anchor_storage);
        allocator.free(self.obligation_anchor_storage);
        allocator.free(self.business_activity_storage);
        allocator.free(self.obligation_storage);
        allocator.free(self.agent_designation_storage);
        allocator.free(self.special_basis_storage);
        allocator.free(self.activity_trace_storage);
        allocator.free(self.trace_storage);
        self.* = undefined;
    }

    pub fn summaryAsOf(
        self: *const OwnedComposition,
        on: model.Date,
    ) registration.Error!registration.RegistrationSummary {
        return self.aggregate.derivedSummary(on);
    }
};

const Counts = struct {
    activities: usize = 0,
    tax_types: usize = 0,
    agent_designations: usize = 0,
    special_bases: usize = 0,
    facts: usize = 0,
};

/// Composes any number of immutable profile revisions into one registration
/// history. Every component requires an exact identity binding, so missing or
/// surplus persistence data fails closed.
pub fn compose(
    allocator: std.mem.Allocator,
    inputs: []const RevisionInput,
) !OwnedComposition {
    if (inputs.len == 0) return error.EmptyInput;
    const profile_id = inputs[0].revision.profile_id;
    const counts = try validateInputs(inputs, profile_id);

    const activity_anchor_storage = try allocator.alloc(
        registration.ActivityAnchor,
        counts.activities,
    );
    errdefer allocator.free(activity_anchor_storage);
    const obligation_anchor_storage = try allocator.alloc(
        registration.ObligationAnchor,
        counts.tax_types,
    );
    errdefer allocator.free(obligation_anchor_storage);
    const activity_storage = try allocator.alloc(
        registration.BusinessActivity,
        counts.activities,
    );
    errdefer allocator.free(activity_storage);
    const obligation_storage = try allocator.alloc(
        registration.RegistrationObligation,
        counts.tax_types,
    );
    errdefer allocator.free(obligation_storage);
    const agent_storage = try allocator.alloc(
        registration.AgentDesignationRevision,
        counts.agent_designations,
    );
    errdefer allocator.free(agent_storage);
    const special_storage = try allocator.alloc(
        registration.SpecialLawOrTreatyBasisRevision,
        counts.special_bases,
    );
    errdefer allocator.free(special_storage);
    const activity_traces = try allocator.alloc(
        ActivityAnchorTrace,
        counts.activities,
    );
    errdefer allocator.free(activity_traces);
    const traces = try allocator.alloc(LegacyFactAnchorTrace, counts.facts);
    errdefer allocator.free(traces);

    var activity_anchor_count: usize = 0;
    var obligation_anchor_count: usize = 0;
    var activity_index: usize = 0;
    var obligation_index: usize = 0;
    var agent_index: usize = 0;
    var special_index: usize = 0;
    var activity_trace_index: usize = 0;
    var trace_index: usize = 0;

    for (inputs) |input| {
        const source = sourceFromProfileRevision(input.revision.source);
        for (input.revision.business_activities) |*activity| {
            const identity = findActivityIdentity(
                input.activity_identities,
                &activity.id,
            ).?;
            if (!containsActivityAnchor(
                activity_anchor_storage[0..activity_anchor_count],
                &identity.anchor_id,
            )) {
                activity_anchor_storage[activity_anchor_count] = .{
                    .owner_profile_id = profile_id,
                    .id = identity.anchor_id,
                };
                activity_anchor_count += 1;
            }
            const target_sequence = identity.target_sequence orelse
                input.revision.sequence;
            activity_storage[activity_index] = .{
                .anchor_id = identity.anchor_id,
                .metadata = metadata(
                    profile_id,
                    identity.target_revision_id,
                    target_sequence,
                    activity.effective,
                    source,
                    input.activity_review,
                ),
                .line_of_business = activity.line_of_business,
                .atc = activity.atc,
            };
            activity_index += 1;
            activity_traces[activity_trace_index] = .{
                .profile_revision_id = input.revision.id,
                .source_component_id = activity.id,
                .anchor_id = identity.anchor_id,
                .target_revision_id = identity.target_revision_id,
                .target_sequence = target_sequence,
            };
            activity_trace_index += 1;
        }

        for (input.revision.registration_facts) |*fact| {
            const identity = findFactIdentity(
                input.registration_fact_identities,
                &fact.id,
            ).?;
            const target_sequence = identity.target_sequence orelse
                input.revision.sequence;
            const fact_metadata = metadata(
                profile_id,
                identity.target_revision_id,
                target_sequence,
                fact.effective,
                source,
                ambiguousReview(input.revision.source),
            );
            const route: LegacyFactRoute = switch (fact.value) {
                .tax_type => |value| blk: {
                    const anchor_id = try registration.ObligationAnchorId.parse(
                        identity.legacy_anchor_id.asSlice(),
                    );
                    if (!containsObligationAnchor(
                        obligation_anchor_storage[0..obligation_anchor_count],
                        &anchor_id,
                    )) {
                        obligation_anchor_storage[obligation_anchor_count] = .{
                            .owner_profile_id = profile_id,
                            .id = anchor_id,
                        };
                        obligation_anchor_count += 1;
                    }
                    obligation_storage[obligation_index] = .{
                        .anchor_id = anchor_id,
                        .metadata = fact_metadata,
                        // Even text such as "VAT" is legacy free text here.
                        // A reviewed migration may later append a typed value.
                        .kind = .{ .unknown_requires_review = value },
                    };
                    obligation_index += 1;
                    break :blk .{ .registration_obligation = anchor_id };
                },
                .government_withholding_agent => |value| blk: {
                    agent_storage[agent_index] = .{
                        .metadata = fact_metadata,
                        .value = switch (value) {
                            .no => .not_designated,
                            .yes => .government_withholding_agent,
                        },
                    };
                    agent_index += 1;
                    break :blk .{ .agent_designation = {} };
                },
                .special_rate_basis => |value| blk: {
                    special_storage[special_index] = .{
                        .metadata = fact_metadata,
                        // The old text cannot prove special-law vs treaty.
                        .value = .{ .unknown_requires_review = value },
                    };
                    special_index += 1;
                    break :blk .{ .special_law_or_treaty_basis = {} };
                },
            };
            traces[trace_index] = .{
                .profile_revision_id = input.revision.id,
                .source_fact_id = fact.id,
                .legacy_anchor_id = identity.legacy_anchor_id,
                .target_revision_id = identity.target_revision_id,
                .target_sequence = target_sequence,
                .route = route,
            };
            trace_index += 1;
        }
    }

    const aggregate = registration.RegistrationAggregate{
        .profile_id = profile_id,
        .activity_anchors = activity_anchor_storage[0..activity_anchor_count],
        .obligation_anchors = obligation_anchor_storage[0..obligation_anchor_count],
        .business_activities = activity_storage,
        .obligations = obligation_storage,
        .agent_designations = agent_storage,
        .special_law_or_treaty_bases = special_storage,
    };
    try aggregate.validate();
    try validateLegacyFactAnchorRoutes(traces);

    return .{
        .aggregate = aggregate,
        .activity_anchor_traces = activity_traces,
        .legacy_fact_anchor_traces = traces,
        .activity_anchor_storage = activity_anchor_storage,
        .obligation_anchor_storage = obligation_anchor_storage,
        .business_activity_storage = activity_storage,
        .obligation_storage = obligation_storage,
        .agent_designation_storage = agent_storage,
        .special_basis_storage = special_storage,
        .activity_trace_storage = activity_traces,
        .trace_storage = traces,
    };
}

/// Convenience API for callers that only need the derived as-of view.
pub fn composeSummaryAsOf(
    allocator: std.mem.Allocator,
    inputs: []const RevisionInput,
    on: model.Date,
) !registration.RegistrationSummary {
    var composition = try compose(allocator, inputs);
    defer composition.deinit(allocator);
    return composition.summaryAsOf(on);
}

fn validateInputs(
    inputs: []const RevisionInput,
    profile_id: model.ProfileId,
) !Counts {
    var counts: Counts = .{};
    for (inputs) |input| {
        if (!input.revision.profile_id.eql(&profile_id)) {
            return error.WrongProfile;
        }
        try input.revision.validate();
        try validateActivityIdentities(input);
        try validateFactIdentities(input);
        counts.activities += input.revision.business_activities.len;
        counts.facts += input.revision.registration_facts.len;
        for (input.revision.registration_facts) |fact| {
            switch (fact.value) {
                .tax_type => counts.tax_types += 1,
                .government_withholding_agent => counts.agent_designations += 1,
                .special_rate_basis => counts.special_bases += 1,
            }
        }
    }
    return counts;
}

fn validateActivityIdentities(input: RevisionInput) Error!void {
    for (input.revision.business_activities) |*activity| {
        var matches: usize = 0;
        for (input.activity_identities) |*identity| {
            matches += @intFromBool(
                identity.source_component_id.eql(&activity.id),
            );
        }
        if (matches == 0) return error.MissingActivityIdentity;
        if (matches > 1) return error.DuplicateActivityIdentity;
    }
    for (input.activity_identities) |*identity| {
        var matches: usize = 0;
        for (input.revision.business_activities) |*activity| {
            matches += @intFromBool(
                identity.source_component_id.eql(&activity.id),
            );
        }
        if (matches == 0) return error.ExtraActivityIdentity;
        if ((identity.target_sequence orelse input.revision.sequence) == 0) {
            return error.InvalidSequence;
        }
    }
}

fn validateFactIdentities(input: RevisionInput) Error!void {
    for (input.revision.registration_facts) |*fact| {
        var matches: usize = 0;
        for (input.registration_fact_identities) |*identity| {
            matches += @intFromBool(identity.source_fact_id.eql(&fact.id));
        }
        if (matches == 0) return error.MissingRegistrationFactIdentity;
        if (matches > 1) return error.DuplicateRegistrationFactIdentity;
    }
    for (input.registration_fact_identities) |*identity| {
        var matches: usize = 0;
        for (input.revision.registration_facts) |*fact| {
            matches += @intFromBool(identity.source_fact_id.eql(&fact.id));
        }
        if (matches == 0) return error.ExtraRegistrationFactIdentity;
        if ((identity.target_sequence orelse input.revision.sequence) == 0) {
            return error.InvalidSequence;
        }
    }
}

fn findActivityIdentity(
    identities: []const ActivityIdentity,
    source_id: *const model.BusinessActivityId,
) ?*const ActivityIdentity {
    for (identities) |*identity| {
        if (identity.source_component_id.eql(source_id)) return identity;
    }
    return null;
}

fn findFactIdentity(
    identities: []const RegistrationFactIdentity,
    source_id: *const model.RegistrationFactId,
) ?*const RegistrationFactIdentity {
    for (identities) |*identity| {
        if (identity.source_fact_id.eql(source_id)) return identity;
    }
    return null;
}

fn sourceFromProfileRevision(
    source: model.RevisionSource,
) registration.RecordSource {
    return switch (source) {
        .manual_entry => .manual_entry,
        .imported => |value| .{ .imported = value },
        .migrated => |value| .{ .migrated = value },
    };
}

fn ambiguousReview(source: model.RevisionSource) registration.ReviewState {
    return .{ .requires_review = switch (source) {
        .manual_entry => .specificity_unknown,
        .imported => .evidence_missing,
        .migrated => .migrated_without_confirmation,
    } };
}

fn metadata(
    profile_id: model.ProfileId,
    revision_id: registration.ComponentRevisionId,
    sequence: u32,
    effective: model.EffectivePeriod,
    source: registration.RecordSource,
    review: registration.ReviewState,
) registration.RevisionMetadata {
    return .{
        .owner_profile_id = profile_id,
        .revision_id = revision_id,
        .sequence = sequence,
        .effective = effective,
        .source = source,
        .review = review,
    };
}

fn containsActivityAnchor(
    anchors: []const registration.ActivityAnchor,
    id: *const registration.ActivityAnchorId,
) bool {
    for (anchors) |*anchor| {
        if (anchor.id.eql(id)) return true;
    }
    return false;
}

fn containsObligationAnchor(
    anchors: []const registration.ObligationAnchor,
    id: *const registration.ObligationAnchorId,
) bool {
    for (anchors) |*anchor| {
        if (anchor.id.eql(id)) return true;
    }
    return false;
}

fn validateLegacyFactAnchorRoutes(
    traces: []const LegacyFactAnchorTrace,
) Error!void {
    for (traces, 0..) |*trace, index| {
        for (traces[index + 1 ..]) |*other| {
            if (!trace.legacy_anchor_id.eql(&other.legacy_anchor_id)) continue;
            if (std.meta.activeTag(trace.route) !=
                std.meta.activeTag(other.route))
            {
                return error.LegacyFactAnchorKindConflict;
            }
        }
    }
}

fn testProfileRevision(
    profile_id: model.ProfileId,
    revision_id: []const u8,
    sequence: u32,
    source: model.RevisionSource,
    activities: []const model.BusinessActivity,
    facts: []const model.RegistrationFact,
) !model.ProfileRevision {
    return .{
        .profile_id = profile_id,
        .id = try model.RevisionId.parse(revision_id),
        .sequence = sequence,
        .effective = try model.EffectivePeriod.init(
            try model.Date.parseIso("2026-01-01"),
            null,
        ),
        .source = source,
        .identity = .{
            .tin = try field.Tin.parse("123-456-789-000"),
            .rdo_code = try field.RdoCode.parse("040"),
        },
        .contact = .{
            .address = try field.RegisteredAddress.parse("Quezon City"),
        },
        .subject = .{ .individual = .{
            .name = try field.TaxpayerName.parse("Adapter Test"),
        } },
        .business_activities = activities,
        .registration_facts = facts,
    };
}

fn activityIdentity(
    source_id: model.BusinessActivityId,
    anchor: []const u8,
    revision: []const u8,
) !ActivityIdentity {
    return .{
        .source_component_id = source_id,
        .anchor_id = try registration.ActivityAnchorId.parse(anchor),
        .target_revision_id = try registration.ComponentRevisionId.parse(
            revision,
        ),
    };
}

fn factIdentity(
    source_id: model.RegistrationFactId,
    anchor: []const u8,
    revision: []const u8,
) !RegistrationFactIdentity {
    return .{
        .source_fact_id = source_id,
        .legacy_anchor_id = try model.RegistrationFactId.parse(anchor),
        .target_revision_id = try registration.ComponentRevisionId.parse(
            revision,
        ),
    };
}

test "activity values and stable anchors map exactly" {
    const profile_id = try model.ProfileId.parse("profile-one");
    const source_ref = try field.SourceReference.parse("COR import 2026");
    const activities = [_]model.BusinessActivity{.{
        .id = try model.BusinessActivityId.parse("legacy-row-1"),
        .line_of_business = try field.LineOfBusiness.parse("Software consulting"),
        .atc = try field.Atc.parse("IT010"),
        .effective = try model.EffectivePeriod.init(
            try model.Date.parseIso("2026-02-01"),
            try model.Date.parseIso("2026-08-31"),
        ),
    }};
    const revision = try testProfileRevision(
        profile_id,
        "profile-revision-1",
        7,
        .{ .imported = source_ref },
        &activities,
        &.{},
    );
    const identities = [_]ActivityIdentity{try activityIdentity(
        activities[0].id,
        "stable-activity-anchor",
        "target-activity-revision",
    )};
    var composition = try compose(std.testing.allocator, &.{.{
        .revision = &revision,
        .activity_identities = &identities,
        .activity_review = .{ .confirmed = .{
            .confirmed_at_unix_seconds = 100,
        } },
    }});
    defer composition.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), composition.aggregate.activity_anchors.len);
    const mapped = composition.aggregate.business_activities[0];
    try std.testing.expectEqualStrings(
        "stable-activity-anchor",
        mapped.anchor_id.asSlice(),
    );
    try std.testing.expectEqualStrings(
        "legacy-row-1",
        composition.activity_anchor_traces[0].source_component_id.asSlice(),
    );
    try std.testing.expectEqualStrings(
        "target-activity-revision",
        composition.activity_anchor_traces[0].target_revision_id.asSlice(),
    );
    try std.testing.expectEqualStrings(
        activities[0].line_of_business.asSlice(),
        mapped.line_of_business.asSlice(),
    );
    try std.testing.expect(mapped.atc.?.eql(&activities[0].atc.?));
    try std.testing.expect(mapped.metadata.effective.eql(activities[0].effective));
    try std.testing.expectEqual(@as(u32, 7), mapped.metadata.sequence);
    try std.testing.expect(mapped.metadata.review.isConfirmed());
    try std.testing.expect(mapped.metadata.source == .imported);
}

test "ambiguous legacy facts remain review-required and preserve anchor traces" {
    const profile_id = try model.ProfileId.parse("profile-one");
    const facts = [_]model.RegistrationFact{
        .{
            .id = try model.RegistrationFactId.parse("tax-row"),
            .effective = try model.EffectivePeriod.init(
                try model.Date.parseIso("2026-01-01"),
                null,
            ),
            .value = .{ .tax_type = try field.TaxType.parse("VAT") },
        },
        .{
            .id = try model.RegistrationFactId.parse("gwa-row"),
            .effective = try model.EffectivePeriod.init(
                try model.Date.parseIso("2026-01-01"),
                null,
            ),
            .value = .{ .government_withholding_agent = .yes },
        },
        .{
            .id = try model.RegistrationFactId.parse("basis-row"),
            .effective = try model.EffectivePeriod.init(
                try model.Date.parseIso("2026-01-01"),
                null,
            ),
            .value = .{ .special_rate_basis = try field.SpecialRateBasis.parse(
                "Treaty or special law text",
            ) },
        },
    };
    const migrated_ref = try field.SourceReference.parse("legacy profile");
    const revision = try testProfileRevision(
        profile_id,
        "profile-revision-1",
        1,
        .{ .migrated = migrated_ref },
        &.{},
        &facts,
    );
    const identities = [_]RegistrationFactIdentity{
        try factIdentity(facts[0].id, "tax-anchor", "target-tax-row"),
        try factIdentity(facts[1].id, "gwa-anchor", "target-gwa-row"),
        try factIdentity(facts[2].id, "basis-anchor", "target-basis-row"),
    };
    var composition = try compose(std.testing.allocator, &.{.{
        .revision = &revision,
        .registration_fact_identities = &identities,
    }});
    defer composition.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 3), composition.legacy_fact_anchor_traces.len);
    try std.testing.expectEqualStrings(
        "tax-anchor",
        composition.aggregate.obligation_anchors[0].id.asSlice(),
    );
    try std.testing.expect(
        composition.aggregate.obligations[0].kind == .unknown_requires_review,
    );
    try std.testing.expectEqualStrings(
        "VAT",
        composition.aggregate.obligations[0].kind.unknown_requires_review.asSlice(),
    );
    try std.testing.expect(
        !composition.aggregate.obligations[0].metadata.review.isConfirmed(),
    );
    try std.testing.expectEqual(
        registration.AgentDesignation.government_withholding_agent,
        composition.aggregate.agent_designations[0].value,
    );
    try std.testing.expect(
        !composition.aggregate.agent_designations[0].metadata.review.isConfirmed(),
    );
    try std.testing.expect(
        composition.aggregate.special_law_or_treaty_bases[0].value ==
            .unknown_requires_review,
    );
    try std.testing.expectEqualStrings(
        "gwa-anchor",
        composition.legacy_fact_anchor_traces[1].legacy_anchor_id.asSlice(),
    );

    const summary = try composition.summaryAsOf(
        try model.Date.parseIso("2026-06-30"),
    );
    try std.testing.expect(!summary.vat.confirmed_registered);
    try std.testing.expectEqual(
        @as(u32, 1),
        summary.unknown_obligation_proposal_count,
    );
}

test "stable activity anchor resolves exact revisions across profile history" {
    const profile_id = try model.ProfileId.parse("profile-one");
    const old_activity = [_]model.BusinessActivity{.{
        .id = try model.BusinessActivityId.parse("old-row"),
        .line_of_business = try field.LineOfBusiness.parse("Old consulting"),
        .effective = try model.EffectivePeriod.init(
            try model.Date.parseIso("2026-01-01"),
            try model.Date.parseIso("2026-06-30"),
        ),
    }};
    const new_activity = [_]model.BusinessActivity{.{
        .id = try model.BusinessActivityId.parse("new-row"),
        .line_of_business = try field.LineOfBusiness.parse("New consulting"),
        .effective = try model.EffectivePeriod.init(
            try model.Date.parseIso("2026-07-01"),
            null,
        ),
    }};
    const old_revision = try testProfileRevision(
        profile_id,
        "profile-old",
        1,
        .manual_entry,
        &old_activity,
        &.{},
    );
    const new_revision = try testProfileRevision(
        profile_id,
        "profile-new",
        2,
        .manual_entry,
        &new_activity,
        &.{},
    );
    const old_identity = [_]ActivityIdentity{try activityIdentity(
        old_activity[0].id,
        "stable-anchor",
        "target-old",
    )};
    const new_identity = [_]ActivityIdentity{try activityIdentity(
        new_activity[0].id,
        "stable-anchor",
        "target-new",
    )};
    const confirmed_review: registration.ReviewState = .{ .confirmed = .{
        .confirmed_at_unix_seconds = 1,
    } };
    var composition = try compose(std.testing.allocator, &.{
        .{
            .revision = &old_revision,
            .activity_identities = &old_identity,
            .activity_review = confirmed_review,
        },
        .{
            .revision = &new_revision,
            .activity_identities = &new_identity,
            .activity_review = confirmed_review,
        },
    });
    defer composition.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), composition.aggregate.activity_anchors.len);
    const old = try composition.aggregate.resolveActivity(
        composition.aggregate.activity_anchors[0].id,
        try model.Date.parseIso("2026-06-30"),
    );
    const new = try composition.aggregate.resolveActivity(
        composition.aggregate.activity_anchors[0].id,
        try model.Date.parseIso("2026-07-01"),
    );
    try std.testing.expectEqualStrings(
        "Old consulting",
        old.confirmed.?.line_of_business.asSlice(),
    );
    try std.testing.expectEqualStrings(
        "New consulting",
        new.confirmed.?.line_of_business.asSlice(),
    );
}

test "identity mappings are exact exhaustive and fail closed" {
    const profile_id = try model.ProfileId.parse("profile-one");
    const activity = [_]model.BusinessActivity{.{
        .id = try model.BusinessActivityId.parse("activity-row"),
        .line_of_business = try field.LineOfBusiness.parse("Consulting"),
        .effective = try model.EffectivePeriod.init(
            try model.Date.parseIso("2026-01-01"),
            null,
        ),
    }};
    const revision = try testProfileRevision(
        profile_id,
        "profile-revision",
        1,
        .manual_entry,
        &activity,
        &.{},
    );
    try std.testing.expectError(
        error.MissingActivityIdentity,
        compose(std.testing.allocator, &.{.{ .revision = &revision }}),
    );

    const identity = try activityIdentity(
        activity[0].id,
        "activity-anchor",
        "activity-target",
    );
    try std.testing.expectError(
        error.DuplicateActivityIdentity,
        compose(std.testing.allocator, &.{.{
            .revision = &revision,
            .activity_identities = &.{ identity, identity },
        }}),
    );

    const extra = try activityIdentity(
        try model.BusinessActivityId.parse("absent-row"),
        "absent-anchor",
        "absent-target",
    );
    try std.testing.expectError(
        error.ExtraActivityIdentity,
        compose(std.testing.allocator, &.{.{
            .revision = &revision,
            .activity_identities = &.{ identity, extra },
        }}),
    );
}

test "registration fact identity mappings also fail closed" {
    const profile_id = try model.ProfileId.parse("profile-one");
    const facts = [_]model.RegistrationFact{.{
        .id = try model.RegistrationFactId.parse("tax-row"),
        .effective = try model.EffectivePeriod.init(
            try model.Date.parseIso("2026-01-01"),
            null,
        ),
        .value = .{ .tax_type = try field.TaxType.parse("VAT") },
    }};
    const revision = try testProfileRevision(
        profile_id,
        "profile-revision",
        1,
        .manual_entry,
        &.{},
        &facts,
    );
    try std.testing.expectError(
        error.MissingRegistrationFactIdentity,
        compose(std.testing.allocator, &.{.{ .revision = &revision }}),
    );

    const identity = try factIdentity(
        facts[0].id,
        "tax-anchor",
        "tax-target",
    );
    try std.testing.expectError(
        error.DuplicateRegistrationFactIdentity,
        compose(std.testing.allocator, &.{.{
            .revision = &revision,
            .registration_fact_identities = &.{ identity, identity },
        }}),
    );

    const extra = try factIdentity(
        try model.RegistrationFactId.parse("absent-row"),
        "absent-anchor",
        "absent-target",
    );
    try std.testing.expectError(
        error.ExtraRegistrationFactIdentity,
        compose(std.testing.allocator, &.{.{
            .revision = &revision,
            .registration_fact_identities = &.{ identity, extra },
        }}),
    );
}

test "different profiles and reused legacy fact anchor kinds reject" {
    const profile_one = try model.ProfileId.parse("profile-one");
    const profile_two = try model.ProfileId.parse("profile-two");
    const fact_one = [_]model.RegistrationFact{.{
        .id = try model.RegistrationFactId.parse("tax-row"),
        .effective = try model.EffectivePeriod.init(
            try model.Date.parseIso("2026-01-01"),
            null,
        ),
        .value = .{ .tax_type = try field.TaxType.parse("VAT") },
    }};
    const fact_two = [_]model.RegistrationFact{.{
        .id = try model.RegistrationFactId.parse("gwa-row"),
        .effective = try model.EffectivePeriod.init(
            try model.Date.parseIso("2026-01-01"),
            null,
        ),
        .value = .{ .government_withholding_agent = .no },
    }};
    const revision_one = try testProfileRevision(
        profile_one,
        "revision-one",
        1,
        .manual_entry,
        &.{},
        &fact_one,
    );
    const revision_two = try testProfileRevision(
        profile_two,
        "revision-two",
        2,
        .manual_entry,
        &.{},
        &fact_two,
    );
    const identity_one = [_]RegistrationFactIdentity{try factIdentity(
        fact_one[0].id,
        "shared-anchor",
        "target-one",
    )};
    const identity_two = [_]RegistrationFactIdentity{try factIdentity(
        fact_two[0].id,
        "shared-anchor",
        "target-two",
    )};
    try std.testing.expectError(
        error.WrongProfile,
        compose(std.testing.allocator, &.{
            .{
                .revision = &revision_one,
                .registration_fact_identities = &identity_one,
            },
            .{
                .revision = &revision_two,
                .registration_fact_identities = &identity_two,
            },
        }),
    );

    const same_profile_revision_two = try testProfileRevision(
        profile_one,
        "revision-two",
        2,
        .manual_entry,
        &.{},
        &fact_two,
    );
    try std.testing.expectError(
        error.LegacyFactAnchorKindConflict,
        compose(std.testing.allocator, &.{
            .{
                .revision = &revision_one,
                .registration_fact_identities = &identity_one,
            },
            .{
                .revision = &same_profile_revision_two,
                .registration_fact_identities = &identity_two,
            },
        }),
    );
}

test "GWA no remains an unreviewed not-designated proposal" {
    const profile_id = try model.ProfileId.parse("profile-one");
    const facts = [_]model.RegistrationFact{.{
        .id = try model.RegistrationFactId.parse("gwa-row"),
        .effective = try model.EffectivePeriod.init(
            try model.Date.parseIso("2026-01-01"),
            null,
        ),
        .value = .{ .government_withholding_agent = .no },
    }};
    const revision = try testProfileRevision(
        profile_id,
        "revision-one",
        1,
        .manual_entry,
        &.{},
        &facts,
    );
    const identities = [_]RegistrationFactIdentity{try factIdentity(
        facts[0].id,
        "gwa-anchor",
        "gwa-target",
    )};
    var composition = try compose(std.testing.allocator, &.{.{
        .revision = &revision,
        .registration_fact_identities = &identities,
    }});
    defer composition.deinit(std.testing.allocator);
    const resolution = try composition.aggregate.resolveAgentDesignation(
        try model.Date.parseIso("2026-06-30"),
    );
    try std.testing.expect(resolution.confirmed == null);
    try std.testing.expectEqual(@as(u32, 1), resolution.proposal_count);
    try std.testing.expectEqual(
        registration.AgentDesignation.not_designated,
        resolution.latest_proposal.?.value,
    );
}

test "summary convenience API respects fact effectivity without inference" {
    const profile_id = try model.ProfileId.parse("profile-one");
    const facts = [_]model.RegistrationFact{.{
        .id = try model.RegistrationFactId.parse("tax-row"),
        .effective = try model.EffectivePeriod.init(
            try model.Date.parseIso("2026-04-01"),
            try model.Date.parseIso("2026-06-30"),
        ),
        .value = .{ .tax_type = try field.TaxType.parse("Percentage Tax") },
    }};
    const revision = try testProfileRevision(
        profile_id,
        "revision-one",
        1,
        .manual_entry,
        &.{},
        &facts,
    );
    const identities = [_]RegistrationFactIdentity{try factIdentity(
        facts[0].id,
        "tax-anchor",
        "tax-target",
    )};
    const inputs = [_]RevisionInput{.{
        .revision = &revision,
        .registration_fact_identities = &identities,
    }};
    const before = try composeSummaryAsOf(
        std.testing.allocator,
        &inputs,
        try model.Date.parseIso("2026-03-31"),
    );
    const during = try composeSummaryAsOf(
        std.testing.allocator,
        &inputs,
        try model.Date.parseIso("2026-06-30"),
    );
    try std.testing.expectEqual(
        @as(u32, 0),
        before.unknown_obligation_proposal_count,
    );
    try std.testing.expectEqual(
        @as(u32, 1),
        during.unknown_obligation_proposal_count,
    );
    try std.testing.expect(!during.percentage_tax.confirmed_registered);
}
