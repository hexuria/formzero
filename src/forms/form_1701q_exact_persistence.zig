//! Durable persistence and fail-closed reopen bridge for the exact
//! BIR Form 1701Q January 2018 workflow.
//!
//! SQLite is an injected repository. This module owns no path, file dialog,
//! network, encryption, queue, endpoint, upload, or submission operation.
//! Stored occurrence values are currently plaintext. The source-classified
//! development artifact may persist them only with its separately minted
//! development capability; synthetic tests retain their narrower capability.
//! Neither path is production-qualified, and the production custody gate stays
//! unavailable until an independently reviewed at-rest design replaces it.

const std = @import("std");
const ids = @import("id.zig");
const form = @import("form_1701q.zig");
const draft_provenance = @import("draft_provenance.zig");
const form_catalog = @import("generated/catalog.zig");
const field = @import("../tax_profile/field.zig");
const forms_set_history = @import("../tax_profile/forms_set_history.zig");
const model = @import("../tax_profile/model.zig");
const projection = @import("../tax_profile/projection.zig");
const store = @import("../tax_profile/store.zig");
const annual_profile = @import("../tax_profile/tax_form_profile.zig");
const year_settings = @import("../tax_profile/taxpayer_year_settings.zig");
const key_custody = @import("../security/key_custody.zig");
const sensitive_memory = @import("../security/sensitive_memory.zig");
const draft = @import("../form_engine/draft.zig");
const occurrence = @import("../form_engine/occurrence.zig");
const form_1701q_2018 = @import("../form_engine/forms/form_1701q_2018/mod.zig");
const evidence = form_1701q_2018.evidence;
const occurrences = form_1701q_2018.occurrences;
const profile_mapping = form_1701q_2018.profile_mapping;
const transaction = form_1701q_2018.transaction;
const workflow = form_1701q_2018.workflow;
const validation = form_1701q_2018.validation;
const ui = @import("form_1701q_exact_ui_state.zig");

pub const synthetic_test_only_at_rest = false;
pub const development_plaintext_at_rest = true;

pub const SecurityBoundary = struct {
    pub const plaintext_storage_state =
        key_custody.PlaintextStorageState.synthetic_plaintext_test_only;
    pub const development_storage_classification =
        key_custody.current_artifact_storage_classification;
    pub const production_storage_state =
        key_custody.current_production_storage_state;
    pub const synthetic_plaintext_persistence_enabled = true;
    pub const development_plaintext_persistence_enabled = true;
    pub const sqlite_values_are_plaintext = true;
    pub const development_only = true;
    pub const synthetic_test_only = false;
    pub const production_key_custody_qualified = false;
    pub const stores_protocol_secrets = false;
    pub const outbound_encryption_enabled = false;
    pub const filesystem_owned_by_adapter = false;
    pub const endpoint_enabled = false;
    pub const queue_enabled = false;
    pub const upload_enabled = false;
    pub const submission_enabled = false;
    pub const transport_enabled = false;
};

pub const Error =
    store.Error ||
    key_custody.SyntheticPlaintextTestError ||
    key_custody.DevelopmentPlaintextStorageError ||
    draft_provenance.Error ||
    workflow.Error ||
    ui.Error ||
    error{
        InvalidRoleBinding,
        DuplicateRoleBinding,
        MissingFilerBinding,
        UnexpectedSpouseBinding,
        MissingSpouseBinding,
        HistoricalProfileBindingMismatch,
        HistoricalProfileDigestMismatch,
        FilingBusinessKeyMismatch,
        ProfileAsOfMismatch,
        RecordedAtInvalid,
        EmptyPersistedWorkspace,
        SelectedShapeMissing,
        PersistedHistoryMismatch,
        PersistedBindingMismatch,
        PersistedOccurrenceContextMismatch,
        LoadedWorkspaceAlreadyConsumed,
        MissingValidationEvidenceReceipt,
        InvalidExactDraftProvenance,
        MissingFilerIncomeTaxRateSource,
        DuplicateFilerIncomeTaxRateSource,
        MissingFilerDeductionMethodSource,
        DuplicateFilerDeductionMethodSource,
        UnexpectedFilerDeductionMethodSource,
        ExactAnnualSelectionMismatch,
        ExactAnnualControlKindMismatch,
    };

/// Caller-owned relation identity layered over the immutable revision
/// provenance already frozen into `projection.Snapshot`.
pub const RoleInstanceBinding = struct {
    role: ids.Role,
    instance_id: []const u8,
    provenance: []const u8 = "historical_profile_projection",
};

/// Allocation-free, caller-owned view of the immutable annual provenance
/// captured before the exact candidate is saved. The Forms Set decision is a
/// value rather than a borrowed pointer so a frozen runtime owner can rebuild
/// it without retaining the SQLite-backed preparation aggregate.
pub const ProvenanceInput = struct {
    applicability_date: model.Date,
    forms_set_decision: forms_set_history.Decision,
    snapshot: *const draft_provenance.DraftProvenance,
};

pub const PersistRequest = struct {
    historical_profile: *const projection.Snapshot,
    role_instances: []const RoleInstanceBinding,
    recorded_at_unix_seconds: i64,
    guard: draft.RevisionGuard,
    /// Null is retained only for pre-v19 synthetic/development compatibility
    /// tests. The application-facing exact runtime requires a frozen value and
    /// never takes this legacy path.
    provenance: ?ProvenanceInput = null,
};

pub const PersistReceipt = struct {
    draft_identity: draft.DraftIdentity,
    revision: draft.DraftRevision,
    parent_revision: ?draft.DraftRevision,
    shape: draft.PayloadShape,
};

const max_role_bindings = 2;
const max_occurrences = occurrences.control_seeds.len;

comptime {
    if (max_occurrences != 173) {
        @compileError("exact 1701Q persistence requires 173 controls");
    }
}

const ExactProvenanceWriteBuffers = struct {
    taxpayers: [draft_provenance.max_taxpayer_roles]store.DraftProvenanceTaxpayerRevisionWrite = undefined,
    sources: [draft_provenance.max_source_snapshots]store.DraftProvenanceSourceSnapshotWrite = undefined,
    seeds: [draft_provenance.max_transaction_seeds]store.DraftProvenanceTransactionSeedWrite = undefined,
    applicability_text: store.DateText = undefined,
};

fn exactProvenanceWrite(
    exact: *const ProvenanceInput,
    buffers: *ExactProvenanceWriteBuffers,
) Error!store.ExactDraftProvenanceWrite {
    const snapshot = exact.snapshot;
    const definition = form_catalog.findForm(
        snapshot.identity.form_code.asSlice(),
    ) orelse return error.InvalidExactDraftProvenance;
    const capture_input: draft_provenance.CaptureInput = .{
        .identity = snapshot.identity,
        .taxpayer_revisions = snapshot.taxpayerRevisions(),
        .taxpayer_year_revision = snapshot.taxpayer_year_revision,
        .tax_form_profile_revision = snapshot.tax_form_profile_revision,
        .source_snapshots = snapshot.sourceSnapshots(),
        .transaction_seeds = snapshot.transactionSeeds(),
    };
    _ = try draft_provenance.DraftProvenance.capture(
        &capture_input,
        definition,
    );
    try validateFormsSetDecision(
        &snapshot.identity,
        exact.applicability_date,
        &exact.forms_set_decision,
    );

    for (snapshot.taxpayerRevisions(), 0..) |*binding, index| {
        buffers.taxpayers[index] = .{
            .role = binding.role,
            .profile_id = binding.profile_id.asSlice(),
            .revision_id = binding.revision_id.asSlice(),
            .revision_sequence = binding.revision_sequence,
        };
    }
    for (snapshot.sourceSnapshots(), 0..) |*source, index| {
        buffers.sources[index] = .{
            .key = provenanceSourceKeyWrite(&source.key),
            .copied_value = provenanceValueWrite(&source.copied_value),
        };
    }
    for (snapshot.transactionSeeds(), 0..) |*seed, index| {
        buffers.seeds[index] = .{
            .filing_field = seed.filing_field.asSlice(),
            .source_key = provenanceSourceKeyWrite(&seed.source_key),
            .source = switch (seed.source) {
                .tax_form_profile_revision => |*revision_id| .{
                    .tax_form_profile_revision = revision_id.asSlice(),
                },
                .catalog_default => |*catalog_binding| .{
                    .catalog_default = .{
                        .revision = catalog_binding.revision.asSlice(),
                        .sha256 = catalog_binding.sha256.asSlice(),
                    },
                },
            },
            .copied_seed_value = provenanceValueWrite(
                &seed.copied_seed_value,
            ),
        };
    }
    _ = exact.applicability_date.writeIso(&buffers.applicability_text);
    return .{
        .owner_profile_id = snapshot.identity.owner_profile_id.asSlice(),
        .tax_year = snapshot.identity.tax_year,
        .form_code = snapshot.identity.form_code.asSlice(),
        .form_revision = snapshot.identity.form_revision.asSlice(),
        .catalog_revision = snapshot.identity.catalog.revision.asSlice(),
        .catalog_sha256 = snapshot.identity.catalog.sha256.asSlice(),
        .setup_spec_revision = snapshot.identity.setup_spec_revision,
        .setup_spec_hash = snapshot.identity.setup_spec_hash.asSlice(),
        .forms_set_decision = .{
            .id = exact.forms_set_decision.id.asSlice(),
            .sequence = exact.forms_set_decision.sequence,
            .source = switch (exact.forms_set_decision.source) {
                .manual => .manual,
                .imported => .imported,
                .cor => .cor,
            },
            .evidence_reference = exact.forms_set_decision.evidence_reference,
            .applicability_date = buffers.applicability_text,
        },
        .taxpayer_revisions = buffers.taxpayers[0..snapshot.taxpayerRevisions().len],
        .taxpayer_year_revision = if (snapshot.taxpayer_year_revision) |*binding|
            .{
                .profile_id = binding.stream.profile_id.asSlice(),
                .tax_year = binding.stream.tax_year,
                .revision_id = binding.revision_id.asSlice(),
                .revision_sequence = binding.revision_sequence,
            }
        else
            null,
        .tax_form_profile_revision = if (snapshot.tax_form_profile_revision) |*binding|
            .{
                .profile_id = binding.stream.profile_id.asSlice(),
                .tax_year = binding.stream.tax_year,
                .form_code = binding.stream.form_code.asSlice(),
                .form_revision = binding.stream.form_revision.asSlice(),
                .revision_id = binding.revision_id.asSlice(),
                .revision_sequence = binding.revision_sequence,
                .spec_revision = binding.spec_revision,
                .spec_hash = binding.spec_hash.asSlice(),
            }
        else
            null,
        .source_snapshots = buffers.sources[0..snapshot.sourceSnapshots().len],
        .transaction_seeds = buffers.seeds[0..snapshot.transactionSeeds().len],
    };
}

fn validateFormsSetDecision(
    identity: *const draft_provenance.FilingIdentity,
    applicability_date: model.Date,
    decision: *const forms_set_history.Decision,
) Error!void {
    if (decision.review != .confirmed or decision.state != .active or
        decision.sequence == 0 or
        !decision.stream.profile_id.eql(&identity.owner_profile_id) or
        decision.stream.tax_year != identity.tax_year or
        !std.mem.eql(
            u8,
            decision.stream.form.code,
            identity.form_code.asSlice(),
        ) or
        !std.mem.eql(
            u8,
            decision.stream.form.revision,
            identity.form_revision.asSlice(),
        ) or
        !decision.appliesOn(applicability_date))
    {
        return error.InvalidExactDraftProvenance;
    }
}

fn provenanceSourceKeyWrite(
    key: *const draft_provenance.SourceKey,
) store.DraftProvenanceSourceKeyWrite {
    return switch (key.*) {
        .taxpayer_fact => |value| .{ .taxpayer_fact = .{
            .role = value.role,
            .key = std.meta.stringToEnum(
                store.DraftProvenanceTaxpayerFactKey,
                @tagName(value.key),
            ).?,
        } },
        .taxpayer_year_setting => |value| .{ .taxpayer_year_setting = .{
            .role = value.role,
            .key = std.meta.stringToEnum(
                store.DraftProvenanceTaxpayerYearSettingKey,
                @tagName(value.key),
            ).?,
        } },
        .tax_form_profile_value => |*value| .{
            .tax_form_profile_value = .{
                .role = value.role,
                .key = value.key,
            },
        },
    };
}

