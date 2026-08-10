//! Native editor state for the canonical registration workspace.
//!
//! `main.zig` wires messages, persistence, and platform effects. This module
//! owns draft buffers and their Taxpayer/Registration Unit ownership, guarded switch
//! decisions, discard copy, and the exact confirmation input passed to the
//! registration workspace.

const std = @import("std");
const native_sdk = @import("native_sdk");
const registration = @import("registration_domain.zig");
const workspace = @import("registration_workspace.zig");

const canvas = native_sdk.canvas;

pub const Field = enum {
    taxpayer_tin_root,
    taxpayer_effective_from,
    branch_code,
    branch_effective_from,
    confirmation_effective_from,
    confirmation_tin_root,
    confirmation_branch_code,
    confirmation_rdo_code,
    registered_address,
    zip_code,
    contact_number,
    email_address,
    evidence_captured_on,
};

pub const DraftOwner = enum {
    branch_candidate,
    registration_unit_evidence,
};

pub const SwitchTarget = union(enum) {
    taxpayer: usize,
    registration_unit: usize,
};

pub const SwitchDecision = enum {
    unchanged,
    apply,
    deferred,
};

pub const MutationGateReason = enum {
    enabled,
    fixture_preview_disabled,
    data_directory_not_explicit,
    inventory_unavailable,
    inventory_wrote_data,
    legacy_profiles_present,
    ownership_unavailable,
    unowned_existing_database,
    unowned_target_rows,
};

pub const MutationGateInputs = struct {
    fixture_preview_requested: bool = false,
    data_directory_explicit: bool = false,
    inventory_collected: bool = false,
    inventory_verified_no_writes: bool = false,
    no_legacy_profiles: bool = false,
    fixture_ownership_verified: bool = false,
    unowned_existing_database: bool = false,
    unowned_target_rows: bool = false,
};

/// Canonical registration writes are a deliberately narrow fixture-preview
/// capability. A normal app model is read-only, and every missing proof fails
/// closed before a ledger handle is accessed.
pub const MutationGate = struct {
    reason: MutationGateReason = .fixture_preview_disabled,

    pub fn evaluate(inputs: MutationGateInputs) MutationGate {
        if (!inputs.fixture_preview_requested) {
            return .{ .reason = .fixture_preview_disabled };
        }
        if (!inputs.data_directory_explicit) {
            return .{ .reason = .data_directory_not_explicit };
        }
        if (!inputs.inventory_collected) {
            return .{ .reason = .inventory_unavailable };
        }
        if (!inputs.inventory_verified_no_writes) {
            return .{ .reason = .inventory_wrote_data };
        }
        if (!inputs.no_legacy_profiles) {
            return .{ .reason = .legacy_profiles_present };
        }
        if (inputs.unowned_existing_database) {
            return .{ .reason = .unowned_existing_database };
        }
        if (inputs.unowned_target_rows) {
            return .{ .reason = .unowned_target_rows };
        }
        if (!inputs.fixture_ownership_verified) {
            return .{ .reason = .ownership_unavailable };
        }
        return .{ .reason = .enabled };
    }

    pub fn enabled(self: MutationGate) bool {
        return self.reason == .enabled;
    }
};

pub const DiscardPrompt = struct {
    title: []const u8,
    body: []const u8,
    action_label: []const u8,
};

pub const EvidenceFileProblem = enum {
    none,
    picker_unavailable,
    picker_failed,
    path_too_long,
    unreadable,
    empty,
    too_large,
    unsupported,
    source_missing,
    source_changed,
};

pub const EvidenceSelection = struct {
    path: []const u8,
    display_name: []const u8,
    sha256: []const u8,
    byte_size: u64,
};

pub const AttachEvidenceError = error{
    PathTooLong,
    DisplayNameTooLong,
    InvalidSha256,
};

