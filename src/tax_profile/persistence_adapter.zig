//! Lossless boundary between the validated tax-profile domain and SQLite rows.
//!
//! The database layer owns SQL concerns and allocated text. This adapter owns
//! semantic parsing and construction: reads must pass every field parser and
//! the typestate editor before a `model.ProfileRevision` is exposed.

const std = @import("std");
const editor = @import("editor.zig");
const field = @import("field.zig");
const model = @import("model.zig");
const persistence = @import("store.zig");
const forms_set_history = @import("forms_set_history.zig");
const registration = @import("registration.zig");
const registration_ui = @import("registration_ui.zig");
const taxpayer_year = @import("taxpayer_year_settings.zig");
const tax_form_profile = @import("tax_form_profile.zig");
const form_catalog = @import("../forms/generated/catalog.zig");

pub const SerializedValue = struct {
    value_type: []const u8,
    text: []const u8,
};

/// Allocated only for repeated SQL rows. All text slices borrow the immutable,
/// allocation-free domain revision supplied to `toWriteRows`.
pub const WriteRows = struct {
    revision: persistence.RevisionWrite,
    business_activities: []persistence.BusinessActivityWrite,
    registration_facts: []persistence.RegistrationFactWrite,

    pub fn components(self: *const WriteRows) persistence.RevisionComponentsWrite {
        return .{
            .business_activities = self.business_activities,
            .registration_facts = self.registration_facts,
        };
    }

    pub fn deinit(self: *WriteRows, allocator: std.mem.Allocator) void {
        allocator.free(self.business_activities);
        allocator.free(self.registration_facts);
        self.* = undefined;
    }
};

/// Owns the repeated arrays referenced by `revision`. Domain fields themselves
/// are fixed-storage values, so the source SQLite row can be released as soon
/// as this conversion returns.
pub const OwnedDomainRevision = struct {
    revision: model.ProfileRevision,
    business_activities: []model.BusinessActivity,
    registration_facts: []model.RegistrationFact,

    pub fn deinit(
        self: *OwnedDomainRevision,
        allocator: std.mem.Allocator,
    ) void {
        allocator.free(self.business_activities);
        allocator.free(self.registration_facts);
        self.* = undefined;
    }
};

pub const OwnedTaxpayerYearHistory = struct {
    history: taxpayer_year.History,
    revisions: []taxpayer_year.Revision,

    pub fn deinit(
        self: *OwnedTaxpayerYearHistory,
        allocator: std.mem.Allocator,
    ) void {
        for (self.revisions) |revision| allocator.free(revision.values);
        allocator.free(self.revisions);
        self.* = undefined;
    }
};

pub const OwnedTaxFormProfileHistory = struct {
    history: tax_form_profile.History,
    revisions: []tax_form_profile.Revision,

    pub fn deinit(
        self: *OwnedTaxFormProfileHistory,
        allocator: std.mem.Allocator,
    ) void {
        for (self.revisions) |revision| allocator.free(revision.values);
        allocator.free(self.revisions);
        self.* = undefined;
    }
};

/// Historical candidates spanning form-revision streams. These rows are not
/// validated against the current generated form definition; callers may use
/// them only as explicit compatibility-review sources.
pub const OwnedTaxFormProfileCandidates = struct {
    revisions: []tax_form_profile.Revision,

    pub fn deinit(
        self: *OwnedTaxFormProfileCandidates,
        allocator: std.mem.Allocator,
    ) void {
        for (self.revisions) |revision| allocator.free(revision.values);
        allocator.free(self.revisions);
        self.* = undefined;
    }
};

/// Owns both the SQLite text backing optional evidence references and the
/// allocation-free decision storage consumed by the pure history domain.
pub const OwnedFormSetDecisionHistory = struct {
    history: forms_set_history.History,
    decisions: []forms_set_history.Decision,
    rows: persistence.FormSetDecisionList,

    pub fn deinit(
        self: *OwnedFormSetDecisionHistory,
        allocator: std.mem.Allocator,
    ) void {
        allocator.free(self.decisions);
        self.rows.deinit(allocator);
        self.* = undefined;
    }
};

pub const OwnedFormSetDecisionResolution = struct {
    owned_history: OwnedFormSetDecisionHistory,
    resolution: forms_set_history.Resolution,

    pub fn deinit(
        self: *OwnedFormSetDecisionResolution,
        allocator: std.mem.Allocator,
    ) void {
        self.owned_history.deinit(allocator);
        self.* = undefined;
    }
};

/// Exact-date registration aggregate plus the independent optimistic stream
/// sequence the UI must carry into its next `SaveIntent`.
pub const OwnedRegistrationAggregate = struct {
    aggregate: registration.RegistrationAggregate,
    stream_sequence: u32,
    activity_anchors: []registration.ActivityAnchor,
    obligation_anchors: []registration.ObligationAnchor,
    business_activities: []registration.BusinessActivity,
    obligations: []registration.RegistrationObligation,
    agent_designations: []registration.AgentDesignationRevision,
    eopt_tiers: []registration.EoptTierRevision,
    activity_statuses: []registration.RegistrationActivityStatusRevision,
    special_bases: []registration.SpecialLawOrTreatyBasisRevision,

    pub fn deinit(
        self: *OwnedRegistrationAggregate,
        allocator: std.mem.Allocator,
    ) void {
        allocator.free(self.activity_anchors);
        allocator.free(self.obligation_anchors);
        allocator.free(self.business_activities);
        allocator.free(self.obligations);
        allocator.free(self.agent_designations);
        allocator.free(self.eopt_tiers);
        allocator.free(self.activity_statuses);
        allocator.free(self.special_bases);
        self.* = undefined;
    }
};

pub fn toWriteRows(
    allocator: std.mem.Allocator,
    revision: *const model.ProfileRevision,
    expected_current_sequence: ?u32,
) !WriteRows {
    try revision.validate();

    const activities = try allocator.alloc(
        persistence.BusinessActivityWrite,
        revision.business_activities.len,
    );
    errdefer allocator.free(activities);
    for (revision.business_activities, 0..) |*activity, index| {
        if (index > std.math.maxInt(u32)) return error.TooManyComponents;
        activities[index] = .{
            .id = activity.id.asSlice(),
            .line_of_business = activity.line_of_business.asSlice(),
            .atc = if (activity.atc) |*atc| atc.asSlice() else null,
            .effective = effectiveToWrite(activity.effective),
            .ordinal = @intCast(index),
        };
    }

    const facts = try allocator.alloc(
        persistence.RegistrationFactWrite,
        revision.registration_facts.len,
    );
    errdefer allocator.free(facts);
    for (revision.registration_facts, 0..) |*fact, index| {
        if (index > std.math.maxInt(u32)) return error.TooManyComponents;
        facts[index] = .{
            .id = fact.id.asSlice(),
            .effective = effectiveToWrite(fact.effective),
            .value = registrationFactToWrite(&fact.value),
            .ordinal = @intCast(index),
        };
    }

    return .{
        .revision = .{
            .id = revision.id.asSlice(),
            .profile_id = revision.profile_id.asSlice(),
            .sequence = revision.sequence,
            .expected_current_sequence = expected_current_sequence,
            .effective = effectiveToWrite(revision.effective),
            .source = sourceToWrite(&revision.source),
            .identity = .{
                .tin = revision.identity.tin.asDigits(),
                .rdo_code = revision.identity.rdo_code.asSlice(),
            },
            .contact = .{
                .registered_address = revision.contact.address.asSlice(),
                .zip_code = if (revision.contact.zip_code) |*zip|
                    zip.asSlice()
                else
                    null,
                .contact_number = if (revision.contact.contact_number) |*number|
                    number.asSlice()
                else
                    null,
                .email_address = if (revision.contact.email_address) |*email|
                    email.asSlice()
                else
                    null,
            },
            .subject = subjectToWrite(&revision.subject),
        },
        .business_activities = activities,
        .registration_facts = facts,
    };
}

pub fn createProfileWithRevision(
    store: *persistence.Store,
    allocator: std.mem.Allocator,
    status: persistence.ProfileStatus,
    revision: *const model.ProfileRevision,
) !void {
    var rows = try toWriteRows(allocator, revision, 0);
    defer rows.deinit(allocator);
    try store.createProfileWithRevision(
        .{
            .id = revision.profile_id.asSlice(),
            .status = status,
        },
        rows.revision,
        rows.components(),
    );
}

pub fn appendRevision(
    store: *persistence.Store,
    allocator: std.mem.Allocator,
    revision: *const model.ProfileRevision,
    expected_current_sequence: u32,
) !void {
    var rows = try toWriteRows(
        allocator,
        revision,
        expected_current_sequence,
    );
    defer rows.deinit(allocator);
    try store.appendRevision(rows.revision, rows.components());
}

/// Appends a revision carrying the durable key to the reviewed COR document
/// it was accepted from. The link is persistence provenance, not a profile
/// fact, so the domain model never sees it.
pub fn appendRevisionLinked(
    store: *persistence.Store,
    allocator: std.mem.Allocator,
    revision: *const model.ProfileRevision,
    expected_current_sequence: u32,
    cor_document_id: []const u8,
) !void {
    var rows = try toWriteRows(
        allocator,
        revision,
        expected_current_sequence,
    );
    defer rows.deinit(allocator);
    rows.revision.cor_document_id = cor_document_id;
    try store.appendRevision(rows.revision, rows.components());
}

pub fn appendFormSetDecision(
    store: *persistence.Store,
    expected_current_sequence: u32,
    decision: *const forms_set_history.DecisionInput,
) !void {
    var effective_from: persistence.DateText = undefined;
    _ = decision.effective.from.writeIso(&effective_from);
    var effective_until: ?persistence.DateText = null;
    if (decision.effective.until) |until| {
        effective_until = undefined;
        _ = until.writeIso(&effective_until.?);
    }
    try store.appendFormSetDecision(.{
        .id = decision.id.asSlice(),
        .profile_id = decision.stream.profile_id.asSlice(),
        .tax_year = decision.stream.tax_year,
        .form_code = decision.stream.form.code,
        .form_revision = decision.stream.form.revision,
        .expected_current_sequence = expected_current_sequence,
        .state = switch (decision.state) {
            .active => .active,
            .inactive => .inactive,
        },
        .scope = switch (decision.scope) {
            .whole_year => .whole_year,
            .interval => .interval,
        },
        .effective = .{
            .from = effective_from,
            .until = effective_until,
        },
        .source = switch (decision.source) {
            .manual => .manual,
            .imported => .imported,
            .cor => .cor,
        },
        .evidence_reference = decision.evidence_reference,
        .review_state = switch (decision.review) {
            .confirmed => .confirmed,
            .review_required => .review_required,
            .rejected => .rejected,
        },
        .supersedes_id = if (decision.supersedes) |*id|
            id.asSlice()
        else
            null,
    });
}

pub fn loadFormSetDecisionHistory(
    store: *persistence.Store,
    allocator: std.mem.Allocator,
    stream: forms_set_history.StreamIdentity,
) !OwnedFormSetDecisionHistory {
    var rows = try store.listFormSetDecisions(
        allocator,
        stream.profile_id.asSlice(),
        stream.tax_year,
        stream.form.code,
        stream.form.revision,
    );
    errdefer rows.deinit(allocator);
    const decisions = try allocator.alloc(
        forms_set_history.Decision,
        rows.items.len,
    );
    errdefer allocator.free(decisions);
    var history = forms_set_history.History.init(decisions);
    for (rows.items) |*row| {
        const row_stream: forms_set_history.StreamIdentity = .{
            .profile_id = try model.ProfileId.parse(row.profile_id),
            .tax_year = row.tax_year,
            .form = .{
                .code = row.form_code,
                .revision = row.form_revision,
            },
        };
        if (!row_stream.eql(&stream)) return persistence.Error.InvalidValue;
        const appended = try history.append(.{
            .id = try model.RevisionId.parse(row.id),
            .stream = row_stream,
            .state = switch (row.state) {
                .active => .active,
                .inactive => .inactive,
            },
            .scope = switch (row.scope) {
                .whole_year => .whole_year,
                .interval => .interval,
            },
            .effective = try parseEffective(
                row.effective_from,
                row.effective_until,
            ),
            .source = switch (row.source) {
                .manual => .manual,
                .imported => .imported,
                .cor => .cor,
            },
            .evidence_reference = row.evidence_reference,
            .review = switch (row.review_state) {
                .confirmed => .confirmed,
                .review_required => .review_required,
                .rejected => .rejected,
            },
            .supersedes = if (row.supersedes_id) |id|
                try model.RevisionId.parse(id)
            else
                null,
        });
        if (appended.sequence != row.sequence) {
            return persistence.Error.InvalidValue;
        }
    }
    return .{
        .history = history,
        .decisions = decisions,
        .rows = rows,
    };
}

pub fn resolveFormSetDecisionOn(
    store: *persistence.Store,
    allocator: std.mem.Allocator,
    stream: forms_set_history.StreamIdentity,
    effective_on: forms_set_history.Date,
) !OwnedFormSetDecisionResolution {
    var owned_history = try loadFormSetDecisionHistory(
        store,
        allocator,
        stream,
    );
    errdefer owned_history.deinit(allocator);
    return .{
        .resolution = try owned_history.history.resolve(
            stream,
            effective_on,
        ),
        .owned_history = owned_history,
    };
}

/// Loads the exact-date registration projection expected by
/// `registration_ui.State.open`, together with its optimistic stream head.
/// Confirmed retirements and superseded values are resolved by the store;
/// current review-required rows remain in the aggregate for inspection.
pub fn loadRegistrationAggregateOn(
    store: *persistence.Store,
    allocator: std.mem.Allocator,
    profile_id: model.ProfileId,
    effective_on: model.Date,
) !OwnedRegistrationAggregate {
    var date_buffer: persistence.DateText = undefined;
    const date_text = effective_on.writeIso(&date_buffer);
    var rows = try store.resolveRegistrationOn(
        allocator,
        profile_id.asSlice(),
        date_text,
    );
    defer rows.deinit(allocator);

    return registrationAggregateFromRows(
        allocator,
        profile_id,
        &rows,
        .already_resolved,
    );
}

/// Loads Registration & Forms for one selected tax year. Unlike an as-of-day
/// projection, a confirmed Jan-Jun component remains present when the screen
/// is opened later in the year. The latest confirmed revision for each stable
/// anchor that intersects the year is selected without changing its stored
/// effective interval.
pub fn loadRegistrationAggregateForYear(
    store: *persistence.Store,
    allocator: std.mem.Allocator,
    profile_id: model.ProfileId,
    tax_year: u16,
) !OwnedRegistrationAggregate {
    _ = try registrationYearPeriod(tax_year);
    var rows = try store.listRegistrationHistory(
        allocator,
        profile_id.asSlice(),
    );
    defer rows.deinit(allocator);

    return registrationAggregateFromRows(
        allocator,
        profile_id,
        &rows,
        .{ .tax_year = tax_year },
    );
}

const RegistrationProjectionScope = union(enum) {
    already_resolved,
    tax_year: u16,
};

fn registrationYearPeriod(tax_year: u16) !model.EffectivePeriod {
    return registration.taxYearPeriod(tax_year);
}

fn registrationMetadataInScope(
    metadata: *const persistence.OwnedRegistrationRevisionMetadata,
    scope: RegistrationProjectionScope,
) !bool {
    if (scope == .already_resolved) return true;
    if (metadata.record_state != .present) return false;
    const period = try parseEffective(
        metadata.effective_from,
        metadata.effective_until,
    );
    return period.overlaps(try registrationYearPeriod(scope.tax_year));
}

fn registrationReviewRevisionIsCurrent(rows: anytype, index: usize) bool {
    const id = rows[index].metadata.id;
    for (rows) |*later| {
        if (later.metadata.supersedes_id) |supersedes| {
            if (std.mem.eql(u8, supersedes, id)) return false;
        }
    }
    return true;
}