fn provenanceValueWrite(
    value: *const draft_provenance.SnapshotValue,
) store.DraftProvenanceValueWrite {
    return switch (value.*) {
        .text => |*text| .{ .text = text.asSlice() },
        .choice => |*choice| .{ .choice = choice.asSlice() },
        .boolean => |boolean| .{ .boolean = boolean },
        .integer => |integer| .{ .integer = integer },
        .date => |date| blk: {
            var serialized: store.DateText = undefined;
            _ = date.writeIso(&serialized);
            break :blk .{ .date = serialized };
        },
        .year => |year| .{ .year = year },
        .profile_id => |*id| .{ .profile_id = id.asSlice() },
        .income_tax_rate_election => |election| .{
            .income_tax_rate_election = switch (election) {
                .graduated => .graduated,
                .eight_percent => .eight_percent,
            },
        },
        .deduction_method => |deduction| .{
            .deduction_method = switch (deduction) {
                .itemized_deduction => .itemized_deduction,
                .optional_standard_deduction => .optional_standard_deduction,
            },
        },
    };
}

/// Form-domain reconstruction of one store-owned v19 exact provenance row.
/// The decision's borrowed strings remain valid only while the caller retains
/// the `OwnedExactDraftProvenance`; consumers should immediately copy this
/// result into their fixed runtime owner.
pub const DecodedExactProvenance = struct {
    provenance_snapshot: draft_provenance.DraftProvenance,
    applicability_date: model.Date,
    forms_set_decision: forms_set_history.Decision,
};

pub fn decodeOwnedExactProvenance(
    raw: *const store.OwnedExactDraftProvenance,
) anyerror!DecodedExactProvenance {
    if (raw.taxpayer_revisions.len > draft_provenance.max_taxpayer_roles or
        raw.source_snapshots.len > draft_provenance.max_source_snapshots or
        raw.transaction_seeds.len > draft_provenance.max_transaction_seeds)
    {
        return error.InvalidExactDraftProvenance;
    }
    const identity: draft_provenance.FilingIdentity = .{
        .owner_profile_id = try model.ProfileId.parse(raw.owner_profile_id),
        .tax_year = raw.tax_year,
        .form_code = try annual_profile.FormCode.parse(raw.form_code),
        .form_revision = try annual_profile.FormRevision.parse(
            raw.form_revision,
        ),
        .catalog = .{
            .revision = try draft_provenance.CatalogRevision.parse(
                raw.catalog_revision,
            ),
            .sha256 = try draft_provenance.Sha256.parse(raw.catalog_sha256),
        },
        .setup_spec_revision = raw.setup_spec_revision,
        .setup_spec_hash = try draft_provenance.Sha256.parse(
            raw.setup_spec_hash,
        ),
    };

    var taxpayers: [draft_provenance.max_taxpayer_roles]draft_provenance.TaxpayerRevisionBinding = undefined;
    for (raw.taxpayer_revisions, 0..) |binding, index| {
        taxpayers[index] = .{
            .role = binding.role,
            .profile_id = try model.ProfileId.parse(binding.profile_id),
            .revision_id = try model.RevisionId.parse(binding.revision_id),
            .revision_sequence = binding.revision_sequence,
        };
    }
    var sources: [draft_provenance.max_source_snapshots]draft_provenance.SourceSnapshot = undefined;
    for (raw.source_snapshots, 0..) |*source, index| {
        sources[index] = .{
            .key = try provenanceSourceKeyFromOwned(&source.key),
            .copied_value = try provenanceValueFromOwned(
                &source.copied_value,
            ),
        };
    }
    var seeds: [draft_provenance.max_transaction_seeds]draft_provenance.TransactionDefaultSeed = undefined;
    for (raw.transaction_seeds, 0..) |*seed, index| {
        seeds[index] = .{
            .filing_field = try draft_provenance.DraftFieldKey.parse(
                seed.filing_field,
            ),
            .source_key = try provenanceSourceKeyFromOwned(&seed.source_key),
            .source = switch (seed.source) {
                .tax_form_profile_revision => |revision_id| .{
                    .tax_form_profile_revision = try annual_profile.RevisionId.parse(
                        revision_id,
                    ),
                },
                .catalog_default => |catalog_binding| .{
                    .catalog_default = .{
                        .revision = try draft_provenance.CatalogRevision.parse(
                            catalog_binding.revision,
                        ),
                        .sha256 = try draft_provenance.Sha256.parse(
                            catalog_binding.sha256,
                        ),
                    },
                },
            },
            .copied_seed_value = try provenanceValueFromOwned(
                &seed.copied_seed_value,
            ),
        };
    }

    const taxpayer_year_revision: ?draft_provenance.TaxpayerYearRevisionBinding =
        if (raw.taxpayer_year_revision) |binding| .{
            .stream = .{
                .profile_id = try model.ProfileId.parse(binding.profile_id),
                .tax_year = binding.tax_year,
            },
            .revision_id = try year_settings.RevisionId.parse(
                binding.revision_id,
            ),
            .revision_sequence = binding.revision_sequence,
        } else null;
    const tax_form_profile_revision: ?draft_provenance.TaxFormProfileRevisionBinding =
        if (raw.tax_form_profile_revision) |binding| .{
            .stream = .{
                .profile_id = try model.ProfileId.parse(binding.profile_id),
                .tax_year = binding.tax_year,
                .form_code = try annual_profile.FormCode.parse(
                    binding.form_code,
                ),
                .form_revision = try annual_profile.FormRevision.parse(
                    binding.form_revision,
                ),
            },
            .revision_id = try annual_profile.RevisionId.parse(
                binding.revision_id,
            ),
            .revision_sequence = binding.revision_sequence,
            .spec_revision = binding.spec_revision,
            .spec_hash = try annual_profile.SpecHash.parse(binding.spec_hash),
        } else null;
    const capture_input: draft_provenance.CaptureInput = .{
        .identity = identity,
        .taxpayer_revisions = taxpayers[0..raw.taxpayer_revisions.len],
        .taxpayer_year_revision = taxpayer_year_revision,
        .tax_form_profile_revision = tax_form_profile_revision,
        .source_snapshots = sources[0..raw.source_snapshots.len],
        .transaction_seeds = seeds[0..raw.transaction_seeds.len],
    };
    const definition = form_catalog.findForm(raw.form_code) orelse
        return error.InvalidExactDraftProvenance;
    const snapshot = try draft_provenance.DraftProvenance.capture(
        &capture_input,
        definition,
    );
    const decision = try formsSetDecisionFromOwned(
        &raw.forms_set_decision,
    );
    const applicability_date = try model.Date.parseIso(
        raw.forms_set_applicability_date,
    );
    try validateFormsSetDecision(
        &snapshot.identity,
        applicability_date,
        &decision,
    );
    return .{
        .provenance_snapshot = snapshot,
        .applicability_date = applicability_date,
        .forms_set_decision = decision,
    };
}

fn provenanceSourceKeyFromOwned(
    key: *const store.OwnedDraftProvenanceSourceKey,
) anyerror!draft_provenance.SourceKey {
    return switch (key.*) {
        .taxpayer_fact => |value| .{ .taxpayer_fact = .{
            .role = value.role,
            .key = std.meta.stringToEnum(
                draft_provenance.TaxpayerFactKey,
                @tagName(value.key),
            ) orelse return error.InvalidExactDraftProvenance,
        } },
        .taxpayer_year_setting => |value| .{ .taxpayer_year_setting = .{
            .role = value.role,
            .key = std.meta.stringToEnum(
                year_settings.SettingKey,
                @tagName(value.key),
            ) orelse return error.InvalidExactDraftProvenance,
        } },
        .tax_form_profile_value => |value| .{ .tax_form_profile_value = .{
            .role = value.role,
            .key = value.key,
        } },
    };
}

fn provenanceValueFromOwned(
    value: *const store.OwnedDraftProvenanceValue,
) anyerror!draft_provenance.SnapshotValue {
    return switch (value.*) {
        .text => |text| .{ .text = try draft_provenance.OwnedText.copy(text) },
        .choice => |choice| .{
            .choice = try draft_provenance.OwnedText.copy(choice),
        },
        .boolean => |boolean| .{ .boolean = boolean },
        .integer => |integer| .{ .integer = integer },
        .date => |date| .{ .date = try model.Date.parseIso(date) },
        .year => |year| .{ .year = year },
        .profile_id => |id| .{ .profile_id = try model.ProfileId.parse(id) },
        .income_tax_rate_election => |election| .{
            .income_tax_rate_election = switch (election) {
                .graduated => .graduated,
                .eight_percent => .eight_percent,
            },
        },
        .deduction_method => |deduction| .{
            .deduction_method = switch (deduction) {
                .itemized_deduction => .itemized_deduction,
                .optional_standard_deduction => .optional_standard_deduction,
            },
        },
    };
}

fn formsSetDecisionFromOwned(
    row: *const store.OwnedFormSetDecision,
) anyerror!forms_set_history.Decision {
    const from = try model.Date.parseIso(row.effective_from);
    const until = if (row.effective_until) |date|
        try model.Date.parseIso(date)
    else
        null;
    return .{
        .id = try forms_set_history.DecisionId.parse(row.id),
        .sequence = row.sequence,
        .stream = .{
            .profile_id = try model.ProfileId.parse(row.profile_id),
            .tax_year = row.tax_year,
            .form = .{
                .code = row.form_code,
                .revision = row.form_revision,
            },
        },
        .state = switch (row.state) {
            .active => .active,
            .inactive => .inactive,
        },
        .scope = switch (row.scope) {
            .whole_year => .whole_year,
            .interval => .interval,
        },
        .effective = try model.EffectivePeriod.init(from, until),
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
            try forms_set_history.DecisionId.parse(id)
        else
            null,
    };
}

fn checkedAnnualControl(
    state: *const ui.State,
    control_id: []const u8,
) Error!bool {
    return switch ((try state.control(control_id)).display) {
        .checked => |checked| checked,
        else => error.ExactAnnualControlKindMismatch,
    };
}

/// Item 16 and Item 16A are filing controls, but their legal value is frozen
/// by the filer taxpayer-year revision. Strict persistence rejects a candidate
/// whose current controls diverge from those exact copied source snapshots.
/// Spouse controls are deliberately not read or written here.
pub const FilerAnnualElection = struct {
    rate: year_settings.IncomeTaxRateElection,
    deduction: ?year_settings.DeductionMethod,
};

pub fn filerAnnualElectionFromProvenance(
    snapshot: *const draft_provenance.DraftProvenance,
) Error!FilerAnnualElection {
    var rate: ?year_settings.IncomeTaxRateElection = null;
    var deduction: ?year_settings.DeductionMethod = null;
    for (snapshot.sourceSnapshots()) |*source| {
        const setting = switch (source.key) {
            .taxpayer_year_setting => |value| value,
            else => continue,
        };
        if (setting.role != .filer) continue;
        switch (setting.key) {
            .income_tax_rate_election => {
                if (rate != null) {
                    return error.DuplicateFilerIncomeTaxRateSource;
                }
                rate = switch (source.copied_value) {
                    .income_tax_rate_election => |value| value,
                    else => return error.InvalidExactDraftProvenance,
                };
            },
            .deduction_method => {
                if (deduction != null) {
                    return error.DuplicateFilerDeductionMethodSource;
                }
                deduction = switch (source.copied_value) {
                    .deduction_method => |value| value,
                    else => return error.InvalidExactDraftProvenance,
                };
            },
        }
    }

    const exact_rate = rate orelse
        return error.MissingFilerIncomeTaxRateSource;
    switch (exact_rate) {
        .graduated => if (deduction == null) {
            return error.MissingFilerDeductionMethodSource;
        },
        .eight_percent => if (deduction != null) {
            return error.UnexpectedFilerDeductionMethodSource;
        },
    }
    return .{ .rate = exact_rate, .deduction = deduction };
}

pub fn validateFilerAnnualSelections(
    state: *const ui.State,
    snapshot: *const draft_provenance.DraftProvenance,
) Error!void {
    const election = try filerAnnualElectionFromProvenance(snapshot);

    const graduated = try checkedAnnualControl(
        state,
        "frm1701q:optTaxRate_1",
    );
    const eight_percent = try checkedAnnualControl(
        state,
        "frm1701q:optTaxRate_2",
    );
    const itemized = try checkedAnnualControl(
        state,
        "frm1701q:optMethodOfDeduction:_1",
    );
    const osd = try checkedAnnualControl(
        state,
        "frm1701q:optMethodOfDeduction:_2",
    );

    switch (election.rate) {
        .graduated => {
            if (!graduated or eight_percent) {
                return error.ExactAnnualSelectionMismatch;
            }
            switch (election.deduction.?) {
                .itemized_deduction => if (!itemized or osd) {
                    return error.ExactAnnualSelectionMismatch;
                },
                .optional_standard_deduction => if (!osd or itemized) {
                    return error.ExactAnnualSelectionMismatch;
                },
            }
        },
        .eight_percent => {
            if (!eight_percent or graduated or itemized or osd) {
                return error.ExactAnnualSelectionMismatch;
            }
        },
    }
}