pub const State = struct {
    taxpayer_tin_root: canvas.TextBuffer(9) = .{},
    taxpayer_effective_from: canvas.TextBuffer(10) = .{},
    branch_code: canvas.TextBuffer(5) = .{},
    branch_effective_from: canvas.TextBuffer(10) = .{},

    confirmation_effective_from: canvas.TextBuffer(10) = .{},
    confirmation_tin_root: canvas.TextBuffer(9) = .{},
    confirmation_branch_code: canvas.TextBuffer(5) = .{},
    confirmation_rdo_code: canvas.TextBuffer(3) = .{},
    registered_address: canvas.TextBuffer(255) = .{},
    zip_code: canvas.TextBuffer(4) = .{},
    contact_number: canvas.TextBuffer(32) = .{},
    email_address: canvas.TextBuffer(254) = .{},
    evidence_display_name: canvas.TextBuffer(255) = .{},
    evidence_sha256: canvas.TextBuffer(64) = .{},
    evidence_byte_size: canvas.TextBuffer(20) = .{},
    evidence_path: canvas.TextBuffer(4096) = .{},
    evidence_captured_on: canvas.TextBuffer(10) = .{},
    evidence_source_kind: ?workspace.EvidenceSourceKind = null,
    evidence_file_problem: EvidenceFileProblem = .none,
    evidence_attempt_problem: EvidenceFileProblem = .none,
    evidence_protection_failed: bool = false,
    vat_registration_confirmed: bool = false,

    branch_candidate_dirty: bool = false,
    registration_unit_evidence_dirty: bool = false,

    pub fn value(self: *const State, field: Field) []const u8 {
        return switch (field) {
            .taxpayer_tin_root => self.taxpayer_tin_root.text(),
            .taxpayer_effective_from => self.taxpayer_effective_from.text(),
            .branch_code => self.branch_code.text(),
            .branch_effective_from => self.branch_effective_from.text(),
            .confirmation_effective_from => self.confirmation_effective_from.text(),
            .confirmation_tin_root => self.confirmation_tin_root.text(),
            .confirmation_branch_code => self.confirmation_branch_code.text(),
            .confirmation_rdo_code => self.confirmation_rdo_code.text(),
            .registered_address => self.registered_address.text(),
            .zip_code => self.zip_code.text(),
            .contact_number => self.contact_number.text(),
            .email_address => self.email_address.text(),
            .evidence_captured_on => self.evidence_captured_on.text(),
        };
    }

    /// Programmatic seeding deliberately does not claim user-owned dirtiness.
    pub fn setValue(self: *State, field: Field, value_text: []const u8) void {
        switch (field) {
            .taxpayer_tin_root => self.taxpayer_tin_root.set(value_text),
            .taxpayer_effective_from => self.taxpayer_effective_from.set(value_text),
            .branch_code => self.branch_code.set(value_text),
            .branch_effective_from => self.branch_effective_from.set(value_text),
            .confirmation_effective_from => self.confirmation_effective_from.set(value_text),
            .confirmation_tin_root => self.confirmation_tin_root.set(value_text),
            .confirmation_branch_code => self.confirmation_branch_code.set(value_text),
            .confirmation_rdo_code => self.confirmation_rdo_code.set(value_text),
            .registered_address => self.registered_address.set(value_text),
            .zip_code => self.zip_code.set(value_text),
            .contact_number => self.contact_number.set(value_text),
            .email_address => self.email_address.set(value_text),
            .evidence_captured_on => self.evidence_captured_on.set(value_text),
        }
    }

    /// User edits mark the draft owner in the same operation as the buffer
    /// mutation, so callers cannot update a Registration Unit field without arming
    /// its switch guard.
    pub fn applyEdit(
        self: *State,
        field: Field,
        edit: canvas.TextInputEvent,
    ) void {
        switch (field) {
            .taxpayer_tin_root => self.taxpayer_tin_root.apply(edit),
            .taxpayer_effective_from => self.taxpayer_effective_from.apply(edit),
            .branch_code => {
                self.branch_code.apply(edit);
                self.branch_candidate_dirty = true;
            },
            .branch_effective_from => {
                self.branch_effective_from.apply(edit);
                self.branch_candidate_dirty = true;
            },
            .confirmation_effective_from => self.applyEvidenceEdit(
                &self.confirmation_effective_from,
                edit,
            ),
            .confirmation_tin_root => self.applyEvidenceEdit(
                &self.confirmation_tin_root,
                edit,
            ),
            .confirmation_branch_code => self.applyEvidenceEdit(
                &self.confirmation_branch_code,
                edit,
            ),
            .confirmation_rdo_code => self.applyEvidenceEdit(
                &self.confirmation_rdo_code,
                edit,
            ),
            .registered_address => self.applyEvidenceEdit(
                &self.registered_address,
                edit,
            ),
            .zip_code => self.applyEvidenceEdit(&self.zip_code, edit),
            .contact_number => self.applyEvidenceEdit(&self.contact_number, edit),
            .email_address => self.applyEvidenceEdit(&self.email_address, edit),
            .evidence_captured_on => self.applyEvidenceEdit(
                &self.evidence_captured_on,
                edit,
            ),
        }
    }

    fn applyEvidenceEdit(
        self: *State,
        buffer: anytype,
        edit: canvas.TextInputEvent,
    ) void {
        buffer.apply(edit);
        self.registration_unit_evidence_dirty = true;
    }

    pub fn markDirty(self: *State, owner: DraftOwner) void {
        switch (owner) {
            .branch_candidate => self.branch_candidate_dirty = true,
            .registration_unit_evidence => self.registration_unit_evidence_dirty = true,
        }
    }

    pub fn toggleVatRegistrationConfirmed(self: *State) void {
        self.vat_registration_confirmed = !self.vat_registration_confirmed;
        self.registration_unit_evidence_dirty = true;
    }

    pub fn selectEvidenceSource(
        self: *State,
        source_kind: workspace.EvidenceSourceKind,
    ) void {
        switch (source_kind) {
            .cor, .ecor, .bir_registration_record => {},
            .migration_record, .other_reviewed => return,
        }
        if (self.evidence_source_kind != source_kind) {
            self.evidence_source_kind = source_kind;
            self.registration_unit_evidence_dirty = true;
        }
    }

    pub fn evidenceSourceLabel(self: *const State) []const u8 {
        const source_kind = self.evidence_source_kind orelse
            return "Choose evidence source";
        return switch (source_kind) {
            .cor => "Certificate of Registration (COR)",
            .ecor => "Electronic Certificate of Registration (eCOR)",
            .bir_registration_record => "Other reviewed BIR registration record",
            .other_reviewed => "Other reviewed registration evidence",
            .migration_record => "Migration record (not selectable)",
        };
    }

    pub fn hasEvidenceSource(self: *const State) bool {
        return self.evidence_source_kind != null;
    }

    pub fn evidenceSourceSelected(
        self: *const State,
        source_kind: workspace.EvidenceSourceKind,
    ) bool {
        const selected = self.evidence_source_kind orelse return false;
        return selected == source_kind;
    }

    pub fn isDirty(self: *const State, owner: DraftOwner) bool {
        return switch (owner) {
            .branch_candidate => self.branch_candidate_dirty,
            .registration_unit_evidence => self.registration_unit_evidence_dirty,
        };
    }

    pub fn useBranchSuggestion(self: *State, branch_code: []const u8) void {
        self.branch_code.set(branch_code);
        self.branch_candidate_dirty = true;
    }

    pub fn switchDecision(
        self: *const State,
        target: SwitchTarget,
        selected_taxpayer_index: ?usize,
        selected_registration_unit_index: ?usize,
    ) SwitchDecision {
        return switch (target) {
            .taxpayer => |index| if (selected_taxpayer_index == index)
                .unchanged
            else if (self.branch_candidate_dirty or self.registration_unit_evidence_dirty)
                .deferred
            else
                .apply,
            .registration_unit => |index| if (selected_registration_unit_index == index)
                .unchanged
            else if (self.registration_unit_evidence_dirty)
                .deferred
            else
                .apply,
        };
    }

    pub fn discardForSwitch(self: *State, target: SwitchTarget) void {
        switch (target) {
            .taxpayer => {
                self.clearBranchDraft();
                self.clearEvidenceDraft();
            },
            .registration_unit => self.clearEvidenceDraft(),
        }
    }

    pub fn discardPrompt(self: *const State, target: SwitchTarget) DiscardPrompt {
        return switch (target) {
            .taxpayer => .{
                .title = "Discard this Registration workspace draft?",
                .body = if (self.branch_candidate_dirty and self.registration_unit_evidence_dirty)
                    "The selected Taxpayer owns an unfinished branch candidate and reviewed-evidence draft. Discard both before switching Taxpayers, or stay here to keep editing."
                else if (self.branch_candidate_dirty)
                    "The selected Taxpayer owns an unfinished branch candidate. Discard it before switching Taxpayers, or stay here to keep editing."
                else
                    "The selected Taxpayer owns a reviewed-evidence draft. Discard it before switching Taxpayers, or stay here to keep editing.",
                .action_label = "Discard and switch Taxpayer",
            },
            .registration_unit => .{
                .title = "Discard this evidence draft?",
                .body = "The selected Registration Unit owns a reviewed-evidence draft. Discard it before switching Registration Units, or stay here to keep editing.",
                .action_label = "Discard and switch Registration Unit",
            },
        };
    }

    pub fn clearBranchDraft(self: *State) void {
        self.branch_code.clear();
        self.branch_effective_from.clear();
        self.branch_candidate_dirty = false;
    }

    pub fn clearEvidenceDraft(self: *State) void {
        self.confirmation_effective_from.clear();
        self.confirmation_tin_root.clear();
        self.confirmation_branch_code.clear();
        self.confirmation_rdo_code.clear();
        self.registered_address.clear();
        self.zip_code.clear();
        self.contact_number.clear();
        self.email_address.clear();
        self.evidence_display_name.clear();
        self.evidence_sha256.clear();
        self.evidence_byte_size.clear();
        self.evidence_path.clear();
        self.evidence_captured_on.clear();
        self.evidence_source_kind = null;
        self.evidence_file_problem = .none;
        self.evidence_attempt_problem = .none;
        self.evidence_protection_failed = false;
        self.vat_registration_confirmed = false;
        self.registration_unit_evidence_dirty = false;
    }

    /// Rehydrates the confirmation form only when no draft is owned by the
    /// current Registration Unit. Refreshing or returning to the tab therefore
    /// cannot erase unfinished evidence review.
    pub fn syncConfirmation(
        self: *State,
        as_of: ?registration.Date,
        unit: ?*const workspace.UnitRow,
    ) void {
        if (self.registration_unit_evidence_dirty) return;
        self.clearEvidenceDraft();

        if (as_of) |date| {
            var buffer: [10]u8 = undefined;
            self.evidence_captured_on.set(date.writeIso(&buffer));
        }

        const selected = unit orelse return;
        if (selected.revision.branch_code_evidence.knownCode()) |code| {
            self.confirmation_branch_code.set(code.asDigits());
        }
        if (selected.revision.rdo_code) |rdo| {
            self.confirmation_rdo_code.set(rdo.asDigits());
        }
        if (selected.contact_revision) |contact_revision| {
            const contact = &contact_revision.contact;
            self.registered_address.set(contact.registered_address.asSlice());
            if (contact.zip_code) |*zip| self.zip_code.set(zip.asSlice());
            if (contact.contact_number) |*number| {
                self.contact_number.set(number.asSlice());
            }
            if (contact.email_address) |*email| {
                self.email_address.set(email.asSlice());
            }
        }
        var buffer: [10]u8 = undefined;
        self.confirmation_effective_from.set(
            selected.revision.effective.from.writeIso(&buffer),
        );
    }

    pub fn attachEvidence(
        self: *State,
        selection: EvidenceSelection,
    ) AttachEvidenceError!void {
        if (selection.path.len > self.evidence_path.storage.len) {
            return error.PathTooLong;
        }
        if (selection.display_name.len > self.evidence_display_name.storage.len) {
            return error.DisplayNameTooLong;
        }
        _ = registration.Sha256Digest.parse(selection.sha256) catch {
            return error.InvalidSha256;
        };

        self.evidence_path.set(selection.path);
        self.evidence_display_name.set(selection.display_name);
        self.setEvidenceFingerprint(selection.sha256, selection.byte_size);
        self.evidence_file_problem = .none;
        self.evidence_attempt_problem = .none;
        self.evidence_protection_failed = false;
        self.registration_unit_evidence_dirty = true;
    }

    fn setEvidenceFingerprint(
        self: *State,
        sha256: []const u8,
        byte_size: u64,
    ) void {
        var size_buffer: [20]u8 = undefined;
        const size_text = std.fmt.bufPrint(
            &size_buffer,
            "{d}",
            .{byte_size},
        ) catch unreachable;
        self.evidence_sha256.set(sha256);
        self.evidence_byte_size.set(size_text);
    }

    /// Records a failed replacement attempt without invalidating or clearing
    /// an already selected, reviewed evidence file.
    pub fn reportEvidenceAttemptProblem(
        self: *State,
        problem: EvidenceFileProblem,
    ) void {
        self.evidence_attempt_problem = problem;
        self.evidence_protection_failed = false;
    }

    /// Marks the selected evidence file unusable after verification proves it moved
    /// or changed. The selected metadata remains visible for review, but a new
    /// attachment is required before confirmation can retry.
    pub fn invalidateSelectedEvidence(
        self: *State,
        problem: EvidenceFileProblem,
    ) void {
        self.evidence_file_problem = problem;
        self.evidence_attempt_problem = .none;
        self.evidence_protection_failed = false;
    }

    /// Protected-store failures do not claim the selected evidence file changed and
    /// do not destroy its valid selection. A later retry may succeed.
    pub fn reportEvidenceProtectionFailure(self: *State) void {
        self.evidence_protection_failed = true;
        self.evidence_attempt_problem = .none;
    }

    pub fn selectedEvidencePath(self: *const State) []const u8 {
        return self.evidence_path.text();
    }

    pub fn evidenceDisplayName(self: *const State) []const u8 {
        return self.evidence_display_name.text();
    }

    pub fn evidenceDigest(self: *const State) []const u8 {
        return self.evidence_sha256.text();
    }

    pub fn evidenceSize(self: *const State) []const u8 {
        return self.evidence_byte_size.text();
    }

    pub fn selectedEvidenceByteSize(self: *const State) ?u64 {
        return std.fmt.parseInt(u64, self.evidence_byte_size.text(), 10) catch null;
    }

    pub fn evidenceFileLabel(self: *const State) []const u8 {
        const name = self.evidence_display_name.text();
        return if (name.len == 0) "No file chosen" else name;
    }

    pub fn evidenceFileProblemVisible(self: *const State) bool {
        return self.evidence_file_problem != .none or
            self.evidence_attempt_problem != .none or
            self.evidence_protection_failed;
    }

    pub fn evidenceFileHelp(self: *const State) []const u8 {
        if (self.evidence_file_problem != .none) {
            return switch (self.evidence_file_problem) {
                .source_missing => "The selected evidence file is missing. Choose and review the evidence again before confirming.",
                .source_changed => "The selected evidence file changed after review. Choose and review the evidence again before confirming.",
                else => problemHelp(self.evidence_file_problem, false),
            };
        }
        if (self.evidence_protection_failed) {
            return "The app could not create or verify the protected evidence copy. No registration change was saved; the selected evidence file remains available to retry.";
        }
        if (self.evidence_attempt_problem != .none) {
            return problemHelp(
                self.evidence_attempt_problem,
                !self.evidence_path.isEmpty(),
            );
        }
        return if (self.evidence_path.isEmpty())
            "Choose the reviewed registration evidence. The app measures its fingerprint and size."
        else
            "Ready. Confirmation will verify these exact bytes before creating a protected local copy.";
    }

    pub fn confirmationDisabled(self: *const State, registration_unit_reviewable: bool) bool {
        const input = self.confirmationInput(self.evidence_path.text(), 0) orelse
            return true;
        return !registration_unit_reviewable or
            self.evidence_path.isEmpty() or
            self.evidence_file_problem != .none or
            workspace.confirmationInputValidationStatus(input) != null;
    }

    /// First actionable reason the confirmation CTA is disabled. Existing
    /// file-integrity warnings retain priority because they may require the
    /// user to reselect evidence even when every typed field is valid.
    pub fn confirmationActionHelp(
        self: *const State,
        registration_unit_reviewable: bool,
    ) ?[]const u8 {
        if (self.evidenceFileProblemVisible()) return self.evidenceFileHelp();
        if (!registration_unit_reviewable) {
            return workspace.ActionStatus.registration_unit_not_reviewable.label();
        }
        const input = self.confirmationInput(self.evidence_path.text(), 0) orelse
            return workspace.ActionStatus.evidence_source_required.label();
        if (workspace.confirmationInputValidationStatus(input)) |status| {
            return status.label();
        }
        return null;
    }

    pub fn vatRegistrationDisabled(self: *const State, repairable: bool) bool {
        const input = self.vatRegistrationInput(self.evidence_path.text(), 0) orelse
            return true;
        return !repairable or
            !self.vat_registration_confirmed or
            self.evidence_path.isEmpty() or
            self.evidence_file_problem != .none or
            workspace.vatRegistrationInputValidationStatus(input) != null;
    }

    /// First actionable reason the VAT-evidence CTA is disabled.
    pub fn vatRegistrationActionHelp(
        self: *const State,
        repairable: bool,
    ) ?[]const u8 {
        if (self.evidenceFileProblemVisible()) return self.evidenceFileHelp();
        if (!repairable) {
            return workspace.ActionStatus.vat_registration_not_recordable.label();
        }
        const input = self.vatRegistrationInput(self.evidence_path.text(), 0) orelse
            return workspace.ActionStatus.evidence_source_required.label();
        if (workspace.vatRegistrationInputValidationStatus(input)) |status| {
            return status.label();
        }
        return null;
    }

    pub fn confirmationInput(
        self: *const State,
        protected_evidence_path: []const u8,
        reviewed_at_unix_seconds: i64,
    ) ?workspace.ConfirmationInput {
        return .{
            .reviewed_evidence = self.reviewedEvidenceInput(
                protected_evidence_path,
                reviewed_at_unix_seconds,
            ) orelse return null,
            .observed_tin_root = self.confirmation_tin_root.text(),
            .observed_branch_code = self.confirmation_branch_code.text(),
            .observed_rdo_code = self.confirmation_rdo_code.text(),
            .registered_address = self.registered_address.text(),
            .zip_code = self.zip_code.text(),
            .contact_number = self.contact_number.text(),
            .email_address = self.email_address.text(),
            .confirm_vat_registration = self.vat_registration_confirmed,
        };
    }

    pub fn vatRegistrationInput(
        self: *const State,
        protected_evidence_path: []const u8,
        reviewed_at_unix_seconds: i64,
    ) ?workspace.VatRegistrationInput {
        return .{
            .reviewed_evidence = self.reviewedEvidenceInput(
                protected_evidence_path,
                reviewed_at_unix_seconds,
            ) orelse return null,
            .observed_tin_root = self.confirmation_tin_root.text(),
            .assert_active_vat_registration = self.vat_registration_confirmed,
        };
    }

    fn reviewedEvidenceInput(
        self: *const State,
        protected_evidence_path: []const u8,
        reviewed_at_unix_seconds: i64,
    ) ?workspace.ReviewedEvidenceInput {
        return .{
            .source_kind = self.evidence_source_kind orelse return null,
            .effective_from = self.confirmation_effective_from.text(),
            .evidence_path = protected_evidence_path,
            .evidence_display_name = self.evidence_display_name.text(),
            .evidence_sha256 = self.evidence_sha256.text(),
            .evidence_byte_size = self.evidence_byte_size.text(),
            .evidence_captured_on = self.evidence_captured_on.text(),
            .reviewed_at_unix_seconds = reviewed_at_unix_seconds,
        };
    }
};