fn registrationActivityInScope(
    rows: []const persistence.OwnedRegistrationActivityRevision,
    index: usize,
    scope: RegistrationProjectionScope,
) !bool {
    const row = &rows[index];
    if (!(try registrationMetadataInScope(&row.metadata, scope))) return false;
    if (scope == .already_resolved) return true;
    if (row.metadata.review_state == .requires_review) {
        return registrationReviewRevisionIsCurrent(rows, index);
    }
    for (rows, 0..) |*other, other_index| {
        if (other_index == index or
            other.metadata.review_state != .confirmed or
            !std.mem.eql(u8, row.anchor_id, other.anchor_id) or
            !(try registrationMetadataInScope(&other.metadata, scope)))
        {
            continue;
        }
        if (other.metadata.component_sequence > row.metadata.component_sequence) {
            return false;
        }
    }
    return true;
}

fn registrationObligationInScope(
    rows: []const persistence.OwnedRegistrationObligationRevision,
    index: usize,
    scope: RegistrationProjectionScope,
) !bool {
    const row = &rows[index];
    if (!(try registrationMetadataInScope(&row.metadata, scope))) return false;
    if (scope == .already_resolved) return true;
    if (row.metadata.review_state == .requires_review) {
        return registrationReviewRevisionIsCurrent(rows, index);
    }
    for (rows, 0..) |*other, other_index| {
        if (other_index == index or
            other.metadata.review_state != .confirmed or
            !std.mem.eql(u8, row.anchor_id, other.anchor_id) or
            !(try registrationMetadataInScope(&other.metadata, scope)))
        {
            continue;
        }
        if (other.metadata.component_sequence > row.metadata.component_sequence) {
            return false;
        }
    }
    return true;
}

fn registrationFactInScope(
    rows: anytype,
    index: usize,
    scope: RegistrationProjectionScope,
) !bool {
    const row = &rows[index];
    if (!(try registrationMetadataInScope(&row.metadata, scope))) return false;
    if (scope == .already_resolved) return true;
    if (row.metadata.review_state == .requires_review) {
        return registrationReviewRevisionIsCurrent(rows, index);
    }
    for (rows, 0..) |*other, other_index| {
        if (other_index == index or
            other.metadata.review_state != .confirmed or
            !(try registrationMetadataInScope(&other.metadata, scope)))
        {
            continue;
        }
        if (other.metadata.component_sequence > row.metadata.component_sequence) {
            return false;
        }
    }
    return true;
}

fn registrationAggregateFromRows(
    allocator: std.mem.Allocator,
    profile_id: model.ProfileId,
    rows: *const persistence.RegistrationHistoryList,
    scope: RegistrationProjectionScope,
) !OwnedRegistrationAggregate {
    var activity_count: usize = 0;
    for (rows.activities, 0..) |_, index| {
        activity_count += @intFromBool(try registrationActivityInScope(
            rows.activities,
            index,
            scope,
        ));
    }
    var obligation_count: usize = 0;
    for (rows.obligations, 0..) |_, index| {
        obligation_count += @intFromBool(try registrationObligationInScope(
            rows.obligations,
            index,
            scope,
        ));
    }
    var agent_count: usize = 0;
    for (rows.agent_designations, 0..) |_, index| {
        agent_count += @intFromBool(try registrationFactInScope(
            rows.agent_designations,
            index,
            scope,
        ));
    }
    var eopt_count: usize = 0;
    for (rows.eopt_tiers, 0..) |_, index| {
        eopt_count += @intFromBool(try registrationFactInScope(
            rows.eopt_tiers,
            index,
            scope,
        ));
    }
    var status_count: usize = 0;
    for (rows.activity_statuses, 0..) |_, index| {
        status_count += @intFromBool(try registrationFactInScope(
            rows.activity_statuses,
            index,
            scope,
        ));
    }
    var basis_count: usize = 0;
    for (rows.special_bases, 0..) |_, index| {
        basis_count += @intFromBool(try registrationFactInScope(
            rows.special_bases,
            index,
            scope,
        ));
    }

    const activity_anchors = try allocator.alloc(
        registration.ActivityAnchor,
        rows.activity_anchors.len,
    );
    errdefer allocator.free(activity_anchors);
    const obligation_anchors = try allocator.alloc(
        registration.ObligationAnchor,
        rows.obligation_anchors.len,
    );
    errdefer allocator.free(obligation_anchors);
    const activities = try allocator.alloc(
        registration.BusinessActivity,
        activity_count,
    );
    errdefer allocator.free(activities);
    const obligations = try allocator.alloc(
        registration.RegistrationObligation,
        obligation_count,
    );
    errdefer allocator.free(obligations);
    const agents = try allocator.alloc(
        registration.AgentDesignationRevision,
        agent_count,
    );
    errdefer allocator.free(agents);
    const eopt = try allocator.alloc(
        registration.EoptTierRevision,
        eopt_count,
    );
    errdefer allocator.free(eopt);
    const statuses = try allocator.alloc(
        registration.RegistrationActivityStatusRevision,
        status_count,
    );
    errdefer allocator.free(statuses);
    const bases = try allocator.alloc(
        registration.SpecialLawOrTreatyBasisRevision,
        basis_count,
    );
    errdefer allocator.free(bases);

    for (rows.activity_anchors, 0..) |*row, index| {
        activity_anchors[index] = .{
            .owner_profile_id = try model.ProfileId.parse(row.profile_id),
            .id = try registration.ActivityAnchorId.parse(row.anchor_id),
        };
    }
    for (rows.obligation_anchors, 0..) |*row, index| {
        obligation_anchors[index] = .{
            .owner_profile_id = try model.ProfileId.parse(row.profile_id),
            .id = try registration.ObligationAnchorId.parse(row.anchor_id),
        };
    }
    var activity_index: usize = 0;
    for (rows.activities, 0..) |*row, source_index| {
        if (!(try registrationActivityInScope(
            rows.activities,
            source_index,
            scope,
        ))) continue;
        activities[activity_index] = .{
            .anchor_id = try registration.ActivityAnchorId.parse(
                row.anchor_id,
            ),
            .metadata = try registrationMetadataToDomain(&row.metadata),
            .line_of_business = try field.LineOfBusiness.parse(
                row.line_of_business,
            ),
            .atc = if (row.atc) |atc| try field.Atc.parse(atc) else null,
        };
        activity_index += 1;
    }
    var obligation_index: usize = 0;
    for (rows.obligations, 0..) |*row, source_index| {
        if (!(try registrationObligationInScope(
            rows.obligations,
            source_index,
            scope,
        ))) continue;
        obligations[obligation_index] = .{
            .anchor_id = try registration.ObligationAnchorId.parse(
                row.anchor_id,
            ),
            .metadata = try registrationMetadataToDomain(&row.metadata),
            .kind = try registrationObligationToDomain(
                row.kind,
                row.value_text,
            ),
        };
        obligation_index += 1;
    }
    var agent_index: usize = 0;
    for (rows.agent_designations, 0..) |*row, source_index| {
        if (!(try registrationFactInScope(
            rows.agent_designations,
            source_index,
            scope,
        ))) continue;
        agents[agent_index] = .{
            .metadata = try registrationMetadataToDomain(&row.metadata),
            .value = switch (row.value) {
                .not_designated => .not_designated,
                .government_withholding_agent => .government_withholding_agent,
                .top_withholding_agent => .top_withholding_agent,
                .government_and_top_withholding_agent => .government_and_top_withholding_agent,
                .unknown_requires_review => .unknown_requires_review,
            },
        };
        agent_index += 1;
    }
    var eopt_index: usize = 0;
    for (rows.eopt_tiers, 0..) |*row, source_index| {
        if (!(try registrationFactInScope(
            rows.eopt_tiers,
            source_index,
            scope,
        ))) continue;
        eopt[eopt_index] = .{
            .metadata = try registrationMetadataToDomain(&row.metadata),
            .value = switch (row.value) {
                .not_applicable => .not_applicable,
                .micro => .micro,
                .small => .small,
                .medium => .medium,
                .large => .large,
                .unknown_requires_review => .unknown_requires_review,
            },
        };
        eopt_index += 1;
    }
    var status_index: usize = 0;
    for (rows.activity_statuses, 0..) |*row, source_index| {
        if (!(try registrationFactInScope(
            rows.activity_statuses,
            source_index,
            scope,
        ))) continue;
        statuses[status_index] = .{
            .metadata = try registrationMetadataToDomain(&row.metadata),
            .value = switch (row.value) {
                .active => .active,
                .inactive => .inactive,
                .unknown_requires_review => .unknown_requires_review,
            },
        };
        status_index += 1;
    }
    var basis_index: usize = 0;
    for (rows.special_bases, 0..) |*row, source_index| {
        if (!(try registrationFactInScope(
            rows.special_bases,
            source_index,
            scope,
        ))) continue;
        const value = try field.SpecialRateBasis.parse(row.value_text);
        bases[basis_index] = .{
            .metadata = try registrationMetadataToDomain(&row.metadata),
            .value = switch (row.kind) {
                .special_law => .{ .special_law = value },
                .treaty => .{ .treaty = value },
                .unknown_requires_review => .{
                    .unknown_requires_review = value,
                },
            },
        };
        basis_index += 1;
    }

    const aggregate: registration.RegistrationAggregate = .{
        .profile_id = profile_id,
        .activity_anchors = activity_anchors,
        .obligation_anchors = obligation_anchors,
        .business_activities = activities,
        .obligations = obligations,
        .agent_designations = agents,
        .eopt_tiers = eopt,
        .registration_activity_statuses = statuses,
        .special_law_or_treaty_bases = bases,
    };
    try aggregate.validate();
    return .{
        .aggregate = aggregate,
        .stream_sequence = rows.stream_sequence,
        .activity_anchors = activity_anchors,
        .obligation_anchors = obligation_anchors,
        .business_activities = activities,
        .obligations = obligations,
        .agent_designations = agents,
        .eopt_tiers = eopt,
        .activity_statuses = statuses,
        .special_bases = bases,
    };
}

/// Persists one complete `registration_ui.SaveIntent` as one optimistic v16
/// stream commit. Only changed/new rows and explicit retirements are appended;
/// review-required proposals and auxiliary facts are never inferred away.
pub fn saveRegistrationIntent(
    store: *persistence.Store,
    allocator: std.mem.Allocator,
    intent: *const registration_ui.SaveIntent,
) !u32 {
    var current = if (intent.selected_tax_year) |tax_year|
        try loadRegistrationAggregateForYear(
            store,
            allocator,
            intent.profile_id,
            tax_year,
        )
    else
        try loadRegistrationAggregateOn(
            store,
            allocator,
            intent.profile_id,
            intent.viewed_on,
        );
    defer current.deinit(allocator);
    if (current.stream_sequence != intent.expected_sequence) {
        return persistence.Error.RegistrationStreamConflict;
    }
    try validateRetainedRegistrationReviews(
        &current.aggregate,
        intent.retained_review_rows,
    );

    var history = try store.listRegistrationHistory(
        allocator,
        intent.profile_id.asSlice(),
    );
    defer history.deinit(allocator);
    if (history.stream_sequence != intent.expected_sequence) {
        return persistence.Error.RegistrationStreamConflict;
    }

    const activity_capacity = current.business_activities.len +
        intent.business_activities.len;
    const obligation_capacity = current.obligations.len +
        intent.registration_obligations.len;
    const activity_ids = try allocator.alloc(
        persistence.OpaqueId,
        activity_capacity,
    );
    defer allocator.free(activity_ids);
    const obligation_ids = try allocator.alloc(
        persistence.OpaqueId,
        obligation_capacity,
    );
    defer allocator.free(obligation_ids);
    const activity_writes = try allocator.alloc(
        persistence.RegistrationActivityRevisionWrite,
        activity_capacity,
    );
    defer allocator.free(activity_writes);
    const obligation_writes = try allocator.alloc(
        persistence.RegistrationObligationRevisionWrite,
        obligation_capacity,
    );
    defer allocator.free(obligation_writes);
    var activity_count: usize = 0;
    var obligation_count: usize = 0;

    for (current.business_activities) |*existing| {
        if (!existing.metadata.review.isConfirmed()) continue;
        if (findDesiredActivity(intent.business_activities, &existing.anchor_id) != null) {
            continue;
        }
        activity_ids[activity_count] = try store.generateOpaqueId();
        activity_writes[activity_count] = .{
            .anchor_id = existing.anchor_id.asSlice(),
            .metadata = .{
                .id = &activity_ids[activity_count],
                .expected_component_sequence = maxActivitySequence(
                    history.activities,
                    &existing.anchor_id,
                ),
                .effective = if (intent.selected_tax_year != null)
                    effectiveToWrite(existing.metadata.effective)
                else
                    registrationRetirementPeriod(intent.viewed_on),
                .record_state = .retired,
                .source = .manual_entry,
                .review_state = .confirmed,
                .supersedes_id = existing.metadata.revision_id.asSlice(),
            },
            .line_of_business = existing.line_of_business.asSlice(),
            .atc = if (existing.atc) |*atc| atc.asSlice() else null,
        };
        activity_count += 1;
    }
    for (intent.business_activities) |*desired| {
        const existing = findConfirmedActivity(
            current.business_activities,
            &desired.anchor_id,
        );
        if (existing) |found| {
            if (registrationActivityEquals(found, desired)) continue;
        }
        activity_ids[activity_count] = try store.generateOpaqueId();
        activity_writes[activity_count] = .{
            .anchor_id = desired.anchor_id.asSlice(),
            .metadata = .{
                .id = &activity_ids[activity_count],
                .expected_component_sequence = maxActivitySequence(
                    history.activities,
                    &desired.anchor_id,
                ),
                .effective = effectiveToWrite(desired.effective),
                .source = .manual_entry,
                .review_state = .confirmed,
                .supersedes_id = if (existing) |found|
                    found.metadata.revision_id.asSlice()
                else
                    null,
            },
            .line_of_business = desired.line_of_business.asSlice(),
            .atc = if (desired.atc) |*atc| atc.asSlice() else null,
        };
        activity_count += 1;
    }

    for (current.obligations) |*existing| {
        if (!existing.metadata.review.isConfirmed()) continue;
        if (findDesiredObligation(
            intent.registration_obligations,
            &existing.anchor_id,
        ) != null) continue;
        obligation_ids[obligation_count] = try store.generateOpaqueId();
        const encoded = registrationObligationToWrite(&existing.kind);
        obligation_writes[obligation_count] = .{
            .anchor_id = existing.anchor_id.asSlice(),
            .metadata = .{
                .id = &obligation_ids[obligation_count],
                .expected_component_sequence = maxObligationSequence(
                    history.obligations,
                    &existing.anchor_id,
                ),
                .effective = if (intent.selected_tax_year != null)
                    effectiveToWrite(existing.metadata.effective)
                else
                    registrationRetirementPeriod(intent.viewed_on),
                .record_state = .retired,
                .source = .manual_entry,
                .review_state = .confirmed,
                .supersedes_id = existing.metadata.revision_id.asSlice(),
            },
            .kind = encoded.kind,
            .value_text = encoded.value_text,
        };
        obligation_count += 1;
    }
    for (intent.registration_obligations) |*desired| {
        const existing = findConfirmedObligation(
            current.obligations,
            &desired.anchor_id,
        );
        if (existing) |found| {
            if (registrationObligationRowEquals(found, desired)) continue;
        }
        obligation_ids[obligation_count] = try store.generateOpaqueId();
        const encoded = registrationObligationToWrite(&desired.kind);
        obligation_writes[obligation_count] = .{
            .anchor_id = desired.anchor_id.asSlice(),
            .metadata = .{
                .id = &obligation_ids[obligation_count],
                .expected_component_sequence = maxObligationSequence(
                    history.obligations,
                    &desired.anchor_id,
                ),
                .effective = effectiveToWrite(desired.effective),
                .source = .manual_entry,
                .review_state = .confirmed,
                .supersedes_id = if (existing) |found|
                    found.metadata.revision_id.asSlice()
                else
                    null,
            },
            .kind = encoded.kind,
            .value_text = encoded.value_text,
        };
        obligation_count += 1;
    }

    if (activity_count == 0 and obligation_count == 0) {
        return persistence.Error.RegistrationNoChanges;
    }
    return try store.appendRegistrationCommit(.{
        .profile_id = intent.profile_id.asSlice(),
        .expected_current_sequence = intent.expected_sequence,
        .activities = activity_writes[0..activity_count],
        .obligations = obligation_writes[0..obligation_count],
    });
}