/// Copies the current generated candidate transactionally with an optimistic
/// create/match guard. Neither the state nor the historical projection is
/// mutated.
pub fn persistCurrentCandidate(
    plaintext_capability: *const key_custody.SyntheticPlaintextTestCapability,
    repository: *store.Store,
    state: *const ui.State,
    request: PersistRequest,
) Error!PersistReceipt {
    return persistCurrentCandidateAuthorized(
        plaintext_capability,
        repository,
        state,
        request,
    );
}

/// Development-artifact counterpart to `persistCurrentCandidate`. The opaque
/// authority is minted only by `bootstrapCurrentArtifactStorage`; this API
/// cannot accept a synthetic or production capability and does not change the
/// fail-closed production-storage decision.
pub fn persistCurrentCandidateDevelopmentPlaintext(
    plaintext_capability: *const key_custody.DevelopmentPlaintextStorageCapability,
    repository: *store.Store,
    state: *const ui.State,
    request: PersistRequest,
) Error!PersistReceipt {
    return persistCurrentCandidateAuthorized(
        plaintext_capability,
        repository,
        state,
        request,
    );
}

fn persistCurrentCandidateAuthorized(
    plaintext_capability: anytype,
    repository: *store.Store,
    state: *const ui.State,
    request: PersistRequest,
) Error!PersistReceipt {
    try requirePlaintextAuthority(plaintext_capability);
    if (request.recorded_at_unix_seconds <= 0) {
        return error.RecordedAtInvalid;
    }
    if (!state.profileAsOf().eql(request.historical_profile.effective_on)) {
        return error.ProfileAsOfMismatch;
    }

    const snapshot = try state.candidateSnapshot();
    const supplied_profile_digest = try historicalProfileDigest(
        request.historical_profile,
    );
    if (!supplied_profile_digest.eql(
        &snapshot.profile_snapshot_digest,
    )) {
        return error.HistoricalProfileDigestMismatch;
    }

    var binding_storage: [max_role_bindings]store.ExactDraftRoleBindingWrite = undefined;
    const bindings = try buildRoleBindingWrites(
        request.historical_profile,
        request.role_instances,
        &binding_storage,
    );
    const filer_profile_id = filerProfileId(bindings) orelse
        return error.MissingFilerBinding;

    var key_storage = FilingKeyStorage.init(
        filer_profile_id,
        state.filingContext(),
    );
    defer sensitive_memory.wipeValue(FilingKeyStorage, &key_storage);
    const filing_key = key_storage.borrowed(filer_profile_id);

    var occurrence_storage: [max_occurrences]store.ExactDraftOccurrenceContextWrite = undefined;
    defer sensitive_memory.wipeValue(
        [max_occurrences]store.ExactDraftOccurrenceContextWrite,
        &occurrence_storage,
    );
    const contexts = try buildOccurrenceContexts(
        snapshot,
        &occurrence_storage,
    );
    const profile_as_of = dateText(state.profileAsOf());
    const validation_evidence = state.validationEvidenceReceipt() orelse
        return error.MissingValidationEvidenceReceipt;
    var provenance_buffers: ExactProvenanceWriteBuffers = .{};
    const provenance_write: ?store.ExactDraftProvenanceWrite =
        if (request.provenance) |*provenance| blk: {
            try validateFilerAnnualSelections(state, provenance.snapshot);
            break :blk try exactProvenanceWrite(
                provenance,
                &provenance_buffers,
            );
        } else null;

    try appendExactDraftRevisionAuthorized(repository, plaintext_capability, request.guard, .{
        .filing_key = filing_key,
        .profile_as_of = profile_as_of,
        .recorded_at_unix_seconds = request.recorded_at_unix_seconds,
        .validation_evidence = .{
            .validation_current_year = validation_evidence.validation_current_year,
            .spouse_tin_checksum = validation_evidence.spouse_tin_checksum,
        },
        .snapshot = snapshot,
        .bindings = bindings,
        .occurrence_contexts = contexts,
    }, provenance_write);
    return .{
        .draft_identity = snapshot.draft_identity,
        .revision = snapshot.revision,
        .parent_revision = snapshot.parent_revision,
        .shape = snapshot.schema.payload_shape,
    };
}

fn appendExactDraftRevisionAuthorized(
    repository: *store.Store,
    plaintext_capability: anytype,
    guard: store.ExactDraftRevisionGuard,
    value: store.ExactDraftRevisionWrite,
    provenance: ?store.ExactDraftProvenanceWrite,
) Error!void {
    const Capability = @TypeOf(plaintext_capability);
    if (comptime Capability ==
        *const key_custody.SyntheticPlaintextTestCapability)
    {
        if (provenance) |exact| {
            return repository.appendExactDraftRevisionWithProvenance(
                plaintext_capability,
                guard,
                value,
                exact,
            );
        }
        return repository.appendExactDraftRevision(
            plaintext_capability,
            guard,
            value,
        );
    } else if (comptime Capability ==
        *const key_custody.DevelopmentPlaintextStorageCapability)
    {
        if (provenance) |exact| {
            return repository
                .appendExactDraftRevisionDevelopmentPlaintextWithProvenance(
                plaintext_capability,
                guard,
                value,
                exact,
            );
        }
        return repository.appendExactDraftRevisionDevelopmentPlaintext(
            plaintext_capability,
            guard,
            value,
        );
    } else {
        @compileError("unsupported exact-draft plaintext authority");
    }
}

/// Shape-specific histories remain siblings under one random workspace.
/// Sidecars retain immutable revision bindings, occurrence provenance,
/// profile-as-of, and timestamps that deliberately do not belong in the
/// pure engine `DraftHistory`.
pub const LoadedWorkspace = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    workspace: workflow.Workspace,
    workspace_owned: bool = true,
    editable_history: ?store.OwnedExactDraftHistory = null,
    final_history: ?store.OwnedExactDraftHistory = null,

    pub fn deinit(self: *Self) void {
        if (self.workspace_owned) self.workspace.deinit();
        if (self.editable_history) |*history| {
            history.deinit(self.allocator);
        }
        if (self.final_history) |*history| {
            history.deinit(self.allocator);
        }
        sensitive_memory.wipeValue(Self, self);
    }

    pub fn revisionCount(
        self: *const Self,
        shape: draft.PayloadShape,
    ) usize {
        return switch (shape) {
            .editable_save => self.workspace.editableRevisionCount(),
            .final_copy_plaintext => self.workspace.finalRevisionCount(),
        };
    }

    pub fn currentPersistedRevision(
        self: *const Self,
        shape: draft.PayloadShape,
    ) ?*const store.OwnedExactDraftRevision {
        const history = switch (shape) {
            .editable_save => if (self.editable_history) |*value|
                value
            else
                return null,
            .final_copy_plaintext => if (self.final_history) |*value|
                value
            else
                return null,
        };
        if (history.revisions.len == 0) return null;
        return &history.revisions[history.revisions.len - 1];
    }

    pub fn persistedIdentity(
        self: *const Self,
        shape: draft.PayloadShape,
    ) ?draft.DraftIdentity {
        const history = switch (shape) {
            .editable_save => if (self.editable_history) |*value|
                value
            else
                return null,
            .final_copy_plaintext => if (self.final_history) |*value|
                value
            else
                return null,
        };
        return history.draft_identity;
    }
};

/// Loads both exact-schema streams for one random workspace and replays every
/// revision through the public validating engine path. `out` is untouched on
/// failure.
pub fn loadWorkspaceInto(
    plaintext_capability: *const key_custody.SyntheticPlaintextTestCapability,
    out: *LoadedWorkspace,
    repository: *store.Store,
    allocator: std.mem.Allocator,
    workspace_id: draft.DraftWorkspaceId,
    filer_profile_id: []const u8,
    context: ui.FilingContext,
) Error!void {
    return loadWorkspaceIntoAuthorized(
        plaintext_capability,
        out,
        repository,
        allocator,
        workspace_id,
        filer_profile_id,
        context,
    );
}

/// Loads and validates a development-artifact plaintext workspace. Every
/// immutable snapshot, role binding, occurrence context, digest, and candidate
/// byte remains subject to the same replay checks as the synthetic test path.
pub fn loadWorkspaceIntoDevelopmentPlaintext(
    plaintext_capability: *const key_custody.DevelopmentPlaintextStorageCapability,
    out: *LoadedWorkspace,
    repository: *store.Store,
    allocator: std.mem.Allocator,
    workspace_id: draft.DraftWorkspaceId,
    filer_profile_id: []const u8,
    context: ui.FilingContext,
) Error!void {
    return loadWorkspaceIntoAuthorized(
        plaintext_capability,
        out,
        repository,
        allocator,
        workspace_id,
        filer_profile_id,
        context,
    );
}

fn loadWorkspaceIntoAuthorized(
    plaintext_capability: anytype,
    out: *LoadedWorkspace,
    repository: *store.Store,
    allocator: std.mem.Allocator,
    workspace_id: draft.DraftWorkspaceId,
    filer_profile_id: []const u8,
    context: ui.FilingContext,
) Error!void {
    try requirePlaintextAuthority(plaintext_capability);
    var key_storage = FilingKeyStorage.init(filer_profile_id, context);
    defer sensitive_memory.wipeValue(FilingKeyStorage, &key_storage);
    const expected_key = key_storage.borrowed(filer_profile_id);

    const editable_schema = try draft.SchemaBinding.exact1701Q(
        .editable_save,
    );
    const final_schema = try draft.SchemaBinding.exact1701Q(
        .final_copy_plaintext,
    );
    const editable_identity: draft.DraftIdentity = .{
        .workspace_id = workspace_id,
        .exact_schema_digest = editable_schema.exact_schema_digest,
    };
    const final_identity: draft.DraftIdentity = .{
        .workspace_id = workspace_id,
        .exact_schema_digest = final_schema.exact_schema_digest,
    };

    var editable = try loadBoundedExactHistory(
        plaintext_capability,
        repository,
        allocator,
        editable_identity,
    );
    var editable_owned = editable != null;
    defer if (editable_owned) {
        editable.?.deinit(allocator);
    };
    var final_copy = try loadBoundedExactHistory(
        plaintext_capability,
        repository,
        allocator,
        final_identity,
    );
    var final_owned = final_copy != null;
    defer if (final_owned) {
        final_copy.?.deinit(allocator);
    };
    if (editable == null and final_copy == null) {
        return error.EmptyPersistedWorkspace;
    }

    if (editable) |*history| {
        if (!filingKeyEql(history.filing_key.borrowed(), expected_key)) {
            return error.FilingBusinessKeyMismatch;
        }
    }
    if (final_copy) |*history| {
        if (!filingKeyEql(history.filing_key.borrowed(), expected_key)) {
            return error.FilingBusinessKeyMismatch;
        }
    }

    var workspace = try workflow.Workspace.init(
        allocator,
        workspace_id,
    );
    var workspace_owned = true;
    defer if (workspace_owned) workspace.deinit();
    if (editable) |*history| {
        try replayOwnedHistory(
            &workspace.editable_history,
            history,
        );
    }
    if (final_copy) |*history| {
        try replayOwnedHistory(
            &workspace.final_history,
            history,
        );
    }

    out.* = .{
        .allocator = allocator,
        .workspace = workspace,
        .editable_history = editable,
        .final_history = final_copy,
    };
    sensitive_memory.wipeValue(workflow.Workspace, &workspace);
    sensitive_memory.wipeValue(
        ?store.OwnedExactDraftHistory,
        &editable,
    );
    sensitive_memory.wipeValue(
        ?store.OwnedExactDraftHistory,
        &final_copy,
    );
    workspace_owned = false;
    editable_owned = false;
    final_owned = false;
}

fn loadBoundedExactHistory(
    plaintext_capability: anytype,
    repository: *store.Store,
    allocator: std.mem.Allocator,
    identity: draft.DraftIdentity,
) Error!?store.OwnedExactDraftHistory {
    return getExactDraftHistoryAuthorized(
        repository,
        plaintext_capability,
        allocator,
        identity,
    ) catch |err| switch (err) {
        // Preserve the store's precise limit reason. The repository returns
        // no owned history on either path, and loadWorkspaceInto's defers
        // release the already-loaded sibling before propagating the error.
        error.DraftRevisionLimitExceeded,
        error.DraftRetainedValueLimitExceeded,
        => return err,
        else => return err,
    };
}

fn getExactDraftHistoryAuthorized(
    repository: *store.Store,
    plaintext_capability: anytype,
    allocator: std.mem.Allocator,
    identity: draft.DraftIdentity,
) Error!?store.OwnedExactDraftHistory {
    const Capability = @TypeOf(plaintext_capability);
    if (comptime Capability ==
        *const key_custody.SyntheticPlaintextTestCapability)
    {
        return repository.getExactDraftHistory(
            plaintext_capability,
            allocator,
            identity,
        );
    } else if (comptime Capability ==
        *const key_custody.DevelopmentPlaintextStorageCapability)
    {
        return repository.getExactDraftHistoryDevelopmentPlaintext(
            plaintext_capability,
            allocator,
            identity,
        );
    } else {
        @compileError("unsupported exact-draft plaintext authority");
    }
}

