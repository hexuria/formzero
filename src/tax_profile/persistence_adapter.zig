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
const taxpayer_year = @import("taxpayer_year_settings.zig");
const tax_form_profile = @import("tax_form_profile.zig");
const form_catalog = @import("../forms/generated/catalog.zig");

pub const SerializedValue = struct {
    value_type: []const u8,
    text: []const u8,
};

/// Normal Base Tax Profile writes contain only the consolidated revision row.
/// Retired activity and registration components are intentionally never
/// emitted by this adapter.
pub const WriteRows = struct {
    revision: persistence.RevisionWrite,

    pub fn deinit(self: *WriteRows, allocator: std.mem.Allocator) void {
        _ = allocator;
        self.* = undefined;
    }
};

/// Normal Base Tax Profile loads expose only consolidated Base fields. Domain
/// fields are fixed-storage values, so the source SQLite row can be released
/// as soon as this conversion returns.
pub const OwnedDomainRevision = struct {
    revision: model.ProfileRevision,

    pub fn deinit(
        self: *OwnedDomainRevision,
        allocator: std.mem.Allocator,
    ) void {
        _ = allocator;
        self.* = undefined;
    }
};

/// Read-only evidence from retired profile-attached component rows. This type
/// is deliberately separate from `OwnedDomainRevision` so normal Base profile
/// editing, readiness, and filing composition cannot consume legacy facts.
pub const LegacyComponentId = struct {
    bytes: [64]u8 = undefined,
    len: u8 = 0,

    pub fn parse(raw: []const u8) model.IdError!LegacyComponentId {
        const value = std.mem.trim(u8, raw, " \t\r\n");
        if (value.len == 0) return error.Empty;
        if (value.len > 64) return error.TooLong;
        for (value) |byte| {
            if (!std.ascii.isAlphanumeric(byte) and
                byte != '-' and byte != '_' and byte != '.' and
                byte != ':')
            {
                return error.InvalidCharacter;
            }
        }
        var result: LegacyComponentId = .{};
        @memcpy(result.bytes[0..value.len], value);
        result.len = @intCast(value.len);
        return result;
    }

    pub fn asSlice(self: *const LegacyComponentId) []const u8 {
        return self.bytes[0..self.len];
    }
};

pub const LegacyBusinessActivity = struct {
    id: LegacyComponentId,
    line_of_business: field.LineOfBusiness,
    atc: ?field.Atc = null,
    effective: model.EffectivePeriod,
};

pub const LegacyRegistrationFactKind = enum {
    tax_type,
    government_withholding_agent,
    special_rate_basis,
};

pub const LegacyRegistrationFactValue = union(LegacyRegistrationFactKind) {
    tax_type: field.TaxType,
    government_withholding_agent: field.GovernmentWithholdingAgent,
    special_rate_basis: field.SpecialRateBasis,
};

pub const LegacyRegistrationFact = struct {
    id: LegacyComponentId,
    effective: model.EffectivePeriod,
    value: LegacyRegistrationFactValue,
};