pub fn appendTaxpayerYearRevision(
    store: *persistence.Store,
    allocator: std.mem.Allocator,
    expected_current_sequence: u32,
    revision: *const taxpayer_year.Revision,
) !void {
    try revision.validate();
    const values = try allocator.alloc(
        persistence.TaxpayerYearSettingValueWrite,
        revision.values.len,
    );
    defer allocator.free(values);
    for (revision.values, 0..) |value, index| {
        values[index] = taxpayerYearValueToWrite(value);
    }
    try store.appendTaxpayerYearRevision(.{
        .id = revision.id.asSlice(),
        .profile_id = revision.stream.profile_id.asSlice(),
        .tax_year = revision.stream.tax_year,
        .sequence = revision.sequence,
        .expected_current_sequence = expected_current_sequence,
        .effective = effectiveToWrite(revision.effective),
        .review_state = switch (revision.review_state) {
            .requires_review => .requires_review,
            .confirmed => .confirmed,
        },
        .confirmed_at_unix_seconds = revision.confirmed_at_unix_seconds,
        .source = taxpayerYearSourceToWrite(&revision.source),
        .values = values,
    });
}

pub fn loadTaxpayerYearHistory(
    store: *persistence.Store,
    allocator: std.mem.Allocator,
    stream: taxpayer_year.StreamKey,
) !OwnedTaxpayerYearHistory {
    try stream.validate();
    var rows = try store.listTaxpayerYearRevisions(
        allocator,
        stream.profile_id.asSlice(),
        stream.tax_year,
    );
    defer rows.deinit(allocator);

    const revisions = try allocator.alloc(
        taxpayer_year.Revision,
        rows.items.len,
    );
    var initialized: usize = 0;
    errdefer {
        for (revisions[0..initialized]) |revision| {
            allocator.free(revision.values);
        }
        allocator.free(revisions);
    }
    for (rows.items, 0..) |*row, index| {
        const values = try allocator.alloc(
            taxpayer_year.SettingValue,
            row.values.len,
        );
        errdefer allocator.free(values);
        for (row.values, 0..) |value, value_index| {
            values[value_index] = taxpayerYearValueToDomain(value);
        }
        revisions[index] = .{
            .id = try taxpayer_year.RevisionId.parse(row.id),
            .stream = .{
                .profile_id = try model.ProfileId.parse(row.profile_id),
                .tax_year = row.tax_year,
            },
            .sequence = row.sequence,
            .effective = try parseEffective(
                row.effective_from,
                row.effective_until,
            ),
            .review_state = switch (row.review_state) {
                .requires_review => .requires_review,
                .confirmed => .confirmed,
            },
            .confirmed_at_unix_seconds = row.confirmed_at_unix_seconds,
            .source = try taxpayerYearSourceToDomain(&row.source),
            .values = values,
        };
        initialized += 1;
    }
    const history: taxpayer_year.History = .{
        .stream = stream,
        .revisions = revisions,
    };
    try history.validate();
    return .{ .history = history, .revisions = revisions };
}

pub fn appendTaxFormProfileRevision(
    store: *persistence.Store,
    allocator: std.mem.Allocator,
    expected_current_sequence: u32,
    revision: *const tax_form_profile.Revision,
) !void {
    const form = form_catalog.findForm(
        revision.stream.form_code.asSlice(),
    ) orelse return tax_form_profile.Error.WrongForm;
    try revision.validate(form);
    const values = try allocator.alloc(
        persistence.TaxFormProfileSetupValueWrite,
        revision.values.len,
    );
    defer allocator.free(values);
    for (revision.values, 0..) |*value, index| {
        values[index] = taxFormProfileValueToWrite(value);
    }
    try store.appendTaxFormProfileRevision(.{
        .id = revision.id.asSlice(),
        .profile_id = revision.stream.profile_id.asSlice(),
        .tax_year = revision.stream.tax_year,
        .form_code = revision.stream.form_code.asSlice(),
        .form_revision = revision.stream.form_revision.asSlice(),
        .sequence = revision.sequence,
        .expected_current_sequence = expected_current_sequence,
        .effective = effectiveToWrite(revision.effective),
        .spec_revision = revision.spec_revision,
        .spec_hash = revision.spec_hash.asSlice(),
        .review_state = switch (revision.review_state) {
            .requires_review => .requires_review,
            .confirmed => .confirmed,
        },
        .confirmed_at_unix_seconds = revision.confirmed_at_unix,
        .source = taxFormProfileRevisionSourceToWrite(&revision.source),
        .values = values,
    });
}

pub fn loadTaxFormProfileHistory(
    store: *persistence.Store,
    allocator: std.mem.Allocator,
    stream: tax_form_profile.StreamKey,
) !OwnedTaxFormProfileHistory {
    var rows = try store.listTaxFormProfileRevisions(
        allocator,
        stream.profile_id.asSlice(),
        stream.tax_year,
        stream.form_code.asSlice(),
        stream.form_revision.asSlice(),
    );
    defer rows.deinit(allocator);
    const revisions = try taxFormProfileRevisionsFromRows(
        allocator,
        rows.items,
    );
    errdefer {
        for (revisions) |revision| allocator.free(revision.values);
        allocator.free(revisions);
    }
    const history: tax_form_profile.History = .{
        .stream = stream,
        .revisions = revisions,
    };
    const form = form_catalog.findForm(stream.form_code.asSlice()) orelse
        return tax_form_profile.Error.WrongForm;
    try history.validate(form);
    return .{ .history = history, .revisions = revisions };
}

pub fn loadTaxFormProfileCandidatesForForm(
    store: *persistence.Store,
    allocator: std.mem.Allocator,
    profile_id: model.ProfileId,
    tax_year: u16,
    form_code: tax_form_profile.FormCode,
) !OwnedTaxFormProfileCandidates {
    var rows = try store.listTaxFormProfileRevisionsForForm(
        allocator,
        profile_id.asSlice(),
        tax_year,
        form_code.asSlice(),
    );
    defer rows.deinit(allocator);
    return .{
        .revisions = try taxFormProfileRevisionsFromRows(
            allocator,
            rows.items,
        ),
    };
}

fn taxFormProfileRevisionsFromRows(
    allocator: std.mem.Allocator,
    rows: []persistence.OwnedTaxFormProfileRevision,
) ![]tax_form_profile.Revision {
    const revisions = try allocator.alloc(
        tax_form_profile.Revision,
        rows.len,
    );
    var initialized: usize = 0;
    errdefer {
        for (revisions[0..initialized]) |revision| {
            allocator.free(revision.values);
        }
        allocator.free(revisions);
    }
    for (rows, 0..) |*row, index| {
        const values = try allocator.alloc(
            tax_form_profile.SetupValue,
            row.values.len,
        );
        errdefer allocator.free(values);
        for (row.values, 0..) |*value, value_index| {
            values[value_index] = try taxFormProfileValueToDomain(value);
        }
        revisions[index] = .{
            .id = try tax_form_profile.RevisionId.parse(row.id),
            .stream = .{
                .profile_id = try model.ProfileId.parse(row.profile_id),
                .tax_year = row.tax_year,
                .form_code = try tax_form_profile.FormCode.parse(row.form_code),
                .form_revision = try tax_form_profile.FormRevision.parse(
                    row.form_revision,
                ),
            },
            .sequence = row.sequence,
            .effective = try parseEffective(
                row.effective_from,
                row.effective_until,
            ),
            .spec_revision = row.spec_revision,
            .spec_hash = try tax_form_profile.SpecHash.parse(row.spec_hash),
            .review_state = switch (row.review_state) {
                .requires_review => .requires_review,
                .confirmed => .confirmed,
            },
            .confirmed_at_unix = row.confirmed_at_unix_seconds,
            .source = try taxFormProfileRevisionSourceToDomain(&row.source),
            .values = values,
        };
        initialized += 1;
    }
    return revisions;
}

/// One reviewed COR decision as one store transaction: the linked revision
/// and the year's forms both land or neither does.
pub fn applyCorReview(
    store: *persistence.Store,
    allocator: std.mem.Allocator,
    revision: *const model.ProfileRevision,
    expected_current_sequence: u32,
    cor_document_id: []const u8,
    forms_tax_year: i32,
    forms: []const persistence.FormRegistrationWrite,
    forms_mode: persistence.FormSetApplyMode,
) !void {
    var rows = try toWriteRows(
        allocator,
        revision,
        expected_current_sequence,
    );
    defer rows.deinit(allocator);
    rows.revision.cor_document_id = cor_document_id;
    try store.applyCorReview(
        rows.revision,
        rows.components(),
        forms_tax_year,
        forms,
        forms_mode,
    );
}

pub fn toDomain(
    allocator: std.mem.Allocator,
    rows: *const persistence.OwnedProfileRevision,
) !OwnedDomainRevision {
    const activities = try allocator.alloc(
        model.BusinessActivity,
        rows.business_activities.len,
    );
    errdefer allocator.free(activities);
    for (rows.business_activities, 0..) |*activity, index| {
        activities[index] = .{
            .id = try model.BusinessActivityId.parse(activity.id),
            .line_of_business = try field.LineOfBusiness.parse(
                activity.line_of_business,
            ),
            .atc = if (activity.atc) |atc|
                try field.Atc.parse(atc)
            else
                null,
            .effective = try parseEffective(
                activity.effective_from,
                activity.effective_until,
            ),
        };
    }

    const facts = try allocator.alloc(
        model.RegistrationFact,
        rows.registration_facts.len,
    );
    errdefer allocator.free(facts);
    for (rows.registration_facts, 0..) |*fact, index| {
        facts[index] = .{
            .id = try model.RegistrationFactId.parse(fact.id),
            .effective = try parseEffective(
                fact.effective_from,
                fact.effective_until,
            ),
            .value = try registrationFactToDomain(&fact.value),
        };
    }

    const base: editor.Base = .{
        .profile_id = try model.ProfileId.parse(rows.profile_id),
        .revision_id = try model.RevisionId.parse(rows.id),
        .sequence = rows.sequence,
        .effective = try parseEffective(
            rows.effective_from,
            rows.effective_until,
        ),
        .source = try sourceToDomain(&rows.source),
        .identity = .{
            .tin = try field.Tin.parse(rows.tin),
            .rdo_code = try field.RdoCode.parse(rows.rdo_code),
        },
        .contact = .{
            // Required: malformed/incomplete legacy rows stop here.
            .address = try field.RegisteredAddress.parse(
                rows.contact.registered_address,
            ),
            .zip_code = if (rows.contact.zip_code) |zip|
                try field.ZipCode.parse(zip)
            else
                null,
            .contact_number = if (rows.contact.contact_number) |number|
                try field.ContactNumber.parse(number)
            else
                null,
            .email_address = if (rows.contact.email_address) |email|
                try field.EmailAddress.parse(email)
            else
                null,
        },
    };
    const subject = try subjectToDomain(&rows.subject);
    const ready = switch (subject) {
        .individual => |person| editor.begin(base).individual(person),
        .sole_proprietor => |proprietor| editor.begin(base).soleProprietor(proprietor),
        .legal_entity => |entity| editor.begin(base).legalEntity(entity),
    };
    const revision = try ready
        .withBusinessActivities(activities)
        .withRegistrationFacts(facts)
        .build();

    return .{
        .revision = revision,
        .business_activities = activities,
        .registration_facts = facts,
    };
}

pub fn loadCurrentRevision(
    store: *persistence.Store,
    allocator: std.mem.Allocator,
    profile_id: model.ProfileId,
) !?OwnedDomainRevision {
    var rows = (try store.getCurrentRevision(
        allocator,
        profile_id.asSlice(),
    )) orelse return null;
    defer rows.deinit(allocator);
    return try toDomain(allocator, &rows);
}

pub fn loadRevision(
    store: *persistence.Store,
    allocator: std.mem.Allocator,
    profile_id: model.ProfileId,
    revision_id: model.RevisionId,
) !?OwnedDomainRevision {
    var rows = (try store.getRevision(
        allocator,
        profile_id.asSlice(),
        revision_id.asSlice(),
    )) orelse return null;
    defer rows.deinit(allocator);
    return try toDomain(allocator, &rows);
}

/// Filing composition uses this lookup; editing screens generally use
/// `loadCurrentRevision`. Highest effective sequence wins when immutable
/// effective periods overlap because a later revision supersedes an earlier
/// one without rewriting history.
pub fn loadEffectiveRevision(
    store: *persistence.Store,
    allocator: std.mem.Allocator,
    profile_id: model.ProfileId,
    on: model.Date,
) !?OwnedDomainRevision {
    var date_buffer: persistence.DateText = undefined;
    const date_text = on.writeIso(&date_buffer);
    var rows = (try store.getEffectiveRevision(
        allocator,
        profile_id.asSlice(),
        date_text,
    )) orelse return null;
    defer rows.deinit(allocator);
    return try toDomain(allocator, &rows);
}

/// Canonical snapshot encoding for every reusable field. Text is always
/// copied into the caller's buffer so the result never borrows a profile.
pub fn serializeValue(
    value: *const field.Value,
    buffer: *[255]u8,
) SerializedValue {
    const text = switch (value.*) {
        .tin => |*item| copyToBuffer(buffer, item.asDigits()),
        .rdo_code => |*item| copyToBuffer(buffer, item.asSlice()),
        .taxpayer_name => |*item| copyToBuffer(buffer, item.asSlice()),
        .registered_name => |*item| copyToBuffer(buffer, item.asSlice()),
        .registered_address => |*item| copyToBuffer(buffer, item.asSlice()),
        .zip_code => |*item| copyToBuffer(buffer, item.asSlice()),
        .contact_number => |*item| copyToBuffer(buffer, item.asSlice()),
        .email_address => |*item| copyToBuffer(buffer, item.asSlice()),
        .date_of_birth => |item| item.writeIso(buffer[0..10]),
        .citizenship => |*item| copyToBuffer(buffer, item.asSlice()),
        .foreign_tax_number => |*item| copyToBuffer(buffer, item.asSlice()),
        .line_of_business => |*item| copyToBuffer(buffer, item.asSlice()),
        .atc => |*item| copyToBuffer(buffer, item.asSlice()),
        .tax_type => |*item| copyToBuffer(buffer, item.asSlice()),
        .government_withholding_agent => |item| copyToBuffer(
            buffer,
            @tagName(item),
        ),
        .special_rate_basis => |*item| copyToBuffer(buffer, item.asSlice()),
    };
    return .{
        .value_type = canonicalValueType(value.field()),
        .text = text,
    };
}

