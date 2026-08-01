//! Application-facing exact-state adapter for BIR Form 1701Q January 2018.
//!
//! This module is deliberately narrower than a page model. It owns one
//! workflow typestate, one in-memory workspace, and at most one artifact-lab
//! candidate. It exposes the exact 173-control inventory without turning a
//! map or UI list into serialization authority.
//!
//! Security and product boundaries:
//! - a caller supplies the allocator and a CSPRNG-produced workspace id;
//! - the qualified profile snapshot is copied into form state, never mutated;
//! - the filing year/quarter is bound to the snapshot's quarter-end date;
//! - only reviewed form-owned inputs are writable;
//! - credentials remain locked empty;
//! - artifact bytes are masked until their individual slot is revealed;
//! - imported ciphertext is accepted only by `artifact_lab.Session`;
//! - protocol secrets are borrowed for one decrypt call and never retained;
//! - there is no encryption, persistence, filesystem, endpoint, queue,
//!   upload, submission, or transport operation.
//!
//! Declaration defaults, maxlengths, disabled flags, kinds, ids, and source
//! lines come from the permanent engine `control_contract`. Filing-context
//! values, the current-page runtime reset, and reviewed UI behavior are
//! explicit runtime layers over those immutable declaration facts.

const std = @import("std");
const form = @import("form_1701q.zig");
const field = @import("../tax_profile/field.zig");
const model = @import("../tax_profile/model.zig");
const projection = @import("../tax_profile/projection.zig");
const occurrence = @import("../form_engine/occurrence.zig");
const draft = @import("../form_engine/draft.zig");
const profile_mapping = @import(
    "../form_engine/forms/form_1701q_2018/profile_mapping.zig",
);
const workflow = @import(
    "../form_engine/forms/form_1701q_2018/workflow.zig",
);
const transaction = @import(
    "../form_engine/forms/form_1701q_2018/transaction.zig",
);
const calculations = @import(
    "../form_engine/forms/form_1701q_2018/calculations.zig",
);
const occurrences = @import(
    "../form_engine/forms/form_1701q_2018/occurrences.zig",
);
const control_contract = @import(
    "../form_engine/forms/form_1701q_2018/control_contract.zig",
);
const validation = @import(
    "../form_engine/forms/form_1701q_2018/validation.zig",
);
const interaction = @import(
    "../form_engine/forms/form_1701q_2018/interaction.zig",
);
const event_contract = @import(
    "../form_engine/forms/form_1701q_2018/event_contract.zig",
);
const rdo_options = @import(
    "../form_engine/forms/form_1701q_2018/rdo_options.zig",
);
const editable_codec = @import(
    "../form_engine/forms/form_1701q_2018/editable_codec.zig",
);
const final_copy_codec = @import(
    "../form_engine/forms/form_1701q_2018/final_copy_codec.zig",
);
const artifact_lab = @import("../artifact_lab/session.zig");
const legacy_container = @import("../container_codec/legacy.zig");

pub const control_count = occurrences.control_seeds.len;

comptime {
    if (control_count != 173) {
        @compileError("1701Q exact UI adapter requires 173 controls");
    }
}

pub const SecurityBoundary = struct {
    pub const stores_protocol_secrets = false;
    pub const outbound_encryption_enabled = false;
    pub const persistence_enabled = false;
    pub const filesystem_enabled = false;
    pub const endpoint_enabled = false;
    pub const queue_enabled = false;
    pub const upload_enabled = false;
    pub const submission_enabled = false;
    pub const transport_enabled = false;
};

pub const Error =
    workflow.Error ||
    artifact_lab.Error ||
    interaction.Error ||
    error{
        InvalidTaxYear,
        ProfileAsOfMismatch,
        InvalidPhase,
        UnknownControl,
        WrongControlKind,
        ForbiddenEditOrigin,
        FilingContextLocked,
        UnreviewedRadioBehavior,
        InvalidRdoOption,
        MoneyRequiresCommit,
        NotMoneyControl,
        NotItem52Control,
        NotScheduleDateControl,
        NoCandidate,
        ReopenHistoryEmpty,
        ReopenWorkspaceMismatch,
        ReopenShapeMismatch,
        ReopenProfileDigestMismatch,
        ReopenTransactionDigestMismatch,
        ReopenValidationStatusMismatch,
        ReopenOccurrenceMismatch,
        ReopenArtifactMismatch,
        PersistedControlValueMismatch,
        CommitValueOutsideKeyPressDomain,
    };

pub const Quarter = enum(u2) {
    first = 1,
    second = 2,
    third = 3,
};

/// Identity-bearing filing context. Changing any member requires opening a
/// new state/workspace with a projection resolved for the new quarter end.
pub const FilingContext = struct {
    tax_year: u16,
    quarter: Quarter,
    amended: bool,

    pub fn profileAsOf(self: FilingContext) error{InvalidTaxYear}!model.Date {
        if (self.tax_year < 1900 or self.tax_year > 9999) {
            return error.InvalidTaxYear;
        }
        const month: u8 = switch (self.quarter) {
            .first => 3,
            .second => 6,
            .third => 9,
        };
        const day: u8 = switch (self.quarter) {
            .first => 31,
            .second => 30,
            .third => 30,
        };
        return model.Date.init(self.tax_year, month, day) catch unreachable;
    }
};

/// Immutable validation inputs that are not derivable from plaintext form
/// values. Persistence freezes this receipt from `SaveValidated`; reopen
/// never substitutes a current external verdict.
pub const ValidationEvidenceReceipt = struct {
    validation_current_year: i32,
    spouse_tin_checksum: validation.TinChecksumStatus,
};

pub const ReopenEvidence = ValidationEvidenceReceipt;

pub const OpenStatus = union(enum) {
    opened: void,
    blocked: profile_mapping.MappingBlock,
};

pub const Phase = enum {
    editing,
    calculated,
    save_failed,
    save_passed,
    full_failed,
    full_blocked,
    full_passed,
    editable_candidate,
    final_candidate,
};

pub const ValidationGate = enum {
    save,
    full,
};

pub const OrderedRuleId = union(enum) {
    save: validation.SaveRuleId,
    full: validation.FullRuleId,
};

pub const RuleMessage = struct {
    gate: ValidationGate,
    id: OrderedRuleId,
    source_order: u8,
    source_line: u16,
    message: []const u8,
};

pub const SaveOutcome = union(enum) {
    failed: RuleMessage,
    passed: void,
};

pub const FullOutcome = union(enum) {
    failed: RuleMessage,
    blocked: struct {
        id: validation.ValidationBlock,
        message: []const u8,
    },
    passed: struct {
        source_line: u16,
        message: []const u8,
    },
};

/// The arbitrary pre-blur JavaScript currency grammar has not been qualified.
/// Money commits therefore accept only the canonical exact transaction
/// parser grammar and fail closed rather than guessing or rounding an
/// unevidenced lexeme.
pub const pre_blur_money_grammar_qualified = false;

pub const MoneyCommitResult = struct {
    canonical: MaskedControlSummary,
};

pub const BlurMutation = enum {
    unchanged,
    cleared,
    reset_to_zero,
};

pub const BlurOutcome = struct {
    alert: ?[]const u8,
    mutation: BlurMutation,
    focus: bool,
    legacy_return_is_valid: ?bool = null,
};

pub const QualifiedBlurContext = interaction.BlurContext;
pub const QualifiedBlurOutcome = interaction.BlurSummary;

pub const QualifiedCommitOutcome = struct {
    blur: ?QualifiedBlurOutcome = null,
};

const ValidationState = union(enum) {
    none,
    save_failed: RuleMessage,
    save_passed,
    full_failed: RuleMessage,
    full_blocked: validation.ValidationBlock,
    full_passed,
};

const CoreState = union(enum) {
    editing: workflow.Editing,
    calculated: workflow.Calculated,
    save_passed: workflow.SaveValidated,
    full_passed: workflow.FullyValidated,
};

pub const RadioGroup = enum {
    quarter,
    amended,
    filer_type,
    filer_atc,
    filer_foreign_tax_credit,
    filer_tax_rate,
    filer_deduction,
    spouse_atc,
    spouse_foreign_tax_credit,
    spouse_tax_rate,
    spouse_deduction,
};

/// `spouse_type_independent` preserves the legacy `clearCheck(id)` behavior:
/// each spouse-type radio has a distinct HTML name and multiple boxes may be
/// checked at once.
pub const RadioBehavior = union(enum) {
    exclusive: RadioGroup,
    spouse_type_independent,
};

pub const ValueSource = enum {
    profile_projection,
    explicit_filing_context,
    hta_markup_default,
    evidence_needed_empty,
    credential_locked_empty,
    user_edit,
    calculated,
};

pub const MaskedControlSummary = struct {
    populated: bool,
    byte_length: usize,
};

pub const ControlDisplay = union(enum) {
    missing,
    masked_text: MaskedControlSummary,
    revealed_text: []const u8,
    checked: bool,
    credential_locked_empty,
};

/// A bounded, generic view of one exact control. Revealed text borrows State
/// and must not be retained across a transition or `deinit`.
pub const ControlView = struct {
    stable_ordinal: u16,
    source_line: u32,
    id: []const u8,
    kind: occurrences.ControlKind,
    maximum_length: ?u16,
    declared_value: []const u8,
    disabled_in_markup: bool,
    disabled: bool,
    origin: occurrence.OriginKind,
    read_only: bool,
    radio_behavior: ?RadioBehavior,
    value_source: ValueSource,
    display: ControlDisplay,
};

pub const RdoSubject = enum {
    filer,
    spouse,
};

/// An index into the exact, evidence-derived RDO option domain.
pub const RdoOption = struct {
    index: u16,

    pub fn parse(raw: []const u8) error{InvalidRdoOption}!RdoOption {
        for (rdo_options.values, 0..) |candidate, index| {
            if (std.mem.eql(u8, candidate, raw)) {
                return .{ .index = @intCast(index) };
            }
        }
        return error.InvalidRdoOption;
    }

    pub fn value(self: RdoOption) []const u8 {
        return rdo_options.values[self.index];
    }
};

pub const RdoSelection = struct {
    subject: RdoSubject,
    control_id: []const u8,
    selected: union(enum) {
        /// Exact legacy select placeholder; deliberately not part of the RDO
        /// option domain.
        placeholder_000,
        option: RdoOption,
    },

    pub fn value(self: RdoSelection) []const u8 {
        return switch (self.selected) {
            .placeholder_000 => "000",
            .option => |option| option.value(),
        };
    }
};

pub fn rdoOptions() []const []const u8 {
    return &rdo_options.values;
}

pub const ArtifactSlot = artifact_lab.ArtifactSlot;
pub const ArtifactDisplay = artifact_lab.DisplayValue;
pub const ArtifactDiff = artifact_lab.DiffSummary;
pub const DecryptLimits = legacy_container.Limits;
pub const ContainerQualification = legacy_container.QualificationSummary;

pub const CandidateSummary = struct {
    shape: draft.PayloadShape,
    label: []const u8,
    exactness: workflow.Exactness,
    evidence_qualified: bool,
    byte_length: usize,
    sha256: [std.crypto.hash.sha2.Sha256.digest_length]u8,
    container_qualification: ContainerQualification,
};