pub const OwnedLegacyProfileComponents = struct {
    business_activities: []LegacyBusinessActivity,
    registration_facts: []LegacyRegistrationFact,

    pub fn deinit(
        self: *OwnedLegacyProfileComponents,
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

pub fn toWriteRows(
    allocator: std.mem.Allocator,
    revision: *const model.ProfileRevision,
    expected_current_sequence: ?u32,
) !WriteRows {
    _ = allocator;
    try revision.validate();

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
            .accounting_period_basis = if (revision.accounting_period_basis) |basis| switch (basis) {
                .calendar => .calendar,
                .fiscal => .fiscal,
            } else null,
            .fiscal_year_end_month = revision.fiscal_year_end_month,
            .eopt_tier = if (revision.eopt_tier) |tier| switch (tier) {
                .micro => .micro,
                .small => .small,
                .medium => .medium,
                .large => .large,
            } else null,
            .primary_line_of_business = if (revision.primary_line_of_business) |*line| line.asSlice() else null,
            .consolidation_review_state = switch (revision.consolidation_review_state) {
                .confirmed => .confirmed,
                .requires_review => .requires_review,
            },
        },
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
    try store.appendRevision(rows.revision);
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
    try store.appendRevision(rows.revision);
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

/// Reports whether a filing crossed the boundary while bound to this exact
/// Tax Form Profile revision. The Store also checks this inside append, so a
/// stale UI cannot weaken the revision-provenance lock.
pub fn isTaxFormProfileLockedByFiling(
    store: *persistence.Store,
    revision: *const tax_form_profile.Revision,
) !bool {
    return store.isTaxFormProfileLockedByFiling(
        revision.stream.profile_id.asSlice(),
        revision.stream.tax_year,
        revision.stream.form_code.asSlice(),
        revision.stream.form_revision.asSlice(),
        revision.id.asSlice(),
        revision.sequence,
    );
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
        forms_tax_year,
        forms,
        forms_mode,
    );
}

fn baseRevisionToDomain(
    allocator: std.mem.Allocator,
    rows: *const persistence.OwnedProfileRevision,
) !OwnedDomainRevision {
    _ = allocator;

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
    var revision = try ready.build();
    revision.accounting_period_basis = if (rows.accounting_period_basis) |basis| switch (basis) {
        .calendar => .calendar,
        .fiscal => .fiscal,
    } else null;
    revision.fiscal_year_end_month = rows.fiscal_year_end_month;
    revision.eopt_tier = if (rows.eopt_tier) |tier| switch (tier) {
        .micro => .micro,
        .small => .small,
        .medium => .medium,
        .large => .large,
    } else null;
    revision.primary_line_of_business = if (rows.primary_line_of_business) |line| try field.LineOfBusiness.parse(line) else null;
    revision.consolidation_review_state = switch (rows.consolidation_review_state) {
        .confirmed => .confirmed,
        .requires_review => .requires_review,
    };
    try revision.validate();

    return .{ .revision = revision };
}

fn legacyProfileComponentsToDomain(
    allocator: std.mem.Allocator,
    rows: *const persistence.OwnedLegacyProfileRevisionComponents,
) !OwnedLegacyProfileComponents {
    const activities = try allocator.alloc(
        LegacyBusinessActivity,
        rows.business_activities.len,
    );
    errdefer allocator.free(activities);
    for (rows.business_activities, 0..) |*activity, index| {
        activities[index] = .{
            .id = try LegacyComponentId.parse(activity.id),
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
        LegacyRegistrationFact,
        rows.registration_facts.len,
    );
    errdefer allocator.free(facts);
    for (rows.registration_facts, 0..) |*fact, index| {
        facts[index] = .{
            .id = try LegacyComponentId.parse(fact.id),
            .effective = try parseEffective(
                fact.effective_from,
                fact.effective_until,
            ),
            .value = try registrationFactToLegacy(&fact.value),
        };
    }

    return .{
        .business_activities = activities,
        .registration_facts = facts,
    };
}

/// Explicit compatibility/export boundary for retired component rows. Normal
/// runtime callers use `loadCurrentRevision`, `loadRevision`, or
/// `loadEffectiveRevision`, whose consolidated Base revision type has no
/// legacy component fields at all.
pub const legacy_profile_component_export = struct {
    pub fn loadRevision(
        store: *persistence.Store,
        allocator: std.mem.Allocator,
        profile_id: model.ProfileId,
        revision_id: model.RevisionId,
    ) !?OwnedLegacyProfileComponents {
        var rows = (try persistence.legacy_registration_export
            .loadProfileRevisionComponents(
            store,
            allocator,
            profile_id.asSlice(),
            revision_id.asSlice(),
        )) orelse return null;
        defer rows.deinit(allocator);
        return try legacyProfileComponentsToDomain(allocator, &rows);
    }
};

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
    return try baseRevisionToDomain(allocator, &rows);
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
    return try baseRevisionToDomain(allocator, &rows);
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
    return try baseRevisionToDomain(allocator, &rows);
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
        .accounting_period_basis => |item| copyToBuffer(
            buffer,
            @tagName(item),
        ),
        .line_of_business => |*item| copyToBuffer(buffer, item.asSlice()),
        .eopt_tier => |*item| copyToBuffer(buffer, item.asSlice()),
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
        .accounting_period_basis => .{
            .accounting_period_basis = std.meta.stringToEnum(
                field.AccountingPeriodBasis,
                text,
            ) orelse return error.InvalidAccountingPeriodBasis,
        },
        .line_of_business => .{
            .line_of_business = try field.LineOfBusiness.parse(text),
        },
        .eopt_tier => .{ .eopt_tier = try field.EoptTier.parse(text) },
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
        .accounting_period_basis => "choice",
        .government_withholding_agent => "yes_no",
        else => "text",
    };
}