pub fn parseValue(
    reusable_field: field.ReusableField,
    value_type: []const u8,
    text: []const u8,
) !field.Value {
    if (!std.mem.eql(
        u8,
        value_type,
        canonicalValueType(reusable_field),
    )) {
        return error.InvalidValueType;
    }
    return switch (reusable_field) {
        .tin => .{ .tin = try field.Tin.parse(text) },
        .rdo_code => .{ .rdo_code = try field.RdoCode.parse(text) },
        .taxpayer_name => .{
            .taxpayer_name = try field.TaxpayerName.parse(text),
        },
        .registered_name => .{
            .registered_name = try field.RegisteredName.parse(text),
        },
        .registered_address => .{
            .registered_address = try field.RegisteredAddress.parse(text),
        },
        .zip_code => .{ .zip_code = try field.ZipCode.parse(text) },
        .contact_number => .{
            .contact_number = try field.ContactNumber.parse(text),
        },
        .email_address => .{
            .email_address = try field.EmailAddress.parse(text),
        },
        .date_of_birth => .{
            .date_of_birth = try model.Date.parseIso(text),
        },
        .citizenship => .{
            .citizenship = try field.Citizenship.parse(text),
        },
        .foreign_tax_number => .{
            .foreign_tax_number = try field.ForeignTaxNumber.parse(text),
        },
        .line_of_business => .{
            .line_of_business = try field.LineOfBusiness.parse(text),
        },
        .atc => .{ .atc = try field.Atc.parse(text) },
        .tax_type => .{ .tax_type = try field.TaxType.parse(text) },
        .government_withholding_agent => .{
            .government_withholding_agent = parseGovernmentWithholdingAgent(text) orelse
                return error.InvalidGovernmentWithholdingAgent,
        },
        .special_rate_basis => .{
            .special_rate_basis = try field.SpecialRateBasis.parse(text),
        },
    };
}

pub fn canonicalValueType(value: field.ReusableField) []const u8 {
    return switch (value) {
        .tin => "tin_digits",
        .date_of_birth => "iso_date",
        .government_withholding_agent => "yes_no",
        else => "text",
    };
}

fn copyToBuffer(buffer: *[255]u8, source: []const u8) []const u8 {
    std.debug.assert(source.len <= buffer.len);
    @memcpy(buffer[0..source.len], source);
    return buffer[0..source.len];
}

fn registrationMetadataToDomain(
    row: *const persistence.OwnedRegistrationRevisionMetadata,
) !registration.RevisionMetadata {
    const source: registration.RecordSource = switch (row.source) {
        .manual_entry => .manual_entry,
        .documented => .{ .documented = try field.SourceReference.parse(
            row.evidence_reference orelse return persistence.Error.InvalidValue,
        ) },
        .imported => .{ .imported = try field.SourceReference.parse(
            row.evidence_reference orelse return persistence.Error.InvalidValue,
        ) },
        .migrated => .{ .migrated = try field.SourceReference.parse(
            row.evidence_reference orelse return persistence.Error.InvalidValue,
        ) },
    };
    const review: registration.ReviewState = switch (row.review_state) {
        .requires_review => .{ .requires_review = switch (row.review_reason orelse return persistence.Error.InvalidValue) {
            .evidence_missing => .evidence_missing,
            .specificity_unknown => .specificity_unknown,
            .migrated_without_confirmation => .migrated_without_confirmation,
            .manual_proposal => .manual_proposal,
        } },
        .confirmed => .{ .confirmed = .{
            .confirmed_at_unix_seconds = row.confirmed_at_unix_seconds orelse
                return persistence.Error.InvalidValue,
        } },
    };
    return .{
        .owner_profile_id = try model.ProfileId.parse(row.profile_id),
        .revision_id = try registration.ComponentRevisionId.parse(row.id),
        .sequence = row.component_sequence,
        .effective = try parseEffective(
            row.effective_from,
            row.effective_until,
        ),
        .source = source,
        .review = review,
    };
}

fn registrationObligationToDomain(
    kind: persistence.RegistrationObligationKind,
    value_text: ?[]const u8,
) !registration.RegistrationObligationKind {
    return switch (kind) {
        .registered_income_tax => .{ .registered_income_tax = {} },
        .vat => .{ .vat = {} },
        .percentage_tax => .{ .percentage_tax = {} },
        .withholding_compensation => .{
            .withholding = .{ .compensation = {} },
        },
        .withholding_expanded => .{
            .withholding = .{ .expanded = {} },
        },
        .withholding_final => .{
            .withholding = .{ .final = {} },
        },
        .withholding_other => .{ .withholding = .{
            .other = try field.TaxType.parse(
                value_text orelse return persistence.Error.InvalidValue,
            ),
        } },
        .withholding_unspecified_requires_review => .{ .withholding = .{
            .unspecified_requires_review = try field.TaxType.parse(
                value_text orelse return persistence.Error.InvalidValue,
            ),
        } },
        .unknown_requires_review => .{
            .unknown_requires_review = try field.TaxType.parse(
                value_text orelse return persistence.Error.InvalidValue,
            ),
        },
    };
}

const EncodedRegistrationObligation = struct {
    kind: persistence.RegistrationObligationKind,
    value_text: ?[]const u8 = null,
};

fn registrationObligationToWrite(
    kind: *const registration.RegistrationObligationKind,
) EncodedRegistrationObligation {
    return switch (kind.*) {
        .registered_income_tax => .{ .kind = .registered_income_tax },
        .vat => .{ .kind = .vat },
        .percentage_tax => .{ .kind = .percentage_tax },
        .withholding => |*value| switch (value.*) {
            .compensation => .{ .kind = .withholding_compensation },
            .expanded => .{ .kind = .withholding_expanded },
            .final => .{ .kind = .withholding_final },
            .other => |*text| .{
                .kind = .withholding_other,
                .value_text = text.asSlice(),
            },
            .unspecified_requires_review => |*text| .{
                .kind = .withholding_unspecified_requires_review,
                .value_text = text.asSlice(),
            },
        },
        .unknown_requires_review => |*text| .{
            .kind = .unknown_requires_review,
            .value_text = text.asSlice(),
        },
    };
}

fn registrationRetirementPeriod(
    viewed_on: model.Date,
) persistence.EffectivePeriodWrite {
    var from: persistence.DateText = undefined;
    _ = viewed_on.writeIso(&from);
    return .{ .from = from };
}

fn findDesiredActivity(
    rows: []const registration_ui.BusinessActivityRow,
    anchor_id: *const registration.ActivityAnchorId,
) ?*const registration_ui.BusinessActivityRow {
    for (rows) |*row| {
        if (row.anchor_id.eql(anchor_id)) return row;
    }
    return null;
}

fn findDesiredObligation(
    rows: []const registration_ui.RegistrationObligationRow,
    anchor_id: *const registration.ObligationAnchorId,
) ?*const registration_ui.RegistrationObligationRow {
    for (rows) |*row| {
        if (row.anchor_id.eql(anchor_id)) return row;
    }
    return null;
}

fn findConfirmedActivity(
    rows: []const registration.BusinessActivity,
    anchor_id: *const registration.ActivityAnchorId,
) ?*const registration.BusinessActivity {
    for (rows) |*row| {
        if (row.metadata.review.isConfirmed() and
            row.anchor_id.eql(anchor_id)) return row;
    }
    return null;
}

fn findConfirmedObligation(
    rows: []const registration.RegistrationObligation,
    anchor_id: *const registration.ObligationAnchorId,
) ?*const registration.RegistrationObligation {
    for (rows) |*row| {
        if (row.metadata.review.isConfirmed() and
            row.anchor_id.eql(anchor_id)) return row;
    }
    return null;
}

fn maxActivitySequence(
    rows: []const persistence.OwnedRegistrationActivityRevision,
    anchor_id: *const registration.ActivityAnchorId,
) u32 {
    var result: u32 = 0;
    for (rows) |*row| {
        if (std.mem.eql(u8, row.anchor_id, anchor_id.asSlice())) {
            result = @max(result, row.metadata.component_sequence);
        }
    }
    return result;
}

fn maxObligationSequence(
    rows: []const persistence.OwnedRegistrationObligationRevision,
    anchor_id: *const registration.ObligationAnchorId,
) u32 {
    var result: u32 = 0;
    for (rows) |*row| {
        if (std.mem.eql(u8, row.anchor_id, anchor_id.asSlice())) {
            result = @max(result, row.metadata.component_sequence);
        }
    }
    return result;
}

fn registrationActivityEquals(
    existing: *const registration.BusinessActivity,
    desired: *const registration_ui.BusinessActivityRow,
) bool {
    if (!existing.metadata.effective.eql(desired.effective) or
        !existing.line_of_business.eql(&desired.line_of_business))
    {
        return false;
    }
    if (existing.atc) |*left| {
        if (desired.atc) |*right| return left.eql(right);
        return false;
    }
    return desired.atc == null;
}

fn registrationObligationRowEquals(
    existing: *const registration.RegistrationObligation,
    desired: *const registration_ui.RegistrationObligationRow,
) bool {
    return existing.metadata.effective.eql(desired.effective) and
        registrationObligationKindsEqual(&existing.kind, &desired.kind);
}

fn registrationObligationKindsEqual(
    left: *const registration.RegistrationObligationKind,
    right: *const registration.RegistrationObligationKind,
) bool {
    if (std.meta.activeTag(left.*) != std.meta.activeTag(right.*)) return false;
    return switch (left.*) {
        .registered_income_tax, .vat, .percentage_tax => true,
        .unknown_requires_review => |*left_text| switch (right.*) {
            .unknown_requires_review => |*right_text| left_text.eql(right_text),
            else => unreachable,
        },
        .withholding => |*left_value| switch (right.*) {
            .withholding => |*right_value| registrationWithholdingKindsEqual(
                left_value,
                right_value,
            ),
            else => unreachable,
        },
    };
}

fn registrationWithholdingKindsEqual(
    left: *const registration.WithholdingObligation,
    right: *const registration.WithholdingObligation,
) bool {
    if (std.meta.activeTag(left.*) != std.meta.activeTag(right.*)) return false;
    return switch (left.*) {
        .compensation, .expanded, .final => true,
        .other => |*left_text| switch (right.*) {
            .other => |*right_text| left_text.eql(right_text),
            else => unreachable,
        },
        .unspecified_requires_review => |*left_text| switch (right.*) {
            .unspecified_requires_review => |*right_text| left_text.eql(right_text),
            else => unreachable,
        },
    };
}

fn validateRetainedRegistrationReviews(
    aggregate: *const registration.RegistrationAggregate,
    rows: []const registration_ui.ReviewRow,
) !void {
    var expected: usize = 0;
    for (aggregate.business_activities) |item| {
        expected += @intFromBool(!item.metadata.review.isConfirmed());
    }
    for (aggregate.obligations) |item| {
        expected += @intFromBool(!item.metadata.review.isConfirmed());
    }
    inline for (.{
        aggregate.agent_designations,
        aggregate.eopt_tiers,
        aggregate.registration_activity_statuses,
        aggregate.special_law_or_treaty_bases,
    }) |items| {
        for (items) |item| {
            expected += @intFromBool(!item.metadata.review.isConfirmed());
        }
    }
    if (rows.len != expected) return persistence.Error.InvalidValue;
    for (rows, 0..) |*row, index| {
        const id = row.revisionId();
        if (!aggregateHasReviewRevision(aggregate, &id)) {
            return persistence.Error.InvalidValue;
        }
        for (rows[index + 1 ..]) |*other| {
            const other_id = other.revisionId();
            if (id.eql(&other_id)) return persistence.Error.InvalidValue;
        }
    }
}

fn aggregateHasReviewRevision(
    aggregate: *const registration.RegistrationAggregate,
    id: *const registration.ComponentRevisionId,
) bool {
    for (aggregate.business_activities) |*item| {
        if (!item.metadata.review.isConfirmed() and
            item.metadata.revision_id.eql(id)) return true;
    }
    for (aggregate.obligations) |*item| {
        if (!item.metadata.review.isConfirmed() and
            item.metadata.revision_id.eql(id)) return true;
    }
    inline for (.{
        aggregate.agent_designations,
        aggregate.eopt_tiers,
        aggregate.registration_activity_statuses,
        aggregate.special_law_or_treaty_bases,
    }) |items| {
        for (items) |*item| {
            if (!item.metadata.review.isConfirmed() and
                item.metadata.revision_id.eql(id)) return true;
        }
    }
    return false;
}

fn effectiveToWrite(
    value: model.EffectivePeriod,
) persistence.EffectivePeriodWrite {
    var from: persistence.DateText = undefined;
    _ = value.from.writeIso(&from);
    var until: ?persistence.DateText = null;
    if (value.until) |last| {
        var buffer: persistence.DateText = undefined;
        _ = last.writeIso(&buffer);
        until = buffer;
    }
    return .{ .from = from, .until = until };
}

fn sourceToWrite(
    value: *const model.RevisionSource,
) persistence.RevisionSourceWrite {
    return switch (value.*) {
        .manual_entry => .{ .manual_entry = {} },
        .imported => |*reference| .{
            .imported = reference.asSlice(),
        },
        .migrated => |*reference| .{
            .migrated = reference.asSlice(),
        },
    };
}

fn taxpayerYearValueToWrite(
    value: taxpayer_year.SettingValue,
) persistence.TaxpayerYearSettingValueWrite {
    return switch (value) {
        .income_tax_rate_election => |election| .{
            .income_tax_rate_election = switch (election) {
                .graduated => .graduated,
                .eight_percent => .eight_percent,
            },
        },
        .deduction_method => |method| .{
            .deduction_method = switch (method) {
                .itemized_deduction => .itemized_deduction,
                .optional_standard_deduction => .optional_standard_deduction,
            },
        },
    };
}

fn taxpayerYearValueToDomain(
    value: persistence.TaxpayerYearSettingValueWrite,
) taxpayer_year.SettingValue {
    return switch (value) {
        .income_tax_rate_election => |election| .{
            .income_tax_rate_election = switch (election) {
                .graduated => .graduated,
                .eight_percent => .eight_percent,
            },
        },
        .deduction_method => |method| .{
            .deduction_method = switch (method) {
                .itemized_deduction => .itemized_deduction,
                .optional_standard_deduction => .optional_standard_deduction,
            },
        },
    };
}

fn taxpayerYearSourceToWrite(
    value: *const taxpayer_year.RevisionSource,
) persistence.TaxpayerYearRevisionSourceWrite {
    return switch (value.*) {
        .manual_entry => .manual_entry,
        .imported => |*reference| .{ .imported = reference.asSlice() },
        .migrated => |*reference| .{ .migrated = reference.asSlice() },
        .copied_from_prior_year => |*copy| .{
            .copied_from_prior_year = .{
                .source_profile_id = copy.stream.profile_id.asSlice(),
                .source_tax_year = copy.stream.tax_year,
                .source_revision_id = copy.revision_id.asSlice(),
                .source_revision_sequence = copy.revision_sequence,
            },
        },
    };
}

fn taxpayerYearSourceToDomain(
    value: *const persistence.OwnedTaxpayerYearRevisionSource,
) !taxpayer_year.RevisionSource {
    return switch (value.*) {
        .manual_entry => .manual_entry,
        .imported => |reference| .{
            .imported = try field.SourceReference.parse(reference),
        },
        .migrated => |reference| .{
            .migrated = try field.SourceReference.parse(reference),
        },
        .copied_from_prior_year => |copy| .{
            .copied_from_prior_year = .{
                .stream = .{
                    .profile_id = try model.ProfileId.parse(
                        copy.source_profile_id,
                    ),
                    .tax_year = copy.source_tax_year,
                },
                .revision_id = try taxpayer_year.RevisionId.parse(
                    copy.source_revision_id,
                ),
                .revision_sequence = copy.source_revision_sequence,
            },
        },
    };
}

fn taxFormProfileValueToWrite(
    value: *const tax_form_profile.SetupValue,
) persistence.TaxFormProfileSetupValueWrite {
    return .{
        .semantic_key = value.semantic_key,
        .role = value.role,
        .value = switch (value.value) {
            .profile_id => |*profile_id| .{
                .profile_id = profile_id.asSlice(),
            },
            .business_activity_anchor_id => |*anchor_id| .{
                .business_activity_anchor_id = anchor_id.asSlice(),
            },
            .registration_obligation_anchor_id => |*anchor_id| .{
                .registration_obligation_anchor_id = anchor_id.asSlice(),
            },
            .text => |*text| .{ .text = text.asSlice() },
            .boolean => |boolean| .{ .boolean = boolean },
            .integer => |integer| .{ .integer = integer },
            .date => |date| blk: {
                var buffer: persistence.DateText = undefined;
                _ = date.writeIso(&buffer);
                break :blk .{ .date = buffer };
            },
            .year => |year| .{ .year = year },
            .choice => |*choice| .{ .choice = choice.asSlice() },
        },
        .source = switch (value.source) {
            .manual_confirmation => .manual_confirmation,
            .copied_from_revision => |*revision_id| .{
                .copied_from_revision = revision_id.asSlice(),
            },
            .migrated => |*reference| .{
                .migrated = reference.asSlice(),
            },
        },
    };
}