/// Unique owner. Initialize only with `openInto`, and call `deinit` exactly
/// once after an `.opened` result.
pub const State = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    filing_context: FilingContext,
    profile_as_of: model.Date,
    workspace: workflow.Workspace,
    core: CoreState,
    interaction_runtime: interaction.Runtime,
    spouse_profile_present: bool,
    validation_state: ValidationState = .none,
    candidate: ?workflow.ArtifactCandidate = null,
    control_revealed: [control_count]bool =
        [_]bool{false} ** control_count,
    user_edited: [control_count]bool =
        [_]bool{false} ** control_count,

    /// Maps an already-qualified projection without mutating it. `out`
    /// remains uninitialized when the result is `.blocked` or an error.
    ///
    /// `random_workspace_id` must be produced by the caller's CSPRNG; this
    /// adapter intentionally has no ambient RNG or persistence dependency.
    pub fn openInto(
        out: *Self,
        allocator: std.mem.Allocator,
        random_workspace_id: draft.DraftWorkspaceId,
        context: FilingContext,
        profile: *const projection.Snapshot,
    ) Error!OpenStatus {
        const profile_as_of = try context.profileAsOf();
        if (!profile.effective_on.eql(profile_as_of)) {
            return error.ProfileAsOfMismatch;
        }

        const mapping = profile_mapping.mapProfileSnapshot(profile.*);
        switch (mapping) {
            .blocked => |block| return .{ .blocked = block },
            .accepted => |accepted| {
                var mapped = accepted;
                defer secureWipe(&mapped);
                const spouse_profile_present =
                    mapped.get("frm1701q:txtSpouseTIN1") != null;

                var editing = try workflow.Editing.init(&mapped);
                errdefer editing.deinit();
                try seedGroundedInitialValues(&editing, context);
                var interaction_runtime = interaction.Runtime.fromMarkup();
                try interaction_runtime.applyInit(
                    &editing.transaction_state,
                    @intCast(context.tax_year),
                    .{
                        .spouse_profile_present = spouse_profile_present,
                    },
                );

                var workspace = try workflow.Workspace.init(
                    allocator,
                    random_workspace_id,
                );
                errdefer workspace.deinit();

                out.* = .{
                    .allocator = allocator,
                    .filing_context = context,
                    .profile_as_of = profile_as_of,
                    .workspace = workspace,
                    .core = .{ .editing = editing },
                    .interaction_runtime = interaction_runtime,
                    .spouse_profile_present = spouse_profile_present,
                };

                // Ownership moved to `out`; erase the shallow stack copies.
                editing.deinit();
                secureWipe(&workspace);
                return .{ .opened = {} };
            },
        }
    }

    /// Reopens from an already schema-validated, replayed workspace.
    /// `workspace` is consumed only on `.opened`; it remains owned by the
    /// caller on `.blocked` or error. The historical profile projection and
    /// non-form validation evidence are explicit and are never replaced with
    /// the current profile.
    pub fn reopenInto(
        out: *Self,
        allocator: std.mem.Allocator,
        workspace: *workflow.Workspace,
        selected_shape: draft.PayloadShape,
        context: FilingContext,
        historical_profile: *const projection.Snapshot,
        reopen_evidence: ReopenEvidence,
    ) Error!OpenStatus {
        const editable_id = workspace.editable_history.identity.workspace_id;
        const final_id = workspace.final_history.identity.workspace_id;
        if (!editable_id.eql(&final_id)) {
            return error.ReopenWorkspaceMismatch;
        }
        const persisted = switch (selected_shape) {
            .editable_save => workspace.editable_history.current(),
            .final_copy_plaintext => workspace.final_history.current(),
        } orelse return error.ReopenHistoryEmpty;
        if (persisted.schema.payload_shape != selected_shape or
            !persisted.draft_identity.workspace_id.eql(&editable_id))
        {
            return error.ReopenShapeMismatch;
        }

        var temporary: Self = undefined;
        const status = try Self.openInto(
            &temporary,
            allocator,
            editable_id,
            context,
            historical_profile,
        );
        switch (status) {
            .blocked => |block| return .{ .blocked = block },
            .opened => {},
        }
        var temporary_owned = true;
        defer if (temporary_owned) temporary.deinit();

        // Persisted candidates already include the source-required
        // `computetxt31()->capital()` normalization. Apply that form-owned
        // in-place view mutation before immutable profile-value comparison;
        // transaction profile digest/provenance remain the historical
        // projection's identity.
        _ = temporary.core.editing.transaction_state
            .applyLegacyCapital();
        try temporary.restorePersistedInputs(persisted);
        try temporary.calculate();

        const regenerated_digests =
            try temporary.transactionState().digestBundle();
        if (!regenerated_digests.profile_snapshot.eql(
            &persisted.profile_snapshot_digest,
        )) {
            return error.ReopenProfileDigestMismatch;
        }
        if (!regenerated_digests.transaction_state.eql(
            &persisted.transaction_state_digest,
        )) {
            return error.ReopenTransactionDigestMismatch;
        }

        const save_outcome = try temporary.validateSave(
            reopen_evidence.validation_current_year,
            reopen_evidence.spouse_tin_checksum,
        );
        switch (save_outcome) {
            .failed => return error.ReopenValidationStatusMismatch,
            .passed => {},
        }
        if (selected_shape == .final_copy_plaintext) {
            const full_outcome = try temporary.validateFull();
            switch (full_outcome) {
                .failed, .blocked => return error.ReopenValidationStatusMismatch,
                .passed => {},
            }
        }

        const expected_validation: draft.ValidationStatus =
            if (selected_shape == .editable_save)
                .{
                    .save_gate = .passed,
                    .full_validation = .not_run,
                }
            else
                .{
                    .save_gate = .passed,
                    .full_validation = .passed,
                };
        if (!std.meta.eql(
            expected_validation,
            persisted.validation_status,
        )) {
            return error.ReopenValidationStatusMismatch;
        }

        // Regenerate through the normal gated candidate path in a temporary
        // history, then compare all value-bearing content to persistence.
        // The temporary revision is destroyed before the replayed workspace
        // is installed, so reopen cannot append a duplicate revision.
        switch (selected_shape) {
            .editable_save => try temporary.generateEditableCandidate(.create),
            .final_copy_plaintext => try temporary.generateFinalCandidate(.create),
        }
        const regenerated = switch (selected_shape) {
            .editable_save => temporary.workspace.editable_history.current().?,
            .final_copy_plaintext => temporary.workspace.final_history.current().?,
        };
        if (!snapshotEnvelopeMatches(regenerated, persisted)) {
            return error.ReopenArtifactMismatch;
        }
        if (!snapshotOccurrencesMatch(regenerated, persisted)) {
            return error.ReopenOccurrenceMismatch;
        }

        temporary.dropCandidate();
        var restored = try workflow.restoreCandidateFromSnapshot(
            allocator,
            persisted,
        );
        defer secureWipe(&restored);
        temporary.candidate = restored;
        secureWipe(&restored);

        // All fallible validation is complete. Move the replayed histories
        // into the state and erase the caller's shallow owner.
        temporary.workspace.deinit();
        temporary.workspace = workspace.*;
        secureWipe(workspace);
        out.* = temporary;
        secureWipe(&temporary);
        temporary_owned = false;
        return .{ .opened = {} };
    }

    pub fn deinit(self: *Self) void {
        self.dropCandidate();
        self.workspace.deinit();
        self.deinitCore();
        secureWipe(self);
    }

    pub fn filingContext(self: *const Self) FilingContext {
        return self.filing_context;
    }

    pub fn profileAsOf(self: *const Self) model.Date {
        return self.profile_as_of;
    }

    pub fn spouseProfilePresent(self: *const Self) bool {
        return self.spouse_profile_present;
    }

    pub fn phase(self: *const Self) Phase {
        if (self.candidate) |*candidate| {
            return switch (candidate.shape) {
                .editable_save => .editable_candidate,
                .final_copy_plaintext => .final_candidate,
            };
        }
        return switch (self.validation_state) {
            .save_failed => .save_failed,
            .full_failed => .full_failed,
            .full_blocked => .full_blocked,
            else => switch (self.core) {
                .editing => .editing,
                .calculated => .calculated,
                .save_passed => .save_passed,
                .full_passed => .full_passed,
            },
        };
    }

    pub fn controls(
        self: *const Self,
    ) [control_count]ControlView {
        var result: [control_count]ControlView = undefined;
        const current = self.transactionState();
        for (occurrences.control_seeds, 0..) |seed, index| {
            const declaration = control_contract.contracts[index];
            std.debug.assert(std.mem.eql(
                u8,
                seed.id,
                declaration.id,
            ));
            std.debug.assert(seed.source_line == declaration.source_line);
            std.debug.assert(seed.kind == declaration.kind);
            const slot = &current.slots[index];
            result[index] = .{
                .stable_ordinal = seed.runtimeFormElementOrdinal(),
                .source_line = declaration.source_line,
                .id = declaration.id,
                .kind = declaration.kind,
                .maximum_length = declaration.max_length,
                .declared_value = declaration.declared_value,
                .disabled_in_markup = declaration.disabled_in_markup,
                .disabled = self.interaction_runtime.isDisabled(
                    seed.id,
                ) catch unreachable,
                .origin = slot.origin,
                .read_only = !isUiEditable(slot.origin, seed.id),
                .radio_behavior = if (seed.kind == .radio)
                    radioBehavior(seed.id)
                else
                    null,
                .value_source = self.valueSource(index),
                .display = self.controlDisplay(index, slot),
            };
        }
        return result;
    }

    pub fn control(
        self: *const Self,
        control_id: []const u8,
    ) Error!ControlView {
        const index = controlIndex(control_id) orelse
            return error.UnknownControl;
        const all = self.controls();
        return all[index];
    }

    pub fn setControlRevealed(
        self: *Self,
        control_id: []const u8,
        revealed: bool,
    ) Error!void {
        const index = controlIndex(control_id) orelse
            return error.UnknownControl;
        const slot = &self.transactionState().slots[index];
        if (slot.kind == .radio) return error.WrongControlKind;
        if (slot.sensitivity == .credential_forbidden) {
            return error.ForbiddenEditOrigin;
        }
        self.control_revealed[index] = revealed;
    }

    /// Exact profile RDO values are read-only here. Profile evolution or RDO
    /// changes must produce a new qualified projection and workspace.
    pub fn rdoSelection(
        self: *const Self,
        subject: RdoSubject,
    ) Error!RdoSelection {
        const control_id = switch (subject) {
            .filer => "frm1701q:txtRDOCode",
            .spouse => "frm1701q:txtSpouseRDOCode",
        };
        const raw = try self.transactionState().text(.profile, control_id);
        return .{
            .subject = subject,
            .control_id = control_id,
            .selected = if (std.mem.eql(u8, raw, "000"))
                .placeholder_000
            else
                .{ .option = try RdoOption.parse(raw) },
        };
    }

    /// Writes a reviewed text/select input and returns the state to Editing.
    /// Filing identity fields and every profile/derived/system/preparer value
    /// are fail-closed.
    fn setText(
        self: *Self,
        control_id: []const u8,
        value: []const u8,
    ) Error!void {
        const index = controlIndex(control_id) orelse
            return error.UnknownControl;
        const slot = &self.transactionState().slots[index];
        if (slot.kind == .radio) return error.WrongControlKind;
        if (isLockedFilingIdentity(control_id)) {
            return error.FilingContextLocked;
        }
        if (!isUiEditable(slot.origin, control_id)) {
            return error.ForbiddenEditOrigin;
        }
        if (try self.interaction_runtime.isDisabled(control_id)) {
            return error.ControlDisabled;
        }
        if (isMoneyControl(control_id)) {
            return error.MoneyRequiresCommit;
        }

        try self.commitText(index, slot.origin, control_id, value);
    }

    /// Commits only canonical exact currency. The canonical formatter is run
    /// after parsing even though the current qualified grammar is already
    /// canonical; this keeps the UI path tied to the same fixed-point
    /// parse/format boundary used by calculation state.
    fn commitMoney(
        self: *Self,
        control_id: []const u8,
        entered_lexeme: []const u8,
    ) Error!MoneyCommitResult {
        const index = controlIndex(control_id) orelse
            return error.UnknownControl;
        const slot = &self.transactionState().slots[index];
        if (!isMoneyControl(control_id)) {
            return error.NotMoneyControl;
        }
        if (slot.origin != .transaction or slot.kind == .radio) {
            return error.ForbiddenEditOrigin;
        }
        if (try self.interaction_runtime.isDisabled(control_id)) {
            return error.ControlDisabled;
        }

        const parsed = try transaction.parseMoney(entered_lexeme);
        var formatted = try transaction.formatMoney(parsed);
        defer secureWipe(&formatted);
        try self.commitText(
            index,
            .transaction,
            control_id,
            formatted.asSlice(),
        );
        const canonical = try self.transactionState().text(
            .transaction,
            control_id,
        );
        return .{
            .canonical = summarizeControl(canonical),
        };
    }

    /// Atomically commits one reviewed editor value and runs its qualified
    /// blur chain, when bound. Neither the raw entered value nor any partial
    /// interaction mutation is installed unless the complete operation
    /// succeeds. The module-private raw setters exist only for focused tests;
    /// application and persistence callers use this boundary.
    ///
    /// The frozen keypress facts also bound candidate-reachable committed
    /// values. This is a conservative commit-domain safety gate, not a claim
    /// that Native reproduces the legacy browser's per-keystroke or mask UX;
    /// `event_contract.key_by_key_filtering_qualified` remains false.
    pub fn commitAndBlurQualified(
        self: *Self,
        control_id: []const u8,
        entered_lexeme: []const u8,
        context: QualifiedBlurContext,
    ) Error!QualifiedCommitOutcome {
        const index = controlIndex(control_id) orelse
            return error.UnknownControl;
        const slot = &self.transactionState().slots[index];
        if (slot.kind == .radio) return error.WrongControlKind;
        if (isLockedFilingIdentity(control_id)) {
            return error.FilingContextLocked;
        }
        if (!isUiEditable(slot.origin, control_id)) {
            return error.ForbiddenEditOrigin;
        }
        if (try self.interaction_runtime.isDisabled(control_id)) {
            return error.ControlDisabled;
        }

        const money_control = isMoneyControl(control_id);
        const parsed_money: ?calculations.Money = if (money_control)
            try transaction.parseMoney(entered_lexeme)
        else
            null;
        try validateQualifiedCommitDomain(
            control_id,
            entered_lexeme,
            if (parsed_money) |money| money.centavos else null,
        );

        var next = self.editingCopy();
        errdefer next.deinit();
        if (parsed_money) |parsed| {
            if (slot.origin != .transaction) {
                return error.ForbiddenEditOrigin;
            }
            var formatted = try transaction.formatMoney(parsed);
            defer secureWipe(&formatted);
            try next.setText(
                .transaction,
                control_id,
                formatted.asSlice(),
            );
        } else {
            try next.setText(
                slot.origin,
                control_id,
                entered_lexeme,
            );
        }

        var next_runtime = self.interaction_runtime;
        const blur_outcome: ?QualifiedBlurOutcome =
            if (event_contract.find(control_id, .blur) != null)
                try next_runtime.blur(
                    &next.transaction_state,
                    control_id,
                    context,
                )
            else
                null;

        self.installEditing(&next);
        self.interaction_runtime = next_runtime;
        self.user_edited[index] = true;
        return .{ .blur = blur_outcome };
    }

    /// Reports the frozen event contract without exposing event internals.
    /// Dynamic disabled state is intentionally separate and remains enforced
    /// by `blurQualified`.
    pub fn hasBlurBinding(
        self: *const Self,
        control_id: []const u8,
    ) Error!bool {
        _ = self;
        _ = controlIndex(control_id) orelse
            return error.UnknownControl;
        return event_contract.find(control_id, .blur) != null;
    }

    /// Routes any qualified blur binding through the exact interaction model.
    /// The mutation is staged against an owned copy and only installed after
    /// the complete handler chain succeeds.
    fn blurQualified(
        self: *Self,
        control_id: []const u8,
        context: QualifiedBlurContext,
    ) Error!QualifiedBlurOutcome {
        const index = controlIndex(control_id) orelse
            return error.UnknownControl;
        const slot = &self.transactionState().slots[index];
        if (slot.kind == .radio) return error.WrongControlKind;
        if (try self.interaction_runtime.isDisabled(control_id)) {
            return error.ControlDisabled;
        }

        var next = self.editingCopy();
        errdefer next.deinit();
        var next_runtime = self.interaction_runtime;
        const outcome = try next_runtime.blur(
            &next.transaction_state,
            control_id,
            context,
        );
        self.installEditing(&next);
        self.interaction_runtime = next_runtime;
        if (outcome.mutation != .unchanged) {
            self.user_edited[index] = true;
        }
        return outcome;
    }

    /// Compatibility wrapper for the immutable filing-year blur. A rejected
    /// future year is cleared while FilingContext/profile-as-of stay bound.
    fn blurYear(
        self: *Self,
        current_year: i32,
    ) Error!BlurOutcome {
        return legacyBlurOutcome(try self.blurQualified(
            "frm1701q:txtYear",
            .{
                .current_year = current_year,
                .schedule_date = dummyScheduleDateContext(current_year),
            },
        ));
    }

    /// Compatibility wrapper for the exact Item 52 blur chain.
    fn blurItem52(
        self: *Self,
        control_id: []const u8,
    ) Error!BlurOutcome {
        if (!std.mem.eql(u8, control_id, "frm1701q:txt52A") and
            !std.mem.eql(u8, control_id, "frm1701q:txt52B"))
        {
            return error.NotItem52Control;
        }
        const current_year: i32 = @intCast(self.filing_context.tax_year);
        return legacyBlurOutcome(try self.blurQualified(
            control_id,
            .{
                .current_year = current_year,
                .schedule_date = dummyScheduleDateContext(current_year),
            },
        ));
    }

    /// Compatibility wrapper for a qualified Schedule I date blur.
    fn blurScheduleDate(
        self: *Self,
        control_id: []const u8,
        context: validation.ScheduleDateContext,
    ) Error!BlurOutcome {
        if (!isScheduleDateControl(control_id)) {
            return error.NotScheduleDateControl;
        }
        return legacyBlurOutcome(try self.blurQualified(
            control_id,
            .{
                .current_year = @intCast(self.filing_context.tax_year),
                .schedule_date = context,
            },
        ));
    }

    /// Applies browser activation and the exact inline click chain atomically.
    /// `checked` remains in the signature for Native/API compatibility; radio
    /// activation, not assignment, is authoritative. Thus a selected named
    /// radio cannot be toggled off, while spouse `clearCheck` remains exact.
    pub fn setRadio(
        self: *Self,
        control_id: []const u8,
        checked: bool,
    ) Error!void {
        _ = checked;
        const index = controlIndex(control_id) orelse
            return error.UnknownControl;
        const slot = &self.transactionState().slots[index];
        if (slot.kind != .radio) return error.WrongControlKind;
        if (slot.origin == .filing_context) {
            return error.FilingContextLocked;
        }
        if (!isUiEditable(slot.origin, control_id)) {
            return error.ForbiddenEditOrigin;
        }
        _ = radioBehavior(control_id) orelse
            return error.UnreviewedRadioBehavior;
        if (try self.interaction_runtime.isDisabled(control_id)) {
            return error.ControlDisabled;
        }

        var next = self.editingCopy();
        errdefer next.deinit();
        var next_runtime = self.interaction_runtime;
        _ = try next_runtime.click(
            &next.transaction_state,
            control_id,
            .{
                .spouse_profile_present = self.spouse_profile_present,
            },
        );
        self.installEditing(&next);
        self.interaction_runtime = next_runtime;
        self.user_edited[index] = true;
    }

    pub fn calculate(self: *Self) Error!void {
        if (self.core != .editing) return error.InvalidPhase;
        var next: workflow.Calculated = undefined;
        try self.core.editing.calculateInto(&next);
        defer next.deinit();
        self.dropCandidate();
        // `calculateInto` consumed the active Editing payload. Erase the
        // enclosing union tag and inactive tail before installing the move.
        secureWipe(&self.core);
        self.core = .{ .calculated = next };
        self.validation_state = .none;
    }

    pub fn validateSave(
        self: *Self,
        current_year: i32,
        spouse_tin_checksum: validation.TinChecksumStatus,
    ) Error!SaveOutcome {
        if (self.core != .calculated) return error.InvalidPhase;
        var check: workflow.SaveCheck = undefined;
        try self.core.calculated.validateSaveInto(
            current_year,
            spouse_tin_checksum,
            &check,
        );
        defer check.deinit();

        return switch (check) {
            .failed => |rule| blk: {
                const message = saveRuleMessage(rule);
                self.validation_state = .{ .save_failed = message };
                break :blk .{ .failed = message };
            },
            .passed => |*passed| blk: {
                self.dropCandidate();
                // The consuming validation transition already deinitialized
                // the Calculated payload on success.
                secureWipe(&self.core);
                self.core = .{ .save_passed = passed.* };
                self.validation_state = .save_passed;
                break :blk .{ .passed = {} };
            },
        };
    }

    pub fn validateFull(self: *Self) Error!FullOutcome {
        if (self.core != .save_passed) return error.InvalidPhase;
        var check: workflow.FullCheck = undefined;
        try self.core.save_passed.validateFullInto(&check);
        defer check.deinit();

        return switch (check) {
            .failed => |failure| blk: {
                const message = fullRuleMessage(failure.rule);
                self.validation_state = .{ .full_failed = message };
                break :blk .{ .failed = message };
            },
            .blocked => |block| blk: {
                self.validation_state = .{ .full_blocked = block };
                break :blk .{ .blocked = .{
                    .id = block,
                    .message = validationBlockMessage(block),
                } };
            },
            .passed => |*passed| blk: {
                const source_line = passed.success.source_line;
                const message = passed.success.alert;
                self.dropCandidate();
                // The consuming validation transition already deinitialized
                // the SaveValidated payload on success.
                secureWipe(&self.core);
                self.core = .{ .full_passed = passed.* };
                self.validation_state = .full_passed;
                break :blk .{ .passed = .{
                    .source_line = source_line,
                    .message = message,
                } };
            },
        };
    }

    /// Borrows no mutable state and creates no second retained copy. The
    /// receipt is derived from the exact `SaveValidated` payload that gated
    /// the current candidate.
    pub fn validationEvidenceReceipt(
        self: *const Self,
    ) ?ValidationEvidenceReceipt {
        const validated = self.saveValidated() orelse return null;
        return .{
            .validation_current_year = validated.current_year,
            .spouse_tin_checksum = validated.spouse_tin_checksum,
        };
    }

    /// Editable plaintext is reachable only from a save-passed workflow
    /// typestate. Existing candidates are retained if creation fails.
    pub fn generateEditableCandidate(
        self: *Self,
        guard: draft.RevisionGuard,
    ) Error!void {
        const validated = self.saveValidated() orelse
            return error.InvalidPhase;
        var next = try validated.appendEditableCandidate(
            &self.workspace,
            guard,
        );
        defer secureWipe(&next);
        self.dropCandidate();
        self.candidate = next;
        secureWipe(&next);
    }

    /// Final Copy plaintext is reachable only after terminal full-validation
    /// success.
    pub fn generateFinalCandidate(
        self: *Self,
        guard: draft.RevisionGuard,
    ) Error!void {
        if (self.core != .full_passed) return error.InvalidPhase;
        var next = try self.core.full_passed.appendFinalCandidate(
            &self.workspace,
            guard,
        );
        defer secureWipe(&next);
        self.dropCandidate();
        self.candidate = next;
        secureWipe(&next);
    }

    pub fn candidateSummary(self: *const Self) Error!CandidateSummary {
        const candidate = if (self.candidate) |*present|
            present
        else
            return error.NoCandidate;
        return .{
            .shape = candidate.shape,
            .label = candidateLabel(
                candidate.shape,
                candidate.exactness,
            ),
            .exactness = candidate.exactness,
            .evidence_qualified = candidate.exactness == .exact,
            .byte_length = candidate.receipt.byte_length,
            .sha256 = candidate.receipt.sha256.asBytes().*,
            .container_qualification = candidate.lab_session.qualification(),
        };
    }

    /// Returned `.revealed` bytes borrow this State and must not be retained.
    pub fn artifactDisplay(
        self: *const Self,
        slot: ArtifactSlot,
    ) Error!ArtifactDisplay {
        const candidate = if (self.candidate) |*present|
            present
        else
            return error.NoCandidate;
        return candidate.lab_session.display(slot);
    }

    pub fn setArtifactRevealed(
        self: *Self,
        slot: ArtifactSlot,
        revealed: bool,
    ) Error!void {
        const candidate = if (self.candidate) |*present|
            present
        else
            return error.NoCandidate;
        try candidate.lab_session.setRevealed(slot, revealed);
    }

    /// Copies ciphertext only through the artifact-lab sensitive buffer.
    pub fn stageImportedCiphertext(
        self: *Self,
        ciphertext: []const u8,
        limits: DecryptLimits,
    ) Error!void {
        const candidate = if (self.candidate) |*present|
            present
        else
            return error.NoCandidate;
        try candidate.lab_session.setImportedCiphertext(
            ciphertext,
            limits,
        );
    }

    /// `borrowed_protocol_secret` is used only by this call. It is never
    /// copied into State, a draft, a diagnostic, or a display value.
    pub fn decryptImported(
        self: *Self,
        borrowed_protocol_secret: []const u8,
        limits: DecryptLimits,
    ) Error!void {
        const candidate = if (self.candidate) |*present|
            present
        else
            return error.NoCandidate;
        const strict_validator: *const fn ([]const u8) bool =
            switch (candidate.shape) {
                .editable_save => strictEditable,
                .final_copy_plaintext => strictFinal,
            };
        try candidate.lab_session.decryptImported(
            borrowed_protocol_secret,
            limits,
            strict_validator,
        );
    }

    pub fn artifactDiff(self: *const Self) Error!ArtifactDiff {
        const candidate = if (self.candidate) |*present|
            present
        else
            return error.NoCandidate;
        return candidate.lab_session.compareGeneratedToDecrypted();
    }

    pub fn artifactQualification(
        self: *const Self,
    ) Error!ContainerQualification {
        const candidate = if (self.candidate) |*present|
            present
        else
            return error.NoCandidate;
        return candidate.lab_session.qualification();
    }

    pub fn editableRevisionCount(self: *const Self) usize {
        return self.workspace.editableRevisionCount();
    }

    pub fn finalRevisionCount(self: *const Self) usize {
        return self.workspace.finalRevisionCount();
    }

    /// Borrows the immutable engine snapshot that produced the current lab
    /// candidate. Persistence must copy it before the next state transition.
    pub fn candidateSnapshot(
        self: *const Self,
    ) Error!*const draft.DraftSnapshot {
        const candidate = if (self.candidate) |*present|
            present
        else
            return error.NoCandidate;
        return switch (candidate.shape) {
            .editable_save => self.workspace.editableSnapshot(
                candidate.draft_revision,
            ) orelse error.ReopenHistoryEmpty,
            .final_copy_plaintext => self.workspace.finalSnapshot(
                candidate.draft_revision,
            ) orelse error.ReopenHistoryEmpty,
        };
    }

    pub fn workspaceId(self: *const Self) draft.DraftWorkspaceId {
        return self.workspace.editable_history.identity.workspace_id;
    }

    fn transactionState(self: *const Self) *const transaction.State {
        return switch (self.core) {
            .editing => |*value| &value.transaction_state,
            .calculated => |*value| &value.transaction_state,
            .save_passed => |*value| &value.calculated.transaction_state,
            .full_passed => |*value| &value.save_validated.calculated.transaction_state,
        };
    }

    fn restorePersistedInputs(
        self: *Self,
        persisted: *const draft.DraftSnapshot,
    ) Error!void {
        // Frozen HTA loadData/loadWFData (source lines 2214/2311) assign
        // restored values without dispatching onclick. Keep this direct restore
        // path separate from Runtime.click so reopen does not invent handlers.
        if (self.core != .editing) return error.InvalidPhase;
        const manifest = switch (persisted.schema.payload_shape) {
            .editable_save => try occurrences.editableManifest(),
            .final_copy_plaintext => try occurrences.finalCopyManifest(),
        };
        if (manifest.items.len != persisted.occurrences.len) {
            return error.ReopenOccurrenceMismatch;
        }

        for (manifest.items, persisted.occurrences) |metadata, stored| {
            if (stored.ordinal != metadata.ordinal or
                stored.same_key_occurrence !=
                    metadata.same_key_occurrence or
                !std.mem.eql(
                    u8,
                    stored.serialized_key,
                    metadata.serialized_key,
                ))
            {
                return error.ReopenOccurrenceMismatch;
            }
            switch (metadata.source_controls) {
                .one => |control_id| try self.restoreOneControl(
                    control_id,
                    stored.raw_value,
                ),
                .two => |control_ids| {
                    const first_index = controlIndex(control_ids[0]) orelse
                        return error.UnknownControl;
                    const second_index = controlIndex(control_ids[1]) orelse
                        return error.UnknownControl;
                    const first_slot =
                        &self.core.editing.transaction_state.slots[first_index];
                    const second_slot =
                        &self.core.editing.transaction_state.slots[second_index];
                    if (first_slot.origin != .profile or
                        second_slot.origin != .profile or
                        !concatenatedSlotsMatch(
                            first_slot,
                            second_slot,
                            stored.raw_value,
                        ))
                    {
                        return error.PersistedControlValueMismatch;
                    }
                },
            }
        }
    }

    fn restoreOneControl(
        self: *Self,
        control_id: []const u8,
        raw: []const u8,
    ) Error!void {
        const index = controlIndex(control_id) orelse
            return error.UnknownControl;
        const slot = &self.core.editing.transaction_state.slots[index];
        switch (slot.origin) {
            .derived => return,
            .profile, .preparer => {
                if (!slotMatchesRaw(slot, raw)) {
                    return error.PersistedControlValueMismatch;
                }
            },
            .filing_context => {
                if (isLockedFilingIdentity(control_id)) {
                    if (!slotMatchesRaw(slot, raw)) {
                        return error.PersistedControlValueMismatch;
                    }
                    return;
                }
                try setEditingSlotFromRaw(
                    &self.core.editing,
                    slot.origin,
                    slot.kind,
                    control_id,
                    raw,
                );
            },
            .transaction, .external_evidence, .system => try setEditingSlotFromRaw(
                &self.core.editing,
                slot.origin,
                slot.kind,
                control_id,
                raw,
            ),
            .unreviewed => unreachable,
        }
    }

    fn editingCopy(self: *const Self) workflow.Editing {
        return .{ .transaction_state = self.transactionState().* };
    }

    fn installEditing(
        self: *Self,
        next: *workflow.Editing,
    ) void {
        self.dropCandidate();
        self.deinitCore();
        self.core = .{ .editing = next.* };
        next.deinit();
        self.validation_state = .none;
    }

    fn commitText(
        self: *Self,
        index: usize,
        origin: occurrence.OriginKind,
        control_id: []const u8,
        value: []const u8,
    ) Error!void {
        var next = self.editingCopy();
        errdefer next.deinit();
        try next.setText(origin, control_id, value);
        self.installEditing(&next);
        self.user_edited[index] = true;
    }

    fn deinitCore(self: *Self) void {
        switch (self.core) {
            .editing => |*value| value.deinit(),
            .calculated => |*value| value.deinit(),
            .save_passed => |*value| value.deinit(),
            .full_passed => |*value| value.deinit(),
        }
        secureWipe(&self.core);
    }

    fn saveValidated(
        self: *const Self,
    ) ?*const workflow.SaveValidated {
        return switch (self.core) {
            .save_passed => |*value| value,
            .full_passed => |*value| &value.save_validated,
            else => null,
        };
    }

    fn dropCandidate(self: *Self) void {
        if (self.candidate) |*candidate| candidate.deinit();
        secureWipe(&self.candidate);
        self.candidate = null;
    }

    fn controlDisplay(
        self: *const Self,
        index: usize,
        slot: *const transaction.Slot,
    ) ControlDisplay {
        if (slot.sensitivity == .credential_forbidden) {
            return .credential_locked_empty;
        }
        return switch (slot.value) {
            .missing => .missing,
            .checked => |checked| .{ .checked = checked },
            .text => |*text| if (self.control_revealed[index])
                .{ .revealed_text = text.asSlice() }
            else
                .{ .masked_text = summarizeControl(text.asSlice()) },
        };
    }

    fn valueSource(self: *const Self, index: usize) ValueSource {
        if (self.user_edited[index]) return .user_edit;
        const slot = &self.transactionState().slots[index];
        return switch (slot.origin) {
            .profile => .profile_projection,
            .filing_context => if (isLockedFilingIdentity(slot.id))
                .explicit_filing_context
            else
                .hta_markup_default,
            .transaction, .system => .hta_markup_default,
            .external_evidence => .evidence_needed_empty,
            .preparer => .credential_locked_empty,
            .derived => switch (self.core) {
                .editing => .hta_markup_default,
                else => .calculated,
            },
            .unreviewed => unreachable,
        };
    }
};