pub fn loadRevisionProvenance(
    plaintext_capability: *const key_custody.SyntheticPlaintextTestCapability,
    repository: *store.Store,
    allocator: std.mem.Allocator,
    identity: draft.DraftIdentity,
    revision: draft.DraftRevision,
) Error!store.ExactDraftProvenanceLoad {
    try requirePlaintextAuthority(plaintext_capability);
    return repository.getExactDraftRevisionProvenance(
        plaintext_capability,
        allocator,
        identity,
        revision,
    );
}

pub fn loadRevisionProvenanceDevelopmentPlaintext(
    plaintext_capability: *const key_custody.DevelopmentPlaintextStorageCapability,
    repository: *store.Store,
    allocator: std.mem.Allocator,
    identity: draft.DraftIdentity,
    revision: draft.DraftRevision,
) Error!store.ExactDraftProvenanceLoad {
    try requirePlaintextAuthority(plaintext_capability);
    return repository.getExactDraftRevisionProvenanceDevelopmentPlaintext(
        plaintext_capability,
        allocator,
        identity,
        revision,
    );
}

/// Validates the latest immutable role bindings against the explicitly
/// supplied historical projection, then consumes the replayed engine
/// workspace into `out` only after UI recalculation, validation, ordered
/// occurrence, digest, and artifact parity all pass. Non-form validation
/// inputs come only from the selected revision's immutable receipt; this API
/// deliberately has no caller-supplied reopen-evidence parameter.
pub fn reopenStateInto(
    plaintext_capability: *const key_custody.SyntheticPlaintextTestCapability,
    out: *ui.State,
    loaded: *LoadedWorkspace,
    selected_shape: draft.PayloadShape,
    context: ui.FilingContext,
    historical_profile: *const projection.Snapshot,
    role_instances: []const RoleInstanceBinding,
) Error!ui.OpenStatus {
    return reopenStateIntoAuthorized(
        plaintext_capability,
        out,
        loaded,
        selected_shape,
        context,
        historical_profile,
        role_instances,
    );
}

/// Reopens an already-loaded development plaintext workspace only after exact
/// historical-profile and role-binding verification. Success consumes the
/// replayed workspace exactly as the synthetic path does.
pub fn reopenStateIntoDevelopmentPlaintext(
    plaintext_capability: *const key_custody.DevelopmentPlaintextStorageCapability,
    out: *ui.State,
    loaded: *LoadedWorkspace,
    selected_shape: draft.PayloadShape,
    context: ui.FilingContext,
    historical_profile: *const projection.Snapshot,
    role_instances: []const RoleInstanceBinding,
) Error!ui.OpenStatus {
    return reopenStateIntoAuthorized(
        plaintext_capability,
        out,
        loaded,
        selected_shape,
        context,
        historical_profile,
        role_instances,
    );
}

fn reopenStateIntoAuthorized(
    plaintext_capability: anytype,
    out: *ui.State,
    loaded: *LoadedWorkspace,
    selected_shape: draft.PayloadShape,
    context: ui.FilingContext,
    historical_profile: *const projection.Snapshot,
    role_instances: []const RoleInstanceBinding,
) Error!ui.OpenStatus {
    try requirePlaintextAuthority(plaintext_capability);
    if (!loaded.workspace_owned) {
        return error.LoadedWorkspaceAlreadyConsumed;
    }
    const persisted = loaded.currentPersistedRevision(
        selected_shape,
    ) orelse return error.SelectedShapeMissing;
    if (!historical_profile.effective_on.eql(
        try context.profileAsOf(),
    )) {
        return error.ProfileAsOfMismatch;
    }
    const expected_date = dateText(historical_profile.effective_on);
    if (!std.mem.eql(
        u8,
        persisted.profile_as_of,
        &expected_date,
    )) {
        return error.ProfileAsOfMismatch;
    }

    const supplied_profile_digest = try historicalProfileDigest(
        historical_profile,
    );
    if (!supplied_profile_digest.eql(
        &persisted.profile_snapshot_digest,
    )) {
        return error.HistoricalProfileDigestMismatch;
    }
    var expected_storage: [max_role_bindings]store.ExactDraftRoleBindingWrite = undefined;
    const expected_bindings = try buildRoleBindingWrites(
        historical_profile,
        role_instances,
        &expected_storage,
    );
    if (!ownedBindingsMatch(
        persisted.bindings,
        expected_bindings,
    )) {
        return error.PersistedBindingMismatch;
    }

    const status = try ui.State.reopenInto(
        out,
        loaded.allocator,
        &loaded.workspace,
        selected_shape,
        context,
        historical_profile,
        .{
            .validation_current_year = persisted.validation_evidence.validation_current_year,
            .spouse_tin_checksum = persisted.validation_evidence.spouse_tin_checksum,
        },
    );
    switch (status) {
        .opened => loaded.workspace_owned = false,
        .blocked => {},
    }
    return status;
}

pub fn listAlternateWorkspaces(
    plaintext_capability: *const key_custody.SyntheticPlaintextTestCapability,
    repository: *store.Store,
    allocator: std.mem.Allocator,
    filer_profile_id: []const u8,
    context: ui.FilingContext,
    excluding_workspace_id: ?draft.DraftWorkspaceId,
) Error!store.ExactDraftAlternateList {
    return listAlternateWorkspacesAuthorized(
        plaintext_capability,
        repository,
        allocator,
        filer_profile_id,
        context,
        excluding_workspace_id,
    );
}

pub fn listAlternateWorkspacesDevelopmentPlaintext(
    plaintext_capability: *const key_custody.DevelopmentPlaintextStorageCapability,
    repository: *store.Store,
    allocator: std.mem.Allocator,
    filer_profile_id: []const u8,
    context: ui.FilingContext,
    excluding_workspace_id: ?draft.DraftWorkspaceId,
) Error!store.ExactDraftAlternateList {
    return listAlternateWorkspacesAuthorized(
        plaintext_capability,
        repository,
        allocator,
        filer_profile_id,
        context,
        excluding_workspace_id,
    );
}

fn listAlternateWorkspacesAuthorized(
    plaintext_capability: anytype,
    repository: *store.Store,
    allocator: std.mem.Allocator,
    filer_profile_id: []const u8,
    context: ui.FilingContext,
    excluding_workspace_id: ?draft.DraftWorkspaceId,
) Error!store.ExactDraftAlternateList {
    try requirePlaintextAuthority(plaintext_capability);
    var key_storage = FilingKeyStorage.init(filer_profile_id, context);
    defer sensitive_memory.wipeValue(FilingKeyStorage, &key_storage);
    const filing_key = key_storage.borrowed(filer_profile_id);
    const Capability = @TypeOf(plaintext_capability);
    if (comptime Capability ==
        *const key_custody.SyntheticPlaintextTestCapability)
    {
        return repository.listExactDraftAlternates(
            plaintext_capability,
            allocator,
            filing_key,
            excluding_workspace_id,
        );
    } else if (comptime Capability ==
        *const key_custody.DevelopmentPlaintextStorageCapability)
    {
        return repository.listExactDraftAlternatesDevelopmentPlaintext(
            plaintext_capability,
            allocator,
            filing_key,
            excluding_workspace_id,
        );
    } else {
        @compileError("unsupported exact-draft plaintext authority");
    }
}

fn requirePlaintextAuthority(plaintext_capability: anytype) Error!void {
    const Capability = @TypeOf(plaintext_capability);
    if (comptime Capability ==
        *const key_custody.SyntheticPlaintextTestCapability)
    {
        return key_custody.requireSyntheticPlaintextForTest(
            plaintext_capability,
        );
    } else if (comptime Capability ==
        *const key_custody.DevelopmentPlaintextStorageCapability)
    {
        return key_custody.requireDevelopmentPlaintextStorage(
            plaintext_capability,
        );
    } else {
        @compileError("unsupported exact-draft plaintext authority");
    }
}

fn replayOwnedHistory(
    destination: *draft.DraftHistory,
    persisted: *const store.OwnedExactDraftHistory,
) Error!void {
    if (!destination.identity.eql(&persisted.draft_identity)) {
        return error.PersistedHistoryMismatch;
    }
    for (persisted.revisions) |*revision| {
        var values: [max_occurrences]draft.OccurrenceValue = undefined;
        defer sensitive_memory.wipeValue(
            [max_occurrences]draft.OccurrenceValue,
            &values,
        );
        if (revision.occurrences.len > values.len) {
            return error.PersistedHistoryMismatch;
        }
        for (revision.occurrences, 0..) |value, index| {
            values[index] = .{
                .ordinal = value.ordinal,
                .serialized_key = value.serialized_key,
                .same_key_occurrence = value.same_key_occurrence,
                .raw_value = value.raw_value,
                .normalized_value = value.normalized_value,
                .emitted_value = value.emitted_value,
            };
        }
        const replayed = try destination.replayPersistedRevision(.{
            .draft_identity = persisted.draft_identity,
            .revision = revision.revision,
            .parent_revision = revision.parent_revision,
            .schema = revision.schema,
            .occurrences = values[0..revision.occurrences.len],
            .profile_snapshot_digest = revision.profile_snapshot_digest,
            .transaction_state_digest = revision.transaction_state_digest,
            .ordered_values_digest = revision.ordered_values_digest,
            .validation_status = revision.validation_status,
            .artifact_status = revision.artifact_status,
        });
        if (!engineRevisionMatchesOwned(replayed, revision)) {
            return error.PersistedHistoryMismatch;
        }
    }
}

fn engineRevisionMatchesOwned(
    engine: *const draft.DraftSnapshot,
    owned: *const store.OwnedExactDraftRevision,
) bool {
    if (engine.revision.value != owned.revision.value or
        !optionalRevisionEql(
            engine.parent_revision,
            owned.parent_revision,
        ) or
        !schemaEql(&engine.schema, &owned.schema) or
        !engine.profile_snapshot_digest.eql(
            &owned.profile_snapshot_digest,
        ) or
        !engine.transaction_state_digest.eql(
            &owned.transaction_state_digest,
        ) or
        !engine.ordered_values_digest.eql(
            &owned.ordered_values_digest,
        ) or
        !std.meta.eql(
            engine.validation_status,
            owned.validation_status,
        ) or
        !std.meta.eql(
            engine.artifact_status,
            owned.artifact_status,
        ) or
        engine.occurrences.len != owned.occurrences.len)
    {
        return false;
    }
    for (engine.occurrences, owned.occurrences) |left, right| {
        if (left.ordinal != right.ordinal or
            left.same_key_occurrence != right.same_key_occurrence or
            !std.mem.eql(
                u8,
                left.serialized_key,
                right.serialized_key,
            ) or
            !std.mem.eql(u8, left.raw_value, right.raw_value) or
            !std.mem.eql(
                u8,
                left.normalized_value,
                right.normalized_value,
            ) or
            !std.mem.eql(
                u8,
                left.emitted_value,
                right.emitted_value,
            ))
        {
            return false;
        }
    }
    return true;
}

fn schemaEql(
    left: *const draft.SchemaBinding,
    right: *const draft.SchemaBinding,
) bool {
    return left.package_key.eql(&right.package_key) and
        left.package_digest.eql(&right.package_digest) and
        left.occurrence_manifest_digest.eql(
            &right.occurrence_manifest_digest,
        ) and
        left.exact_schema_digest.eql(&right.exact_schema_digest) and
        left.payload_shape == right.payload_shape and
        left.occurrence_count == right.occurrence_count and
        std.meta.eql(
            left.evidence_readiness,
            right.evidence_readiness,
        );
}

fn optionalRevisionEql(
    left: ?draft.DraftRevision,
    right: ?draft.DraftRevision,
) bool {
    if (left == null or right == null) return left == null and right == null;
    return left.?.value == right.?.value;
}

fn historicalProfileDigest(
    historical_profile: *const projection.Snapshot,
) Error!@TypeOf(evidence.package_key.canonicalDigest()) {
    const mapped_outcome = profile_mapping.mapProfileSnapshot(
        historical_profile.*,
    );
    return switch (mapped_outcome) {
        .blocked => error.HistoricalProfileBindingMismatch,
        .accepted => |accepted| blk: {
            var mapped = accepted;
            defer sensitive_memory.wipeValue(
                profile_mapping.ControlSnapshot,
                &mapped,
            );
            var editing = try workflow.Editing.init(&mapped);
            defer editing.deinit();
            const digests = try editing.transaction_state.digestBundle();
            break :blk digests.profile_snapshot;
        },
    };
}