fn problemHelp(problem: EvidenceFileProblem, preserved_selection: bool) []const u8 {
    if (preserved_selection) {
        return "The replacement could not be reviewed. Your previous selected evidence remains ready.";
    }
    return switch (problem) {
        .picker_unavailable => "File selection is not available on this system.",
        .picker_failed => "The file chooser could not be opened. Try again.",
        .path_too_long => "That file path is too long for the app.",
        .unreadable => "That file could not be read. Check that it still exists and try again.",
        .empty => "That file is empty. Choose a BIR registration document.",
        .too_large => "Choose a registration document smaller than 16 MB.",
        .unsupported => "Choose a PDF, PNG, or JPEG registration document.",
        .source_missing => "The selected evidence file is missing. Choose it again.",
        .source_changed => "The selected evidence file changed. Choose it again.",
        .none => "",
    };
}

fn seedValidConfirmationAction(state: *State) void {
    state.selectEvidenceSource(.bir_registration_record);
    state.setValue(.confirmation_effective_from, "2026-01-01");
    state.setValue(.confirmation_tin_root, "123456789");
    state.setValue(.confirmation_branch_code, "00001");
    state.setValue(.registered_address, "123 Registration Avenue");
    state.setValue(.evidence_captured_on, "2026-01-02");
}