fn setEditingSlotFromRaw(
    editing: *workflow.Editing,
    origin: transaction.Origin,
    kind: occurrences.ControlKind,
    control_id: []const u8,
    raw: []const u8,
) Error!void {
    switch (kind) {
        .radio => {
            const checked = if (std.mem.eql(u8, raw, "true"))
                true
            else if (std.mem.eql(u8, raw, "false"))
                false
            else
                return error.PersistedControlValueMismatch;
            try editing.setChecked(origin, control_id, checked);
        },
        .text, .select_one => try editing.setText(origin, control_id, raw),
    }
}

fn slotMatchesRaw(
    slot: *const transaction.Slot,
    raw: []const u8,
) bool {
    return switch (slot.value) {
        .missing => false,
        .text => |*text| std.mem.eql(u8, text.asSlice(), raw),
        .checked => |checked| std.mem.eql(
            u8,
            raw,
            if (checked) "true" else "false",
        ),
    };
}

fn concatenatedSlotsMatch(
    first: *const transaction.Slot,
    second: *const transaction.Slot,
    raw: []const u8,
) bool {
    const first_text = switch (first.value) {
        .text => |*text| text.asSlice(),
        else => return false,
    };
    const second_text = switch (second.value) {
        .text => |*text| text.asSlice(),
        else => return false,
    };
    const joined_len = std.math.add(
        usize,
        first_text.len,
        second_text.len,
    ) catch return false;
    return raw.len == joined_len and
        std.mem.eql(u8, raw[0..first_text.len], first_text) and
        std.mem.eql(u8, raw[first_text.len..], second_text);
}