fn buildRoleBindingWrites(
    profile: *const projection.Snapshot,
    supplied: []const RoleInstanceBinding,
    output: *[max_role_bindings]store.ExactDraftRoleBindingWrite,
) Error![]const store.ExactDraftRoleBindingWrite {
    if (supplied.len == 0 or supplied.len > output.len) {
        return error.InvalidRoleBinding;
    }
    var filer_count: usize = 0;
    var spouse_count: usize = 0;
    for (supplied, 0..) |binding, index| {
        switch (binding.role) {
            .filer => filer_count += 1,
            .spouse => spouse_count += 1,
            else => return error.InvalidRoleBinding,
        }
        if (binding.instance_id.len == 0 or
            binding.provenance.len == 0)
        {
            return error.InvalidRoleBinding;
        }
        for (supplied[index + 1 ..]) |other| {
            if (binding.role == other.role and
                std.mem.eql(
                    u8,
                    binding.instance_id,
                    other.instance_id,
                ))
            {
                return error.DuplicateRoleBinding;
            }
        }

        const historical = try provenanceForRole(profile, binding.role);
        output[index] = .{
            .role = @tagName(binding.role),
            .instance_id = binding.instance_id,
            .profile_id = historical.profile_id.asSlice(),
            .profile_revision_id = historical.revision_id.asSlice(),
            .profile_revision_sequence = historical.revision_sequence,
            // Retained physical column for pre-simplification history only.
            .business_activity_id = null,
            .provenance = binding.provenance,
        };
    }
    if (filer_count != 1) return error.MissingFilerBinding;
    if (spouse_count > 1) return error.InvalidRoleBinding;

    const profile_has_spouse = profileRolePresent(profile, .spouse);
    if (profile_has_spouse and spouse_count == 0) {
        return error.MissingSpouseBinding;
    }
    if (!profile_has_spouse and spouse_count != 0) {
        return error.UnexpectedSpouseBinding;
    }
    return output[0..supplied.len];
}

fn provenanceForRole(
    profile: *const projection.Snapshot,
    role: ids.Role,
) Error!*const projection.Provenance {
    var representative: ?*const projection.Provenance = null;
    for (profile.slice()) |*entry| {
        if (entry.role != role) continue;
        if (representative) |prior| {
            if (!prior.profile_id.eql(
                &entry.provenance.profile_id,
            ) or
                !prior.revision_id.eql(
                    &entry.provenance.revision_id,
                ) or
                prior.revision_sequence !=
                    entry.provenance.revision_sequence)
            {
                return error.HistoricalProfileBindingMismatch;
            }
        } else {
            representative = &entry.provenance;
        }
    }
    return representative orelse
        error.HistoricalProfileBindingMismatch;
}

fn profileRolePresent(
    profile: *const projection.Snapshot,
    role: ids.Role,
) bool {
    for (profile.slice()) |entry| {
        if (entry.role == role) return true;
    }
    return false;
}

fn filerProfileId(
    bindings: []const store.ExactDraftRoleBindingWrite,
) ?[]const u8 {
    for (bindings) |binding| {
        if (std.mem.eql(u8, binding.role, "filer")) {
            return binding.profile_id;
        }
    }
    return null;
}

fn buildOccurrenceContexts(
    snapshot: *const draft.DraftSnapshot,
    output: *[max_occurrences]store.ExactDraftOccurrenceContextWrite,
) Error![]const store.ExactDraftOccurrenceContextWrite {
    const manifest = switch (snapshot.schema.payload_shape) {
        .editable_save => try occurrences.editableManifest(),
        .final_copy_plaintext => try occurrences.finalCopyManifest(),
    };
    if (manifest.items.len != snapshot.occurrences.len or
        manifest.items.len > output.len)
    {
        return error.PersistedOccurrenceContextMismatch;
    }
    for (manifest.items, snapshot.occurrences, 0..) |
        metadata,
        value,
        index,
    | {
        if (metadata.ordinal != value.ordinal or
            metadata.same_key_occurrence !=
                value.same_key_occurrence or
            !std.mem.eql(
                u8,
                metadata.serialized_key,
                value.serialized_key,
            ))
        {
            return error.PersistedOccurrenceContextMismatch;
        }
        const origin = try occurrenceOrigin(metadata);
        output[index] = .{
            .ordinal = value.ordinal,
            .origin = origin,
            .provenance = occurrenceProvenance(origin),
        };
    }
    return output[0..manifest.items.len];
}

fn occurrenceOrigin(
    metadata: occurrence.OccurrenceMetadata,
) Error!occurrence.OriginKind {
    var result: ?occurrence.OriginKind = null;
    for (0..metadata.source_controls.len()) |source_index| {
        const control_id = metadata.source_controls.at(
            @intCast(source_index),
        ).?;
        const candidate = transaction.classifyControl(control_id) orelse
            return error.PersistedOccurrenceContextMismatch;
        if (result) |prior| {
            if (prior != candidate) {
                return error.PersistedOccurrenceContextMismatch;
            }
        } else {
            result = candidate;
        }
    }
    return result orelse error.PersistedOccurrenceContextMismatch;
}

fn occurrenceProvenance(origin: occurrence.OriginKind) []const u8 {
    return switch (origin) {
        .profile => "immutable_profile_revision_binding",
        .transaction => "form_transaction",
        .preparer => "credential_locked_empty",
        .filing_context => "explicit_filing_context",
        .external_evidence => "historical_external_evidence",
        .derived => "grounded_calculation",
        .system => "grounded_runtime_system_value",
        .unreviewed => unreachable,
    };
}

fn ownedBindingsMatch(
    owned: []const store.OwnedExactDraftRoleBinding,
    expected: []const store.ExactDraftRoleBindingWrite,
) bool {
    if (owned.len != expected.len) return false;
    for (expected) |right| {
        const left = findOwnedBinding(
            owned,
            right.role,
            right.instance_id,
        ) orelse return false;
        if (!std.mem.eql(u8, left.profile_id, right.profile_id) or
            !std.mem.eql(
                u8,
                left.profile_revision_id,
                right.profile_revision_id,
            ) or
            left.profile_revision_sequence !=
                right.profile_revision_sequence or
            // Current exact provenance writes NULL. A historical component
            // binding is not silently coerced into the simplified model.
            left.business_activity_id != null or
            right.business_activity_id != null or
            !std.mem.eql(u8, left.provenance, right.provenance))
        {
            return false;
        }
    }
    return true;
}

fn findOwnedBinding(
    bindings: []const store.OwnedExactDraftRoleBinding,
    role: []const u8,
    instance_id: []const u8,
) ?*const store.OwnedExactDraftRoleBinding {
    for (bindings) |*binding| {
        if (std.mem.eql(u8, binding.role, role) and
            std.mem.eql(u8, binding.instance_id, instance_id))
        {
            return binding;
        }
    }
    return null;
}

fn optionalTextEql(
    left: ?[]const u8,
    right: ?[]const u8,
) bool {
    if (left == null or right == null) return left == null and right == null;
    return std.mem.eql(u8, left.?, right.?);
}

const FilingKeyStorage = struct {
    period_key: [7]u8,
    intent: store.FilingIntent,

    fn init(
        filer_profile_id: []const u8,
        context: ui.FilingContext,
    ) FilingKeyStorage {
        _ = filer_profile_id;
        const year = context.tax_year;
        return .{
            .period_key = .{
                @intCast('0' + (year / 1000) % 10),
                @intCast('0' + (year / 100) % 10),
                @intCast('0' + (year / 10) % 10),
                @intCast('0' + year % 10),
                '-',
                'Q',
                @as(u8, '0') +
                    @as(u8, @intFromEnum(context.quarter)),
            },
            .intent = if (context.amended) .amended else .original,
        };
    }

    fn borrowed(
        self: *const FilingKeyStorage,
        filer_profile_id: []const u8,
    ) store.CanonicalFilingBusinessKeyWrite {
        return .{
            .filer_profile_id = filer_profile_id,
            .form_code = evidence.package_key.revision.code.asSlice(),
            .form_revision = evidence.package_key.revision.revision.asSlice(),
            .period_key = &self.period_key,
            .intent = self.intent,
        };
    }
};

fn filingKeyEql(
    left: store.CanonicalFilingBusinessKeyWrite,
    right: store.CanonicalFilingBusinessKeyWrite,
) bool {
    return std.mem.eql(
        u8,
        left.filer_profile_id,
        right.filer_profile_id,
    ) and
        std.mem.eql(u8, left.form_code, right.form_code) and
        std.mem.eql(
            u8,
            left.form_revision,
            right.form_revision,
        ) and
        std.mem.eql(u8, left.period_key, right.period_key) and
        left.intent == right.intent;
}

fn dateText(value: model.Date) store.DateText {
    return .{
        @intCast('0' + (value.year / 1000) % 10),
        @intCast('0' + (value.year / 100) % 10),
        @intCast('0' + (value.year / 10) % 10),
        @intCast('0' + value.year % 10),
        '-',
        @intCast('0' + (value.month / 10) % 10),
        @intCast('0' + value.month % 10),
        '-',
        @intCast('0' + (value.day / 10) % 10),
        @intCast('0' + value.day % 10),
    };
}

// -------------------------------------------------------------------------
// Exact persistence/reopen tests.

fn syntheticPlaintextTestCapability() *const key_custody.SyntheticPlaintextTestCapability {
    return key_custody.acquireSyntheticPlaintextForTest();
}

fn developmentPlaintextCapability() *const key_custody.DevelopmentPlaintextStorageCapability {
    return key_custody.bootstrapCurrentArtifactStorage().development_plaintext;
}

fn testHistoricalProfile(
    revision_id: []const u8,
    email: []const u8,
    effective_on: model.Date,
) !projection.Snapshot {
    var snapshot = projection.Snapshot.init(form.revision, effective_on);
    const provenance: projection.Provenance = .{
        .profile_id = try model.ProfileId.parse(
            "persistence-synthetic-filer",
        ),
        .revision_id = try model.RevisionId.parse(revision_id),
        .revision_sequence = if (std.mem.endsWith(
            u8,
            revision_id,
            "r2",
        ))
            2
        else
            1,
        .revision_source = .manual_entry,
    };
    try snapshot.append(.{
        .role = .filer,
        .target = form.filer_requirements[0].target,
        .value = .{ .tin = try field.Tin.parse("123-456-789-000") },
        .provenance = provenance,
    });
    try snapshot.append(.{
        .role = .filer,
        .target = form.filer_requirements[1].target,
        .value = .{ .rdo_code = try field.RdoCode.parse("019") },
        .provenance = provenance,
    });
    try snapshot.append(.{
        .role = .filer,
        .target = form.filer_requirements[2].target,
        .value = .{
            .taxpayer_name = try field.TaxpayerName.parse(
                "PERSISTENCE SYNTHETIC FILER",
            ),
        },
        .provenance = provenance,
    });
    try snapshot.append(.{
        .role = .filer,
        .target = form.filer_requirements[3].target,
        .value = .{
            .registered_address = try field.RegisteredAddress.parse(
                "SYNTHETIC PERSISTENCE ADDRESS",
            ),
        },
        .provenance = provenance,
    });
    try snapshot.append(.{
        .role = .filer,
        .target = form.filer_requirements[4].target,
        .value = .{ .zip_code = try field.ZipCode.parse("1000") },
        .provenance = provenance,
    });
    try snapshot.append(.{
        .role = .filer,
        .target = form.filer_requirements[5].target,
        .value = .{
            .date_of_birth = try model.Date.init(1990, 1, 15),
        },
        .provenance = provenance,
    });
    try snapshot.append(.{
        .role = .filer,
        .target = form.filer_requirements[6].target,
        .value = .{
            .email_address = try field.EmailAddress.parse(email),
        },
        .provenance = provenance,
    });
    return snapshot;
}

fn testMixedHistoricalProfile(
    revision_id: []const u8,
    effective_on: model.Date,
) !projection.Snapshot {
    var snapshot = try testHistoricalProfile(
        revision_id,
        "Synthetic.R1@Example.Test",
        effective_on,
    );
    for (snapshot.entries[0..snapshot.len]) |*entry| {
        if (entry.target.eql(&form.filer_requirements[2].target)) {
            entry.value = .{
                .taxpayer_name = try field.TaxpayerName.parse(
                    "Persistence Synthetic Filer",
                ),
            };
        } else if (entry.target.eql(
            &form.filer_requirements[3].target,
        )) {
            entry.value = .{
                .registered_address = try field.RegisteredAddress.parse(
                    "Synthetic Persistence Address",
                ),
            };
        }
    }
    try snapshot.append(.{
        .role = .filer,
        .target = form.filer_requirements[7].target,
        .value = .{
            .citizenship = try field.Citizenship.parse("Filipino"),
        },
        .provenance = snapshot.entries[0].provenance,
    });
    return snapshot;
}