test "switch decisions preserve Taxpayer and Registration Unit draft ownership" {
    var state: State = .{};

    try std.testing.expectEqual(
        SwitchDecision.unchanged,
        state.switchDecision(.{ .taxpayer = 2 }, 2, 4),
    );
    try std.testing.expectEqual(
        SwitchDecision.apply,
        state.switchDecision(.{ .taxpayer = 3 }, 2, 4),
    );

    state.markDirty(.branch_candidate);
    try std.testing.expectEqual(
        SwitchDecision.deferred,
        state.switchDecision(.{ .taxpayer = 3 }, 2, 4),
    );
    try std.testing.expectEqual(
        SwitchDecision.apply,
        state.switchDecision(.{ .registration_unit = 5 }, 2, 4),
    );

    state.markDirty(.registration_unit_evidence);
    try std.testing.expectEqual(
        SwitchDecision.deferred,
        state.switchDecision(.{ .registration_unit = 5 }, 2, 4),
    );
    const prompt = state.discardPrompt(.{ .registration_unit = 5 });
    try std.testing.expectEqualStrings(
        "Discard and switch Registration Unit",
        prompt.action_label,
    );
    try std.testing.expect(
        std.mem.indexOf(u8, prompt.body, "selected Registration Unit") != null,
    );
    try std.testing.expect(std.mem.indexOf(u8, prompt.body, "Source Unit") == null);

    state.discardForSwitch(.{ .registration_unit = 5 });
    try std.testing.expect(state.isDirty(.branch_candidate));
    try std.testing.expect(!state.isDirty(.registration_unit_evidence));
    state.discardForSwitch(.{ .taxpayer = 3 });
    try std.testing.expect(!state.isDirty(.branch_candidate));
}