fn copyToBuffer(buffer: *[255]u8, source: []const u8) []const u8 {
    std.debug.assert(source.len <= buffer.len);
    @memcpy(buffer[0..source.len], source);
    return buffer[0..source.len];
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
                    .cooperative => .cooperative,
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
                    .cooperative => .cooperative,
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

fn registrationFactToLegacy(
    value: *const persistence.OwnedRegistrationFactValue,
) !LegacyRegistrationFactValue {
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

    var profile = try testIndividualRevision();
    try createProfileWithRevision(&store, allocator, .active, &profile);

    var other_base = try testBase(
        "profile-other-anchor",
        "revision-other-anchor",
        .manual_entry,
    );
    other_base.identity.tin = try field.Tin.parse("987-654-321-000");
    const other_profile = try editor.begin(other_base)
        .individual(.{
            .name = try field.TaxpayerName.parse("OTHER TAXPAYER"),
        })
        .build();
    try createProfileWithRevision(
        &store,
        allocator,
        .active,
        &other_profile,
    );

    const form_2551q = form_catalog.findForm("2551Q").?;
    const form_1701q = form_catalog.findForm("1701Q").?;
    const active_forms = [_]persistence.FormRegistrationWrite{
        .{
            .form_code = form_2551q.code,
            .form_revision = form_2551q.revision.?,
        },
        .{
            .form_code = form_1701q.code,
            .form_revision = form_1701q.revision.?,
        },
    };
    try store.replaceFormSet(
        profile.profile_id.asSlice(),
        2026,
        &active_forms,
    );
    const income_rate_value = [_]tax_form_profile.SetupValue{.{
        .semantic_key = .income_tax_rate_election,
        .role = .filer,
        .value = .{ .choice = try tax_form_profile.TextValue.parse(
            "graduated",
        ) },
    }};
    const first = try testTaxFormProfileRevision(
        profile.profile_id,
        2026,
        form_2551q,
        "setup-2551q-2026-first",
        1,
        "2026-01-01",
        "2026-06-30",
        .confirmed,
        .manual_entry,
        &income_rate_value,
    );
    try appendTaxFormProfileRevision(&store, allocator, 0, &first);
    try std.testing.expect(!(try isTaxFormProfileLockedByFiling(
        &store,
        &first,
    )));

    const spouse_value = [_]tax_form_profile.SetupValue{.{
        .semantic_key = .spouse_profile_id,
        .role = .spouse,
        .value = .{ .profile_id = other_profile.profile_id },
    }};
    const second_form = try testTaxFormProfileRevision(
        profile.profile_id,
        2026,
        form_1701q,
        "setup-1701q-2026",
        1,
        "2026-01-01",
        null,
        .confirmed,
        .manual_entry,
        &spouse_value,
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
            form_2551q,
            try tax_form_profile.Date.parseIso("2026-06-30"),
        )).sequence,
    );
    try std.testing.expectError(
        tax_form_profile.Error.NoEffectiveRevision,
        loaded.history.effectiveOn(
            form_2551q,
            try tax_form_profile.Date.parseIso("2026-07-01"),
        ),
    );

    const next = try testTaxFormProfileRevision(
        profile.profile_id,
        2026,
        form_2551q,
        "setup-2551q-2026-second",
        2,
        "2026-07-01",
        null,
        .confirmed,
        .manual_entry,
        &income_rate_value,
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
            .form_code = form_1701q.code,
            .form_revision = form_1701q.revision.?,
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
        form_2551q,
        "setup-2551q-2028",
        1,
        "2028-01-01",
        null,
        .confirmed,
        .manual_entry,
        &income_rate_value,
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

    // A profile reference must identify a distinct compatible profile.
    try store.replaceFormSet(
        profile.profile_id.asSlice(),
        2029,
        active_forms[1..2],
    );
    const self_spouse_value = [_]tax_form_profile.SetupValue{.{
        .semantic_key = .spouse_profile_id,
        .role = .spouse,
        .value = .{ .profile_id = profile.profile_id },
    }};
    const self_spouse = try testTaxFormProfileRevision(
        profile.profile_id,
        2029,
        form_1701q,
        "setup-self-spouse",
        1,
        "2029-01-01",
        null,
        .confirmed,
        .manual_entry,
        &self_spouse_value,
    );
    try std.testing.expectError(
        persistence.Error.TaxFormProfileReferenceInvalid,
        appendTaxFormProfileRevision(&store, allocator, 0, &self_spouse),
    );

    // After explicit acknowledgement, prior-year copy provenance remains
    // exact on the confirmed revision and satisfies filing readiness.
    try store.replaceFormSet(
        profile.profile_id.asSlice(),
        2027,
        active_forms[0..1],
    );
    const copied_income_rate_value = [_]tax_form_profile.SetupValue{.{
        .semantic_key = .income_tax_rate_election,
        .role = .filer,
        .value = .{ .choice = try tax_form_profile.TextValue.parse(
            "graduated",
        ) },
        .source = .{ .copied_from_revision = first.id },
    }};
    const copied = try testTaxFormProfileRevision(
        profile.profile_id,
        2027,
        form_2551q,
        "setup-2551q-2027-copy",
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
        &copied_income_rate_value,
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
            form_2551q,
            try tax_form_profile.Date.parseIso("2027-03-01"),
        )).sequence,
    );

    // A generated profile-reference value round-trips by profile ID only.
    try store.replaceFormSet(
        profile.profile_id.asSlice(),
        2030,
        &.{.{
            .form_code = form_1701q.code,
            .form_revision = form_1701q.revision.?,
        }},
    );
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

    // Invalid generated contracts fail before persistence. An empty optional
    // setup is instead an explicit append-only clear and must round-trip.
    var invalid = try testTaxFormProfileRevision(
        profile.profile_id,
        2031,
        form_2551q,
        "setup-invalid-contract",
        1,
        "2031-01-01",
        null,
        .confirmed,
        .manual_entry,
        &income_rate_value,
    );
    invalid.spec_revision += 1;
    try std.testing.expectError(
        tax_form_profile.Error.SpecRevisionMismatch,
        appendTaxFormProfileRevision(&store, allocator, 0, &invalid),
    );
    invalid.spec_revision -= 1;
    const wrong_type = [_]tax_form_profile.SetupValue{.{
        .semantic_key = .income_tax_rate_election,
        .role = .filer,
        .value = .{ .profile_id = other_profile.profile_id },
    }};
    invalid.values = &wrong_type;
    try std.testing.expectError(
        tax_form_profile.Error.WrongValueType,
        appendTaxFormProfileRevision(&store, allocator, 0, &invalid),
    );
    const duplicates = [_]tax_form_profile.SetupValue{
        income_rate_value[0],
        income_rate_value[0],
    };
    invalid.values = &duplicates;
    try std.testing.expectError(
        tax_form_profile.Error.DuplicateValue,
        appendTaxFormProfileRevision(&store, allocator, 0, &invalid),
    );
    try store.replaceFormSet(profile.profile_id.asSlice(), 2031, &.{
        .{
            .form_code = form_2551q.code,
            .form_revision = form_2551q.revision.?,
        },
        .{
            .form_code = form_1701q.code,
            .form_revision = form_1701q.revision.?,
        },
    });
    invalid.values = &.{};
    try std.testing.expectError(
        tax_form_profile.Error.MissingRequiredValue,
        appendTaxFormProfileRevision(&store, allocator, 0, &invalid),
    );

    const empty_optional = try testTaxFormProfileRevision(
        profile.profile_id,
        2031,
        form_1701q,
        "setup-optional-clear",
        1,
        "2031-01-01",
        null,
        .confirmed,
        .manual_entry,
        &.{},
    );
    try appendTaxFormProfileRevision(&store, allocator, 0, &empty_optional);

    const no_setup_form = form_catalog.findForm("1601C").?;
    invalid.stream.form_code = try tax_form_profile.FormCode.parse(
        no_setup_form.code,
    );
    invalid.stream.form_revision = try tax_form_profile.FormRevision.parse(
        no_setup_form.revision.?,
    );
    invalid.values = &income_rate_value;
    try std.testing.expectError(
        tax_form_profile.Error.NoSetupContract,
        appendTaxFormProfileRevision(&store, allocator, 0, &invalid),
    );
    var cleared_stream = try loadTaxFormProfileHistory(
        &store,
        allocator,
        .{
            .profile_id = profile.profile_id,
            .tax_year = 2031,
            .form_code = try tax_form_profile.FormCode.parse(form_1701q.code),
            .form_revision = try tax_form_profile.FormRevision.parse(
                form_1701q.revision.?,
            ),
        },
    );
    defer cleared_stream.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 1), cleared_stream.revisions.len);
    try std.testing.expectEqual(
        @as(usize, 0),
        cleared_stream.revisions[0].values.len,
    );
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
    var profile = try testIndividualRevision();
    try createProfileWithRevision(&store, allocator, .active, &profile);
    const form = form_catalog.findForm("2551Q").?;
    try store.replaceFormSet(
        profile.profile_id.asSlice(),
        2026,
        &.{.{
            .form_code = form.code,
            .form_revision = form.revision.?,
        }},
    );
    const values = [_]tax_form_profile.SetupValue{.{
        .semantic_key = .income_tax_rate_election,
        .role = .filer,
        .value = .{ .choice = try tax_form_profile.TextValue.parse(
            "graduated",
        ) },
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

test "normal Base writes create no retired component rows" {
    const allocator = std.testing.allocator;
    var store = try persistence.Store.openMemory(allocator);
    defer store.close();
    const base = try testBase(
        "profile-sole-proprietor",
        "revision-sole-proprietor",
        .{ .imported = try field.SourceReference.parse("bir-import-2026") },
    );
    var revision = try editor.begin(base)
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
        .build();
    try revision.validate();

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

    var legacy_components = (try legacy_profile_component_export.loadRevision(
        &store,
        allocator,
        revision.profile_id,
        revision.id,
    )).?;
    defer legacy_components.deinit(allocator);
    try std.testing.expectEqual(
        @as(usize, 0),
        legacy_components.business_activities.len,
    );
    try std.testing.expectEqual(
        @as(usize, 0),
        legacy_components.registration_facts.len,
    );
}

test "retired component rows require the explicit compatibility reader" {
    const allocator = std.testing.allocator;
    var store = try persistence.Store.openMemory(allocator);
    defer store.close();

    const first = try testIndividualRevision();
    try createProfileWithRevision(&store, allocator, .active, &first);

    var second = first;
    second.id = try model.RevisionId.parse("revision-legacy-evidence");
    second.sequence = 2;
    var rows = try toWriteRows(allocator, &second, 1);
    defer rows.deinit(allocator);
    const legacy_activities = [_]persistence.BusinessActivityWrite{.{
        .id = "legacy-activity",
        .line_of_business = "Legacy consulting",
        .atc = "PT010",
        .effective = effectiveToWrite(second.effective),
    }};
    const legacy_facts = [_]persistence.RegistrationFactWrite{.{
        .id = "legacy-tax-type",
        .effective = effectiveToWrite(second.effective),
        .value = .{ .tax_type = "Percentage Tax" },
    }};
    // Simulate an older writer explicitly. The current adapter never supplies
    // these component slices to the Store.
    try persistence.testing.appendLegacyRevision(&store, rows.revision, .{
        .business_activities = &legacy_activities,
        .registration_facts = &legacy_facts,
    });

    var normal = (try loadRevision(
        &store,
        allocator,
        second.profile_id,
        second.id,
    )).?;
    defer normal.deinit(allocator);
    try std.testing.expectEqual(@as(u32, 2), normal.revision.sequence);

    var legacy = (try legacy_profile_component_export.loadRevision(
        &store,
        allocator,
        second.profile_id,
        second.id,
    )).?;
    defer legacy.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 1), legacy.business_activities.len);
    try std.testing.expectEqualStrings(
        "Legacy consulting",
        legacy.business_activities[0].line_of_business.asSlice(),
    );
    try std.testing.expectEqual(@as(usize, 1), legacy.registration_facts.len);
    try std.testing.expectEqualStrings(
        "Percentage Tax",
        legacy.registration_facts[0].value.tax_type.asSlice(),
    );
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
        .cooperative,
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
        .{ .accounting_period_basis = .fiscal },
        .{ .line_of_business = try field.LineOfBusiness.parse("Retail") },
        .{ .eopt_tier = try field.EoptTier.parse("micro") },
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
        expected.accounting_period_basis,
        actual.accounting_period_basis,
    );
    try std.testing.expectEqual(
        expected.fiscal_year_end_month,
        actual.fiscal_year_end_month,
    );
    try std.testing.expectEqual(expected.eopt_tier, actual.eopt_tier);
    try expectOptionalFieldEqual(
        field.LineOfBusiness,
        expected.primary_line_of_business,
        actual.primary_line_of_business,
    );
    try std.testing.expectEqual(
        expected.consolidation_review_state,
        actual.consolidation_review_state,
    );
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