fn snapshotEnvelopeMatches(
    regenerated: *const draft.DraftSnapshot,
    persisted: *const draft.DraftSnapshot,
) bool {
    return regenerated.schema.package_key.eql(
        &persisted.schema.package_key,
    ) and
        regenerated.schema.package_digest.eql(
            &persisted.schema.package_digest,
        ) and
        regenerated.schema.occurrence_manifest_digest.eql(
            &persisted.schema.occurrence_manifest_digest,
        ) and
        regenerated.schema.exact_schema_digest.eql(
            &persisted.schema.exact_schema_digest,
        ) and
        regenerated.schema.payload_shape ==
            persisted.schema.payload_shape and
        regenerated.schema.occurrence_count ==
            persisted.schema.occurrence_count and
        std.meta.eql(
            regenerated.schema.evidence_readiness,
            persisted.schema.evidence_readiness,
        ) and
        regenerated.profile_snapshot_digest.eql(
            &persisted.profile_snapshot_digest,
        ) and
        regenerated.transaction_state_digest.eql(
            &persisted.transaction_state_digest,
        ) and
        regenerated.ordered_values_digest.eql(
            &persisted.ordered_values_digest,
        ) and
        std.meta.eql(
            regenerated.validation_status,
            persisted.validation_status,
        ) and
        std.meta.eql(
            regenerated.artifact_status,
            persisted.artifact_status,
        );
}