test "mutation gate requires every fixture-preview prerequisite" {
    const enabled_inputs: MutationGateInputs = .{
        .fixture_preview_requested = true,
        .data_directory_explicit = true,
        .inventory_collected = true,
        .inventory_verified_no_writes = true,
        .no_legacy_profiles = true,
        .fixture_ownership_verified = true,
    };
    try std.testing.expect(MutationGate.evaluate(enabled_inputs).enabled());

    var missing = enabled_inputs;
    missing.fixture_preview_requested = false;
    try std.testing.expectEqual(
        MutationGateReason.fixture_preview_disabled,
        MutationGate.evaluate(missing).reason,
    );
    missing = enabled_inputs;
    missing.data_directory_explicit = false;
    try std.testing.expectEqual(
        MutationGateReason.data_directory_not_explicit,
        MutationGate.evaluate(missing).reason,
    );
    missing = enabled_inputs;
    missing.inventory_collected = false;
    try std.testing.expectEqual(
        MutationGateReason.inventory_unavailable,
        MutationGate.evaluate(missing).reason,
    );
    missing = enabled_inputs;
    missing.inventory_verified_no_writes = false;
    try std.testing.expectEqual(
        MutationGateReason.inventory_wrote_data,
        MutationGate.evaluate(missing).reason,
    );
    missing = enabled_inputs;
    missing.no_legacy_profiles = false;
    try std.testing.expectEqual(
        MutationGateReason.legacy_profiles_present,
        MutationGate.evaluate(missing).reason,
    );

    missing = enabled_inputs;
    missing.fixture_ownership_verified = false;
    try std.testing.expectEqual(
        MutationGateReason.ownership_unavailable,
        MutationGate.evaluate(missing).reason,
    );
    missing = enabled_inputs;
    missing.unowned_target_rows = true;
    try std.testing.expectEqual(
        MutationGateReason.unowned_target_rows,
        MutationGate.evaluate(missing).reason,
    );
}