fn expectRevealedControlText(
    state: *ui.State,
    control_id: []const u8,
    expected: []const u8,
) !void {
    try state.setControlRevealed(control_id, true);
    defer state.setControlRevealed(control_id, false) catch {};
    switch ((try state.control(control_id)).display) {
        .revealed_text => |actual| {
            try std.testing.expectEqualStrings(expected, actual);
        },
        else => return error.ExpectedRevealedControlText,
    }
}

const test_context: ui.FilingContext = .{
    .tax_year = 2025,
    .quarter = .first,
    .amended = false,
};

const test_role_instances = [_]RoleInstanceBinding{.{
    .role = .filer,
    .instance_id = "synthetic-filer-instance",
}};

fn openSyntheticState(
    out: *ui.State,
    allocator: std.mem.Allocator,
    workspace_id: draft.DraftWorkspaceId,
    profile: *const projection.Snapshot,
) !void {
    switch (try ui.State.openInto(
        out,
        allocator,
        workspace_id,
        test_context,
        profile,
    )) {
        .opened => {},
        .blocked => return error.UnexpectedProfileMappingBlock,
    }
}

fn selectRequiredSyntheticElections(state: *ui.State) !void {
    try state.setRadio("frm1701q:optType_1", true);
    try state.setRadio("frm1701q:optATC_1", true);
    try state.setRadio("frm1701q:optTaxRate_1", true);
    try state.setRadio(
        "frm1701q:optMethodOfDeduction:_1",
        true,
    );
}

fn savePassed(state: *ui.State) !void {
    switch (try state.validateSave(2026, .not_evaluated)) {
        .passed => {},
        .failed => return error.ExpectedSavePass,
    }
}

fn fullPassed(state: *ui.State) !void {
    switch (try state.validateFull()) {
        .passed => {},
        .failed, .blocked => return error.ExpectedFullPass,
    }
}

fn seedSyntheticProfileRepository(repository: *store.Store) !void {
    try repository.createProfileWithRevision(
        .{ .id = "persistence-synthetic-filer" },
        .{
            .id = "persistence-synthetic-filer-r1",
            .profile_id = "persistence-synthetic-filer",
            .sequence = 1,
            .expected_current_sequence = 0,
            .effective = .{
                .from = dateText(try model.Date.init(2020, 1, 1)),
            },
            .source = .manual_entry,
            .identity = .{
                .tin = "123-456-789-000",
                .rdo_code = "019",
            },
            .contact = .{
                .registered_address = "SYNTHETIC PERSISTENCE ADDRESS",
                .zip_code = "1000",
                .contact_number = "+639171234567",
                .email_address = "synthetic-r1@example.test",
            },
            .accounting_period_basis = .calendar,
            .subject = .{ .individual = .{
                .name = "PERSISTENCE SYNTHETIC FILER",
                .date_of_birth = dateText(
                    try model.Date.init(1990, 1, 15),
                ),
                .citizenship = "Filipino",
            } },
        },
    );
}

fn expectCandidateSummaryEqual(
    left: ui.CandidateSummary,
    right: ui.CandidateSummary,
) !void {
    try std.testing.expectEqual(left.shape, right.shape);
    try std.testing.expectEqual(left.exactness, right.exactness);
    try std.testing.expectEqual(left.byte_length, right.byte_length);
    try std.testing.expectEqualSlices(u8, &left.sha256, &right.sha256);
}

fn annualSelectionProvenance(
    rate: year_settings.IncomeTaxRateElection,
    deduction: ?year_settings.DeductionMethod,
) draft_provenance.DraftProvenance {
    var result: draft_provenance.DraftProvenance = undefined;
    result.source_snapshot_count = 1;
    result.source_snapshots_storage[0] = .{
        .key = .{ .taxpayer_year_setting = .{
            .role = .filer,
            .key = .income_tax_rate_election,
        } },
        .copied_value = .{ .income_tax_rate_election = rate },
    };
    if (deduction) |method| {
        result.source_snapshots_storage[1] = .{
            .key = .{ .taxpayer_year_setting = .{
                .role = .filer,
                .key = .deduction_method,
            } },
            .copied_value = .{ .deduction_method = method },
        };
        result.source_snapshot_count = 2;
    }
    return result;
}

test "exact persistence boundary is development-only plaintext and has no submission surface" {
    try std.testing.expect(!synthetic_test_only_at_rest);
    try std.testing.expect(development_plaintext_at_rest);
    try std.testing.expectEqual(
        key_custody.PlaintextStorageState.synthetic_plaintext_test_only,
        SecurityBoundary.plaintext_storage_state,
    );
    try std.testing.expectEqual(
        key_custody.ArtifactStorageClassification
            .development_only_plaintext_not_production,
        SecurityBoundary.development_storage_classification,
    );
    try std.testing.expectEqual(
        key_custody.ProductionStorageState
            .unavailable_authenticated_storage_backend_unselected,
        SecurityBoundary.production_storage_state,
    );
    try std.testing.expectError(
        error.ProductionStorageUnavailable,
        key_custody.requireProductionStorage(),
    );
    try std.testing.expect(
        SecurityBoundary.synthetic_plaintext_persistence_enabled,
    );
    try std.testing.expect(
        SecurityBoundary.development_plaintext_persistence_enabled,
    );
    try std.testing.expect(SecurityBoundary.sqlite_values_are_plaintext);
    try std.testing.expect(SecurityBoundary.development_only);
    try std.testing.expect(!SecurityBoundary.synthetic_test_only);
    try std.testing.expect(
        !SecurityBoundary.production_key_custody_qualified,
    );
    try std.testing.expect(
        !SecurityBoundary.outbound_encryption_enabled,
    );
    try std.testing.expect(!SecurityBoundary.transport_enabled);
    try std.testing.expect(!@hasDecl(@This(), "submit"));
    try std.testing.expect(!@hasDecl(@This(), "encrypt"));
    try std.testing.expect(!@hasDecl(@This(), "upload"));
}

test "strict exact persistence validates filer annual controls against frozen taxpayer-year sources" {
    const allocator = std.testing.allocator;
    var repository = try store.Store.openMemory(allocator);
    defer repository.close();
    var profile = try testMixedHistoricalProfile(
        "persistence-synthetic-filer-r1",
        try test_context.profileAsOf(),
    );
    var state: ui.State = undefined;
    try openSyntheticState(
        &state,
        allocator,
        try repository.generateDraftWorkspaceId(),
        &profile,
    );
    defer state.deinit();
    try selectRequiredSyntheticElections(&state);

    const graduated_itemized = annualSelectionProvenance(
        .graduated,
        .itemized_deduction,
    );
    try validateFilerAnnualSelections(&state, &graduated_itemized);

    const graduated_osd = annualSelectionProvenance(
        .graduated,
        .optional_standard_deduction,
    );
    try std.testing.expectError(
        error.ExactAnnualSelectionMismatch,
        validateFilerAnnualSelections(&state, &graduated_osd),
    );

    // The exact legacy interaction derives Item 16 from the chosen ATC. Use a
    // fresh state so this assertion is about an eight-percent workspace, not
    // the separate legacy transition from a previously chosen deduction.
    var eight_state: ui.State = undefined;
    try openSyntheticState(
        &eight_state,
        allocator,
        try repository.generateDraftWorkspaceId(),
        &profile,
    );
    defer eight_state.deinit();
    try eight_state.setRadio("frm1701q:optType_1", true);
    try eight_state.setRadio("frm1701q:optATC_4", true);
    const eight_percent = annualSelectionProvenance(
        .eight_percent,
        null,
    );
    try validateFilerAnnualSelections(&eight_state, &eight_percent);
    const invalid_eight_percent = annualSelectionProvenance(
        .eight_percent,
        .itemized_deduction,
    );
    try std.testing.expectError(
        error.UnexpectedFilerDeductionMethodSource,
        validateFilerAnnualSelections(&eight_state, &invalid_eight_percent),
    );
}

test "development exact persistence APIs require the explicit development capability" {
    const persist = @typeInfo(
        @TypeOf(persistCurrentCandidateDevelopmentPlaintext),
    ).@"fn";
    const load = @typeInfo(
        @TypeOf(loadWorkspaceIntoDevelopmentPlaintext),
    ).@"fn";
    const reopen = @typeInfo(
        @TypeOf(reopenStateIntoDevelopmentPlaintext),
    ).@"fn";
    const alternates = @typeInfo(
        @TypeOf(listAlternateWorkspacesDevelopmentPlaintext),
    ).@"fn";
    inline for (.{ persist, load, reopen, alternates }) |api| {
        try std.testing.expect(
            api.params[0].type.? ==
                *const key_custody.DevelopmentPlaintextStorageCapability,
        );
        try std.testing.expect(
            api.params[0].type.? !=
                *const key_custody.ProductionStorageCapability,
        );
    }
}