fn taxFormProfileValueToDomain(
    value: *const persistence.OwnedTaxFormProfileSetupValue,
) !tax_form_profile.SetupValue {
    return .{
        .semantic_key = value.semantic_key,
        .role = value.role,
        .value = switch (value.value) {
            .profile_id => |profile_id| .{
                .profile_id = try model.ProfileId.parse(profile_id),
            },
            .business_activity_anchor_id => |anchor_id| .{
                .business_activity_anchor_id = try tax_form_profile.ComponentAnchorId.parse(anchor_id),
            },
            .registration_obligation_anchor_id => |anchor_id| .{
                .registration_obligation_anchor_id = try tax_form_profile.ComponentAnchorId.parse(anchor_id),
            },
            .text => |text| .{
                .text = try tax_form_profile.TextValue.parse(text),
            },
            .boolean => |boolean| .{ .boolean = boolean },
            .integer => |integer| .{ .integer = integer },
            .date => |date| .{ .date = try tax_form_profile.Date.parseIso(date) },
            .year => |year| .{ .year = year },
            .choice => |choice| .{
                .choice = try tax_form_profile.TextValue.parse(choice),
            },
        },
        .source = switch (value.source) {
            .manual_confirmation => .manual_confirmation,
            .copied_from_revision => |revision_id| .{
                .copied_from_revision = try tax_form_profile.RevisionId.parse(
                    revision_id,
                ),
            },
            .migrated => |reference| .{
                .migrated = try tax_form_profile.TextValue.parse(reference),
            },
        },
    };
}

fn taxFormProfileRevisionSourceToWrite(
    value: *const tax_form_profile.RevisionSource,
) persistence.TaxFormProfileRevisionSourceWrite {
    return switch (value.*) {
        .manual_entry => .manual_entry,
        .copied_from_prior_year => |*copy| .{
            .copied_from_prior_year = .{
                .source_tax_year = copy.source_tax_year,
                .source_form_revision = copy.source_form_revision.asSlice(),
                .source_spec_revision = copy.source_spec_revision,
                .source_spec_hash = copy.source_spec_hash.asSlice(),
                .source_revision_id = copy.source_revision_id.asSlice(),
            },
        },
        .migrated => |*reference| .{
            .migrated = reference.asSlice(),
        },
    };
}

fn taxFormProfileRevisionSourceToDomain(
    value: *const persistence.OwnedTaxFormProfileRevisionSource,
) !tax_form_profile.RevisionSource {
    return switch (value.*) {
        .manual_entry => .manual_entry,
        .copied_from_prior_year => |copy| .{
            .copied_from_prior_year = .{
                .source_tax_year = copy.source_tax_year,
                .source_form_revision = try tax_form_profile.FormRevision.parse(
                    copy.source_form_revision,
                ),
                .source_spec_revision = copy.source_spec_revision,
                .source_spec_hash = try tax_form_profile.SpecHash.parse(
                    copy.source_spec_hash,
                ),
                .source_revision_id = try tax_form_profile.RevisionId.parse(
                    copy.source_revision_id,
                ),
            },
        },
        .migrated => |reference| .{
            .migrated = try tax_form_profile.TextValue.parse(reference),
        },
    };
}

fn subjectToWrite(value: *const model.Subject) persistence.SubjectWrite {
    return switch (value.*) {
        .individual => |*person| .{
            .individual = individualToWrite(person),
        },
        .sole_proprietor => |*proprietor| .{
            .sole_proprietor = .{
                .person = individualToWrite(&proprietor.person),
                .trade_name = if (proprietor.trade_name) |*name|
                    name.asSlice()
                else
                    null,
            },
        },
        .legal_entity => |*entity| .{
            .legal_entity = .{
                .registered_name = entity.registered_name.asSlice(),
                .trade_name = if (entity.trade_name) |*name|
                    name.asSlice()
                else
                    null,
                .kind = switch (entity.kind) {
                    .corporation => .corporation,
                    .partnership => .partnership,
                    .estate => .estate,
                    .trust => .trust,
                    .other => .other,
                },
            },
        },
    };
}

fn individualToWrite(
    value: *const model.Individual,
) persistence.IndividualWrite {
    return .{
        .name = value.name.asSlice(),
        .classification = naturalPersonClassificationToWrite(
            value.classification,
        ),
        .trade_name = if (value.trade_name) |*name|
            name.asSlice()
        else
            null,
        .date_of_birth = if (value.date_of_birth) |date| blk: {
            var buffer: persistence.DateText = undefined;
            _ = date.writeIso(&buffer);
            break :blk buffer;
        } else null,
        .citizenship = if (value.citizenship) |*citizenship|
            citizenship.asSlice()
        else
            null,
        .foreign_tax_number = if (value.foreign_tax_number) |*number|
            number.asSlice()
        else
            null,
    };
}

fn naturalPersonClassificationToWrite(
    value: model.NaturalPersonClassification,
) persistence.NaturalPersonClassification {
    return switch (value) {
        .classification_unknown => .classification_unknown,
        .pure_compensation => .pure_compensation,
        .self_employed => .self_employed,
        .mixed_income => .mixed_income,
    };
}

fn registrationFactToWrite(
    value: *const model.RegistrationFactValue,
) persistence.RegistrationFactValueWrite {
    return switch (value.*) {
        .tax_type => |*tax_type| .{
            .tax_type = tax_type.asSlice(),
        },
        .government_withholding_agent => |answer| .{
            .government_withholding_agent = switch (answer) {
                .no => .no,
                .yes => .yes,
            },
        },
        .special_rate_basis => |*basis| .{
            .special_rate_basis = basis.asSlice(),
        },
    };
}

fn parseEffective(
    from: []const u8,
    until: ?[]const u8,
) !model.EffectivePeriod {
    return try model.EffectivePeriod.init(
        try model.Date.parseIso(from),
        if (until) |last| try model.Date.parseIso(last) else null,
    );
}

fn sourceToDomain(
    value: *const persistence.OwnedRevisionSource,
) !model.RevisionSource {
    return switch (value.*) {
        .manual_entry => .manual_entry,
        .imported => |reference| .{
            .imported = try field.SourceReference.parse(reference),
        },
        .migrated => |reference| .{
            .migrated = try field.SourceReference.parse(reference),
        },
    };
}

fn subjectToDomain(value: *const persistence.OwnedSubject) !model.Subject {
    return switch (value.*) {
        .individual => |*person| .{
            .individual = try individualToDomain(person),
        },
        .sole_proprietor => |*proprietor| .{
            .sole_proprietor = .{
                .person = try individualToDomain(&proprietor.person),
                .trade_name = if (proprietor.trade_name) |name|
                    try field.RegisteredName.parse(name)
                else
                    null,
            },
        },
        .legal_entity => |*entity| .{
            .legal_entity = .{
                .registered_name = try field.RegisteredName.parse(
                    entity.registered_name,
                ),
                .trade_name = if (entity.trade_name) |name|
                    try field.RegisteredName.parse(name)
                else
                    null,
                .kind = switch (entity.kind) {
                    .corporation => .corporation,
                    .partnership => .partnership,
                    .estate => .estate,
                    .trust => .trust,
                    .other => .other,
                },
            },
        },
    };
}

fn individualToDomain(
    value: *const persistence.OwnedIndividual,
) !model.Individual {
    return .{
        .name = try field.TaxpayerName.parse(value.name),
        .classification = naturalPersonClassificationToDomain(
            value.classification,
        ),
        .trade_name = if (value.trade_name) |name|
            try field.RegisteredName.parse(name)
        else
            null,
        .date_of_birth = if (value.date_of_birth) |date|
            try model.Date.parseIso(date)
        else
            null,
        .citizenship = if (value.citizenship) |citizenship|
            try field.Citizenship.parse(citizenship)
        else
            null,
        .foreign_tax_number = if (value.foreign_tax_number) |number|
            try field.ForeignTaxNumber.parse(number)
        else
            null,
    };
}

fn naturalPersonClassificationToDomain(
    value: persistence.NaturalPersonClassification,
) model.NaturalPersonClassification {
    return switch (value) {
        .classification_unknown => .classification_unknown,
        .pure_compensation => .pure_compensation,
        .self_employed => .self_employed,
        .mixed_income => .mixed_income,
    };
}

fn registrationFactToDomain(
    value: *const persistence.OwnedRegistrationFactValue,
) !model.RegistrationFactValue {
    return switch (value.*) {
        .tax_type => |tax_type| .{
            .tax_type = try field.TaxType.parse(tax_type),
        },
        .government_withholding_agent => |answer| .{
            .government_withholding_agent = switch (answer) {
                .no => .no,
                .yes => .yes,
            },
        },
        .special_rate_basis => |basis| .{
            .special_rate_basis = try field.SpecialRateBasis.parse(basis),
        },
    };
}

fn parseGovernmentWithholdingAgent(
    value: []const u8,
) ?field.GovernmentWithholdingAgent {
    if (std.mem.eql(u8, value, "no")) return .no;
    if (std.mem.eql(u8, value, "yes")) return .yes;
    return null;
}

test "Forms Set decision adapter round trips exact append list and resolve" {
    const allocator = std.testing.allocator;
    var store = try persistence.Store.openMemory(allocator);
    defer store.close();
    const profile = try testIndividualRevision();
    try createProfileWithRevision(&store, allocator, .active, &profile);
    const stream: forms_set_history.StreamIdentity = .{
        .profile_id = profile.profile_id,
        .tax_year = 2026,
        .form = .{ .code = "2551Q", .revision = "2018" },
    };
    const base: forms_set_history.DecisionInput = .{
        .id = try model.RevisionId.parse("adapter-decision-base"),
        .stream = stream,
        .state = .active,
        .scope = .whole_year,
        .effective = try forms_set_history.EffectivePeriod.init(
            try forms_set_history.Date.parseIso("2026-01-01"),
            null,
        ),
        .source = .manual,
        .review = .confirmed,
    };
    try appendFormSetDecision(&store, 0, &base);
    const interval: forms_set_history.DecisionInput = .{
        .id = try model.RevisionId.parse("adapter-decision-interval"),
        .stream = stream,
        .state = .inactive,
        .scope = .interval,
        .effective = try forms_set_history.EffectivePeriod.init(
            try forms_set_history.Date.parseIso("2026-07-01"),
            try forms_set_history.Date.parseIso("2026-09-30"),
        ),
        .source = .manual,
        .review = .confirmed,
    };
    try appendFormSetDecision(&store, 1, &interval);

    var loaded = try loadFormSetDecisionHistory(&store, allocator, stream);
    defer loaded.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 2), loaded.history.records().len);
    try std.testing.expectEqual(
        forms_set_history.Availability.inactive,
        (try loaded.history.resolve(
            stream,
            try forms_set_history.Date.parseIso("2026-08-01"),
        )).availability,
    );

    var resolved = try resolveFormSetDecisionOn(
        &store,
        allocator,
        stream,
        try forms_set_history.Date.parseIso("2026-12-01"),
    );
    defer resolved.deinit(allocator);
    try std.testing.expectEqual(
        forms_set_history.Availability.active,
        resolved.resolution.availability,
    );
    try std.testing.expectEqualStrings(
        "adapter-decision-base",
        resolved.resolution.decision.?.id.asSlice(),
    );
}

test "registration SaveIntent round trips multiple stable typed components by date" {
    const allocator = std.testing.allocator;
    var store = try persistence.Store.openMemory(allocator);
    defer store.close();
    const profile = try testIndividualRevision();
    try createProfileWithRevision(&store, allocator, .active, &profile);

    const initial_activities = [_]persistence.RegistrationActivityRevisionWrite{
        .{
            .anchor_id = "consulting",
            .metadata = .{
                .id = "activity-consulting-v1",
                .expected_component_sequence = 0,
                .effective = .{ .from = "2026-01-01".* },
                .source = .manual_entry,
                .review_state = .confirmed,
                .confirmed_at_unix_seconds = 1,
            },
            .line_of_business = "Software consulting",
            .atc = "IT010",
        },
        .{
            .anchor_id = "retail",
            .metadata = .{
                .id = "activity-retail-v1",
                .expected_component_sequence = 0,
                .effective = .{ .from = "2026-01-01".* },
                .source = .manual_entry,
                .review_state = .confirmed,
                .confirmed_at_unix_seconds = 2,
            },
            .line_of_business = "Retail trade",
        },
    };
    const initial_obligations = [_]persistence.RegistrationObligationRevisionWrite{
        .{
            .anchor_id = "income",
            .metadata = .{
                .id = "obligation-income-v1",
                .expected_component_sequence = 0,
                .effective = .{ .from = "2026-01-01".* },
                .source = .manual_entry,
                .review_state = .confirmed,
                .confirmed_at_unix_seconds = 3,
            },
            .kind = .registered_income_tax,
        },
        .{
            .anchor_id = "vat",
            .metadata = .{
                .id = "obligation-vat-v1",
                .expected_component_sequence = 0,
                .effective = .{ .from = "2026-01-01".* },
                .source = .manual_entry,
                .review_state = .confirmed,
                .confirmed_at_unix_seconds = 4,
            },
            .kind = .vat,
        },
        .{
            .anchor_id = "expanded",
            .metadata = .{
                .id = "obligation-expanded-v1",
                .expected_component_sequence = 0,
                .effective = .{ .from = "2026-01-01".* },
                .source = .manual_entry,
                .review_state = .confirmed,
                .confirmed_at_unix_seconds = 5,
            },
            .kind = .withholding_expanded,
        },
    };
    const agent = [_]persistence.RegistrationAgentDesignationRevisionWrite{.{
        .metadata = .{
            .id = "agent-v1",
            .expected_component_sequence = 0,
            .effective = .{ .from = "2026-01-01".* },
            .source = .documented,
            .evidence_reference = "COR-2026",
            .review_state = .confirmed,
            .confirmed_at_unix_seconds = 6,
        },
        .value = .government_withholding_agent,
    }};
    try std.testing.expectEqual(
        @as(u32, 1),
        try store.appendRegistrationCommit(.{
            .profile_id = profile.profile_id.asSlice(),
            .expected_current_sequence = 0,
            .activities = &initial_activities,
            .obligations = &initial_obligations,
            .agent_designations = &agent,
        }),
    );

    const july_first = try model.Date.parseIso("2026-07-01");
    var july = try loadRegistrationAggregateOn(
        &store,
        allocator,
        profile.profile_id,
        july_first,
    );
    defer july.deinit(allocator);
    try std.testing.expectEqual(@as(u32, 1), july.stream_sequence);
    try std.testing.expectEqual(@as(usize, 2), july.business_activities.len);
    try std.testing.expectEqual(@as(usize, 3), july.obligations.len);
    try std.testing.expectEqual(@as(usize, 1), july.agent_designations.len);
    const consulting_anchor = try registration.ActivityAnchorId.parse(
        "consulting",
    );
    const vat_anchor = try registration.ObligationAnchorId.parse("vat");
    try std.testing.expectEqualStrings(
        "Software consulting",
        (try july.aggregate.resolveActivity(
            consulting_anchor,
            july_first,
        )).confirmed.?.line_of_business.asSlice(),
    );
    try std.testing.expect(
        (try july.aggregate.resolveObligation(vat_anchor, july_first))
            .confirmed != null,
    );

    var state = try registration_ui.State.open(.{
        .aggregate = &july.aggregate,
        .viewed_on = july_first,
        .subject_kind = .individual,
        .natural_person_classification = .self_employed,
        .expected_sequence = july.stream_sequence,
    });
    try state.beginEdit();
    try state.updateBusinessActivity(
        consulting_anchor,
        "Cloud software consulting",
        "IT011",
        try registration.EffectivePeriod.init(july_first, null),
    );
    try state.removeRegistrationObligation(vat_anchor);
    try state.addRegistrationObligation(
        try registration.ObligationAnchorId.parse("percentage"),
        .percentage_tax,
        try registration.EffectivePeriod.init(july_first, null),
    );
    const intent = try state.beginSave();
    const new_sequence = try saveRegistrationIntent(
        &store,
        allocator,
        &intent,
    );
    try std.testing.expectEqual(@as(u32, 2), new_sequence);
    try state.saveSucceeded(new_sequence);

    var june = try loadRegistrationAggregateOn(
        &store,
        allocator,
        profile.profile_id,
        try model.Date.parseIso("2026-06-30"),
    );
    defer june.deinit(allocator);
    try std.testing.expectEqualStrings(
        "Software consulting",
        (try june.aggregate.resolveActivity(
            consulting_anchor,
            try model.Date.parseIso("2026-06-30"),
        )).confirmed.?.line_of_business.asSlice(),
    );
    try std.testing.expect(
        (try june.aggregate.resolveObligation(
            vat_anchor,
            try model.Date.parseIso("2026-06-30"),
        )).confirmed != null,
    );

    var changed = try loadRegistrationAggregateOn(
        &store,
        allocator,
        profile.profile_id,
        july_first,
    );
    defer changed.deinit(allocator);
    try std.testing.expectEqualStrings(
        "Cloud software consulting",
        (try changed.aggregate.resolveActivity(
            consulting_anchor,
            july_first,
        )).confirmed.?.line_of_business.asSlice(),
    );
    try std.testing.expect(
        (try changed.aggregate.resolveObligation(vat_anchor, july_first))
            .confirmed == null,
    );
    const percentage = try changed.aggregate.resolveObligation(
        try registration.ObligationAnchorId.parse("percentage"),
        july_first,
    );
    try std.testing.expect(percentage.confirmed != null);
    try std.testing.expect(percentage.confirmed.?.kind == .percentage_tax);

    var history = try store.listRegistrationHistory(
        allocator,
        profile.profile_id.asSlice(),
    );
    defer history.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 3), history.activities.len);
    try std.testing.expectEqual(@as(usize, 5), history.obligations.len);
    try std.testing.expectEqualStrings(
        "consulting",
        history.activities[2].anchor_id,
    );
}