test "evidence attachment keeps selected fingerprint immutable for protected input" {
    var state: State = .{};
    seedValidConfirmationAction(&state);
    const first_digest = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";

    try state.attachEvidence(.{
        .path = "/source/registration.pdf",
        .display_name = "registration.pdf",
        .sha256 = first_digest,
        .byte_size = 128,
    });
    try std.testing.expectEqualStrings(
        "/source/registration.pdf",
        state.selectedEvidencePath(),
    );
    try std.testing.expect(!state.confirmationDisabled(true));

    const input = state.confirmationInput("/protected/by-digest", 42).?;
    try std.testing.expectEqualStrings("123456789", input.observed_tin_root);
    try std.testing.expectEqualStrings(
        first_digest,
        input.reviewed_evidence.evidence_sha256,
    );
    try std.testing.expectEqualStrings(
        "128",
        input.reviewed_evidence.evidence_byte_size,
    );
    try std.testing.expectEqualStrings(
        "/protected/by-digest",
        input.reviewed_evidence.evidence_path,
    );
    try std.testing.expectEqual(
        @as(i64, 42),
        input.reviewed_evidence.reviewed_at_unix_seconds,
    );
    try std.testing.expectEqual(
        workspace.EvidenceSourceKind.bir_registration_record,
        input.reviewed_evidence.source_kind,
    );
}

test "evidence source selection is visible typed and owned by the evidence draft" {
    var state: State = .{};
    try std.testing.expectEqualStrings(
        "Choose evidence source",
        state.evidenceSourceLabel(),
    );
    try std.testing.expect(!state.hasEvidenceSource());
    try std.testing.expect(!state.evidenceSourceSelected(.cor));
    try std.testing.expect(state.confirmationInput("/protected/by-digest", 42) == null);

    const cases = [_]workspace.EvidenceSourceKind{
        .cor,
        .ecor,
        .bir_registration_record,
    };
    for (cases) |source_kind| {
        state.selectEvidenceSource(source_kind);
        try std.testing.expect(state.evidenceSourceSelected(source_kind));
        try std.testing.expectEqual(
            source_kind,
            state.confirmationInput("/protected/by-digest", 42).?
                .reviewed_evidence.source_kind,
        );
    }
    try std.testing.expect(state.isDirty(.registration_unit_evidence));

    state.clearEvidenceDraft();
    try std.testing.expect(!state.hasEvidenceSource());
    try std.testing.expect(!state.isDirty(.registration_unit_evidence));
}