test "development exact persistence round trip resumes and lists alternate workspaces without a coarse draft" {
    const allocator = std.testing.allocator;
    const plaintext_capability = developmentPlaintextCapability();
    var repository = try store.Store.openMemory(allocator);
    defer repository.close();
    try seedSyntheticProfileRepository(&repository);

    var profile = try testMixedHistoricalProfile(
        "persistence-synthetic-filer-r1",
        try test_context.profileAsOf(),
    );
    defer sensitive_memory.wipeValue(projection.Snapshot, &profile);
    const qualified_blur_context: ui.QualifiedBlurContext = .{
        .current_year = 2026,
        .schedule_date = .{
            .current_date = .{ .year = 2026, .month = 7, .day = 30 },
            .empty_default_input_was_later = false,
        },
    };

    const workspace_id = try repository.generateDraftWorkspaceId();
    var original: ui.State = undefined;
    try openSyntheticState(
        &original,
        allocator,
        workspace_id,
        &profile,
    );
    defer original.deinit();
    try selectRequiredSyntheticElections(&original);
    _ = try original.commitAndBlurQualified(
        "frm1701q:txtSheets",
        "1",
        qualified_blur_context,
    );
    try original.calculate();
    try savePassed(&original);
    try original.generateEditableCandidate(.create);
    const first_snapshot = try original.candidateSnapshot();
    const first_receipt = try persistCurrentCandidateDevelopmentPlaintext(
        plaintext_capability,
        &repository,
        &original,
        .{
            .historical_profile = &profile,
            .role_instances = &test_role_instances,
            .recorded_at_unix_seconds = 1_750_100_001,
            .guard = .create,
        },
    );

    var first_loaded: LoadedWorkspace = undefined;
    try loadWorkspaceIntoDevelopmentPlaintext(
        plaintext_capability,
        &first_loaded,
        &repository,
        allocator,
        workspace_id,
        "persistence-synthetic-filer",
        test_context,
    );
    defer first_loaded.deinit();
    const first_persisted = first_loaded.currentPersistedRevision(
        .editable_save,
    ).?;
    try std.testing.expect(first_persisted.profile_snapshot_digest.eql(
        &first_snapshot.profile_snapshot_digest,
    ));
    try std.testing.expect(first_persisted.transaction_state_digest.eql(
        &first_snapshot.transaction_state_digest,
    ));
    try std.testing.expect(first_persisted.ordered_values_digest.eql(
        &first_snapshot.ordered_values_digest,
    ));
    try std.testing.expectEqualStrings(
        "historical_profile_projection",
        first_persisted.bindings[0].provenance,
    );
    var saw_profile_provenance = false;
    var saw_transaction_provenance = false;
    for (first_persisted.occurrences) |value| {
        switch (value.origin) {
            .profile => {
                try std.testing.expectEqualStrings(
                    "immutable_profile_revision_binding",
                    value.provenance,
                );
                saw_profile_provenance = true;
            },
            .transaction => {
                try std.testing.expectEqualStrings(
                    "form_transaction",
                    value.provenance,
                );
                saw_transaction_provenance = true;
            },
            else => {},
        }
    }
    try std.testing.expect(saw_profile_provenance);
    try std.testing.expect(saw_transaction_provenance);

    var resumed: ui.State = undefined;
    switch (try reopenStateIntoDevelopmentPlaintext(
        plaintext_capability,
        &resumed,
        &first_loaded,
        .editable_save,
        test_context,
        &profile,
        &test_role_instances,
    )) {
        .opened => {},
        .blocked => return error.UnexpectedProfileMappingBlock,
    }
    defer resumed.deinit();
    _ = try resumed.commitAndBlurQualified(
        "frm1701q:txtSheets",
        "2",
        qualified_blur_context,
    );
    try resumed.calculate();
    try savePassed(&resumed);
    try resumed.generateEditableCandidate(.{
        .match = first_receipt.revision,
    });
    const resumed_summary = try resumed.candidateSummary();
    const second_receipt = try persistCurrentCandidateDevelopmentPlaintext(
        plaintext_capability,
        &repository,
        &resumed,
        .{
            .historical_profile = &profile,
            .role_instances = &test_role_instances,
            .recorded_at_unix_seconds = 1_750_100_002,
            .guard = .{ .match = first_receipt.revision },
        },
    );
    try std.testing.expectEqual(@as(u64, 2), second_receipt.revision.value);
    try std.testing.expectEqual(
        @as(u64, 1),
        second_receipt.parent_revision.?.value,
    );

    var resumed_history = (try repository
        .getExactDraftHistoryDevelopmentPlaintext(
        plaintext_capability,
        allocator,
        second_receipt.draft_identity,
    )).?;
    defer resumed_history.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 2), resumed_history.revisions.len);
    const editable_manifest = try occurrences.editableManifest();
    const expected_sheets = editable_manifest.findKeyOccurrence(
        "frm1701q:txtSheets",
        1,
    ).?;
    const resumed_sheets = blk: {
        for (resumed_history.revisions[1].occurrences) |*value| {
            if (value.same_key_occurrence ==
                expected_sheets.same_key_occurrence and
                std.mem.eql(
                    u8,
                    value.serialized_key,
                    expected_sheets.serialized_key,
                ))
            {
                break :blk value;
            }
        }
        return error.ExpectedPersistedSchedulesCount;
    };
    try std.testing.expectEqual(expected_sheets.ordinal, resumed_sheets.ordinal);
    try std.testing.expectEqualStrings(
        "frm1701q:txtSheets",
        resumed_sheets.serialized_key,
    );
    try std.testing.expectEqual(
        @as(u16, 1),
        resumed_sheets.same_key_occurrence,
    );
    try std.testing.expectEqualStrings(
        "2",
        resumed_sheets.raw_value,
    );
    try std.testing.expectEqual(
        occurrence.OriginKind.filing_context,
        resumed_sheets.origin,
    );
    try std.testing.expectEqualStrings(
        "explicit_filing_context",
        resumed_sheets.provenance,
    );

    const alternate_workspace_id = try repository.generateDraftWorkspaceId();
    var alternate: ui.State = undefined;
    try openSyntheticState(
        &alternate,
        allocator,
        alternate_workspace_id,
        &profile,
    );
    defer alternate.deinit();
    try selectRequiredSyntheticElections(&alternate);
    try alternate.calculate();
    try savePassed(&alternate);
    try alternate.generateEditableCandidate(.create);
    _ = try persistCurrentCandidateDevelopmentPlaintext(
        plaintext_capability,
        &repository,
        &alternate,
        .{
            .historical_profile = &profile,
            .role_instances = &test_role_instances,
            .recorded_at_unix_seconds = 1_750_100_003,
            .guard = .create,
        },
    );

    var alternates = try listAlternateWorkspacesDevelopmentPlaintext(
        plaintext_capability,
        &repository,
        allocator,
        "persistence-synthetic-filer",
        test_context,
        workspace_id,
    );
    defer alternates.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 1), alternates.items.len);
    try std.testing.expect(alternates.items[0].workspace_id.eql(
        &alternate_workspace_id,
    ));
    try std.testing.expectEqual(@as(u32, 1), alternates.items[0].schema_stream_count);

    var reloaded: LoadedWorkspace = undefined;
    try loadWorkspaceIntoDevelopmentPlaintext(
        plaintext_capability,
        &reloaded,
        &repository,
        allocator,
        workspace_id,
        "persistence-synthetic-filer",
        test_context,
    );
    defer reloaded.deinit();
    try std.testing.expectEqual(
        @as(usize, 2),
        reloaded.revisionCount(.editable_save),
    );
    var reopened: ui.State = undefined;
    switch (try reopenStateIntoDevelopmentPlaintext(
        plaintext_capability,
        &reopened,
        &reloaded,
        .editable_save,
        test_context,
        &profile,
        &test_role_instances,
    )) {
        .opened => {},
        .blocked => return error.UnexpectedProfileMappingBlock,
    }
    defer reopened.deinit();
    try expectCandidateSummaryEqual(
        resumed_summary,
        try reopened.candidateSummary(),
    );

    // The exact 1701Q path is deliberately disjoint from the coarse draft
    // aggregate and its v17 provenance sidecar.
    var coarse = try repository.listDraftSummariesForProfile(
        allocator,
        "persistence-synthetic-filer",
        2025,
    );
    defer coarse.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), coarse.items.len);
}

test "editable and Final sibling streams persist, replay, and reopen exactly" {
    const allocator = std.testing.allocator;
    var repository = try store.Store.openMemory(allocator);
    defer repository.close();
    try seedSyntheticProfileRepository(&repository);

    var profile = try testMixedHistoricalProfile(
        "persistence-synthetic-filer-r1",
        try test_context.profileAsOf(),
    );
    defer sensitive_memory.wipeValue(projection.Snapshot, &profile);
    const workspace_id = try repository.generateDraftWorkspaceId();

    var state: ui.State = undefined;
    try openSyntheticState(
        &state,
        allocator,
        workspace_id,
        &profile,
    );
    defer state.deinit();
    try selectRequiredSyntheticElections(&state);
    const qualified_blur_context: ui.QualifiedBlurContext = .{
        .current_year = 2026,
        .schedule_date = .{
            .current_date = .{ .year = 2026, .month = 7, .day = 30 },
            .empty_default_input_was_later = false,
        },
    };
    _ = try state.commitAndBlurQualified(
        "frm1701q:txtSheets",
        "2",
        qualified_blur_context,
    );
    _ = try state.commitAndBlurQualified(
        "frm1701q:txt36A",
        "123.45",
        qualified_blur_context,
    );
    try expectRevealedControlText(
        &state,
        "frm1701q:txtTaxpayerName",
        "PERSISTENCE SYNTHETIC FILER",
    );
    try expectRevealedControlText(
        &state,
        "frm1701q:txtAddress",
        "SYNTHETIC PERSISTENCE ADDRESS",
    );
    try expectRevealedControlText(
        &state,
        "frm1701q:txtCitizenship",
        "FILIPINO",
    );
    try expectRevealedControlText(
        &state,
        "txtEmail",
        "Synthetic.R1@Example.Test",
    );
    try state.calculate();
    try savePassed(&state);
    try state.generateEditableCandidate(.create);
    const editable_summary = try state.candidateSummary();
    const editable_receipt = try persistCurrentCandidate(
        syntheticPlaintextTestCapability(),
        &repository,
        &state,
        .{
            .historical_profile = &profile,
            .role_instances = &test_role_instances,
            .recorded_at_unix_seconds = 1_750_000_001,
            .guard = .create,
        },
    );
    try std.testing.expectEqual(
        draft.PayloadShape.editable_save,
        editable_receipt.shape,
    );

    try fullPassed(&state);
    try state.generateFinalCandidate(.create);
    const final_summary = try state.candidateSummary();
    const final_receipt = try persistCurrentCandidate(
        syntheticPlaintextTestCapability(),
        &repository,
        &state,
        .{
            .historical_profile = &profile,
            .role_instances = &test_role_instances,
            .recorded_at_unix_seconds = 1_750_000_002,
            .guard = .create,
        },
    );
    try std.testing.expect(
        editable_receipt.draft_identity.workspace_id.eql(
            &final_receipt.draft_identity.workspace_id,
        ),
    );
    try std.testing.expect(
        !editable_receipt.draft_identity.exact_schema_digest.eql(
            &final_receipt.draft_identity.exact_schema_digest,
        ),
    );

    var loaded: LoadedWorkspace = undefined;
    try loadWorkspaceInto(
        syntheticPlaintextTestCapability(),
        &loaded,
        &repository,
        allocator,
        workspace_id,
        "persistence-synthetic-filer",
        test_context,
    );
    defer loaded.deinit();
    try std.testing.expectEqual(
        @as(usize, 1),
        loaded.revisionCount(.editable_save),
    );
    try std.testing.expectEqual(
        @as(usize, 1),
        loaded.revisionCount(.final_copy_plaintext),
    );
    const persisted_editable = loaded.currentPersistedRevision(
        .editable_save,
    ).?;
    const persisted_final = loaded.currentPersistedRevision(
        .final_copy_plaintext,
    ).?;
    try std.testing.expect(std.meta.eql(
        persisted_editable.validation_evidence,
        persisted_final.validation_evidence,
    ));
    try std.testing.expectEqual(
        @as(usize, 173),
        persisted_final.occurrences.len,
    );
    try std.testing.expectEqual(
        @as(i64, 1_750_000_002),
        persisted_final.recorded_at_unix_seconds,
    );
    try std.testing.expectEqual(
        @as(i32, 2026),
        persisted_final.validation_evidence.validation_current_year,
    );
    try std.testing.expectEqual(
        validation.TinChecksumStatus.not_evaluated,
        persisted_final.validation_evidence.spouse_tin_checksum,
    );
    try std.testing.expectEqualStrings(
        "2025-03-31",
        persisted_final.profile_as_of,
    );
    try std.testing.expectEqualStrings(
        "persistence-synthetic-filer-r1",
        persisted_final.bindings[0].profile_revision_id,
    );
    try std.testing.expectEqualStrings(
        "synthetic-filer-instance",
        persisted_final.bindings[0].instance_id,
    );
    for (persisted_final.occurrences) |value| {
        try std.testing.expect(value.origin != .unreviewed);
        try std.testing.expect(value.provenance.len != 0);
    }
    // The caveat is observable and permanent: values are plaintext.
    var saw_synthetic_value = false;
    for (persisted_final.occurrences) |value| {
        if (std.mem.eql(u8, value.raw_value, "123.45")) {
            saw_synthetic_value = true;
            break;
        }
    }
    try std.testing.expect(saw_synthetic_value);

    var forged_token: u8 = 0;
    const forged: *const key_custody.SyntheticPlaintextTestCapability =
        @ptrCast(&forged_token);
    var rejected_reopen: ui.State = undefined;
    try std.testing.expectError(
        error.InvalidSyntheticPlaintextTestCapability,
        reopenStateInto(
            forged,
            &rejected_reopen,
            &loaded,
            .final_copy_plaintext,
            test_context,
            &profile,
            &test_role_instances,
        ),
    );
    try std.testing.expect(loaded.workspace_owned);

    var reopened: ui.State = undefined;
    switch (try reopenStateInto(
        syntheticPlaintextTestCapability(),
        &reopened,
        &loaded,
        .final_copy_plaintext,
        test_context,
        &profile,
        &test_role_instances,
    )) {
        .opened => {},
        .blocked => return error.UnexpectedProfileMappingBlock,
    }
    defer reopened.deinit();
    try std.testing.expectEqual(ui.Phase.final_candidate, reopened.phase());
    try expectCandidateSummaryEqual(
        final_summary,
        try reopened.candidateSummary(),
    );
    try std.testing.expectEqual(
        @as(usize, 1),
        reopened.editableRevisionCount(),
    );
    try std.testing.expectEqual(
        @as(usize, 1),
        reopened.finalRevisionCount(),
    );
    try expectRevealedControlText(
        &reopened,
        "frm1701q:txtTaxpayerName",
        "PERSISTENCE SYNTHETIC FILER",
    );
    try expectRevealedControlText(
        &reopened,
        "frm1701q:txtAddress",
        "SYNTHETIC PERSISTENCE ADDRESS",
    );
    try expectRevealedControlText(
        &reopened,
        "frm1701q:txtCitizenship",
        "FILIPINO",
    );
    try expectRevealedControlText(
        &reopened,
        "txtEmail",
        "Synthetic.R1@Example.Test",
    );

    var loaded_editable: LoadedWorkspace = undefined;
    try loadWorkspaceInto(
        syntheticPlaintextTestCapability(),
        &loaded_editable,
        &repository,
        allocator,
        workspace_id,
        "persistence-synthetic-filer",
        test_context,
    );
    defer loaded_editable.deinit();
    var reopened_editable: ui.State = undefined;
    switch (try reopenStateInto(
        syntheticPlaintextTestCapability(),
        &reopened_editable,
        &loaded_editable,
        .editable_save,
        test_context,
        &profile,
        &test_role_instances,
    )) {
        .opened => {},
        .blocked => return error.UnexpectedProfileMappingBlock,
    }
    defer reopened_editable.deinit();
    try expectCandidateSummaryEqual(
        editable_summary,
        try reopened_editable.candidateSummary(),
    );
    try expectRevealedControlText(
        &reopened_editable,
        "frm1701q:txtTaxpayerName",
        "PERSISTENCE SYNTHETIC FILER",
    );
    try expectRevealedControlText(
        &reopened_editable,
        "frm1701q:txtAddress",
        "SYNTHETIC PERSISTENCE ADDRESS",
    );
    try expectRevealedControlText(
        &reopened_editable,
        "frm1701q:txtCitizenship",
        "FILIPINO",
    );
    try expectRevealedControlText(
        &reopened_editable,
        "txtEmail",
        "Synthetic.R1@Example.Test",
    );
}