test "registration selected year edits and reloads a finite interval losslessly" {
    const allocator = std.testing.allocator;
    var store = try persistence.Store.openMemory(allocator);
    defer store.close();
    const profile = try testIndividualRevision();
    try createProfileWithRevision(&store, allocator, .active, &profile);

    const activities = [_]persistence.RegistrationActivityRevisionWrite{.{
        .anchor_id = "first-half-activity",
        .metadata = .{
            .id = "first-half-activity-r1",
            .expected_component_sequence = 0,
            .effective = .{
                .from = "2026-01-01".*,
                .until = "2026-06-30".*,
            },
            .source = .manual_entry,
            .review_state = .confirmed,
            .confirmed_at_unix_seconds = 1,
        },
        .line_of_business = "Seasonal consulting",
        .atc = "PT010",
    }};
    const obligations = [_]persistence.RegistrationObligationRevisionWrite{.{
        .anchor_id = "first-half-percentage-tax",
        .metadata = .{
            .id = "first-half-percentage-tax-r1",
            .expected_component_sequence = 0,
            .effective = .{
                .from = "2026-01-01".*,
                .until = "2026-06-30".*,
            },
            .source = .manual_entry,
            .review_state = .confirmed,
            .confirmed_at_unix_seconds = 2,
        },
        .kind = .percentage_tax,
    }};
    try std.testing.expectEqual(
        @as(u32, 1),
        try store.appendRegistrationCommit(.{
            .profile_id = profile.profile_id.asSlice(),
            .expected_current_sequence = 0,
            .activities = &activities,
            .obligations = &obligations,
        }),
    );

    const year_end = try model.Date.parseIso("2026-12-31");
    var as_of_year_end = try loadRegistrationAggregateOn(
        &store,
        allocator,
        profile.profile_id,
        year_end,
    );
    defer as_of_year_end.deinit(allocator);
    try std.testing.expectEqual(
        @as(usize, 0),
        as_of_year_end.business_activities.len,
    );

    var selected_year = try loadRegistrationAggregateForYear(
        &store,
        allocator,
        profile.profile_id,
        2026,
    );
    defer selected_year.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 1), selected_year.business_activities.len);
    try std.testing.expectEqual(@as(usize, 1), selected_year.obligations.len);

    var state = try registration_ui.State.open(.{
        .aggregate = &selected_year.aggregate,
        .viewed_on = year_end,
        .selected_tax_year = 2026,
        .subject_kind = .sole_proprietor,
        .natural_person_classification = .self_employed,
        .expected_sequence = selected_year.stream_sequence,
    });
    const anchor = state.businessActivities()[0].anchor_id;
    const exact_period = state.businessActivities()[0].effective;
    try state.beginEdit();
    try state.updateBusinessActivity(
        anchor,
        "Seasonal advisory",
        "PT011",
        exact_period,
    );
    const intent = try state.beginSave();
    const new_sequence = try saveRegistrationIntent(&store, allocator, &intent);
    try std.testing.expectEqual(@as(u32, 2), new_sequence);
    try state.saveSucceeded(new_sequence);

    var reloaded = try loadRegistrationAggregateForYear(
        &store,
        allocator,
        profile.profile_id,
        2026,
    );
    defer reloaded.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 1), reloaded.business_activities.len);
    try std.testing.expectEqual(@as(usize, 1), reloaded.obligations.len);
    const reloaded_activity = &reloaded.business_activities[0];
    try std.testing.expect(reloaded_activity.anchor_id.eql(&anchor));
    try std.testing.expect(reloaded_activity.metadata.effective.eql(exact_period));
    try std.testing.expectEqualStrings(
        "Seasonal advisory",
        reloaded_activity.line_of_business.asSlice(),
    );
    try std.testing.expectEqualStrings("PT011", reloaded_activity.atc.?.asSlice());
    try std.testing.expect(reloaded.obligations[0].metadata.effective.eql(
        exact_period,
    ));
}

test "taxpayer-year settings persist exact annual streams and explicit copy review" {
    const allocator = std.testing.allocator;
    var store = try persistence.Store.openMemory(allocator);
    defer store.close();

    const profile = try testIndividualRevision();
    try createProfileWithRevision(&store, allocator, .active, &profile);
    const profile_id = profile.profile_id;
    const stream_2025: taxpayer_year.StreamKey = .{
        .profile_id = profile_id,
        .tax_year = 2025,
    };
    const first_values = [_]taxpayer_year.SettingValue{
        .{ .income_tax_rate_election = .graduated },
        .{ .deduction_method = .optional_standard_deduction },
    };
    const first: taxpayer_year.Revision = .{
        .id = try taxpayer_year.RevisionId.parse("annual-2025-first"),
        .stream = stream_2025,
        .sequence = 1,
        .effective = try taxpayer_year.EffectivePeriod.init(
            try taxpayer_year.Date.parseIso("2025-01-01"),
            try taxpayer_year.Date.parseIso("2025-06-30"),
        ),
        .review_state = .confirmed,
        .confirmed_at_unix_seconds = 1_735_689_600,
        .source = .manual_entry,
        .values = &first_values,
    };
    try appendTaxpayerYearRevision(&store, allocator, 0, &first);

    const second_values = [_]taxpayer_year.SettingValue{
        .{ .income_tax_rate_election = .eight_percent },
    };
    const second: taxpayer_year.Revision = .{
        .id = try taxpayer_year.RevisionId.parse("annual-2025-second"),
        .stream = stream_2025,
        .sequence = 2,
        .effective = try taxpayer_year.EffectivePeriod.init(
            try taxpayer_year.Date.parseIso("2025-07-01"),
            try taxpayer_year.Date.parseIso("2025-12-31"),
        ),
        .review_state = .confirmed,
        .confirmed_at_unix_seconds = 1_751_328_000,
        .source = .{ .imported = try field.SourceReference.parse(
            "reviewed-2025-election",
        ) },
        .values = &second_values,
    };
    try appendTaxpayerYearRevision(&store, allocator, 1, &second);

    var loaded_2025 = try loadTaxpayerYearHistory(
        &store,
        allocator,
        stream_2025,
    );
    defer loaded_2025.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 2), loaded_2025.revisions.len);
    try std.testing.expectEqual(
        @as(u32, 1),
        (try loaded_2025.history.confirmedEffectiveOn(
            try taxpayer_year.Date.parseIso("2025-06-30"),
        )).sequence,
    );
    const july = try loaded_2025.history.resolveSetting(
        try taxpayer_year.Date.parseIso("2025-07-01"),
        .income_tax_rate_election,
    );
    try std.testing.expectEqual(@as(u32, 2), july.revision.sequence);
    try std.testing.expectEqual(
        taxpayer_year.IncomeTaxRateElection.eight_percent,
        july.value.income_tax_rate_election,
    );
    try std.testing.expect(
        loaded_2025.revisions[1].effective.until.?.eql(
            try taxpayer_year.Date.parseIso("2025-12-31"),
        ),
    );

    const stale_values = [_]taxpayer_year.SettingValue{
        .{ .income_tax_rate_election = .graduated },
    };
    const stale_candidate: taxpayer_year.Revision = .{
        .id = try taxpayer_year.RevisionId.parse("annual-stale-candidate"),
        .stream = stream_2025,
        .sequence = 3,
        .effective = try taxpayer_year.EffectivePeriod.init(
            try taxpayer_year.Date.parseIso("2025-09-01"),
            try taxpayer_year.Date.parseIso("2025-09-30"),
        ),
        .review_state = .confirmed,
        .confirmed_at_unix_seconds = 1_756_684_800,
        .source = .manual_entry,
        .values = &stale_values,
    };
    const stale_id_before = stale_candidate.id;
    const stale_sequence_before = stale_candidate.sequence;
    try std.testing.expectError(
        persistence.Error.RevisionConflict,
        appendTaxpayerYearRevision(&store, allocator, 0, &stale_candidate),
    );
    try std.testing.expect(stale_id_before.eql(&stale_candidate.id));
    try std.testing.expectEqual(
        stale_sequence_before,
        stale_candidate.sequence,
    );
    try std.testing.expectError(
        persistence.Error.TaxpayerYearIntervalOverlap,
        appendTaxpayerYearRevision(&store, allocator, 2, &stale_candidate),
    );

    const stream_2026: taxpayer_year.StreamKey = .{
        .profile_id = profile_id,
        .tax_year = 2026,
    };
    const copied_values = [_]taxpayer_year.SettingValue{
        .{ .income_tax_rate_election = .eight_percent },
    };
    const copied: taxpayer_year.Revision = .{
        .id = try taxpayer_year.RevisionId.parse("annual-2026-copy"),
        .stream = stream_2026,
        .sequence = 1,
        .effective = try taxpayer_year.EffectivePeriod.init(
            try taxpayer_year.Date.parseIso("2026-01-01"),
            try taxpayer_year.Date.parseIso("2026-12-31"),
        ),
        .review_state = .requires_review,
        .source = .{ .copied_from_prior_year = .{
            .stream = stream_2025,
            .revision_id = second.id,
            .revision_sequence = second.sequence,
        } },
        .values = &copied_values,
    };
    try appendTaxpayerYearRevision(&store, allocator, 0, &copied);
    var loaded_2026 = try loadTaxpayerYearHistory(
        &store,
        allocator,
        stream_2026,
    );
    defer loaded_2026.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 1), loaded_2026.revisions.len);
    try std.testing.expectEqual(
        taxpayer_year.ReviewState.requires_review,
        loaded_2026.revisions[0].review_state,
    );
    const copy_source = loaded_2026.revisions[0]
        .source.copied_from_prior_year;
    try std.testing.expect(copy_source.stream.eql(&stream_2025));
    try std.testing.expect(copy_source.revision_id.eql(&second.id));
    try std.testing.expectEqual(second.sequence, copy_source.revision_sequence);
    try std.testing.expectError(
        taxpayer_year.Error.EffectiveRevisionRequiresReview,
        loaded_2026.history.confirmedEffectiveOn(
            try taxpayer_year.Date.parseIso("2026-02-01"),
        ),
    );

    var empty = try loadTaxpayerYearHistory(
        &store,
        allocator,
        .{ .profile_id = profile_id, .tax_year = 2024 },
    );
    defer empty.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), empty.revisions.len);
}

test "taxpayer-year full-year corrections append and resolve newest sequence" {
    const allocator = std.testing.allocator;
    var store = try persistence.Store.openMemory(allocator);
    defer store.close();
    const profile = try testIndividualRevision();
    try createProfileWithRevision(&store, allocator, .active, &profile);
    const stream: taxpayer_year.StreamKey = .{
        .profile_id = profile.profile_id,
        .tax_year = 2026,
    };
    const first_values = [_]taxpayer_year.SettingValue{
        .{ .income_tax_rate_election = .graduated },
    };
    const first: taxpayer_year.Revision = .{
        .id = try taxpayer_year.RevisionId.parse("annual-correction-first"),
        .stream = stream,
        .sequence = 1,
        .effective = try taxpayer_year.EffectivePeriod.init(
            try taxpayer_year.Date.parseIso("2026-01-01"),
            try taxpayer_year.Date.parseIso("2026-12-31"),
        ),
        .review_state = .confirmed,
        .confirmed_at_unix_seconds = 1_767_225_600,
        .source = .manual_entry,
        .values = &first_values,
    };
    try appendTaxpayerYearRevision(&store, allocator, 0, &first);
    const corrected_values = [_]taxpayer_year.SettingValue{
        .{ .income_tax_rate_election = .eight_percent },
    };
    const corrected: taxpayer_year.Revision = .{
        .id = try taxpayer_year.RevisionId.parse("annual-correction-second"),
        .stream = stream,
        .sequence = 2,
        .effective = first.effective,
        .review_state = .confirmed,
        .confirmed_at_unix_seconds = 1_767_225_601,
        .source = .manual_entry,
        .values = &corrected_values,
    };
    try appendTaxpayerYearRevision(&store, allocator, 1, &corrected);

    var loaded = try loadTaxpayerYearHistory(&store, allocator, stream);
    defer loaded.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 2), loaded.revisions.len);
    const resolved = try loaded.history.resolveSetting(
        try taxpayer_year.Date.parseIso("2026-06-30"),
        .income_tax_rate_election,
    );
    try std.testing.expectEqual(@as(u32, 2), resolved.revision.sequence);
    try std.testing.expectEqual(
        taxpayer_year.IncomeTaxRateElection.eight_percent,
        resolved.value.income_tax_rate_election,
    );

    var partial = corrected;
    partial.id = try taxpayer_year.RevisionId.parse("annual-partial-overlap");
    partial.sequence = 3;
    partial.effective = try taxpayer_year.EffectivePeriod.init(
        try taxpayer_year.Date.parseIso("2026-07-01"),
        try taxpayer_year.Date.parseIso("2026-12-31"),
    );
    try std.testing.expectError(
        persistence.Error.TaxpayerYearIntervalOverlap,
        appendTaxpayerYearRevision(&store, allocator, 2, &partial),
    );
}