test "no evidence source keeps confirmation and VAT actions disabled with guidance" {
    var state: State = .{};
    state.setValue(.confirmation_effective_from, "2026-01-01");
    state.setValue(.confirmation_tin_root, "123456789");
    state.setValue(.confirmation_branch_code, "00001");
    state.setValue(.registered_address, "123 Registration Avenue");
    state.setValue(.evidence_captured_on, "2026-01-02");
    try state.attachEvidence(.{
        .path = "/source/registration.pdf",
        .display_name = "registration.pdf",
        .sha256 = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        .byte_size = 128,
    });
    state.toggleVatRegistrationConfirmed();

    const expected =
        "Choose whether the reviewed evidence is a COR, eCOR, or another reviewed BIR registration record.";
    try std.testing.expect(state.confirmationDisabled(true));
    try std.testing.expectEqualStrings(expected, state.confirmationActionHelp(true).?);
    try std.testing.expect(state.vatRegistrationDisabled(true));
    try std.testing.expectEqualStrings(expected, state.vatRegistrationActionHelp(true).?);
}

test "confirmation readiness requires every parse-valid submission field" {
    var state: State = .{};
    state.selectEvidenceSource(.cor);
    const digest = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
    try state.attachEvidence(.{
        .path = "/source/registration.pdf",
        .display_name = "registration.pdf",
        .sha256 = digest,
        .byte_size = 128,
    });
    try std.testing.expect(state.confirmationDisabled(true));
    try std.testing.expectEqualStrings(
        "Enter a valid effective date as YYYY-MM-DD.",
        state.confirmationActionHelp(true).?,
    );

    seedValidConfirmationAction(&state);
    try std.testing.expect(!state.confirmationDisabled(true));
    try std.testing.expect(state.confirmationActionHelp(true) == null);

    state.setValue(.confirmation_tin_root, "");
    try std.testing.expect(state.confirmationDisabled(true));
    try std.testing.expectEqualStrings(
        "Enter the exact nine-digit taxpayer TIN shown on the reviewed evidence.",
        state.confirmationActionHelp(true).?,
    );
    state.setValue(.confirmation_tin_root, "12345678x");
    try std.testing.expect(state.confirmationDisabled(true));
    try std.testing.expectEqualStrings(
        "Enter the exact nine-digit taxpayer TIN shown on the reviewed evidence.",
        state.confirmationActionHelp(true).?,
    );
    state.setValue(.confirmation_tin_root, "123456789");

    state.setValue(.confirmation_effective_from, "2026-13-01");
    try std.testing.expect(state.confirmationDisabled(true));
    state.setValue(.confirmation_effective_from, "2026-01-01");
    state.setValue(.evidence_captured_on, "");
    try std.testing.expect(state.confirmationDisabled(true));
    state.setValue(.evidence_captured_on, "2026-01-02");
    state.setValue(.confirmation_branch_code, "001");
    try std.testing.expect(state.confirmationDisabled(true));
    try std.testing.expectEqualStrings(
        "Enter the exact five-digit BIR Branch Code.",
        state.confirmationActionHelp(true).?,
    );
    state.setValue(.confirmation_branch_code, "00001");
    state.setValue(.registered_address, " ");
    try std.testing.expect(state.confirmationDisabled(true));
    state.setValue(.registered_address, "123 Registration Avenue");

    state.setValue(.confirmation_rdo_code, "12");
    try std.testing.expect(state.confirmationDisabled(true));
    state.setValue(.confirmation_rdo_code, "");
    state.setValue(.zip_code, "123");
    try std.testing.expect(state.confirmationDisabled(true));
    state.setValue(.zip_code, "");
    state.setValue(.contact_number, "not-a-phone");
    try std.testing.expect(state.confirmationDisabled(true));
    try std.testing.expect(!state.evidenceFileProblemVisible());
    try std.testing.expectEqualStrings(
        workspace.ActionStatus.invalid_contact_number.label(),
        state.confirmationActionHelp(true).?,
    );
    try std.testing.expectEqualStrings(
        "Ready. Confirmation will verify these exact bytes before creating a protected local copy.",
        state.evidenceFileHelp(),
    );
    state.setValue(.contact_number, "");
    state.setValue(.email_address, "missing-at.example.test");
    try std.testing.expect(state.confirmationDisabled(true));
    state.setValue(.email_address, "");

    state.evidence_sha256.set("invalid");
    try std.testing.expect(state.confirmationDisabled(true));
    state.evidence_sha256.set(digest);
    state.evidence_byte_size.set("0");
    try std.testing.expect(state.confirmationDisabled(true));
    state.evidence_byte_size.set("128");
    state.evidence_display_name.set("");
    try std.testing.expect(state.confirmationDisabled(true));
    state.evidence_display_name.set("registration.pdf");
    try std.testing.expect(!state.confirmationDisabled(true));
}