test "reopen requires old immutable profile binding and rejects context substitution" {
    const allocator = std.testing.allocator;
    var repository = try store.Store.openMemory(allocator);
    defer repository.close();
    try seedSyntheticProfileRepository(&repository);
    var old_profile = try testHistoricalProfile(
        "persistence-synthetic-filer-r1",
        "synthetic-old@example.test",
        try test_context.profileAsOf(),
    );
    defer sensitive_memory.wipeValue(
        projection.Snapshot,
        &old_profile,
    );
    const workspace_id = try repository.generateDraftWorkspaceId();
    var state: ui.State = undefined;
    try openSyntheticState(
        &state,
        allocator,
        workspace_id,
        &old_profile,
    );
    defer state.deinit();
    try selectRequiredSyntheticElections(&state);
    try state.calculate();
    try savePassed(&state);
    try state.generateEditableCandidate(.create);
    _ = try persistCurrentCandidate(
        syntheticPlaintextTestCapability(),
        &repository,
        &state,
        .{
            .historical_profile = &old_profile,
            .role_instances = &test_role_instances,
            .recorded_at_unix_seconds = 1_750_000_010,
            .guard = .create,
        },
    );

    const wrong_context: ui.FilingContext = .{
        .tax_year = 2025,
        .quarter = .second,
        .amended = false,
    };
    var wrong_loaded: LoadedWorkspace = undefined;
    try std.testing.expectError(
        error.FilingBusinessKeyMismatch,
        loadWorkspaceInto(
            syntheticPlaintextTestCapability(),
            &wrong_loaded,
            &repository,
            allocator,
            workspace_id,
            "persistence-synthetic-filer",
            wrong_context,
        ),
    );

    var loaded: LoadedWorkspace = undefined;
    try loadWorkspaceInto(
        syntheticPlaintextTestCapability(),
        &loaded,
        &repository,
        allocator,
        workspace_id,
        "persistence-synthetic-filer",
        test_context,
    );
    defer loaded.deinit();
    var current_profile = try testHistoricalProfile(
        "persistence-synthetic-filer-r2",
        "synthetic-current@example.test",
        try test_context.profileAsOf(),
    );
    defer sensitive_memory.wipeValue(
        projection.Snapshot,
        &current_profile,
    );
    var rejected_state: ui.State = undefined;
    try std.testing.expectError(
        error.HistoricalProfileDigestMismatch,
        reopenStateInto(
            syntheticPlaintextTestCapability(),
            &rejected_state,
            &loaded,
            .editable_save,
            test_context,
            &current_profile,
            &test_role_instances,
        ),
    );
    try std.testing.expect(loaded.workspace_owned);

    var reopened: ui.State = undefined;
    switch (try reopenStateInto(
        syntheticPlaintextTestCapability(),
        &reopened,
        &loaded,
        .editable_save,
        test_context,
        &old_profile,
        &test_role_instances,
    )) {
        .opened => {},
        .blocked => return error.UnexpectedProfileMappingBlock,
    }
    defer reopened.deinit();
}

test "stale writer and tampered replay fail without mutating committed history" {
    const allocator = std.testing.allocator;
    var repository = try store.Store.openMemory(allocator);
    defer repository.close();
    try seedSyntheticProfileRepository(&repository);
    var profile = try testHistoricalProfile(
        "persistence-synthetic-filer-r1",
        "synthetic-stale@example.test",
        try test_context.profileAsOf(),
    );
    defer sensitive_memory.wipeValue(projection.Snapshot, &profile);
    const workspace_id = try repository.generateDraftWorkspaceId();
    var state: ui.State = undefined;
    try openSyntheticState(
        &state,
        allocator,
        workspace_id,
        &profile,
    );
    defer state.deinit();
    try selectRequiredSyntheticElections(&state);
    try state.calculate();
    try savePassed(&state);
    try state.generateEditableCandidate(.create);
    const first = try persistCurrentCandidate(
        syntheticPlaintextTestCapability(),
        &repository,
        &state,
        .{
            .historical_profile = &profile,
            .role_instances = &test_role_instances,
            .recorded_at_unix_seconds = 1_750_000_020,
            .guard = .create,
        },
    );
    try state.generateEditableCandidate(.{
        .match = first.revision,
    });
    try std.testing.expectError(
        error.DraftStaleRevision,
        persistCurrentCandidate(
            syntheticPlaintextTestCapability(),
            &repository,
            &state,
            .{
                .historical_profile = &profile,
                .role_instances = &test_role_instances,
                .recorded_at_unix_seconds = 1_750_000_021,
                .guard = .{
                    .match = try draft.DraftRevision.init(2),
                },
            },
        ),
    );

    const schema = try draft.SchemaBinding.exact1701Q(
        .editable_save,
    );
    const identity: draft.DraftIdentity = .{
        .workspace_id = workspace_id,
        .exact_schema_digest = schema.exact_schema_digest,
    };
    var persisted = (try repository.getExactDraftHistory(
        syntheticPlaintextTestCapability(),
        allocator,
        identity,
    )).?;
    defer persisted.deinit(allocator);
    try std.testing.expectEqual(
        @as(usize, 1),
        persisted.revisions.len,
    );

    const owned = &persisted.revisions[0];
    var values: [max_occurrences]draft.OccurrenceValue = undefined;
    defer sensitive_memory.wipeValue(
        [max_occurrences]draft.OccurrenceValue,
        &values,
    );
    for (owned.occurrences, 0..) |value, index| {
        values[index] = .{
            .ordinal = value.ordinal,
            .serialized_key = value.serialized_key,
            .same_key_occurrence = value.same_key_occurrence,
            .raw_value = value.raw_value,
            .normalized_value = value.normalized_value,
            .emitted_value = value.emitted_value,
        };
    }
    var history = try draft.DraftHistory.initExact1701Q(
        allocator,
        workspace_id,
        .editable_save,
    );
    defer history.deinit();
    var tampered_digest = owned.ordered_values_digest;
    tampered_digest.bytes[0] ^= 0xff;
    try std.testing.expectError(
        error.ReplayOrderedValuesDigestMismatch,
        history.replayPersistedRevision(.{
            .draft_identity = identity,
            .revision = owned.revision,
            .parent_revision = owned.parent_revision,
            .schema = owned.schema,
            .occurrences = values[0..owned.occurrences.len],
            .profile_snapshot_digest = owned.profile_snapshot_digest,
            .transaction_state_digest = owned.transaction_state_digest,
            .ordered_values_digest = tampered_digest,
            .validation_status = owned.validation_status,
            .artifact_status = owned.artifact_status,
        }),
    );
    try std.testing.expectEqual(@as(usize, 0), history.revisionCount());

    values[0].ordinal = 2;
    try std.testing.expectError(
        error.OccurrenceOrdinalMismatch,
        history.replayPersistedRevision(.{
            .draft_identity = identity,
            .revision = owned.revision,
            .parent_revision = owned.parent_revision,
            .schema = owned.schema,
            .occurrences = values[0..owned.occurrences.len],
            .profile_snapshot_digest = owned.profile_snapshot_digest,
            .transaction_state_digest = owned.transaction_state_digest,
            .ordered_values_digest = owned.ordered_values_digest,
            .validation_status = owned.validation_status,
            .artifact_status = owned.artifact_status,
        }),
    );
    try std.testing.expectEqual(@as(usize, 0), history.revisionCount());

    values[0].ordinal = 1;
    const wrong_shape_schema = try draft.SchemaBinding.exact1701Q(
        .final_copy_plaintext,
    );
    try std.testing.expectError(
        error.ReplaySchemaMismatch,
        history.replayPersistedRevision(.{
            .draft_identity = identity,
            .revision = owned.revision,
            .parent_revision = owned.parent_revision,
            .schema = wrong_shape_schema,
            .occurrences = values[0..owned.occurrences.len],
            .profile_snapshot_digest = owned.profile_snapshot_digest,
            .transaction_state_digest = owned.transaction_state_digest,
            .ordered_values_digest = owned.ordered_values_digest,
            .validation_status = owned.validation_status,
            .artifact_status = owned.artifact_status,
        }),
    );
    try std.testing.expectEqual(@as(usize, 0), history.revisionCount());
}

test "reopen replay rejects cap plus one with a destructible temporary owner" {
    const allocator = std.testing.allocator;
    var repository = try store.Store.openMemory(allocator);
    defer repository.close();
    try seedSyntheticProfileRepository(&repository);
    var profile = try testHistoricalProfile(
        "persistence-synthetic-filer-r1",
        "synthetic-replay-limit@example.test",
        try test_context.profileAsOf(),
    );
    defer sensitive_memory.wipeValue(projection.Snapshot, &profile);
    const workspace_id = try repository.generateDraftWorkspaceId();
    var state: ui.State = undefined;
    try openSyntheticState(
        &state,
        allocator,
        workspace_id,
        &profile,
    );
    defer state.deinit();
    try selectRequiredSyntheticElections(&state);
    try state.calculate();
    try savePassed(&state);
    try state.generateEditableCandidate(.create);
    const receipt = try persistCurrentCandidate(
        syntheticPlaintextTestCapability(),
        &repository,
        &state,
        .{
            .historical_profile = &profile,
            .role_instances = &test_role_instances,
            .recorded_at_unix_seconds = 1_750_000_025,
            .guard = .create,
        },
    );
    var persisted = (try repository.getExactDraftHistory(
        syntheticPlaintextTestCapability(),
        allocator,
        receipt.draft_identity,
    )).?;
    defer persisted.deinit(allocator);

    var repeated: [
        draft.max_revisions_per_exact_shape_stream +
            1
    ]store.OwnedExactDraftRevision = undefined;
    for (&repeated, 0..) |*revision, index| {
        revision.* = persisted.revisions[0];
        revision.revision = try draft.DraftRevision.init(index + 1);
        revision.parent_revision = if (index == 0)
            null
        else
            try draft.DraftRevision.init(index);
    }
    var forged = persisted;
    forged.revisions = &repeated;

    var temporary = try workflow.Workspace.init(
        allocator,
        workspace_id,
    );
    defer temporary.deinit();
    try std.testing.expectError(
        error.DraftRevisionLimitExceeded,
        replayOwnedHistory(&temporary.editable_history, &forged),
    );
    try std.testing.expectEqual(
        draft.max_revisions_per_exact_shape_stream,
        temporary.editableRevisionCount(),
    );
    try std.testing.expect(
        temporary.editable_history.retainedValueBytes() <=
            draft.max_retained_exact_value_bytes,
    );
}

test "alternate workspace listing groups sibling schema streams" {
    const allocator = std.testing.allocator;
    var repository = try store.Store.openMemory(allocator);
    defer repository.close();
    try seedSyntheticProfileRepository(&repository);
    var profile = try testHistoricalProfile(
        "persistence-synthetic-filer-r1",
        "synthetic-alternate@example.test",
        try test_context.profileAsOf(),
    );
    defer sensitive_memory.wipeValue(projection.Snapshot, &profile);

    var workspace_ids: [2]draft.DraftWorkspaceId = undefined;
    for (&workspace_ids, 0..) |*workspace_id, index| {
        workspace_id.* = try repository.generateDraftWorkspaceId();
        var state: ui.State = undefined;
        try openSyntheticState(
            &state,
            allocator,
            workspace_id.*,
            &profile,
        );
        defer state.deinit();
        try selectRequiredSyntheticElections(&state);
        try state.calculate();
        try savePassed(&state);
        try state.generateEditableCandidate(.create);
        _ = try persistCurrentCandidate(
            syntheticPlaintextTestCapability(),
            &repository,
            &state,
            .{
                .historical_profile = &profile,
                .role_instances = &test_role_instances,
                .recorded_at_unix_seconds = 1_750_000_030 + @as(i64, @intCast(index)),
                .guard = .create,
            },
        );
        if (index == 0) {
            try fullPassed(&state);
            try state.generateFinalCandidate(.create);
            _ = try persistCurrentCandidate(
                syntheticPlaintextTestCapability(),
                &repository,
                &state,
                .{
                    .historical_profile = &profile,
                    .role_instances = &test_role_instances,
                    .recorded_at_unix_seconds = 1_750_000_040,
                    .guard = .create,
                },
            );
        }
    }

    var alternates = try listAlternateWorkspaces(
        syntheticPlaintextTestCapability(),
        &repository,
        allocator,
        "persistence-synthetic-filer",
        test_context,
        workspace_ids[1],
    );
    defer alternates.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 1), alternates.items.len);
    try std.testing.expect(
        alternates.items[0].workspace_id.eql(&workspace_ids[0]),
    );
    try std.testing.expectEqual(
        @as(u32, 2),
        alternates.items[0].schema_stream_count,
    );
}