test "Tax Form Profile persistence enforces generated setup and Forms Set coverage" {
    const allocator = std.testing.allocator;
    var store = try persistence.Store.openMemory(allocator);
    defer store.close();

    const activity = [_]model.BusinessActivity{.{
        .id = try model.BusinessActivityId.parse("activity-primary"),
        .line_of_business = try field.LineOfBusiness.parse(
            "Professional services",
        ),
        .atc = try field.Atc.parse("PT010"),
        .effective = try model.EffectivePeriod.init(
            try model.Date.parseIso("2026-01-01"),
            null,
        ),
    }};
    var profile = try testIndividualRevision();
    profile.business_activities = &activity;
    try createProfileWithRevision(&store, allocator, .active, &profile);

    var other_base = try testBase(
        "profile-other-anchor",
        "revision-other-anchor",
        .manual_entry,
    );
    other_base.identity.tin = try field.Tin.parse("987-654-321-000");
    const other_activity = [_]model.BusinessActivity{.{
        .id = try model.BusinessActivityId.parse("activity-other"),
        .line_of_business = try field.LineOfBusiness.parse("Other business"),
        .effective = try model.EffectivePeriod.init(
            try model.Date.parseIso("2026-01-01"),
            null,
        ),
    }};
    const other_profile = try editor.begin(other_base)
        .individual(.{
            .name = try field.TaxpayerName.parse("OTHER TAXPAYER"),
        })
        .withBusinessActivities(&other_activity)
        .build();
    try createProfileWithRevision(
        &store,
        allocator,
        .active,
        &other_profile,
    );

    const form_1601c = form_catalog.findForm("1601C").?;
    const form_1702rt = form_catalog.findForm("1702RT").?;
    const active_forms = [_]persistence.FormRegistrationWrite{
        .{
            .form_code = form_1601c.code,
            .form_revision = form_1601c.revision.?,
        },
        .{
            .form_code = form_1702rt.code,
            .form_revision = form_1702rt.revision.?,
        },
    };
    try store.replaceFormSet(
        profile.profile_id.asSlice(),
        2026,
        &active_forms,
    );
    const activity_value = [_]tax_form_profile.SetupValue{.{
        .semantic_key = .business_activity_anchor_id,
        .role = .filer,
        .value = .{ .business_activity_anchor_id = try tax_form_profile.ComponentAnchorId.parse("activity-primary") },
    }};
    const first = try testTaxFormProfileRevision(
        profile.profile_id,
        2026,
        form_1601c,
        "setup-1601c-2026-first",
        1,
        "2026-01-01",
        "2026-06-30",
        .confirmed,
        .manual_entry,
        &activity_value,
    );
    try appendTaxFormProfileRevision(&store, allocator, 0, &first);

    const second_form = try testTaxFormProfileRevision(
        profile.profile_id,
        2026,
        form_1702rt,
        "setup-1702rt-2026",
        1,
        "2026-01-01",
        null,
        .confirmed,
        .manual_entry,
        &activity_value,
    );
    try appendTaxFormProfileRevision(&store, allocator, 0, &second_form);
    var second_stream = try loadTaxFormProfileHistory(
        &store,
        allocator,
        second_form.stream,
    );
    defer second_stream.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 1), second_stream.revisions.len);
    try std.testing.expectEqual(@as(u32, 1), second_stream.revisions[0].sequence);

    var loaded = try loadTaxFormProfileHistory(
        &store,
        allocator,
        first.stream,
    );
    defer loaded.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 1), loaded.revisions.len);
    try std.testing.expectEqual(
        @as(u32, 1),
        (try loaded.history.effectiveOn(
            form_1601c,
            try tax_form_profile.Date.parseIso("2026-06-30"),
        )).sequence,
    );
    try std.testing.expectError(
        tax_form_profile.Error.NoEffectiveRevision,
        loaded.history.effectiveOn(
            form_1601c,
            try tax_form_profile.Date.parseIso("2026-07-01"),
        ),
    );

    const next = try testTaxFormProfileRevision(
        profile.profile_id,
        2026,
        form_1601c,
        "setup-1601c-2026-second",
        2,
        "2026-07-01",
        null,
        .confirmed,
        .manual_entry,
        &activity_value,
    );
    const next_id_before = next.id;
    try std.testing.expectError(
        persistence.Error.RevisionConflict,
        appendTaxFormProfileRevision(&store, allocator, 0, &next),
    );
    try std.testing.expect(next_id_before.eql(&next.id));
    var overlap = next;
    overlap.id = try tax_form_profile.RevisionId.parse("setup-overlap");
    overlap.effective = try tax_form_profile.EffectivePeriod.init(
        try tax_form_profile.Date.parseIso("2026-06-30"),
        try tax_form_profile.Date.parseIso("2026-07-31"),
    );
    try std.testing.expectError(
        persistence.Error.TaxFormProfileIntervalOverlap,
        appendTaxFormProfileRevision(&store, allocator, 1, &overlap),
    );

    // Deactivation never deletes history, but it refuses the next append.
    try store.updateFormSet(
        profile.profile_id.asSlice(),
        2026,
        &.{.{
            .form_code = form_1702rt.code,
            .form_revision = form_1702rt.revision.?,
        }},
    );
    try std.testing.expectError(
        persistence.Error.TaxFormProfileInactive,
        appendTaxFormProfileRevision(&store, allocator, 1, &next),
    );
    var after_deactivation = try loadTaxFormProfileHistory(
        &store,
        allocator,
        first.stream,
    );
    defer after_deactivation.deinit(allocator);
    try std.testing.expectEqual(
        @as(usize, 1),
        after_deactivation.revisions.len,
    );

    // A bounded empty override makes the middle inactive even though both
    // endpoints resolve to the active base set.
    try store.replaceFormSet(
        profile.profile_id.asSlice(),
        2028,
        active_forms[0..1],
    );
    try store.createFormSetInterval(.{
        .id = "forms-2028-midyear-disabled",
        .profile_id = profile.profile_id.asSlice(),
        .tax_year = 2028,
        .effective_from = "2028-07-01",
        .effective_until = "2028-08-31",
        .forms = &.{},
    });
    const boundary_candidate = try testTaxFormProfileRevision(
        profile.profile_id,
        2028,
        form_1601c,
        "setup-1601c-2028",
        1,
        "2028-01-01",
        null,
        .confirmed,
        .manual_entry,
        &activity_value,
    );
    try std.testing.expectError(
        persistence.Error.TaxFormProfileInactive,
        appendTaxFormProfileRevision(
            &store,
            allocator,
            0,
            &boundary_candidate,
        ),
    );
    var no_boundary_stream = try loadTaxFormProfileHistory(
        &store,
        allocator,
        boundary_candidate.stream,
    );
    defer no_boundary_stream.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), no_boundary_stream.revisions.len);

    // An anchor belongs to its selected profile, never merely to a component
    // row with a matching-looking ID.
    try store.replaceFormSet(
        profile.profile_id.asSlice(),
        2029,
        active_forms[0..1],
    );
    const foreign_anchor_value = [_]tax_form_profile.SetupValue{.{
        .semantic_key = .business_activity_anchor_id,
        .role = .filer,
        .value = .{ .business_activity_anchor_id = try tax_form_profile.ComponentAnchorId.parse("activity-other") },
    }};
    const foreign_anchor = try testTaxFormProfileRevision(
        profile.profile_id,
        2029,
        form_1601c,
        "setup-cross-profile-anchor",
        1,
        "2029-01-01",
        null,
        .confirmed,
        .manual_entry,
        &foreign_anchor_value,
    );
    try std.testing.expectError(
        persistence.Error.TaxFormProfileReferenceInvalid,
        appendTaxFormProfileRevision(&store, allocator, 0, &foreign_anchor),
    );

    // After explicit acknowledgement, prior-year copy provenance remains
    // exact on the confirmed revision and satisfies filing readiness.
    try store.replaceFormSet(
        profile.profile_id.asSlice(),
        2027,
        active_forms[0..1],
    );
    const copied_activity_value = [_]tax_form_profile.SetupValue{.{
        .semantic_key = .business_activity_anchor_id,
        .role = .filer,
        .value = .{ .business_activity_anchor_id = try tax_form_profile.ComponentAnchorId.parse("activity-primary") },
        .source = .{ .copied_from_revision = first.id },
    }};
    const copied = try testTaxFormProfileRevision(
        profile.profile_id,
        2027,
        form_1601c,
        "setup-1601c-2027-copy",
        1,
        "2027-01-01",
        null,
        .confirmed,
        .{ .copied_from_prior_year = .{
            .source_tax_year = 2026,
            .source_form_revision = first.stream.form_revision,
            .source_spec_revision = first.spec_revision,
            .source_spec_hash = first.spec_hash,
            .source_revision_id = first.id,
        } },
        &copied_activity_value,
    );
    try appendTaxFormProfileRevision(&store, allocator, 0, &copied);
    var copied_history = try loadTaxFormProfileHistory(
        &store,
        allocator,
        copied.stream,
    );
    defer copied_history.deinit(allocator);
    try std.testing.expectEqual(
        tax_form_profile.ReviewState.confirmed,
        copied_history.revisions[0].review_state,
    );
    try std.testing.expectEqual(
        @as(?i64, 1_767_225_600),
        copied_history.revisions[0].confirmed_at_unix,
    );
    try std.testing.expectEqual(
        @as(u16, 2026),
        copied_history.revisions[0]
            .source.copied_from_prior_year.source_tax_year,
    );
    try std.testing.expectEqual(
        @as(u32, 1),
        (try copied_history.history.effectiveOn(
            form_1601c,
            try tax_form_profile.Date.parseIso("2027-03-01"),
        )).sequence,
    );

    // A generated profile-reference value round-trips by profile ID only.
    const form_1701q = form_catalog.findForm("1701Q").?;
    try store.replaceFormSet(
        profile.profile_id.asSlice(),
        2030,
        &.{.{
            .form_code = form_1701q.code,
            .form_revision = form_1701q.revision.?,
        }},
    );
    const spouse_value = [_]tax_form_profile.SetupValue{.{
        .semantic_key = .spouse_profile_id,
        .role = .spouse,
        .value = .{ .profile_id = other_profile.profile_id },
        .source = .{ .migrated = try tax_form_profile.TextValue.parse(
            "reviewed-spouse-binding",
        ) },
    }};
    const spouse_setup = try testTaxFormProfileRevision(
        profile.profile_id,
        2030,
        form_1701q,
        "setup-1701q-2030",
        1,
        "2030-01-01",
        null,
        .confirmed,
        .{ .migrated = try tax_form_profile.TextValue.parse(
            "imported-annual-setup",
        ) },
        &spouse_value,
    );
    try appendTaxFormProfileRevision(&store, allocator, 0, &spouse_setup);
    var spouse_history = try loadTaxFormProfileHistory(
        &store,
        allocator,
        spouse_setup.stream,
    );
    defer spouse_history.deinit(allocator);
    try std.testing.expect(
        spouse_history.revisions[0].values[0]
            .value.profile_id.eql(&other_profile.profile_id),
    );

    // Invalid generated contracts fail before persistence and leave no
    // accidental empty stream behind.
    var invalid = try testTaxFormProfileRevision(
        profile.profile_id,
        2031,
        form_1601c,
        "setup-invalid-contract",
        1,
        "2031-01-01",
        null,
        .confirmed,
        .manual_entry,
        &activity_value,
    );
    invalid.spec_revision += 1;
    try std.testing.expectError(
        tax_form_profile.Error.SpecRevisionMismatch,
        appendTaxFormProfileRevision(&store, allocator, 0, &invalid),
    );
    invalid.spec_revision -= 1;
    const wrong_type = [_]tax_form_profile.SetupValue{.{
        .semantic_key = .business_activity_anchor_id,
        .role = .filer,
        .value = .{ .profile_id = other_profile.profile_id },
    }};
    invalid.values = &wrong_type;
    try std.testing.expectError(
        tax_form_profile.Error.WrongValueType,
        appendTaxFormProfileRevision(&store, allocator, 0, &invalid),
    );
    const duplicates = [_]tax_form_profile.SetupValue{
        activity_value[0],
        activity_value[0],
    };
    invalid.values = &duplicates;
    try std.testing.expectError(
        tax_form_profile.Error.DuplicateValue,
        appendTaxFormProfileRevision(&store, allocator, 0, &invalid),
    );
    invalid.values = &.{};
    try std.testing.expectError(
        tax_form_profile.Error.EmptySetupRevision,
        appendTaxFormProfileRevision(&store, allocator, 0, &invalid),
    );
    const no_setup_form = form_catalog.findForm("2551Q").?;
    invalid.stream.form_code = try tax_form_profile.FormCode.parse(
        no_setup_form.code,
    );
    invalid.stream.form_revision = try tax_form_profile.FormRevision.parse(
        no_setup_form.revision.?,
    );
    invalid.values = &activity_value;
    try std.testing.expectError(
        tax_form_profile.Error.NoSetupContract,
        appendTaxFormProfileRevision(&store, allocator, 0, &invalid),
    );
    var invalid_stream = try loadTaxFormProfileHistory(
        &store,
        allocator,
        .{
            .profile_id = profile.profile_id,
            .tax_year = 2031,
            .form_code = try tax_form_profile.FormCode.parse(form_1601c.code),
            .form_revision = try tax_form_profile.FormRevision.parse(
                form_1601c.revision.?,
            ),
        },
    );
    defer invalid_stream.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), invalid_stream.revisions.len);
}

fn testTaxFormProfileRevision(
    profile_id: model.ProfileId,
    tax_year: u16,
    form: *const form_catalog.FormDefinition,
    id: []const u8,
    sequence: u32,
    effective_from: []const u8,
    effective_until: ?[]const u8,
    review_state: tax_form_profile.ReviewState,
    source: tax_form_profile.RevisionSource,
    values: []const tax_form_profile.SetupValue,
) !tax_form_profile.Revision {
    return .{
        .id = try tax_form_profile.RevisionId.parse(id),
        .stream = .{
            .profile_id = profile_id,
            .tax_year = tax_year,
            .form_code = try tax_form_profile.FormCode.parse(form.code),
            .form_revision = try tax_form_profile.FormRevision.parse(
                form.revision.?,
            ),
        },
        .sequence = sequence,
        .effective = try tax_form_profile.EffectivePeriod.init(
            try tax_form_profile.Date.parseIso(effective_from),
            if (effective_until) |until|
                try tax_form_profile.Date.parseIso(until)
            else
                null,
        ),
        .spec_revision = form.tax_form_profile.spec_revision.?,
        .spec_hash = try tax_form_profile.SpecHash.parse(
            form.tax_form_profile.spec_hash.?,
        ),
        .review_state = review_state,
        .confirmed_at_unix = if (review_state == .confirmed)
            1_767_225_600
        else
            null,
        .source = source,
        .values = values,
    };
}

test "Tax Form Profile full-year corrections append and resolve newest sequence" {
    const allocator = std.testing.allocator;
    var store = try persistence.Store.openMemory(allocator);
    defer store.close();
    const activity = [_]model.BusinessActivity{.{
        .id = try model.BusinessActivityId.parse("correction-activity"),
        .line_of_business = try field.LineOfBusiness.parse("Consulting"),
        .effective = try model.EffectivePeriod.init(
            try model.Date.parseIso("2026-01-01"),
            null,
        ),
    }};
    var profile = try testIndividualRevision();
    profile.business_activities = &activity;
    try createProfileWithRevision(&store, allocator, .active, &profile);
    const form = form_catalog.findForm("1601C").?;
    try store.replaceFormSet(
        profile.profile_id.asSlice(),
        2026,
        &.{.{
            .form_code = form.code,
            .form_revision = form.revision.?,
        }},
    );
    const values = [_]tax_form_profile.SetupValue{.{
        .semantic_key = .business_activity_anchor_id,
        .role = .filer,
        .value = .{
            .business_activity_anchor_id = try tax_form_profile.ComponentAnchorId.parse(
                "correction-activity",
            ),
        },
    }};
    const first = try testTaxFormProfileRevision(
        profile.profile_id,
        2026,
        form,
        "form-profile-correction-first",
        1,
        "2026-01-01",
        null,
        .confirmed,
        .manual_entry,
        &values,
    );
    try appendTaxFormProfileRevision(&store, allocator, 0, &first);
    const corrected = try testTaxFormProfileRevision(
        profile.profile_id,
        2026,
        form,
        "form-profile-correction-second",
        2,
        "2026-01-01",
        null,
        .confirmed,
        .manual_entry,
        &values,
    );
    try appendTaxFormProfileRevision(&store, allocator, 1, &corrected);

    var loaded = try loadTaxFormProfileHistory(
        &store,
        allocator,
        first.stream,
    );
    defer loaded.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 2), loaded.revisions.len);
    try std.testing.expectEqual(
        @as(u32, 2),
        (try loaded.history.effectiveOn(
            form,
            try tax_form_profile.Date.parseIso("2026-06-30"),
        )).sequence,
    );

    var partial = corrected;
    partial.id = try tax_form_profile.RevisionId.parse(
        "form-profile-partial-overlap",
    );
    partial.sequence = 3;
    partial.effective = try tax_form_profile.EffectivePeriod.init(
        try tax_form_profile.Date.parseIso("2026-07-01"),
        try tax_form_profile.Date.parseIso("2026-12-31"),
    );
    try std.testing.expectError(
        persistence.Error.TaxFormProfileIntervalOverlap,
        appendTaxFormProfileRevision(&store, allocator, 2, &partial),
    );
}