test "VAT repair readiness applies reviewed evidence parsing and assertion" {
    var state: State = .{};
    state.selectEvidenceSource(.ecor);
    try state.attachEvidence(.{
        .path = "/source/vat-registration.pdf",
        .display_name = "vat-registration.pdf",
        .sha256 = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
        .byte_size = 256,
    });
    state.setValue(.confirmation_effective_from, "2026-01-01");
    state.setValue(.evidence_captured_on, "2026-01-02");

    try std.testing.expect(state.vatRegistrationDisabled(true));
    try std.testing.expectEqualStrings(
        "Enter the exact nine-digit taxpayer TIN shown on the reviewed evidence.",
        state.vatRegistrationActionHelp(true).?,
    );
    state.setValue(.confirmation_tin_root, "12345678x");
    try std.testing.expect(state.vatRegistrationDisabled(true));
    try std.testing.expectEqualStrings(
        "Enter the exact nine-digit taxpayer TIN shown on the reviewed evidence.",
        state.vatRegistrationActionHelp(true).?,
    );
    state.setValue(.confirmation_tin_root, "123456789");
    try std.testing.expectEqualStrings(
        "Explicitly confirm that the reviewed evidence records an active VAT registration.",
        state.vatRegistrationActionHelp(true).?,
    );
    state.toggleVatRegistrationConfirmed();
    try std.testing.expect(!state.vatRegistrationDisabled(true));
    try std.testing.expect(state.vatRegistrationActionHelp(true) == null);
    try std.testing.expectEqualStrings(
        "123456789",
        state.vatRegistrationInput("/protected/by-digest", 42).?
            .observed_tin_root,
    );
    state.setValue(.evidence_captured_on, "not-a-date");
    try std.testing.expect(state.vatRegistrationDisabled(true));
    try std.testing.expectEqualStrings(
        "Enter a valid evidence capture date as YYYY-MM-DD.",
        state.vatRegistrationActionHelp(true).?,
    );
    state.setValue(.evidence_captured_on, "2026-01-02");
    state.evidence_byte_size.set("0");
    try std.testing.expect(state.vatRegistrationDisabled(true));
}

test "invalid replacement attempt preserves previous evidence selection" {
    var state: State = .{};
    seedValidConfirmationAction(&state);
    const digest = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
    try state.attachEvidence(.{
        .path = "/source/registration.pdf",
        .display_name = "registration.pdf",
        .sha256 = digest,
        .byte_size = 128,
    });

    const too_long_path = "x" ** 4097;
    try std.testing.expectError(error.PathTooLong, state.attachEvidence(.{
        .path = too_long_path,
        .display_name = "replacement.pdf",
        .sha256 = digest,
        .byte_size = 256,
    }));
    try std.testing.expectError(error.InvalidSha256, state.attachEvidence(.{
        .path = "/source/uppercase.pdf",
        .display_name = "uppercase.pdf",
        .sha256 = "ABCDEF0123456789abcdef0123456789abcdef0123456789abcdef0123456789",
        .byte_size = 256,
    }));
    state.reportEvidenceAttemptProblem(.path_too_long);

    try std.testing.expectEqualStrings(
        "/source/registration.pdf",
        state.selectedEvidencePath(),
    );
    try std.testing.expectEqualStrings(digest, state.evidenceDigest());
    try std.testing.expectEqual(@as(?u64, 128), state.selectedEvidenceByteSize());
    try std.testing.expect(!state.confirmationDisabled(true));
    try std.testing.expect(std.mem.indexOf(
        u8,
        state.evidenceFileHelp(),
        "previous selected evidence remains ready",
    ) != null);
}

test "changed evidence file requires successful reselection before retry" {
    var state: State = .{};
    seedValidConfirmationAction(&state);
    const first_digest = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
    const second_digest = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";
    try state.attachEvidence(.{
        .path = "/source/registration.pdf",
        .display_name = "registration.pdf",
        .sha256 = first_digest,
        .byte_size = 128,
    });
    state.invalidateSelectedEvidence(.source_changed);
    try std.testing.expect(state.confirmationDisabled(true));

    // A cancelled picker does not call any state mutation and therefore does
    // not make the invalidated evidence file usable again.
    try std.testing.expectEqualStrings(first_digest, state.evidenceDigest());
    try std.testing.expect(state.confirmationDisabled(true));

    try state.attachEvidence(.{
        .path = "/source/reselected.pdf",
        .display_name = "reselected.pdf",
        .sha256 = second_digest,
        .byte_size = 256,
    });
    try std.testing.expect(!state.confirmationDisabled(true));
    try std.testing.expectEqualStrings(second_digest, state.evidenceDigest());
}

test "discard prompts describe the exact owned draft" {
    var state: State = .{};
    state.markDirty(.registration_unit_evidence);
    const evidence_only = state.discardPrompt(.{ .taxpayer = 1 });
    try std.testing.expect(std.mem.indexOf(
        u8,
        evidence_only.body,
        "reviewed-evidence draft",
    ) != null);

    state.markDirty(.branch_candidate);
    const both = state.discardPrompt(.{ .taxpayer = 1 });
    try std.testing.expect(std.mem.indexOf(u8, both.body, "both") != null);
    try std.testing.expectEqualStrings(
        "Discard and switch Taxpayer",
        both.action_label,
    );
}