fn snapshotOccurrencesMatch(
    regenerated: *const draft.DraftSnapshot,
    persisted: *const draft.DraftSnapshot,
) bool {
    if (regenerated.occurrences.len != persisted.occurrences.len) {
        return false;
    }
    for (
        regenerated.occurrences,
        persisted.occurrences,
    ) |left, right| {
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

fn saveRuleMessage(rule: validation.SaveRule) RuleMessage {
    return .{
        .gate = .save,
        .id = .{ .save = rule.id },
        .source_order = rule.source_order,
        .source_line = rule.source_line,
        .message = rule.alert,
    };
}

fn fullRuleMessage(rule: validation.FullRule) RuleMessage {
    return .{
        .gate = .full,
        .id = .{ .full = rule.id },
        .source_order = rule.source_order,
        .source_line = rule.source_line,
        .message = rule.alert,
    };
}

fn validationBlockMessage(block: validation.ValidationBlock) []const u8 {
    return switch (block) {
        .spouse_tin_checksum_not_evaluated => "Spouse TIN checksum has not been evaluated by the grounded adapter.",
    };
}

fn candidateLabel(
    shape: draft.PayloadShape,
    exactness: workflow.Exactness,
) []const u8 {
    return switch (shape) {
        .editable_save => switch (exactness) {
            .candidate => "1701Q editable plaintext candidate (not evidence-qualified)",
            .exact => "1701Q exact editable plaintext (evidence-qualified)",
        },
        .final_copy_plaintext => switch (exactness) {
            .candidate => "1701Q Final Copy plaintext candidate (not evidence-qualified)",
            .exact => "1701Q exact Final Copy plaintext (evidence-qualified)",
        },
    };
}

fn summarizeControl(raw: []const u8) MaskedControlSummary {
    return .{
        .populated = raw.len != 0,
        .byte_length = raw.len,
    };
}

fn strictEditable(bytes: []const u8) bool {
    var parsed = editable_codec.parseAsciiExact(
        std.heap.page_allocator,
        bytes,
        .editable,
    ) catch return false;
    defer parsed.deinit(std.heap.page_allocator);
    return true;
}

fn strictFinal(bytes: []const u8) bool {
    var parsed = final_copy_codec.parseAsciiExact(
        std.heap.page_allocator,
        bytes,
    ) catch return false;
    defer parsed.deinit(std.heap.page_allocator);
    return true;
}

fn countSubslice(haystack: []const u8, needle: []const u8) usize {
    if (needle.len == 0 or needle.len > haystack.len) return 0;
    var count: usize = 0;
    var index: usize = 0;
    while (index + needle.len <= haystack.len) : (index += 1) {
        if (std.mem.eql(u8, haystack[index..][0..needle.len], needle)) {
            count += 1;
        }
    }
    return count;
}

fn secureWipe(value: anytype) void {
    std.crypto.secureZero(u8, std.mem.asBytes(value));
}

fn legacyBlurOutcome(
    outcome: QualifiedBlurOutcome,
) BlurOutcome {
    return .{
        .alert = outcome.alert,
        .mutation = switch (outcome.mutation) {
            .cleared => .cleared,
            .reset_to_zero => .reset_to_zero,
            .unchanged, .uppercased, .canonical_money => .unchanged,
        },
        .focus = outcome.focus,
        .legacy_return_is_valid = outcome.legacy_return_is_valid,
    };
}

fn dummyScheduleDateContext(
    current_year: i32,
) validation.ScheduleDateContext {
    return .{
        .current_date = .{
            .year = current_year,
            .month = 1,
            .day = 1,
        },
        .empty_default_input_was_later = false,
    };
}

// -------------------------------------------------------------------------
// Runtime/context behavior layered over the permanent declaration contract.

const InitialOverride = enum {
    profile_projection,
    filing_year,
    filing_quarter,
    filing_amended,
    current_page_runtime_reset,
};

fn initialOverride(
    origin: occurrence.OriginKind,
    control_id: []const u8,
) ?InitialOverride {
    if (origin == .profile) return .profile_projection;
    if (std.mem.eql(u8, control_id, "frm1701q:txtYear")) {
        return .filing_year;
    }
    if (std.mem.startsWith(
        u8,
        control_id,
        "frm1701q:DateQuarter_",
    )) return .filing_quarter;
    if (std.mem.startsWith(
        u8,
        control_id,
        "frm1701q:AmendedRtn_",
    )) return .filing_amended;
    if (std.mem.eql(
        u8,
        control_id,
        "frm1701q:txtCurrentPage",
    )) return .current_page_runtime_reset;
    return null;
}

fn seedGroundedInitialValues(
    editing: *workflow.Editing,
    context: FilingContext,
) Error!void {
    const year = yearText(context.tax_year);

    for (occurrences.control_seeds, 0..) |seed, index| {
        const declaration = control_contract.contracts[index];
        std.debug.assert(std.mem.eql(u8, seed.id, declaration.id));
        std.debug.assert(seed.kind == declaration.kind);
        std.debug.assert(seed.source_line == declaration.source_line);
        const origin = editing.transaction_state.slots[index].origin;
        switch (origin) {
            .profile => {},
            .filing_context => switch (seed.kind) {
                .text, .select_one => try editing.setText(
                    .filing_context,
                    seed.id,
                    if (std.mem.eql(u8, seed.id, "frm1701q:txtYear"))
                        &year
                    else
                        declaration.declared_value,
                ),
                .radio => try editing.setChecked(
                    .filing_context,
                    seed.id,
                    filingContextRadioValue(context, seed.id),
                ),
            },
            .transaction => switch (seed.kind) {
                .radio => try editing.setChecked(
                    .transaction,
                    seed.id,
                    declaration.radio_declaration.?.checked,
                ),
                .text, .select_one => try editing.setText(
                    .transaction,
                    seed.id,
                    declaration.declared_value,
                ),
            },
            .external_evidence => try editing.setText(
                .external_evidence,
                seed.id,
                declaration.declared_value,
            ),
            .derived => setInternalText(
                &editing.transaction_state,
                index,
                declaration.declared_value,
            ),
            .system => try editing.setText(
                .system,
                seed.id,
                if (std.mem.eql(
                    u8,
                    seed.id,
                    "frm1701q:txtCurrentPage",
                ))
                    "1"
                else
                    declaration.declared_value,
            ),
            .preparer => std.debug.assert(std.mem.eql(
                u8,
                declaration.declared_value,
                "",
            )),
            .unreviewed => unreachable,
        }
    }
}

fn yearText(year: u16) [4]u8 {
    std.debug.assert(year >= 1000 and year <= 9999);
    return .{
        @intCast('0' + (year / 1000) % 10),
        @intCast('0' + (year / 100) % 10),
        @intCast('0' + (year / 10) % 10),
        @intCast('0' + year % 10),
    };
}

fn filingContextRadioValue(
    context: FilingContext,
    control_id: []const u8,
) bool {
    if (std.mem.eql(u8, control_id, "frm1701q:DateQuarter_1")) {
        return context.quarter == .first;
    }
    if (std.mem.eql(u8, control_id, "frm1701q:DateQuarter_2")) {
        return context.quarter == .second;
    }
    if (std.mem.eql(u8, control_id, "frm1701q:DateQuarter_3")) {
        return context.quarter == .third;
    }
    if (std.mem.eql(u8, control_id, "frm1701q:AmendedRtn_1")) {
        return context.amended;
    }
    if (std.mem.eql(u8, control_id, "frm1701q:AmendedRtn_2")) {
        return !context.amended;
    }
    unreachable;
}

fn isMoneyControl(control_id: []const u8) bool {
    if (std.mem.startsWith(u8, control_id, "frm1701q:txtAmount")) {
        return true;
    }
    const origin = transaction.classifyControl(control_id) orelse
        return false;
    if (origin != .transaction) {
        return false;
    }
    const declaration = control_contract.find(control_id) orelse
        return false;
    return std.mem.eql(u8, declaration.declared_value, "0.00");
}

fn isScheduleDateControl(control_id: []const u8) bool {
    return std.mem.eql(u8, control_id, "frm1701q:txtDate32") or
        std.mem.eql(u8, control_id, "frm1701q:txtDate33") or
        std.mem.eql(u8, control_id, "frm1701q:txtDate34") or
        std.mem.eql(u8, control_id, "frm1701q:txtDate35");
}

/// Derived fields are reserved from application edits. Seeding their
/// declaration defaults therefore writes the public typed slot directly; the
/// next workflow calculation replaces every one atomically.
fn setInternalText(
    state: *transaction.State,
    index: usize,
    raw: []const u8,
) void {
    std.debug.assert(state.slots[index].origin == .derived);
    std.debug.assert(state.slots[index].kind != .radio);
    var stored: transaction.StoredText = .{};
    @memcpy(stored.bytes[0..raw.len], raw);
    stored.len = @intCast(raw.len);
    state.slots[index].value = .{ .text = stored };
}

fn controlIndex(control_id: []const u8) ?usize {
    for (occurrences.control_seeds, 0..) |seed, index| {
        if (std.mem.eql(u8, seed.id, control_id)) return index;
    }
    return null;
}

fn validateQualifiedCommitDomain(
    control_id: []const u8,
    entered: []const u8,
    money_centavos: ?i64,
) Error!void {
    const binding = event_contract.find(
        control_id,
        .key_press,
    ) orelse return;
    switch (binding.fact) {
        .empty_attribute => {},
        .key_press_date_only => {
            if (money_centavos != null or
                !allBytesIn(entered, "0123456789/"))
            {
                return error.CommitValueOutsideKeyPressDomain;
            }
        },
        .key_press_letter_number => {
            if (money_centavos != null or
                !allAsciiAlphaNumeric(entered))
            {
                return error.CommitValueOutsideKeyPressDomain;
            }
        },
        .key_press_numbers_only => {
            const centavos = money_centavos orelse
                return error.CommitValueOutsideKeyPressDomain;
            if (centavos < 0) {
                return error.CommitValueOutsideKeyPressDomain;
            }
        },
        .key_press_numbers_with_negative => {
            _ = money_centavos orelse
                return error.CommitValueOutsideKeyPressDomain;
        },
        .key_press_whole_number => {
            if (money_centavos) |centavos| {
                if (centavos < 0) {
                    return error.CommitValueOutsideKeyPressDomain;
                }
            } else if (!allBytesIn(entered, "0123456789")) {
                return error.CommitValueOutsideKeyPressDomain;
            }
        },
        else => unreachable,
    }
}

fn allBytesIn(value: []const u8, allowed: []const u8) bool {
    for (value) |byte| {
        if (std.mem.indexOfScalar(u8, allowed, byte) == null) {
            return false;
        }
    }
    return true;
}

fn allAsciiAlphaNumeric(value: []const u8) bool {
    for (value) |byte| {
        if (!std.ascii.isAlphabetic(byte) and
            !std.ascii.isDigit(byte))
        {
            return false;
        }
    }
    return true;
}

fn isLockedFilingIdentity(control_id: []const u8) bool {
    return std.mem.eql(u8, control_id, "frm1701q:txtYear") or
        std.mem.startsWith(
            u8,
            control_id,
            "frm1701q:DateQuarter_",
        ) or
        std.mem.startsWith(
            u8,
            control_id,
            "frm1701q:AmendedRtn_",
        );
}

fn isUiEditable(
    origin: occurrence.OriginKind,
    control_id: []const u8,
) bool {
    return switch (origin) {
        .transaction, .external_evidence => true,
        .filing_context => !isLockedFilingIdentity(control_id),
        else => false,
    };
}

const quarter_radios = [_][]const u8{
    "frm1701q:DateQuarter_1",
    "frm1701q:DateQuarter_2",
    "frm1701q:DateQuarter_3",
};
const amended_radios = [_][]const u8{
    "frm1701q:AmendedRtn_1",
    "frm1701q:AmendedRtn_2",
};
const filer_type_radios = [_][]const u8{
    "frm1701q:optType_1",
    "frm1701q:optType_2",
    "frm1701q:optType_3",
    "frm1701q:optType_4",
};
const filer_atc_radios = [_][]const u8{
    "frm1701q:optATC_1",
    "frm1701q:optATC_2",
    "frm1701q:optATC_3",
    "frm1701q:optATC_4",
    "frm1701q:optATC_5",
    "frm1701q:optATC_6",
};
const filer_foreign_credit_radios = [_][]const u8{
    "frm1701q:optForeignTaxCredits_1",
    "frm1701q:optForeignTaxCredits_2",
};
const filer_tax_rate_radios = [_][]const u8{
    "frm1701q:optTaxRate_1",
    "frm1701q:optTaxRate_2",
};
const filer_deduction_radios = [_][]const u8{
    "frm1701q:optMethodOfDeduction:_1",
    "frm1701q:optMethodOfDeduction:_2",
};
const spouse_type_radios = [_][]const u8{
    "frm1701q:optSpouseType_1",
    "frm1701q:optSpouseType_2",
    "frm1701q:optSpouseType_3",
};
const spouse_atc_radios = [_][]const u8{
    "frm1701q:optSpouseATC_1",
    "frm1701q:optSpouseATC_2",
    "frm1701q:optSpouseATC_3",
    "frm1701q:optSpouseATC_4",
    "frm1701q:optSpouseATC_5",
    "frm1701q:optSpouseATC_6",
    "frm1701q:optSpouseATC_7",
};
const spouse_foreign_credit_radios = [_][]const u8{
    "frm1701q:optSpouseForeignTaxCred_1",
    "frm1701q:optSpouseForeignTaxCred_2",
};
const spouse_tax_rate_radios = [_][]const u8{
    "frm1701q:optSpouseTaxRate_1",
    "frm1701q:optSpouseTaxRate_2",
};
const spouse_deduction_radios = [_][]const u8{
    "frm1701q:optSpouseMethod:_1",
    "frm1701q:optSpouseMethod:_2",
};

fn radioBehavior(control_id: []const u8) ?RadioBehavior {
    inline for (std.meta.fields(RadioGroup)) |group_field| {
        const group: RadioGroup = @enumFromInt(group_field.value);
        for (radioGroupMembers(group)) |member| {
            if (std.mem.eql(u8, member, control_id)) {
                return .{ .exclusive = group };
            }
        }
    }
    for (spouse_type_radios) |member| {
        if (std.mem.eql(u8, member, control_id)) {
            return .spouse_type_independent;
        }
    }
    return null;
}

fn radioGroupMembers(group: RadioGroup) []const []const u8 {
    return switch (group) {
        .quarter => &quarter_radios,
        .amended => &amended_radios,
        .filer_type => &filer_type_radios,
        .filer_atc => &filer_atc_radios,
        .filer_foreign_tax_credit => &filer_foreign_credit_radios,
        .filer_tax_rate => &filer_tax_rate_radios,
        .filer_deduction => &filer_deduction_radios,
        .spouse_atc => &spouse_atc_radios,
        .spouse_foreign_tax_credit => &spouse_foreign_credit_radios,
        .spouse_tax_rate => &spouse_tax_rate_radios,
        .spouse_deduction => &spouse_deduction_radios,
    };
}

// -------------------------------------------------------------------------
// Focused adapter tests.

fn testProfile(
    include_spouse: bool,
    effective_on: model.Date,
) !projection.Snapshot {
    var snapshot = projection.Snapshot.init(form.revision, effective_on);
    const filer_provenance: projection.Provenance = .{
        .profile_id = try model.ProfileId.parse(
            "exact-ui-synthetic-filer",
        ),
        .revision_id = try model.RevisionId.parse(
            "exact-ui-synthetic-filer-r1",
        ),
        .revision_sequence = 1,
        .revision_source = .manual_entry,
    };
    try snapshot.append(.{
        .role = .filer,
        .target = form.filer_requirements[0].target,
        .value = .{ .tin = try field.Tin.parse("123-456-789-000") },
        .provenance = filer_provenance,
    });
    try snapshot.append(.{
        .role = .filer,
        .target = form.filer_requirements[1].target,
        .value = .{ .rdo_code = try field.RdoCode.parse("019") },
        .provenance = filer_provenance,
    });
    try snapshot.append(.{
        .role = .filer,
        .target = form.filer_requirements[2].target,
        .value = .{
            .taxpayer_name = try field.TaxpayerName.parse(
                "SYNTHETIC FILER",
            ),
        },
        .provenance = filer_provenance,
    });
    try snapshot.append(.{
        .role = .filer,
        .target = form.filer_requirements[3].target,
        .value = .{
            .registered_address = try field.RegisteredAddress.parse(
                "SYNTHETIC REGISTERED ADDRESS",
            ),
        },
        .provenance = filer_provenance,
    });
    try snapshot.append(.{
        .role = .filer,
        .target = form.filer_requirements[4].target,
        .value = .{ .zip_code = try field.ZipCode.parse("1000") },
        .provenance = filer_provenance,
    });
    try snapshot.append(.{
        .role = .filer,
        .target = form.filer_requirements[5].target,
        .value = .{
            .date_of_birth = try model.Date.init(1990, 1, 15),
        },
        .provenance = filer_provenance,
    });
    try snapshot.append(.{
        .role = .filer,
        .target = form.filer_requirements[6].target,
        .value = .{
            .email_address = try field.EmailAddress.parse(
                "synthetic@example.test",
            ),
        },
        .provenance = filer_provenance,
    });

    if (include_spouse) {
        const spouse_provenance: projection.Provenance = .{
            .profile_id = try model.ProfileId.parse(
                "exact-ui-synthetic-spouse",
            ),
            .revision_id = try model.RevisionId.parse(
                "exact-ui-synthetic-spouse-r1",
            ),
            .revision_sequence = 1,
            .revision_source = .manual_entry,
        };
        try snapshot.append(.{
            .role = .spouse,
            .target = form.spouse_requirements[0].target,
            .value = .{
                .tin = try field.Tin.parse("987-654-321-001"),
            },
            .provenance = spouse_provenance,
        });
        try snapshot.append(.{
            .role = .spouse,
            .target = form.spouse_requirements[1].target,
            .value = .{ .rdo_code = try field.RdoCode.parse("020") },
            .provenance = spouse_provenance,
        });
        try snapshot.append(.{
            .role = .spouse,
            .target = form.spouse_requirements[2].target,
            .value = .{
                .taxpayer_name = try field.TaxpayerName.parse(
                    "SYNTHETIC SPOUSE",
                ),
            },
            .provenance = spouse_provenance,
        });
    }
    return snapshot;
}

fn initTestState(
    out: *State,
    include_spouse: bool,
    context: FilingContext,
    workspace_byte: u8,
) !void {
    var snapshot = try testProfile(
        include_spouse,
        try context.profileAsOf(),
    );
    defer secureWipe(&snapshot);
    const workspace_id = try draft.DraftWorkspaceId.init(
        [_]u8{workspace_byte} ** 16,
    );
    switch (try State.openInto(
        out,
        std.testing.allocator,
        workspace_id,
        context,
        &snapshot,
    )) {
        .opened => {},
        .blocked => return error.UnexpectedProfileMappingBlock,
    }
}

fn expectText(
    state: *State,
    control_id: []const u8,
    expected: []const u8,
) !void {
    try state.setControlRevealed(control_id, true);
    const view = try state.control(control_id);
    switch (view.display) {
        .revealed_text => |actual| try std.testing.expectEqualStrings(
            expected,
            actual,
        ),
        else => return error.ExpectedRevealedText,
    }
}

fn checkedValue(
    state: *const State,
    control_id: []const u8,
) !bool {
    const view = try state.control(control_id);
    return switch (view.display) {
        .checked => |checked| checked,
        else => error.ExpectedCheckedValue,
    };
}

fn expectSlotTextDirect(
    slot: *const transaction.Slot,
    expected: []const u8,
) !void {
    switch (slot.value) {
        .text => |*text| try std.testing.expectEqualStrings(
            expected,
            text.asSlice(),
        ),
        else => return error.ExpectedStoredText,
    }
}

fn selectRequiredElections(
    state: *State,
    include_spouse: bool,
) !void {
    try state.setRadio("frm1701q:optType_1", true);
    try state.setRadio("frm1701q:optATC_1", true);
    try state.setRadio("frm1701q:optTaxRate_1", true);
    try state.setRadio(
        "frm1701q:optMethodOfDeduction:_1",
        true,
    );
    if (include_spouse) {
        // Each legacy spouse-type control starts with waschecked="true":
        // the first activation clears it and the second selects it.
        try state.setRadio("frm1701q:optSpouseType_1", true);
        try state.setRadio("frm1701q:optSpouseType_1", true);
        try state.setRadio("frm1701q:optSpouseATC_1", true);
        try state.setRadio("frm1701q:optSpouseTaxRate_1", true);
        try state.setRadio(
            "frm1701q:optSpouseMethod:_1",
            true,
        );
    }
}

fn expectSavePassed(
    state: *State,
    checksum: validation.TinChecksumStatus,
) !void {
    switch (try state.validateSave(2026, checksum)) {
        .passed => {},
        .failed => return error.ExpectedSavePass,
    }
}

fn expectFullPassed(state: *State) !void {
    switch (try state.validateFull()) {
        .passed => {},
        .failed, .blocked => return error.ExpectedFullPass,
    }
}

fn replaySnapshot(
    history: *draft.DraftHistory,
    snapshot: *const draft.DraftSnapshot,
) !void {
    if (snapshot.occurrences.len > control_count) {
        return error.ReopenOccurrenceMismatch;
    }
    var values: [control_count]draft.OccurrenceValue = undefined;
    defer secureWipe(&values);
    for (snapshot.occurrences, 0..) |stored, index| {
        values[index] = .{
            .ordinal = stored.ordinal,
            .serialized_key = stored.serialized_key,
            .same_key_occurrence = stored.same_key_occurrence,
            .raw_value = stored.raw_value,
            .normalized_value = stored.normalized_value,
            .emitted_value = stored.emitted_value,
        };
    }
    _ = try history.replayPersistedRevision(.{
        .draft_identity = snapshot.draft_identity,
        .revision = snapshot.revision,
        .parent_revision = snapshot.parent_revision,
        .schema = snapshot.schema,
        .occurrences = values[0..snapshot.occurrences.len],
        .profile_snapshot_digest = snapshot.profile_snapshot_digest,
        .transaction_state_digest = snapshot.transaction_state_digest,
        .ordered_values_digest = snapshot.ordered_values_digest,
        .validation_status = snapshot.validation_status,
        .artifact_status = snapshot.artifact_status,
    });
}

fn decodeSyntheticCiphertext(
    comptime encoded: []const u8,
) [encoded.len / 2]u8 {
    var decoded: [encoded.len / 2]u8 = undefined;
    _ = std.fmt.hexToBytes(&decoded, encoded) catch unreachable;
    return decoded;
}

test "exact UI adapter: consuming phases retain one inline owner and deinit erases it" {
    const context: FilingContext = .{
        .tax_year = 2025,
        .quarter = .first,
        .amended = false,
    };
    var state: State = undefined;
    try initTestState(&state, false, context, 0x10);
    var owns_state = true;
    defer if (owns_state) state.deinit();

    const unique_profile_value = "synthetic@example.test";
    try std.testing.expectEqual(
        @as(usize, 1),
        countSubslice(std.mem.asBytes(&state), unique_profile_value),
    );

    try selectRequiredElections(&state, false);
    try state.calculate();
    try std.testing.expectEqual(
        @as(usize, 1),
        countSubslice(std.mem.asBytes(&state), unique_profile_value),
    );
    try expectSavePassed(&state, .not_evaluated);
    try std.testing.expectEqual(
        @as(usize, 1),
        countSubslice(std.mem.asBytes(&state), unique_profile_value),
    );
    try expectFullPassed(&state);
    try std.testing.expectEqual(
        @as(usize, 1),
        countSubslice(std.mem.asBytes(&state), unique_profile_value),
    );

    state.deinit();
    owns_state = false;
    for (std.mem.asBytes(&state)) |byte| {
        try std.testing.expectEqual(@as(u8, 0), byte);
    }
}

test "exact UI adapter: filer-only open binds quarter-end identity and all 173 defaults" {
    const context: FilingContext = .{
        .tax_year = 2025,
        .quarter = .first,
        .amended = false,
    };
    var state: State = undefined;
    try initTestState(&state, false, context, 0x11);
    defer state.deinit();

    try std.testing.expectEqual(Phase.editing, state.phase());
    try std.testing.expect(!state.spouseProfilePresent());
    try std.testing.expect(std.meta.eql(
        context,
        state.filingContext(),
    ));
    try std.testing.expect(state.profileAsOf().eql(
        try model.Date.init(2025, 3, 31),
    ));

    const controls = state.controls();
    try std.testing.expectEqual(@as(usize, 173), controls.len);
    for (controls) |control| {
        switch (control.display) {
            .missing => return error.UnexpectedMissingInitialValue,
            else => {},
        }
        if (control.kind == .radio) {
            try std.testing.expect(control.radio_behavior != null);
        }
    }
    try std.testing.expectEqual(@as(u16, 1), controls[0].stable_ordinal);
    try std.testing.expectEqualStrings(
        "frm1701q:txtYear",
        controls[0].id,
    );
    try expectText(&state, "frm1701q:txtYear", "2025");
    try expectText(&state, "frm1701q:txtSheets", "0");
    try expectText(&state, "frm1701q:txtCurrentPage", "1");
    try expectText(&state, "frm1701q:txtMaxPage", "2");
    try expectText(&state, "txtFinalFlag", "0");
    try expectText(&state, "txtEnroll", "N");
    try std.testing.expect(try checkedValue(
        &state,
        "frm1701q:DateQuarter_1",
    ));
    try std.testing.expect(!(try checkedValue(
        &state,
        "frm1701q:AmendedRtn_1",
    )));
    try std.testing.expect(try checkedValue(
        &state,
        "frm1701q:AmendedRtn_2",
    ));
    try std.testing.expect(!(try state.control(
        "frm1701q:AmendedRtn_1",
    )).disabled);
    try std.testing.expect((try state.control(
        "frm1701q:txt59A",
    )).disabled);

    const taxpayer_name = try state.control(
        "frm1701q:txtTaxpayerName",
    );
    try std.testing.expect(taxpayer_name.read_only);
    switch (taxpayer_name.display) {
        .masked_text => |summary| {
            try std.testing.expect(summary.populated);
        },
        else => return error.ExpectedMaskedProfileValue,
    }
    try expectText(
        &state,
        "frm1701q:txtTaxpayerName",
        "SYNTHETIC FILER",
    );
    try expectText(&state, "frm1701q:txtSpouseName", "");

    const filer_rdo = try state.rdoSelection(.filer);
    try std.testing.expectEqualStrings("019", filer_rdo.value());
    const spouse_rdo = try state.rdoSelection(.spouse);
    try std.testing.expectEqualStrings("000", spouse_rdo.value());
    try std.testing.expectError(
        error.InvalidRdoOption,
        RdoOption.parse("999"),
    );
    try std.testing.expectError(
        error.ForbiddenEditOrigin,
        state.setText("frm1701q:txtRDOCode", "020"),
    );

    // Grounded defaults make calculation possible after genuine elections;
    // callers never need to synthesize hidden/system values.
    try selectRequiredElections(&state, false);
    try state.calculate();
    try std.testing.expectEqual(Phase.calculated, state.phase());
}

test "exact UI adapter: every initial view reconciles the engine declaration contract" {
    const context: FilingContext = .{
        .tax_year = 2025,
        .quarter = .second,
        .amended = true,
    };
    var state: State = undefined;
    try initTestState(&state, true, context, 0x1b);
    defer state.deinit();

    const views = state.controls();
    const current = state.transactionState();
    for (
        views,
        control_contract.contracts,
        &current.slots,
        0..,
    ) |view, declaration, *slot, index| {
        try std.testing.expectEqualStrings(declaration.id, view.id);
        try std.testing.expectEqual(
            declaration.source_line,
            view.source_line,
        );
        try std.testing.expectEqual(declaration.kind, view.kind);
        try std.testing.expectEqual(
            declaration.max_length,
            view.maximum_length,
        );
        try std.testing.expectEqualStrings(
            declaration.declared_value,
            view.declared_value,
        );
        try std.testing.expectEqual(
            declaration.disabled_in_markup,
            view.disabled_in_markup,
        );
        try std.testing.expectEqualStrings(
            occurrences.control_seeds[index].id,
            view.id,
        );

        if (initialOverride(slot.origin, slot.id)) |override| {
            switch (override) {
                .profile_projection => {
                    try std.testing.expectEqual(
                        occurrence.OriginKind.profile,
                        slot.origin,
                    );
                },
                .filing_year => try expectSlotTextDirect(
                    slot,
                    "2025",
                ),
                .filing_quarter => switch (slot.value) {
                    .checked => |checked| try std.testing.expectEqual(
                        filingContextRadioValue(context, slot.id),
                        checked,
                    ),
                    else => return error.ExpectedCheckedValue,
                },
                .filing_amended => switch (slot.value) {
                    .checked => |checked| try std.testing.expectEqual(
                        filingContextRadioValue(context, slot.id),
                        checked,
                    ),
                    else => return error.ExpectedCheckedValue,
                },
                .current_page_runtime_reset => try expectSlotTextDirect(slot, "1"),
            }
            continue;
        }

        switch (declaration.kind) {
            .radio => switch (slot.value) {
                .checked => |checked| try std.testing.expectEqual(
                    declaration.radio_declaration.?.checked,
                    checked,
                ),
                else => return error.ExpectedCheckedValue,
            },
            .text, .select_one => try expectSlotTextDirect(
                slot,
                declaration.declared_value,
            ),
        }
    }
}

test "exact UI adapter: distinct spouse projection remains visible and separately qualified" {
    const context: FilingContext = .{
        .tax_year = 2025,
        .quarter = .second,
        .amended = true,
    };
    var state: State = undefined;
    try initTestState(&state, true, context, 0x12);
    defer state.deinit();

    try expectText(
        &state,
        "frm1701q:txtSpouseName",
        "SYNTHETIC SPOUSE",
    );
    try std.testing.expect(state.spouseProfilePresent());
    try std.testing.expect(!(try state.control(
        "frm1701q:txt59A",
    )).disabled);
    try std.testing.expect(!(try state.control(
        "frm1701q:txt59B",
    )).disabled);
    const spouse_rdo = try state.rdoSelection(.spouse);
    try std.testing.expectEqualStrings("020", spouse_rdo.value());
    try std.testing.expect(state.profileAsOf().eql(
        try model.Date.init(2025, 6, 30),
    ));
    try std.testing.expect(try checkedValue(
        &state,
        "frm1701q:AmendedRtn_1",
    ));

    try selectRequiredElections(&state, true);
    try state.calculate();
    try expectSavePassed(&state, .valid);
    try expectFullPassed(&state);
}

test "exact UI adapter: open rejects profile-as-of drift and filing identity is locked" {
    const context: FilingContext = .{
        .tax_year = 2025,
        .quarter = .third,
        .amended = false,
    };
    var snapshot = try testProfile(
        false,
        try model.Date.init(2025, 6, 30),
    );
    defer secureWipe(&snapshot);
    var state: State = undefined;
    try std.testing.expectError(
        error.ProfileAsOfMismatch,
        State.openInto(
            &state,
            std.testing.allocator,
            try draft.DraftWorkspaceId.init([_]u8{0x13} ** 16),
            context,
            &snapshot,
        ),
    );

    try initTestState(&state, false, context, 0x14);
    defer state.deinit();
    try std.testing.expectError(
        error.FilingContextLocked,
        state.setText("frm1701q:txtYear", "2024"),
    );
    try std.testing.expectError(
        error.FilingContextLocked,
        state.setRadio("frm1701q:DateQuarter_1", true),
    );
    try std.testing.expectError(
        error.FilingContextLocked,
        state.setRadio("frm1701q:AmendedRtn_1", true),
    );
    try std.testing.expect(state.profileAsOf().eql(
        try model.Date.init(2025, 9, 30),
    ));
}

test "exact UI adapter: radio groups are atomic while spouse type preserves multi-check quirk" {
    const context: FilingContext = .{
        .tax_year = 2025,
        .quarter = .first,
        .amended = false,
    };
    var state: State = undefined;
    try initTestState(&state, true, context, 0x15);
    defer state.deinit();

    try state.setRadio("frm1701q:optType_1", true);
    try state.setRadio("frm1701q:optType_2", true);
    try std.testing.expect(!(try checkedValue(
        &state,
        "frm1701q:optType_1",
    )));
    try std.testing.expect(try checkedValue(
        &state,
        "frm1701q:optType_2",
    ));

    try state.setRadio("frm1701q:optSpouseType_1", true);
    try state.setRadio("frm1701q:optSpouseType_1", true);
    try state.setRadio("frm1701q:optSpouseType_2", true);
    try state.setRadio("frm1701q:optSpouseType_2", true);
    try std.testing.expect(try checkedValue(
        &state,
        "frm1701q:optSpouseType_1",
    ));
    try std.testing.expect(try checkedValue(
        &state,
        "frm1701q:optSpouseType_2",
    ));
    // The compatibility Boolean cannot force a named browser radio off.
    try state.setRadio("frm1701q:optType_2", false);
    try std.testing.expect(try checkedValue(
        &state,
        "frm1701q:optType_2",
    ));
    try state.setRadio("frm1701q:optSpouseType_1", false);
    try std.testing.expect(!(try checkedValue(
        &state,
        "frm1701q:optSpouseType_1",
    )));
    try std.testing.expect(try checkedValue(
        &state,
        "frm1701q:optSpouseType_2",
    ));
}

test "exact UI adapter: runtime clicks enable, recalculate, clear, and reject disabled actions" {
    const context: FilingContext = .{
        .tax_year = 2025,
        .quarter = .first,
        .amended = false,
    };
    var state: State = undefined;
    try initTestState(&state, false, context, 0x2a);
    defer state.deinit();

    try std.testing.expect((try state.control(
        "frm1701q:txt37A",
    )).disabled);
    try std.testing.expectError(
        error.ControlDisabled,
        state.commitMoney("frm1701q:txt37A", "1.00"),
    );
    try std.testing.expectError(
        error.ControlDisabled,
        state.setText("frm1701q:txtDate32", "03/31/2025"),
    );

    try state.setRadio("frm1701q:optType_1", true);
    try state.setRadio("frm1701q:optATC_1", true);
    try std.testing.expect(!(try state.control(
        "frm1701q:txt36A",
    )).disabled);
    try std.testing.expect((try state.control(
        "frm1701q:txt37A",
    )).disabled);
    try state.setRadio("frm1701q:optMethodOfDeduction:_1", true);
    try std.testing.expect(!(try state.control(
        "frm1701q:txt37A",
    )).disabled);
    try std.testing.expect(!(try state.control(
        "frm1701q:txt39A",
    )).disabled);

    _ = try state.commitMoney("frm1701q:txt36A", "123.00");
    _ = try state.commitMoney("frm1701q:txt37A", "23.00");
    _ = try state.commitMoney("frm1701q:txt39A", "10.00");
    // Re-activating an already selected named radio cannot turn it off; its
    // exact handler still runs and refreshes all derived values.
    try state.setRadio("frm1701q:optMethodOfDeduction:_1", false);
    try std.testing.expect(try checkedValue(
        &state,
        "frm1701q:optMethodOfDeduction:_1",
    ));
    try expectText(&state, "frm1701q:txt38A", "100.00");

    try state.setRadio("frm1701q:optMethodOfDeduction:_2", true);
    try std.testing.expect((try state.control(
        "frm1701q:txt37A",
    )).disabled);
    try std.testing.expect((try state.control(
        "frm1701q:txt39A",
    )).disabled);
    try expectText(&state, "frm1701q:txt37A", "0.00");
    try expectText(&state, "frm1701q:txt39A", "0.00");

    try state.setRadio("frm1701q:optType_3", true);
    try std.testing.expect((try state.control(
        "frm1701q:optSpouseType_1",
    )).disabled);
    try std.testing.expectError(
        error.ControlDisabled,
        state.setRadio("frm1701q:optSpouseType_1", true),
    );
}

test "exact UI adapter: spouse-profile click conflict preserves candidate atomically" {
    const context: FilingContext = .{
        .tax_year = 2025,
        .quarter = .second,
        .amended = true,
    };
    var state: State = undefined;
    try initTestState(&state, true, context, 0x2b);
    defer state.deinit();
    try std.testing.expect(state.spouseProfilePresent());

    try selectRequiredElections(&state, true);
    try state.calculate();
    try expectSavePassed(&state, .valid);
    try state.generateEditableCandidate(.create);
    const before = try state.candidateSummary();
    try std.testing.expectError(
        error.ImmutableSpouseProfileConflict,
        state.setRadio("frm1701q:optType_3", true),
    );
    try std.testing.expectEqual(
        Phase.editable_candidate,
        state.phase(),
    );
    const after = try state.candidateSummary();
    try std.testing.expectEqualSlices(
        u8,
        &before.sha256,
        &after.sha256,
    );
    try std.testing.expect(!(try checkedValue(
        &state,
        "frm1701q:optType_3",
    )));
    try expectText(
        &state,
        "frm1701q:txtSpouseName",
        "SYNTHETIC SPOUSE",
    );
}

test "exact UI adapter: global uppercase blur normalizes form projection without rewriting profile identity" {
    const context: FilingContext = .{
        .tax_year = 2025,
        .quarter = .first,
        .amended = false,
    };
    var snapshot = try testProfile(
        false,
        try context.profileAsOf(),
    );
    defer secureWipe(&snapshot);
    for (snapshot.entries[0..snapshot.len]) |*entry| {
        if (entry.role == .filer and entry.target.eql(
            &form.filer_requirements[2].target,
        )) {
            entry.value = .{
                .taxpayer_name = try field.TaxpayerName.parse(
                    "Mixed Case Filer",
                ),
            };
        }
    }

    var state: State = undefined;
    switch (try State.openInto(
        &state,
        std.testing.allocator,
        try draft.DraftWorkspaceId.init([_]u8{0x2e} ** 16),
        context,
        &snapshot,
    )) {
        .opened => {},
        .blocked => return error.UnexpectedProfileMappingBlock,
    }
    defer state.deinit();
    const profile_digest_before =
        try state.transactionState().digestBundle();
    const provenance_before = try state.transactionState().profileProvenance(
        "frm1701q:txtTaxpayerName",
    );
    const committed = try state.commitAndBlurQualified(
        "frm1701q:txtLOB",
        "small shop",
        .{
            .current_year = 2026,
            .schedule_date = dummyScheduleDateContext(2026),
        },
    );
    const summary = committed.blur orelse
        return error.ExpectedQualifiedBlur;
    try std.testing.expectEqual(
        interaction.BlurMutation.uppercased,
        summary.mutation,
    );
    try expectText(&state, "frm1701q:txtLOB", "SMALL SHOP");
    try expectText(
        &state,
        "frm1701q:txtTaxpayerName",
        "MIXED CASE FILER",
    );
    const profile_digest_after =
        try state.transactionState().digestBundle();
    try std.testing.expect(profile_digest_before.profile_snapshot.eql(
        &profile_digest_after.profile_snapshot,
    ));
    const provenance_after = try state.transactionState().profileProvenance(
        "frm1701q:txtTaxpayerName",
    );
    try std.testing.expect(std.meta.eql(
        provenance_before,
        provenance_after,
    ));
    try std.testing.expectEqual(Phase.editing, state.phase());
}

test "exact UI adapter: atomic qualified commit never installs rejected editor bytes" {
    const context: FilingContext = .{
        .tax_year = 2025,
        .quarter = .first,
        .amended = false,
    };
    var state: State = undefined;
    try initTestState(&state, false, context, 0x2f);
    defer state.deinit();
    const blur_context: QualifiedBlurContext = .{
        .current_year = 2026,
        .schedule_date = dummyScheduleDateContext(2026),
    };

    try selectRequiredElections(&state, false);
    try expectText(&state, "frm1701q:txt36A", "0.00");
    try std.testing.expectError(
        error.InvalidMoney,
        state.commitAndBlurQualified(
            "frm1701q:txt36A",
            "rejected-editor-bytes",
            blur_context,
        ),
    );
    try expectText(&state, "frm1701q:txt36A", "0.00");
    try std.testing.expectError(
        error.CommitValueOutsideKeyPressDomain,
        state.commitAndBlurQualified(
            "frm1701q:txtSheets",
            "1x",
            blur_context,
        ),
    );
    try expectText(&state, "frm1701q:txtSheets", "0");
    try std.testing.expectError(
        error.CommitValueOutsideKeyPressDomain,
        state.commitAndBlurQualified(
            "frm1701q:txt64A",
            "-1.00",
            blur_context,
        ),
    );
    try expectText(&state, "frm1701q:txt64A", "0.00");
    try std.testing.expectEqual(Phase.editing, state.phase());

    // Even a direct follow-up workflow call can only consume the unchanged
    // exact transaction; the rejected editor lexeme was never installed.
    try state.calculate();
    try expectText(&state, "frm1701q:txt36A", "0.00");
    try std.testing.expectEqual(Phase.calculated, state.phase());
}

test "exact UI adapter: atomic commit domain covers every restrictive keypress fact" {
    var restrictive_bindings: usize = 0;
    for (occurrences.control_seeds) |seed| {
        const binding = event_contract.find(
            seed.id,
            .key_press,
        ) orelse continue;
        if (event_contract.isEmpty(binding.fact)) continue;
        restrictive_bindings += 1;
        switch (binding.fact) {
            .key_press_date_only,
            .key_press_letter_number,
            .key_press_numbers_only,
            .key_press_numbers_with_negative,
            .key_press_whole_number,
            => {},
            else => return error.UnclassifiedRestrictiveKeyPressFact,
        }
    }
    try std.testing.expectEqual(
        @as(usize, 78),
        restrictive_bindings,
    );
    try validateQualifiedCommitDomain(
        "frm1701q:txtDate32",
        "01/31/2026",
        null,
    );
    try std.testing.expectError(
        error.CommitValueOutsideKeyPressDomain,
        validateQualifiedCommitDomain(
            "frm1701q:txtDate32",
            "01/31/ABCD",
            null,
        ),
    );
    try validateQualifiedCommitDomain(
        "frm1701q:txtForeignTaxNumber",
        "AbC123",
        null,
    );
    try std.testing.expectError(
        error.CommitValueOutsideKeyPressDomain,
        validateQualifiedCommitDomain(
            "frm1701q:txtForeignTaxNumber",
            "ABC-123",
            null,
        ),
    );
    try validateQualifiedCommitDomain(
        "frm1701q:txtAmount32",
        "1.00",
        100,
    );
    try std.testing.expectError(
        error.CommitValueOutsideKeyPressDomain,
        validateQualifiedCommitDomain(
            "frm1701q:txtAmount32",
            "-1.00",
            -100,
        ),
    );
    try validateQualifiedCommitDomain(
        "frm1701q:txt42A",
        "-1.00",
        -100,
    );
    try std.testing.expectError(
        error.CommitValueOutsideKeyPressDomain,
        validateQualifiedCommitDomain(
            "frm1701q:txt36A",
            "-1.00",
            -100,
        ),
    );
    try validateQualifiedCommitDomain(
        "frm1701q:txtSheets",
        "12",
        null,
    );
    try std.testing.expectError(
        error.CommitValueOutsideKeyPressDomain,
        validateQualifiedCommitDomain(
            "frm1701q:txtTelno",
            "555-0100",
            null,
        ),
    );
    try std.testing.expect(
        !event_contract.key_by_key_filtering_qualified,
    );
}

test "exact UI adapter: qualified blur recalculates and invalidates a stale candidate" {
    const context: FilingContext = .{
        .tax_year = 2025,
        .quarter = .first,
        .amended = false,
    };
    var state: State = undefined;
    try initTestState(&state, false, context, 0x2c);
    defer state.deinit();

    try std.testing.expect(try state.hasBlurBinding(
        "frm1701q:txt36A",
    ));
    try std.testing.expect(!(try state.hasBlurBinding(
        "frm1701q:txtSheets",
    )));
    try std.testing.expect(try state.hasBlurBinding(
        "frm1701q:txtDate32",
    ));
    try std.testing.expectError(
        error.UnknownControl,
        state.hasBlurBinding("frm1701q:not-a-control"),
    );

    try state.setRadio("frm1701q:optType_1", true);
    try state.setRadio("frm1701q:optATC_1", true);
    try state.setRadio("frm1701q:optMethodOfDeduction:_1", true);
    _ = try state.commitMoney("frm1701q:txt36A", "123.49");
    _ = try state.commitMoney("frm1701q:txt37A", "23.00");
    const first = try state.blurQualified(
        "frm1701q:txt36A",
        .{
            .current_year = 2026,
            .schedule_date = dummyScheduleDateContext(2026),
        },
    );
    try std.testing.expectEqual(
        interaction.BlurMutation.canonical_money,
        first.mutation,
    );
    try std.testing.expect(first.recalculated);
    try expectText(&state, "frm1701q:txt38A", "100.00");

    try state.calculate();
    try expectSavePassed(&state, .not_evaluated);
    try state.generateEditableCandidate(.create);
    try std.testing.expectEqual(
        Phase.editable_candidate,
        state.phase(),
    );
    _ = try state.blurQualified(
        "frm1701q:txt36A",
        .{
            .current_year = 2026,
            .schedule_date = dummyScheduleDateContext(2026),
        },
    );
    try std.testing.expectEqual(Phase.editing, state.phase());
    try std.testing.expectError(
        error.NoCandidate,
        state.candidateSummary(),
    );
    try std.testing.expectError(
        error.ControlDisabled,
        state.blurQualified(
            "frm1701q:txtDate32",
            .{
                .current_year = 2026,
                .schedule_date = dummyScheduleDateContext(2026),
            },
        ),
    );
}

test "exact UI adapter: calculated controls are read-only and full validation keeps first rule" {
    const context: FilingContext = .{
        .tax_year = 2025,
        .quarter = .first,
        .amended = false,
    };
    var state: State = undefined;
    try initTestState(&state, false, context, 0x16);
    defer state.deinit();

    try state.calculate();
    const derived = try state.control("frm1701q:txt26A");
    try std.testing.expect(derived.read_only);
    try std.testing.expectEqual(ValueSource.calculated, derived.value_source);
    try expectText(&state, "frm1701q:txt26A", "0.00");
    try std.testing.expectError(
        error.ForbiddenEditOrigin,
        state.setText("frm1701q:txt26A", "1.00"),
    );

    try expectSavePassed(&state, .not_evaluated);
    switch (try state.validateFull()) {
        .failed => |failure| {
            try std.testing.expectEqual(
                validation.FullRuleId.taxpayer_type_required,
                failure.id.full,
            );
            try std.testing.expectEqual(@as(u8, 19), failure.source_order);
            try std.testing.expect(failure.message.len != 0);
        },
        else => return error.ExpectedOrderedFullFailure,
    }
    try std.testing.expectEqual(Phase.full_failed, state.phase());
}

test "exact UI adapter: money commits and exact blur mutations fail closed" {
    const context: FilingContext = .{
        .tax_year = 2025,
        .quarter = .first,
        .amended = false,
    };
    var state: State = undefined;
    try initTestState(&state, false, context, 0x17);
    defer state.deinit();

    try std.testing.expect(!pre_blur_money_grammar_qualified);
    try std.testing.expectError(
        error.ControlDisabled,
        state.setText("frm1701q:txt52A", "1.00"),
    );
    try std.testing.expectError(
        error.ControlDisabled,
        state.commitMoney("frm1701q:txt52A", "250,000.01"),
    );
    try state.setRadio("frm1701q:optType_1", true);
    try state.setRadio("frm1701q:optATC_4", true);
    try std.testing.expect(!(try state.control(
        "frm1701q:txt52A",
    )).disabled);
    try std.testing.expectError(
        error.MoneyRequiresCommit,
        state.setText("frm1701q:txt52A", "1.00"),
    );
    try std.testing.expectError(
        error.InvalidMoney,
        state.commitMoney("frm1701q:txt52A", "1234.56"),
    );
    const committed = try state.commitMoney(
        "frm1701q:txt52A",
        "250,000.01",
    );
    try std.testing.expectEqual(
        @as(usize, "250,000.01".len),
        committed.canonical.byte_length,
    );
    const item52 = try state.blurItem52("frm1701q:txt52A");
    try std.testing.expectEqual(
        BlurMutation.reset_to_zero,
        item52.mutation,
    );
    try std.testing.expect(item52.alert != null);
    try expectText(&state, "frm1701q:txt52A", "0.00");

    try std.testing.expectError(
        error.ControlDisabled,
        state.setText("frm1701q:txtDate32", "12/31/2026"),
    );
    // Official load restores values without replaying click handlers. Seed the
    // persisted lexeme through that same internal route before testing blur.
    try state.restoreOneControl(
        "frm1701q:txtDate32",
        "12/31/2026",
    );
    try std.testing.expectError(
        error.ControlDisabled,
        state.blurScheduleDate(
            "frm1701q:txtDate32",
            .{
                .current_date = .{
                    .year = 2025,
                    .month = 12,
                    .day = 31,
                },
                .empty_default_input_was_later = false,
            },
        ),
    );
    try expectText(&state, "frm1701q:txtDate32", "12/31/2026");

    try state.restoreOneControl(
        "frm1701q:txtDate33",
        "03/31/2025",
    );
    try std.testing.expectError(
        error.ControlDisabled,
        state.blurScheduleDate(
            "frm1701q:txtDate33",
            .{
                .current_date = .{
                    .year = 2025,
                    .month = 3,
                    .day = 31,
                },
                .empty_default_input_was_later = false,
            },
        ),
    );
    try expectText(
        &state,
        "frm1701q:txtDate33",
        "03/31/2025",
    );
}

test "exact UI adapter: year blur clears rejected display without rewriting filing identity" {
    const context: FilingContext = .{
        .tax_year = 2027,
        .quarter = .first,
        .amended = false,
    };
    var state: State = undefined;
    try initTestState(&state, false, context, 0x18);
    defer state.deinit();

    const result = try state.blurYear(2026);
    try std.testing.expectEqual(BlurMutation.cleared, result.mutation);
    try std.testing.expect(result.alert != null);
    try expectText(&state, "frm1701q:txtYear", "");
    try std.testing.expectEqual(@as(u16, 2027), state.filingContext().tax_year);
    try std.testing.expect(state.profileAsOf().eql(
        try model.Date.init(2027, 3, 31),
    ));
    try std.testing.expectError(error.InvalidYear, state.calculate());
}

test "exact UI adapter: candidate is masked, imported decrypt is strict, and edit disposes it" {
    const context: FilingContext = .{
        .tax_year = 2025,
        .quarter = .first,
        .amended = false,
    };
    var state: State = undefined;
    try initTestState(&state, false, context, 0x19);
    defer state.deinit();
    try selectRequiredElections(&state, false);
    try state.calculate();
    try expectSavePassed(&state, .not_evaluated);
    try state.generateEditableCandidate(.create);

    try std.testing.expectEqual(
        Phase.editable_candidate,
        state.phase(),
    );
    const summary = try state.candidateSummary();
    try std.testing.expectEqual(workflow.Exactness.candidate, summary.exactness);
    try std.testing.expect(!summary.evidence_qualified);
    try std.testing.expect(std.mem.indexOf(
        u8,
        summary.label,
        "not evidence-qualified",
    ) != null);
    try std.testing.expect(summary.byte_length != 0);
    try std.testing.expectEqual(
        @as(u16, 0),
        summary.container_qualification.verified_decrypt_vectors,
    );
    switch (try state.artifactDisplay(.generated_plaintext)) {
        .masked => |masked| try std.testing.expectEqual(
            summary.byte_length,
            masked.byte_length,
        ),
        .revealed => return error.ExpectedMaskedCandidate,
    }
    try state.setArtifactRevealed(.generated_plaintext, true);
    switch (try state.artifactDisplay(.generated_plaintext)) {
        .revealed => |bytes| try std.testing.expect(bytes.len != 0),
        .masked => return error.ExpectedRevealedCandidate,
    }

    const ciphertext = decodeSyntheticCiphertext(
        "fd36392320a2f11c1afee6e0ee1ac1ff" ++
            "63fd0111eb753a4d3f1cfe518849da4f",
    );
    try state.stageImportedCiphertext(&ciphertext, .{});
    switch (try state.artifactDisplay(.imported_ciphertext)) {
        .masked => {},
        .revealed => return error.ExpectedMaskedCiphertext,
    }
    try std.testing.expectError(
        error.MalformedPayloadStructure,
        state.decryptImported(
            "synthetic-legacy-codec-test-key-v2",
            .{},
        ),
    );
    try std.testing.expectError(
        error.MissingDecryptedPlaintext,
        state.artifactDiff(),
    );

    try state.setText("frm1701q:txtSheets", "1");
    try std.testing.expectEqual(Phase.editing, state.phase());
    try std.testing.expectError(
        error.NoCandidate,
        state.candidateSummary(),
    );
    try std.testing.expectEqual(@as(usize, 1), state.editableRevisionCount());
}

test "exact UI adapter: reopen restores values without replaying onclick runtime mutations" {
    const context: FilingContext = .{
        .tax_year = 2025,
        .quarter = .first,
        .amended = false,
    };
    var source: State = undefined;
    try initTestState(&source, false, context, 0x2d);
    defer source.deinit();
    try selectRequiredElections(&source, false);
    try std.testing.expect(!(try source.control(
        "frm1701q:txt36A",
    )).disabled);
    try source.calculate();
    try expectSavePassed(&source, .not_evaluated);
    try source.generateEditableCandidate(.create);
    const source_summary = try source.candidateSummary();
    const persisted = try source.candidateSnapshot();

    var replayed = try workflow.Workspace.init(
        std.testing.allocator,
        source.workspaceId(),
    );
    var replayed_owned = true;
    defer if (replayed_owned) replayed.deinit();
    try replaySnapshot(&replayed.editable_history, persisted);

    var historical_profile = try testProfile(
        false,
        try context.profileAsOf(),
    );
    defer secureWipe(&historical_profile);
    var reopened: State = undefined;
    switch (try State.reopenInto(
        &reopened,
        std.testing.allocator,
        &replayed,
        .editable_save,
        context,
        &historical_profile,
        .{
            .validation_current_year = 2026,
            .spouse_tin_checksum = .not_evaluated,
        },
    )) {
        .opened => replayed_owned = false,
        .blocked => return error.UnexpectedProfileMappingBlock,
    }
    defer reopened.deinit();

    try std.testing.expectEqual(
        Phase.editable_candidate,
        reopened.phase(),
    );
    try std.testing.expectEqual(
        @as(usize, 1),
        reopened.editableRevisionCount(),
    );
    const reopened_summary = try reopened.candidateSummary();
    try std.testing.expectEqualSlices(
        u8,
        &source_summary.sha256,
        &reopened_summary.sha256,
    );
    try std.testing.expect(try checkedValue(
        &reopened,
        "frm1701q:optType_1",
    ));
    try std.testing.expect(try checkedValue(
        &reopened,
        "frm1701q:optATC_1",
    ));
    // HTA loadData/loadWFData assign restored values but do not dispatch the
    // controls' onclick handlers. Runtime flags therefore remain post-init.
    try std.testing.expect((try reopened.control(
        "frm1701q:txt36A",
    )).disabled);

    try reopened.setRadio("frm1701q:optATC_1", false);
    try std.testing.expect(!(try reopened.control(
        "frm1701q:txt36A",
    )).disabled);
    try std.testing.expectEqual(Phase.editing, reopened.phase());
    try std.testing.expectError(
        error.NoCandidate,
        reopened.candidateSummary(),
    );
    try std.testing.expectEqual(
        @as(usize, 1),
        reopened.editableRevisionCount(),
    );
}

test "exact UI adapter: Final Copy requires full success and remains a plaintext candidate" {
    const context: FilingContext = .{
        .tax_year = 2025,
        .quarter = .first,
        .amended = false,
    };
    var state: State = undefined;
    try initTestState(&state, false, context, 0x1a);
    defer state.deinit();

    try std.testing.expectError(
        error.InvalidPhase,
        state.generateFinalCandidate(.create),
    );
    try selectRequiredElections(&state, false);
    try state.calculate();
    try expectSavePassed(&state, .not_evaluated);
    try expectFullPassed(&state);
    try state.generateFinalCandidate(.create);
    try std.testing.expectEqual(Phase.final_candidate, state.phase());
    const summary = try state.candidateSummary();
    try std.testing.expectEqual(
        draft.PayloadShape.final_copy_plaintext,
        summary.shape,
    );
    try std.testing.expectEqual(workflow.Exactness.candidate, summary.exactness);
    try std.testing.expectEqual(@as(usize, 1), state.finalRevisionCount());
}

test "exact UI adapter: exposes no secret retention, encryption, transport, or I/O API" {
    try std.testing.expect(!@hasField(State, "protocol_secret"));
    try std.testing.expect(!@hasDecl(State, "encrypt"));
    try std.testing.expect(!@hasDecl(State, "submit"));
    try std.testing.expect(!@hasDecl(State, "queue"));
    try std.testing.expect(!@hasDecl(State, "upload"));
    try std.testing.expect(!@hasDecl(State, "persist"));
    try std.testing.expect(!@hasDecl(State, "saveFile"));
    try std.testing.expect(!@hasDecl(State, "endpoint"));
    try std.testing.expect(!SecurityBoundary.outbound_encryption_enabled);
    try std.testing.expect(!SecurityBoundary.transport_enabled);
    try std.testing.expect(!SecurityBoundary.persistence_enabled);
}