test "individual revision round trips through cohesive persistence rows" {
    const allocator = std.testing.allocator;
    var store = try persistence.Store.openMemory(allocator);
    defer store.close();

    const revision = try testIndividualRevision();
    try createProfileWithRevision(&store, allocator, .active, &revision);
    var loaded = (try loadCurrentRevision(
        &store,
        allocator,
        revision.profile_id,
    )).?;
    defer loaded.deinit(allocator);
    try expectRevisionEqual(&revision, &loaded.revision);
}

test "sole proprietor compatibility writes load as canonical self employed individual" {
    const allocator = std.testing.allocator;
    var store = try persistence.Store.openMemory(allocator);
    defer store.close();

    const activities = [_]model.BusinessActivity{
        .{
            .id = try model.BusinessActivityId.parse("activity-retail"),
            .line_of_business = try field.LineOfBusiness.parse("Retail"),
            .atc = try field.Atc.parse("PT010"),
            .effective = try model.EffectivePeriod.init(
                try model.Date.parseIso("2026-01-01"),
                null,
            ),
        },
        .{
            .id = try model.BusinessActivityId.parse("activity-consulting"),
            .line_of_business = try field.LineOfBusiness.parse("Consulting"),
            .effective = try model.EffectivePeriod.init(
                try model.Date.parseIso("2026-04-01"),
                try model.Date.parseIso("2026-12-31"),
            ),
        },
    };
    const facts = [_]model.RegistrationFact{
        .{
            .id = try model.RegistrationFactId.parse("fact-tax-type"),
            .effective = try model.EffectivePeriod.init(
                try model.Date.parseIso("2026-01-01"),
                null,
            ),
            .value = .{
                .tax_type = try field.TaxType.parse("Percentage Tax"),
            },
        },
        .{
            .id = try model.RegistrationFactId.parse("fact-gwa"),
            .effective = try model.EffectivePeriod.init(
                try model.Date.parseIso("2026-02-01"),
                null,
            ),
            .value = .{ .government_withholding_agent = .yes },
        },
        .{
            .id = try model.RegistrationFactId.parse("fact-special-rate"),
            .effective = try model.EffectivePeriod.init(
                try model.Date.parseIso("2026-03-01"),
                null,
            ),
            .value = .{
                .special_rate_basis = try field.SpecialRateBasis.parse(
                    "Tax treaty article 7",
                ),
            },
        },
    };
    const base = try testBase(
        "profile-sole-proprietor",
        "revision-sole-proprietor",
        .{ .imported = try field.SourceReference.parse("bir-import-2026") },
    );
    const revision = try editor.begin(base)
        .soleProprietor(.{
            .person = .{
                .name = try field.TaxpayerName.parse("MARIA SANTOS"),
                .date_of_birth = try model.Date.parseIso("1995-06-01"),
                .citizenship = try field.Citizenship.parse("Filipino"),
                .foreign_tax_number = try field.ForeignTaxNumber.parse(
                    "US-12345",
                ),
            },
            .trade_name = try field.RegisteredName.parse("MARIA'S BAKERY"),
        })
        .withBusinessActivities(&activities)
        .withRegistrationFacts(&facts)
        .build();

    try createProfileWithRevision(&store, allocator, .active, &revision);
    var loaded = (try loadCurrentRevision(
        &store,
        allocator,
        revision.profile_id,
    )).?;
    defer loaded.deinit(allocator);
    var canonical_person = revision.subject.sole_proprietor.person;
    canonical_person.classification = .self_employed;
    canonical_person.trade_name = revision.subject.sole_proprietor.trade_name;
    var canonical_revision = revision;
    canonical_revision.subject = .{ .individual = canonical_person };
    try expectRevisionEqual(&canonical_revision, &loaded.revision);
}

test "every natural person classification and trade name round trips" {
    const allocator = std.testing.allocator;
    const classifications = [_]model.NaturalPersonClassification{
        .classification_unknown,
        .pure_compensation,
        .self_employed,
        .mixed_income,
    };
    for (classifications) |classification| {
        var store = try persistence.Store.openMemory(allocator);
        defer store.close();

        var revision = try testIndividualRevision();
        revision.subject.individual.classification = classification;
        revision.subject.individual.trade_name =
            try field.RegisteredName.parse("JUAN'S SERVICES");
        try createProfileWithRevision(&store, allocator, .active, &revision);
        var loaded = (try loadCurrentRevision(
            &store,
            allocator,
            revision.profile_id,
        )).?;
        defer loaded.deinit(allocator);
        try expectRevisionEqual(&revision, &loaded.revision);
    }
}

test "every legal entity subject kind round trips exactly" {
    const allocator = std.testing.allocator;
    var store = try persistence.Store.openMemory(allocator);
    defer store.close();

    const kinds = [_]model.LegalEntityKind{
        .corporation,
        .partnership,
        .estate,
        .trust,
        .other,
    };
    for (kinds, 0..) |kind, index| {
        var profile_buffer: [64]u8 = undefined;
        const profile_text = try std.fmt.bufPrint(
            &profile_buffer,
            "profile-legal-{d}",
            .{index},
        );
        var revision_buffer: [64]u8 = undefined;
        const revision_text = try std.fmt.bufPrint(
            &revision_buffer,
            "revision-legal-{d}",
            .{index},
        );
        var base = try testBase(
            profile_text,
            revision_text,
            .{ .migrated = try field.SourceReference.parse(
                "legacy-profile-v1",
            ) },
        );
        // Distinct taxpayers need distinct TINs: one canonical TIN identifies
        // exactly one taxpayer, and the store now enforces it.
        var tin_buffer: [16]u8 = undefined;
        base.identity.tin = try field.Tin.parse(try std.fmt.bufPrint(
            &tin_buffer,
            "123-456-78{d}-000",
            .{index},
        ));
        const revision = try editor.begin(base).legalEntity(.{
            .registered_name = try field.RegisteredName.parse(
                "EXAMPLE LEGAL ENTITY",
            ),
            .trade_name = try field.RegisteredName.parse("EXAMPLE TRADE"),
            .kind = kind,
        }).build();
        try createProfileWithRevision(&store, allocator, .active, &revision);
        var loaded = (try loadCurrentRevision(
            &store,
            allocator,
            revision.profile_id,
        )).?;
        defer loaded.deinit(allocator);
        try expectRevisionEqual(&revision, &loaded.revision);
    }
}

test "canonical value codec round trips all reusable field variants" {
    const values = [_]field.Value{
        .{ .tin = try field.Tin.parse("123-456-789-000") },
        .{ .rdo_code = try field.RdoCode.parse("019") },
        .{ .taxpayer_name = try field.TaxpayerName.parse("MARIA SANTOS") },
        .{ .registered_name = try field.RegisteredName.parse("MARIA BAKERY") },
        .{ .registered_address = try field.RegisteredAddress.parse(
            "1 Taxpayer Street",
        ) },
        .{ .zip_code = try field.ZipCode.parse("1000") },
        .{ .contact_number = try field.ContactNumber.parse("09171234567") },
        .{ .email_address = try field.EmailAddress.parse("tax@example.ph") },
        .{ .date_of_birth = try model.Date.parseIso("1995-06-01") },
        .{ .citizenship = try field.Citizenship.parse("Filipino") },
        .{ .foreign_tax_number = try field.ForeignTaxNumber.parse("US-123") },
        .{ .line_of_business = try field.LineOfBusiness.parse("Retail") },
        .{ .atc = try field.Atc.parse("PT010") },
        .{ .tax_type = try field.TaxType.parse("Percentage Tax") },
        .{ .government_withholding_agent = .yes },
        .{ .special_rate_basis = try field.SpecialRateBasis.parse(
            "Treaty article 7",
        ) },
    };
    for (&values) |*value| {
        var buffer: [255]u8 = undefined;
        const encoded = serializeValue(value, &buffer);
        const decoded = try parseValue(
            value.field(),
            encoded.value_type,
            encoded.text,
        );
        try std.testing.expect(value.eql(&decoded));
    }
}

fn testIndividualRevision() !model.ProfileRevision {
    const base = try testBase(
        "profile-individual",
        "revision-individual",
        .manual_entry,
    );
    return try editor.begin(base).individual(.{
        .name = try field.TaxpayerName.parse("JUAN DELA CRUZ"),
        .date_of_birth = try model.Date.parseIso("1990-01-02"),
        .citizenship = try field.Citizenship.parse("Filipino"),
        .foreign_tax_number = try field.ForeignTaxNumber.parse("JP-98765"),
    }).build();
}

fn testBase(
    profile_id: []const u8,
    revision_id: []const u8,
    source: model.RevisionSource,
) !editor.Base {
    return .{
        .profile_id = try model.ProfileId.parse(profile_id),
        .revision_id = try model.RevisionId.parse(revision_id),
        .sequence = 1,
        .effective = try model.EffectivePeriod.init(
            try model.Date.parseIso("2026-01-01"),
            null,
        ),
        .source = source,
        .identity = .{
            .tin = try field.Tin.parse("123-456-789-000"),
            .rdo_code = try field.RdoCode.parse("019"),
        },
        .contact = .{
            .address = try field.RegisteredAddress.parse("1 Taxpayer Street"),
            .zip_code = try field.ZipCode.parse("1000"),
            .contact_number = try field.ContactNumber.parse("09171234567"),
            .email_address = try field.EmailAddress.parse("tax@example.ph"),
        },
    };
}

fn expectRevisionEqual(
    expected: *const model.ProfileRevision,
    actual: *const model.ProfileRevision,
) !void {
    try std.testing.expect(expected.profile_id.eql(&actual.profile_id));
    try std.testing.expect(expected.id.eql(&actual.id));
    try std.testing.expectEqual(expected.sequence, actual.sequence);
    try expectEffectiveEqual(expected.effective, actual.effective);
    try expectSourceEqual(&expected.source, &actual.source);
    try std.testing.expect(expected.identity.tin.eql(&actual.identity.tin));
    try std.testing.expect(
        expected.identity.rdo_code.eql(&actual.identity.rdo_code),
    );
    try std.testing.expect(
        expected.contact.address.eql(&actual.contact.address),
    );
    try expectOptionalFieldEqual(
        field.ZipCode,
        expected.contact.zip_code,
        actual.contact.zip_code,
    );
    try expectOptionalFieldEqual(
        field.ContactNumber,
        expected.contact.contact_number,
        actual.contact.contact_number,
    );
    try expectOptionalFieldEqual(
        field.EmailAddress,
        expected.contact.email_address,
        actual.contact.email_address,
    );
    try expectSubjectEqual(&expected.subject, &actual.subject);

    try std.testing.expectEqual(
        expected.business_activities.len,
        actual.business_activities.len,
    );
    for (
        expected.business_activities,
        actual.business_activities,
    ) |*left, *right| {
        try std.testing.expect(left.id.eql(&right.id));
        try std.testing.expect(
            left.line_of_business.eql(&right.line_of_business),
        );
        try expectOptionalFieldEqual(field.Atc, left.atc, right.atc);
        try expectEffectiveEqual(left.effective, right.effective);
    }

    try std.testing.expectEqual(
        expected.registration_facts.len,
        actual.registration_facts.len,
    );
    for (
        expected.registration_facts,
        actual.registration_facts,
    ) |*left, *right| {
        try std.testing.expect(left.id.eql(&right.id));
        try expectEffectiveEqual(left.effective, right.effective);
        try std.testing.expectEqual(left.kind(), right.kind());
        switch (left.value) {
            .tax_type => |value| try std.testing.expect(
                value.eql(&right.value.tax_type),
            ),
            .government_withholding_agent => |value| try std.testing.expectEqual(
                value,
                right.value.government_withholding_agent,
            ),
            .special_rate_basis => |value| try std.testing.expect(
                value.eql(&right.value.special_rate_basis),
            ),
        }
    }
}

fn expectEffectiveEqual(
    expected: model.EffectivePeriod,
    actual: model.EffectivePeriod,
) !void {
    try std.testing.expect(expected.from.eql(actual.from));
    if (expected.until) |left| {
        try std.testing.expect(actual.until != null);
        try std.testing.expect(left.eql(actual.until.?));
    } else {
        try std.testing.expect(actual.until == null);
    }
}

fn expectSourceEqual(
    expected: *const model.RevisionSource,
    actual: *const model.RevisionSource,
) !void {
    try std.testing.expectEqual(
        std.meta.activeTag(expected.*),
        std.meta.activeTag(actual.*),
    );
    switch (expected.*) {
        .manual_entry => {},
        .imported => |reference| try std.testing.expect(
            reference.eql(&actual.imported),
        ),
        .migrated => |reference| try std.testing.expect(
            reference.eql(&actual.migrated),
        ),
    }
}

fn expectSubjectEqual(
    expected: *const model.Subject,
    actual: *const model.Subject,
) !void {
    try std.testing.expectEqual(
        std.meta.activeTag(expected.*),
        std.meta.activeTag(actual.*),
    );
    switch (expected.*) {
        .individual => |person| try expectIndividualEqual(
            &person,
            &actual.individual,
        ),
        .sole_proprietor => |proprietor| {
            try expectIndividualEqual(
                &proprietor.person,
                &actual.sole_proprietor.person,
            );
            try expectOptionalFieldEqual(
                field.RegisteredName,
                proprietor.trade_name,
                actual.sole_proprietor.trade_name,
            );
        },
        .legal_entity => |entity| {
            try std.testing.expectEqual(entity.kind, actual.legal_entity.kind);
            try std.testing.expect(
                entity.registered_name.eql(
                    &actual.legal_entity.registered_name,
                ),
            );
            try expectOptionalFieldEqual(
                field.RegisteredName,
                entity.trade_name,
                actual.legal_entity.trade_name,
            );
        },
    }
}

fn expectIndividualEqual(
    expected: *const model.Individual,
    actual: *const model.Individual,
) !void {
    try std.testing.expect(expected.name.eql(&actual.name));
    try std.testing.expectEqual(
        expected.classification,
        actual.classification,
    );
    try expectOptionalFieldEqual(
        field.RegisteredName,
        expected.trade_name,
        actual.trade_name,
    );
    if (expected.date_of_birth) |date| {
        try std.testing.expect(actual.date_of_birth != null);
        try std.testing.expect(date.eql(actual.date_of_birth.?));
    } else {
        try std.testing.expect(actual.date_of_birth == null);
    }
    try expectOptionalFieldEqual(
        field.Citizenship,
        expected.citizenship,
        actual.citizenship,
    );
    try expectOptionalFieldEqual(
        field.ForeignTaxNumber,
        expected.foreign_tax_number,
        actual.foreign_tax_number,
    );
}

fn expectOptionalFieldEqual(
    comptime T: type,
    expected: ?T,
    actual: ?T,
) !void {
    if (expected) |left| {
        try std.testing.expect(actual != null);
        try std.testing.expect(left.eql(&actual.?));
    } else {
        try std.testing.expect(actual == null);
    }
}
