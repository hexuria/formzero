//! Native-facing page state for the exact BIR Form 1701Q January 2018
//! adapter.
//!
//! This layer is intentionally a view/controller, never a serializer. The
//! exact 173-control transaction state remains the sole payload authority.
//! Rows contain identifiers, metadata, and masked digests only. One selected
//! value may be copied into the fixed editor buffer after an explicit reveal;
//! that buffer is securely erased on hide, selection change, close, and
//! deinitialization.
//!
//! Persistence is deliberately fail-closed here until the exact occurrence
//! persistence adapter and local key-custody policy are both connected. The
//! only revisions this page can currently guard are the exact in-memory
//! workspace histories owned by `form_1701q_exact_ui_state`.

const std = @import("std");
const native_sdk = @import("native_sdk");
const exact_ui = @import("form_1701q_exact_ui_state.zig");
const draft = @import("../form_engine/draft.zig");
const profile_model = @import("../tax_profile/model.zig");
const projection = @import("../tax_profile/projection.zig");
const key_custody = @import("../security/key_custody.zig");
const sensitive_memory = @import("../security/sensitive_memory.zig");

const canvas = native_sdk.canvas;
const max_editor_bytes: usize = 1024;
const max_notice_bytes: usize = 512;
const max_mask_label_bytes: usize = 128;
const max_meta_label_bytes: usize = 160;

pub const SecurityBoundary = struct {
    pub const production_storage_state =
        key_custody.current_production_storage_state;
    pub const row_list_is_serialization_authority = false;
    pub const durable_persistence_enabled = false;
    pub const stores_protocol_secrets = false;
    pub const outbound_encryption_enabled = false;
    pub const filesystem_import_enabled = false;
    pub const endpoint_enabled = false;
    pub const queue_enabled = false;
    pub const submission_enabled = false;
    pub const transport_enabled = false;
};

/// Narrow integration seam for the separately reviewed exact persistence
/// adapter. No branch in this module treats this status as a successful save.
pub const PersistenceStatus = enum {
    unavailable_pending_exact_adapter_and_key_custody,
};

pub const FilerProfileBinding = struct {
    profile_id: profile_model.ProfileId,
    revision_id: profile_model.RevisionId,
    revision_sequence: u32,
    revision_source: profile_model.RevisionSource,

    fn capture(
        provenance: projection.Provenance,
    ) error{InvalidFilerRevisionSequence}!FilerProfileBinding {
        if (provenance.revision_sequence == 0) {
            return error.InvalidFilerRevisionSequence;
        }
        return .{
            .profile_id = provenance.profile_id,
            .revision_id = provenance.revision_id,
            .revision_sequence = provenance.revision_sequence,
            .revision_source = provenance.revision_source,
        };
    }

    fn matchesProvenance(
        self: *const FilerProfileBinding,
        provenance: *const projection.Provenance,
    ) bool {
        return self.profile_id.eql(&provenance.profile_id) and
            self.revision_id.eql(&provenance.revision_id) and
            self.revision_sequence == provenance.revision_sequence and
            revisionSourcesEqual(
                &self.revision_source,
                &provenance.revision_source,
            );
    }

    fn matchesProfileId(
        self: *const FilerProfileBinding,
        candidate: *const profile_model.ProfileId,
    ) bool {
        return self.profile_id.eql(candidate);
    }
};

const FilerProfileBindingError = error{
    MissingFilerProfileProvenance,
    InconsistentFilerProfileProvenance,
    InvalidFilerRevisionSequence,
};

fn captureFilerProfileBinding(
    snapshot: *const projection.Snapshot,
) FilerProfileBindingError!FilerProfileBinding {
    var captured: ?FilerProfileBinding = null;
    for (snapshot.slice()) |*entry| {
        if (entry.role != .filer) continue;
        if (captured) |*binding| {
            if (!binding.matchesProvenance(&entry.provenance)) {
                return error.InconsistentFilerProfileProvenance;
            }
            continue;
        }
        captured = try FilerProfileBinding.capture(entry.provenance);
    }
    return captured orelse error.MissingFilerProfileProvenance;
}

fn revisionSourcesEqual(
    left: *const profile_model.RevisionSource,
    right: *const profile_model.RevisionSource,
) bool {
    return switch (left.*) {
        .manual_entry => switch (right.*) {
            .manual_entry => true,
            else => false,
        },
        .imported => |left_reference| switch (right.*) {
            .imported => |right_reference| left_reference.eql(
                &right_reference,
            ),
            else => false,
        },
        .migrated => |left_reference| switch (right.*) {
            .migrated => |right_reference| left_reference.eql(
                &right_reference,
            ),
            else => false,
        },
    };
}

fn FixedText(comptime capacity: usize) type {
    return struct {
        const Self = @This();

        storage: [capacity]u8 = [_]u8{0} ** capacity,
        len: usize = 0,

        fn set(self: *Self, value: []const u8) void {
            std.crypto.secureZero(u8, &self.storage);
            const copy_len = @min(value.len, capacity);
            @memcpy(self.storage[0..copy_len], value[0..copy_len]);
            self.len = copy_len;
        }

        fn setFmt(
            self: *Self,
            comptime format: []const u8,
            args: anytype,
        ) void {
            var scratch: [capacity]u8 = [_]u8{0} ** capacity;
            defer std.crypto.secureZero(u8, &scratch);
            const rendered = std.fmt.bufPrint(
                &scratch,
                format,
                args,
            ) catch {
                self.set("Display value unavailable");
                return;
            };
            self.set(rendered);
        }

        fn text(self: *const Self) []const u8 {
            return self.storage[0..self.len];
        }

        fn wipe(self: *Self) void {
            sensitive_memory.wipeValue(Self, self);
        }
    };
}

const MaskLabel = FixedText(max_mask_label_bytes);
const MetaLabel = FixedText(max_meta_label_bytes);
const NoticeText = FixedText(max_notice_bytes);

/// Application-owned editor for explicitly revealed taxpayer values.
///
/// The SDK's edit primitive remains the behavior authority for selection,
/// composition, deletion, and replacement. Storage ownership and erasure are
/// local: every scratch buffer is securely zeroed, and every installed value
/// first erases the complete prior fixed-capacity storage.
fn SecureEditor(comptime capacity: usize) type {
    return struct {
        const Self = @This();

        storage: [capacity]u8 = [_]u8{0} ** capacity,
        len: usize = 0,
        selection: canvas.TextSelection = .{},
        composition: ?canvas.TextRange = null,
        /// Mirrors the SDK seam: true only when the most recent edit had to
        /// clamp an insertion or reject another over-capacity edit.
        truncated: bool = false,

        pub fn text(self: *const Self) []const u8 {
            return self.storage[0..self.len];
        }

        pub fn apply(self: *Self, event: canvas.TextInputEvent) void {
            var scratch: [capacity]u8 = [_]u8{0} ** capacity;
            defer std.crypto.secureZero(u8, &scratch);
            const state: canvas.TextEditState = .{
                .text = self.text(),
                .selection = self.selection,
                .composition = self.composition,
            };
            const next = canvas.applyTextInputEvent(
                state,
                event,
                &scratch,
            ) catch {
                self.truncated = true;
                const clamped = clampedInsertEvent(
                    state,
                    event,
                    capacity,
                ) orelse return;
                std.crypto.secureZero(u8, &scratch);
                const next_clamped = canvas.applyTextInputEvent(
                    state,
                    clamped,
                    &scratch,
                ) catch return;
                self.install(next_clamped, &scratch);
                return;
            };
            self.truncated = false;
            self.install(next, &scratch);
        }

        pub fn set(self: *Self, value: []const u8) void {
            var scratch: [capacity]u8 = [_]u8{0} ** capacity;
            defer std.crypto.secureZero(u8, &scratch);
            const next_len = @min(value.len, capacity);
            @memcpy(scratch[0..next_len], value[0..next_len]);
            std.crypto.secureZero(u8, &self.storage);
            @memcpy(self.storage[0..next_len], scratch[0..next_len]);
            self.len = next_len;
            self.selection = canvas.TextSelection.collapsed(next_len);
            self.composition = null;
            self.truncated = value.len > capacity;
        }

        pub fn clear(self: *Self) void {
            std.crypto.secureZero(u8, &self.storage);
            self.len = 0;
            self.selection = .{};
            self.composition = null;
            self.truncated = false;
        }

        fn install(
            self: *Self,
            next: canvas.TextEditState,
            scratch: *[capacity]u8,
        ) void {
            const next_len = @min(next.text.len, capacity);

            // State-only SDK events borrow the current storage rather than
            // the output slice. Stage those bytes before erasing the owner.
            if (next_len != 0 and
                @intFromPtr(next.text.ptr) != @intFromPtr(&scratch[0]))
            {
                std.mem.copyForwards(
                    u8,
                    scratch[0..next_len],
                    next.text[0..next_len],
                );
            }

            std.crypto.secureZero(u8, &self.storage);
            @memcpy(
                self.storage[0..next_len],
                scratch[0..next_len],
            );
            self.len = next_len;
            self.selection = next.selection;
            self.composition = next.composition;
        }
    };
}

/// Same insertion-clamping contract as the SDK editor, expressed entirely
/// through public Canvas edit types and UTF-8 snapping helpers.
fn clampedInsertEvent(
    state: canvas.TextEditState,
    event: canvas.TextInputEvent,
    capacity: usize,
) ?canvas.TextInputEvent {
    const insertion = switch (event) {
        .insert_text => |text| text,
        else => return null,
    };
    const selection = canvas.snapTextSelection(
        state.text,
        state.selection,
    );
    const replace_range = if (state.composition) |composition|
        canvas.snapTextRange(state.text, composition)
    else
        selection.range(state.text.len);
    const kept = state.text.len -
        replace_range.byteLen(state.text.len);
    if (kept >= capacity) return null;
    const available = capacity - kept;
    if (available >= insertion.len) return null;
    const clamped_len = canvas.snapTextOffset(insertion, available);
    if (clamped_len == 0) return null;
    return .{ .insert_text = insertion[0..clamped_len] };
}

pub const ControlRow = struct {
    slot: usize = 0,
    id: []const u8 = "",
    ordinal: u16 = 0,
    source_line: u32 = 0,
    read_only: bool = true,
    disabled: bool = true,
    radio: bool = false,
    independent_radio_toggle: bool = false,
    checked: bool = false,
    selected_state: bool = false,
    revealable: bool = false,
    mask_label: MaskLabel = .{},
    meta_label: MetaLabel = .{},

    pub fn idLabel(self: *const ControlRow) []const u8 {
        return self.id;
    }

    pub fn valueLabel(self: *const ControlRow) []const u8 {
        return self.mask_label.text();
    }

    pub fn metaLabel(self: *const ControlRow) []const u8 {
        return self.meta_label.text();
    }

    pub fn selected(self: *const ControlRow) bool {
        return self.selected_state;
    }

    pub fn accessLabel(self: *const ControlRow) []const u8 {
        if (self.disabled) return "Disabled by exact interaction";
        return if (self.read_only) "Read-only" else "Reviewed editable";
    }

    fn wipe(self: *ControlRow) void {
        self.mask_label.wipe();
        self.meta_label.wipe();
        sensitive_memory.wipeValue(ControlRow, self);
    }
};

const NoticeKind = enum {
    neutral,
    success,
    failure,
};

pub const State = struct {
    const Self = @This();

    allocator: ?std.mem.Allocator = null,
    blur_context: exact_ui.QualifiedBlurContext = .{
        .current_year = 0,
        .schedule_date = .{
            .current_date = .{ .year = 0, .month = 0, .day = 0 },
            .empty_default_input_was_later = false,
        },
    },
    exact: ?*exact_ui.State = null,
    filer_profile_binding: ?FilerProfileBinding = null,

    rows_storage: [exact_ui.control_count]ControlRow =
        [_]ControlRow{.{}} ** exact_ui.control_count,
    row_count: usize = 0,
    selected_slot: ?usize = null,
    selected_revealed: bool = false,
    editor: SecureEditor(max_editor_bytes) = .{},
    editor_dirty: bool = false,

    notice: NoticeText = .{},
    notice_kind: NoticeKind = .neutral,
    generated_revealed: bool = false,
    material_work: bool = false,
    failed_interaction_slots: std.StaticBitSet(exact_ui.control_count) = .initEmpty(),
    persistence_status: PersistenceStatus =
        .unavailable_pending_exact_adapter_and_key_custody,

    pub fn attach(
        self: *Self,
        allocator: std.mem.Allocator,
        blur_context: exact_ui.QualifiedBlurContext,
    ) void {
        self.deinit();
        self.* = .{
            .allocator = allocator,
            .blur_context = blur_context,
        };
    }

    pub fn deinit(self: *Self) void {
        self.closeForm();
        sensitive_memory.wipeValue(Self, self);
        self.* = .{};
    }

    /// Closes only the active form and preserves allocator/year context for a
    /// later workspace.
    pub fn close(self: *Self) void {
        self.closeForm();
        self.notice.wipe();
        self.notice = .{};
        self.notice_kind = .neutral;
    }

    pub fn discardWorkspace(self: *Self) void {
        self.close();
        self.setNotice(
            .success,
            "Exact workspace and all in-memory edits/candidates were explicitly discarded.",
        );
    }

    /// Opens an identity-bearing exact workspace using an opaque identifier
    /// minted by the Store-owning application layer. This Native state has no
    /// Store, persistence, random-ID generation, or draft-lookup capability.
    /// Returns false only for a grounded profile-mapping block.
    pub fn open(
        self: *Self,
        workspace_id: draft.DraftWorkspaceId,
        profile: *const projection.Snapshot,
        context: exact_ui.FilingContext,
    ) !bool {
        const allocator = self.allocator orelse return error.NotAttached;
        self.closeForm();
        var filer_profile_binding =
            try captureFilerProfileBinding(profile);
        defer sensitive_memory.wipeValue(
            FilerProfileBinding,
            &filer_profile_binding,
        );

        const next = try allocator.create(exact_ui.State);
        errdefer sensitive_memory.wipeAndDestroyDefaultAligned(
            exact_ui.State,
            allocator,
            next,
        );

        switch (try exact_ui.State.openInto(
            next,
            allocator,
            workspace_id,
            context,
            profile,
        )) {
            .opened => {
                self.exact = next;
                self.filer_profile_binding = filer_profile_binding;
                self.refreshRows();
                self.setNotice(
                    .neutral,
                    "Exact 173-control workspace opened. Durable persistence remains unavailable until the exact adapter and local key custody are connected.",
                );
                return true;
            },
            .blocked => |block| {
                sensitive_memory.wipeAndDestroyDefaultAligned(
                    exact_ui.State,
                    allocator,
                    next,
                );
                self.setNoticeFmt(
                    .failure,
                    "Exact profile mapping blocked: {s}.",
                    .{@tagName(block.reason)},
                );
                return false;
            },
        }
    }

    /// Makes an upstream open/projection failure visible without inventing a
    /// partially initialized exact state.
    pub fn blockOpen(self: *Self, err: anyerror) void {
        self.closeForm();
        self.setNoticeFmt(
            .failure,
            "Exact 1701Q workspace failed closed: {s}.",
            .{@errorName(err)},
        );
    }

    pub fn ready(self: *const Self) bool {
        return self.exact != null;
    }

    pub fn amended(self: *const Self) bool {
        const exact = self.exact orelse return false;
        return exact.filingContext().amended;
    }

    pub fn workspaceId(
        self: *const Self,
    ) ?draft.DraftWorkspaceId {
        const exact = self.exact orelse return null;
        return exact.workspaceId();
    }

    pub fn filerProfileMatches(
        self: *const Self,
        candidate_profile_id: []const u8,
    ) bool {
        const binding = if (self.filer_profile_binding) |*value|
            value
        else
            return false;
        const candidate = profile_model.ProfileId.parse(
            candidate_profile_id,
        ) catch return false;
        return binding.matchesProfileId(&candidate);
    }

    pub fn filerProfileId(self: *const Self) ?[]const u8 {
        const binding = if (self.filer_profile_binding) |*value|
            value
        else
            return null;
        return binding.profile_id.asSlice();
    }

    pub fn filerRevisionSequence(self: *const Self) ?u32 {
        const binding = self.filer_profile_binding orelse return null;
        return binding.revision_sequence;
    }

    pub fn reportNewerProfileRevision(self: *Self) void {
        if (!self.ready()) return;
        self.setNotice(
            .neutral,
            "A newer tax-profile revision was saved. This material exact workspace remains bound to the immutable profile revision captured when it opened; explicitly discard and reopen the workspace to use the newer revision.",
        );
    }

    pub fn hasDirtyOrMaterialWork(self: *const Self) bool {
        return self.editor_dirty or
            self.material_work or
            self.hasPendingInteractionFailure();
    }

    pub fn rejectContextChange(self: *Self) void {
        self.setNotice(
            .failure,
            "Exact profile or filing context was not changed because this workspace has uncommitted or material work. Use 'Discard and close exact workspace' to intentionally discard it first.",
        );
    }

    pub fn reportContextBindingFailure(
        self: *Self,
        err: anyerror,
    ) void {
        self.setNoticeFmt(
            .failure,
            "Exact profile context binding failed; the existing workspace was preserved: {s}.",
            .{@errorName(err)},
        );
    }

    pub fn rows(self: *const Self) []const ControlRow {
        return self.rows_storage[0..self.row_count];
    }

    pub fn selectControl(self: *Self, slot: usize) void {
        const exact = self.exact orelse return;
        if (self.editor_dirty) {
            self.setNotice(
                .failure,
                "Commit the revealed editor value or explicitly discard it before selecting another exact control.",
            );
            return;
        }
        if (slot >= self.row_count) {
            self.setNotice(.failure, "Unknown exact control selection.");
            return;
        }
        self.hideSelectedValue();
        self.selected_slot = slot;
        self.refreshRows();

        // Radios reveal only their boolean state, never text.
        if (self.rows_storage[slot].radio) {
            const view = exact.control(
                self.rows_storage[slot].id,
            ) catch |err| {
                self.setErrorNotice(err);
                return;
            };
            self.rows_storage[slot].checked = switch (view.display) {
                .checked => |checked| checked,
                else => false,
            };
        }
    }

    pub fn toggleSelectedReveal(self: *Self) void {
        const exact = self.exact orelse return;
        const slot = self.selected_slot orelse return;
        const row = &self.rows_storage[slot];
        if (!row.revealable or row.radio) {
            self.setNotice(
                .failure,
                "This control has no revealable text value.",
            );
            return;
        }

        if (self.selected_revealed) {
            const discarded = self.editor_dirty;
            self.hideSelectedValue();
            self.refreshRows();
            if (discarded) {
                self.setNotice(
                    .success,
                    "Uncommitted exact editor value explicitly discarded.",
                );
            }
            return;
        }

        exact.setControlRevealed(row.id, true) catch |err| {
            self.setErrorNotice(err);
            return;
        };
        const view = exact.control(row.id) catch |err| {
            exact.setControlRevealed(row.id, false) catch {};
            self.setErrorNotice(err);
            return;
        };
        const revealed = switch (view.display) {
            .revealed_text => |value| value,
            else => {
                exact.setControlRevealed(row.id, false) catch {};
                self.setNotice(
                    .failure,
                    "Exact control did not expose a text value.",
                );
                return;
            },
        };
        self.wipeEditor();
        self.editor.set(revealed);
        if (self.editor.truncated) {
            self.hideSelectedValue();
            self.setNotice(
                .failure,
                "The exact value exceeds the bounded Native editor.",
            );
            return;
        }
        self.selected_revealed = true;
        self.editor_dirty = false;
        self.refreshRows();
    }

    pub fn applyEditorInput(
        self: *Self,
        event: canvas.TextInputEvent,
    ) void {
        if (!self.selectedCanEdit()) {
            self.setNotice(
                .failure,
                "Reveal a reviewed editable control before changing it.",
            );
            return;
        }
        self.editor.apply(event);
        self.editor_dirty = self.editorDiffersFromExact();
        if (self.editor.truncated) {
            self.setNotice(
                .failure,
                "Input was truncated by the bounded Native editor; commit is blocked.",
            );
        } else if (self.editor_dirty) {
            self.setNotice(
                .neutral,
                "Exact editor has an uncommitted value. Commit it or explicitly discard it before continuing.",
            );
        }
    }

    pub fn commitSelected(self: *Self) void {
        const exact = self.exact orelse return;
        const slot = self.selected_slot orelse return;
        if (!self.selectedCanEdit()) {
            self.setNotice(
                .failure,
                "Reveal an enabled reviewed text control before committing it.",
            );
            return;
        }
        if (self.editor.truncated) {
            self.setNotice(
                .failure,
                "Truncated input cannot be committed.",
            );
            return;
        }

        const control_id = self.rows_storage[slot].id;
        const entered = self.editor.text();
        const outcome = exact.commitAndBlurQualified(
            control_id,
            entered,
            self.blur_context,
        ) catch |err| {
            self.markInteractionFailure(err);
            return;
        };
        const has_blur_binding = outcome.blur != null;
        const blur_alert = if (outcome.blur) |blur|
            blur.alert
        else
            null;

        self.failed_interaction_slots.unset(slot);
        self.editor_dirty = false;
        self.material_work = true;
        self.generated_revealed = false;
        self.reloadSelectedEditor();
        self.refreshRows();
        if (blur_alert) |alert| {
            self.setNotice(.failure, alert);
            return;
        }
        self.setNotice(
            .success,
            if (has_blur_binding)
                "Exact control committed and its qualified blur chain applied."
            else
                "Exact control committed. Recalculate before validation.",
        );
    }

    pub fn toggleSelectedRadio(self: *Self) void {
        const exact = self.exact orelse return;
        const slot = self.selected_slot orelse return;
        const row = &self.rows_storage[slot];
        if (!self.selectedCanToggleRadio()) {
            self.setNotice(
                .failure,
                "This radio control is read-only or dynamically disabled.",
            );
            return;
        }
        const next_checked = if (row.independent_radio_toggle)
            !row.checked
        else
            true;
        exact.setRadio(row.id, next_checked) catch |err| {
            self.setErrorNotice(err);
            return;
        };
        self.material_work = true;
        self.generated_revealed = false;
        self.refreshRows();
        self.setNotice(
            .success,
            "Exact radio behavior applied. Recalculate before validation.",
        );
    }

    pub fn calculate(self: *Self) void {
        const exact = self.exact orelse return;
        if (self.blockUnsafeWorkflow()) return;
        exact.calculate() catch |err| {
            self.setErrorNotice(err);
            return;
        };
        self.material_work = true;
        self.generated_revealed = false;
        self.refreshRows();
        self.setNotice(
            .success,
            "Exact source-ordered calculations completed.",
        );
    }

    pub fn validateSave(self: *Self) void {
        const exact = self.exact orelse return;
        if (self.blockUnsafeWorkflow()) return;
        const outcome = exact.validateSave(
            self.blur_context.current_year,
            .not_evaluated,
        ) catch |err| {
            self.setErrorNotice(err);
            return;
        };
        self.material_work = true;
        switch (outcome) {
            .failed => |failure| self.setNotice(
                .failure,
                failure.message,
            ),
            .passed => self.setNotice(
                .success,
                "Save validation passed in exact source order.",
            ),
        }
    }

    pub fn generateEditableCandidate(self: *Self) void {
        const exact = self.exact orelse return;
        if (self.blockUnsafeWorkflow()) return;
        exact.generateEditableCandidate(
            revisionGuard(exact.editableRevisionCount()) catch |err| {
                self.setErrorNotice(err);
                return;
            },
        ) catch |err| {
            self.setErrorNotice(err);
            return;
        };
        self.material_work = true;
        self.generated_revealed = false;
        self.setNotice(
            .success,
            "Editable plaintext candidate generated in memory. It is not evidence-qualified and was not persisted or submitted.",
        );
    }

    pub fn validateFull(self: *Self) void {
        const exact = self.exact orelse return;
        if (self.blockUnsafeWorkflow()) return;
        const outcome = exact.validateFull() catch |err| {
            self.setErrorNotice(err);
            return;
        };
        self.material_work = true;
        switch (outcome) {
            .failed => |failure| self.setNotice(
                .failure,
                failure.message,
            ),
            .blocked => |block| self.setNotice(
                .failure,
                block.message,
            ),
            .passed => |passed| self.setNotice(
                .success,
                passed.message,
            ),
        }
        self.generated_revealed = false;
    }

    pub fn generateFinalCandidate(self: *Self) void {
        const exact = self.exact orelse return;
        if (self.blockUnsafeWorkflow()) return;
        exact.generateFinalCandidate(
            revisionGuard(exact.finalRevisionCount()) catch |err| {
                self.setErrorNotice(err);
                return;
            },
        ) catch |err| {
            self.setErrorNotice(err);
            return;
        };
        self.material_work = true;
        self.generated_revealed = false;
        self.setNotice(
            .success,
            "Final Copy plaintext candidate generated in memory. It is not evidence-qualified and was not encrypted, persisted, or submitted.",
        );
    }

    pub fn toggleGeneratedReveal(self: *Self) void {
        const exact = self.exact orelse return;
        if (self.blockUnsafeWorkflow()) return;
        // The exact lab session is authoritative. Failed/blocked full
        // validation retains the editable candidate and its reveal state, so
        // a UI-only mirror cannot decide whether the next action hides it.
        const next = !self.generatedArtifactRevealed();
        exact.setArtifactRevealed(
            .generated_plaintext,
            next,
        ) catch |err| {
            self.setErrorNotice(err);
            return;
        };
        self.generated_revealed = next;
    }

    pub fn phaseLabel(self: *const Self) []const u8 {
        const exact = self.exact orelse return "Blocked / not opened";
        return switch (exact.phase()) {
            .editing => "Editing",
            .calculated => "Calculated",
            .save_failed => "Save validation failed",
            .save_passed => "Save validation passed",
            .full_failed => "Full validation failed",
            .full_blocked => "Full validation blocked",
            .full_passed => "Full validation passed",
            .editable_candidate => "Editable candidate",
            .final_candidate => "Final Copy candidate",
        };
    }

    pub fn filingContextLabel(
        self: *const Self,
        arena: std.mem.Allocator,
    ) []const u8 {
        const exact = self.exact orelse return "No exact filing context";
        const context = exact.filingContext();
        return std.fmt.allocPrint(
            arena,
            "Tax year {d} - Q{d} - amended: {s}",
            .{
                context.tax_year,
                @intFromEnum(context.quarter),
                if (context.amended) "yes" else "no",
            },
        ) catch "Exact filing context unavailable";
    }

    pub fn historyLabel(
        self: *const Self,
        arena: std.mem.Allocator,
    ) []const u8 {
        const exact = self.exact orelse
            return "No exact workspace history";
        return std.fmt.allocPrint(
            arena,
            "In-memory guarded history - Editable: {d} - Final Copy: {d}",
            .{
                exact.editableRevisionCount(),
                exact.finalRevisionCount(),
            },
        ) catch "Exact workspace history unavailable";
    }

    pub fn noticeVisible(self: *const Self) bool {
        return self.notice.len != 0;
    }

    pub fn noticeText(self: *const Self) []const u8 {
        return self.notice.text();
    }

    pub fn noticeTone(self: *const Self) []const u8 {
        return switch (self.notice_kind) {
            .neutral => "secondary",
            .success => "primary",
            .failure => "destructive",
        };
    }

    pub fn selectedVisible(self: *const Self) bool {
        return self.selected_slot != null;
    }

    pub fn selectedId(self: *const Self) []const u8 {
        const slot = self.selected_slot orelse return "";
        return self.rows_storage[slot].id;
    }

    pub fn selectedMeta(self: *const Self) []const u8 {
        const slot = self.selected_slot orelse return "";
        return self.rows_storage[slot].metaLabel();
    }

    pub fn selectedValueLabel(self: *const Self) []const u8 {
        const slot = self.selected_slot orelse return "";
        return self.rows_storage[slot].valueLabel();
    }

    pub fn selectedIsRadio(self: *const Self) bool {
        const slot = self.selected_slot orelse return false;
        return self.rows_storage[slot].radio;
    }

    pub fn selectedRadioLabel(self: *const Self) []const u8 {
        const slot = self.selected_slot orelse return "";
        return if (self.rows_storage[slot].checked)
            "Checked"
        else
            "Not checked";
    }

    pub fn selectedCanToggleRadio(self: *const Self) bool {
        const slot = self.selected_slot orelse return false;
        const row = &self.rows_storage[slot];
        return row.radio and !row.read_only and !row.disabled;
    }

    pub fn selectedCanReveal(self: *const Self) bool {
        const slot = self.selected_slot orelse return false;
        return self.rows_storage[slot].revealable;
    }

    pub fn selectedRevealLabel(self: *const Self) []const u8 {
        return if (self.selected_revealed and self.editor_dirty)
            "Discard uncommitted edit and hide"
        else if (self.selected_revealed)
            "Hide selected value"
        else
            "Reveal selected value";
    }

    pub fn selectedEditorText(self: *const Self) []const u8 {
        if (!self.selected_revealed) return "";
        return self.editor.text();
    }

    pub fn selectedCanEdit(self: *const Self) bool {
        const slot = self.selected_slot orelse return false;
        const row = &self.rows_storage[slot];
        return self.selected_revealed and
            !row.read_only and
            !row.disabled and
            !row.radio and
            !self.editor.truncated;
    }

    pub fn canCalculate(self: *const Self) bool {
        if (self.editor_dirty) return false;
        if (self.hasPendingInteractionFailure()) return false;
        const exact = self.exact orelse return false;
        return exact.phase() == .editing;
    }

    pub fn canValidateSave(self: *const Self) bool {
        if (self.editor_dirty) return false;
        if (self.hasPendingInteractionFailure()) return false;
        const exact = self.exact orelse return false;
        return switch (exact.phase()) {
            .calculated, .save_failed => true,
            else => false,
        };
    }

    pub fn canGenerateEditableCandidate(self: *const Self) bool {
        if (self.editor_dirty) return false;
        if (self.hasPendingInteractionFailure()) return false;
        const exact = self.exact orelse return false;
        return exact.phase() == .save_passed;
    }

    pub fn canValidateFull(self: *const Self) bool {
        if (self.editor_dirty) return false;
        if (self.hasPendingInteractionFailure()) return false;
        const exact = self.exact orelse return false;
        return switch (exact.phase()) {
            .save_passed,
            .editable_candidate,
            .full_failed,
            .full_blocked,
            => true,
            else => false,
        };
    }

    pub fn canGenerateFinalCandidate(self: *const Self) bool {
        if (self.editor_dirty) return false;
        if (self.hasPendingInteractionFailure()) return false;
        const exact = self.exact orelse return false;
        return exact.phase() == .full_passed;
    }

    pub fn candidateVisible(self: *const Self) bool {
        if (self.editor_dirty or
            self.hasPendingInteractionFailure()) return false;
        const exact = self.exact orelse return false;
        _ = exact.candidateSummary() catch return false;
        return true;
    }

    pub fn candidateLabel(self: *const Self) []const u8 {
        if (self.editor_dirty or
            self.hasPendingInteractionFailure()) return "";
        const exact = self.exact orelse return "";
        const summary = exact.candidateSummary() catch return "";
        return summary.label;
    }

    pub fn candidateQualificationLabel(self: *const Self) []const u8 {
        if (self.editor_dirty or
            self.hasPendingInteractionFailure()) return "";
        const exact = self.exact orelse return "";
        const summary = exact.candidateSummary() catch return "";
        return if (summary.evidence_qualified)
            "Evidence-qualified"
        else
            "Candidate only - not evidence-qualified";
    }

    pub fn candidateShapeLabel(self: *const Self) []const u8 {
        if (self.editor_dirty or
            self.hasPendingInteractionFailure()) return "";
        const exact = self.exact orelse return "";
        const summary = exact.candidateSummary() catch return "";
        return switch (summary.shape) {
            .editable_save => "Editable Save plaintext",
            .final_copy_plaintext => "Final Copy plaintext",
        };
    }

    pub fn candidateMaskedLabel(
        self: *const Self,
        arena: std.mem.Allocator,
    ) []const u8 {
        if (self.editor_dirty or
            self.hasPendingInteractionFailure()) return "";
        const exact = self.exact orelse return "";
        const summary = exact.candidateSummary() catch return "";
        return formatMaskedArena(
            arena,
            summary.byte_length,
            summary.sha256,
        );
    }

    pub fn generatedArtifactRevealed(self: *const Self) bool {
        if (self.editor_dirty or
            self.hasPendingInteractionFailure()) return false;
        const exact = self.exact orelse return false;
        return switch (exact.artifactDisplay(
            .generated_plaintext,
        ) catch return false) {
            .revealed => true,
            .masked => false,
        };
    }

    pub fn generatedArtifactRevealLabel(self: *const Self) []const u8 {
        return if (self.generatedArtifactRevealed())
            "Hide generated plaintext"
        else
            "Reveal generated plaintext";
    }

    /// Revealed bytes borrow the exact state. Native renders them directly;
    /// this page state never copies them into a second artifact buffer.
    pub fn generatedArtifactText(self: *const Self) []const u8 {
        if (self.editor_dirty or
            self.hasPendingInteractionFailure()) return "";
        const exact = self.exact orelse return "";
        return switch (exact.artifactDisplay(
            .generated_plaintext,
        ) catch return "") {
            .revealed => |bytes| bytes,
            .masked => "",
        };
    }

    fn refreshRows(self: *Self) void {
        const exact = self.exact orelse {
            self.row_count = 0;
            return;
        };
        const views = exact.controls();
        for (views, 0..) |view, index| {
            const row = &self.rows_storage[index];
            row.wipe();
            row.* = .{
                .slot = index,
                .id = view.id,
                .ordinal = view.stable_ordinal,
                .source_line = view.source_line,
                .read_only = view.read_only,
                .disabled = view.disabled,
                .radio = view.kind == .radio,
                .independent_radio_toggle = if (view.radio_behavior) |behavior|
                    switch (behavior) {
                        .spouse_type_independent => true,
                        .exclusive => false,
                    }
                else
                    false,
                .selected_state = self.selected_slot == index,
                .revealable = switch (view.display) {
                    .masked_text, .revealed_text => true,
                    .missing, .checked, .credential_locked_empty => false,
                },
            };
            row.meta_label.setFmt(
                "#{d} - {s} - {s} - source line {d} - {s}",
                .{
                    view.stable_ordinal,
                    @tagName(view.kind),
                    @tagName(view.origin),
                    view.source_line,
                    if (view.disabled)
                        "disabled"
                    else if (view.read_only)
                        "read-only"
                    else
                        "editable",
                },
            );
            switch (view.display) {
                .missing => row.mask_label.set("Missing exact value"),
                .credential_locked_empty => row.mask_label.set(
                    "Credential locked empty",
                ),
                .checked => |checked| {
                    row.checked = checked;
                    row.mask_label.set(
                        if (checked) "Checked" else "Not checked",
                    );
                },
                .masked_text => |summary| row.mask_label.setFmt(
                    "Masked - {d} bytes",
                    .{summary.byte_length},
                ),
                .revealed_text => |value| row.mask_label.setFmt(
                    "Masked - {d} bytes",
                    .{value.len},
                ),
            }
        }
        self.row_count = views.len;
    }

    fn hideSelectedValue(self: *Self) void {
        if (self.selected_revealed) {
            if (self.exact) |exact| {
                if (self.selected_slot) |slot| {
                    exact.setControlRevealed(
                        self.rows_storage[slot].id,
                        false,
                    ) catch {};
                }
            }
        }
        self.selected_revealed = false;
        self.wipeEditor();
    }

    fn reloadSelectedEditor(self: *Self) void {
        const exact = self.exact orelse return;
        const slot = self.selected_slot orelse return;
        if (!self.selected_revealed) return;
        const view = exact.control(
            self.rows_storage[slot].id,
        ) catch {
            self.hideSelectedValue();
            return;
        };
        const raw = switch (view.display) {
            .revealed_text => |value| value,
            else => {
                self.hideSelectedValue();
                return;
            },
        };
        self.wipeEditor();
        self.editor.set(raw);
        if (self.editor.truncated) self.hideSelectedValue();
    }

    fn wipeEditor(self: *Self) void {
        sensitive_memory.wipeValue(@TypeOf(self.editor), &self.editor);
        self.editor = .{};
        self.editor_dirty = false;
    }

    fn editorDiffersFromExact(self: *const Self) bool {
        const exact = self.exact orelse return true;
        const slot = self.selected_slot orelse return true;
        if (!self.selected_revealed) return false;
        const view = exact.control(
            self.rows_storage[slot].id,
        ) catch return true;
        return switch (view.display) {
            .revealed_text => |raw| !std.mem.eql(
                u8,
                self.editor.text(),
                raw,
            ),
            else => true,
        };
    }

    fn markInteractionFailure(self: *Self, err: anyerror) void {
        if (self.selected_slot) |slot| {
            self.failed_interaction_slots.set(slot);
        }
        self.editor_dirty = self.editorDiffersFromExact();
        self.generated_revealed = false;
        self.setErrorNotice(err);
    }

    fn blockUnsafeWorkflow(self: *Self) bool {
        if (self.editor_dirty) {
            self.setNotice(
                .failure,
                "Commit the revealed editor value or explicitly discard it before calculation, validation, or candidate access.",
            );
            return true;
        }
        return self.blockPendingInteraction();
    }

    fn blockPendingInteraction(self: *Self) bool {
        if (!self.hasPendingInteractionFailure()) return false;
        self.setNotice(
            .failure,
            "Resolve the failed exact control interaction with a successful corrective commit, or reopen the workspace, before calculation or candidate generation.",
        );
        return true;
    }

    fn hasPendingInteractionFailure(self: *const Self) bool {
        return self.failed_interaction_slots.count() != 0;
    }

    fn closeForm(self: *Self) void {
        self.hideSelectedValue();
        if (self.filer_profile_binding) |*binding| {
            sensitive_memory.wipeValue(FilerProfileBinding, binding);
        }
        self.filer_profile_binding = null;
        if (self.exact) |exact| {
            const allocator = self.allocator orelse unreachable;
            exact.deinit();
            sensitive_memory.wipeAndDestroyDefaultAligned(
                exact_ui.State,
                allocator,
                exact,
            );
            self.exact = null;
        }
        for (&self.rows_storage) |*row| {
            row.wipe();
            row.* = .{};
        }
        self.row_count = 0;
        self.selected_slot = null;
        self.selected_revealed = false;
        self.editor_dirty = false;
        self.generated_revealed = false;
        self.material_work = false;
        self.failed_interaction_slots =
            std.StaticBitSet(exact_ui.control_count).initEmpty();
    }

    fn setNotice(
        self: *Self,
        kind: NoticeKind,
        message: []const u8,
    ) void {
        self.notice.set(message);
        self.notice_kind = kind;
    }

    fn setNoticeFmt(
        self: *Self,
        kind: NoticeKind,
        comptime format: []const u8,
        args: anytype,
    ) void {
        self.notice.setFmt(format, args);
        self.notice_kind = kind;
    }

    fn setErrorNotice(self: *Self, err: anyerror) void {
        self.setNoticeFmt(
            .failure,
            "Exact 1701Q action failed closed: {s}.",
            .{@errorName(err)},
        );
    }
};

fn digestHex(
    digest: [std.crypto.hash.sha2.Sha256.digest_length]u8,
) [std.crypto.hash.sha2.Sha256.digest_length * 2]u8 {
    const alphabet = "0123456789abcdef";
    var result: [std.crypto.hash.sha2.Sha256.digest_length * 2]u8 =
        undefined;
    for (digest, 0..) |byte, index| {
        result[index * 2] = alphabet[byte >> 4];
        result[index * 2 + 1] = alphabet[byte & 0x0f];
    }
    return result;
}

fn formatMaskedArena(
    arena: std.mem.Allocator,
    byte_length: usize,
    digest: [std.crypto.hash.sha2.Sha256.digest_length]u8,
) []const u8 {
    return std.fmt.allocPrint(
        arena,
        "Masked - {d} bytes - SHA-256 {s}",
        .{ byte_length, digestHex(digest) },
    ) catch "Masked artifact metadata unavailable";
}

fn revisionGuard(count: usize) !draft.RevisionGuard {
    if (count == 0) return .create;
    return .{
        .match = try draft.DraftRevision.init(
            std.math.cast(u64, count) orelse
                return error.InvalidDraftRevision,
        ),
    };
}

fn nativeBlurTestProfile(
    mixed_case_immutable_name: bool,
) !projection.Snapshot {
    const form = @import("form_1701q.zig");
    const field = @import("../tax_profile/field.zig");
    const model = @import("../tax_profile/model.zig");
    const effective_on = try model.Date.parseIso("2026-06-30");
    var snapshot = projection.Snapshot.init(form.revision, effective_on);
    const provenance: projection.Provenance = .{
        .profile_id = try model.ProfileId.parse("native-blur-filer"),
        .revision_id = try model.RevisionId.parse("native-blur-filer-r1"),
        .revision_sequence = 1,
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
        .value = .{ .rdo_code = try field.RdoCode.parse("040") },
        .provenance = provenance,
    });
    try snapshot.append(.{
        .role = .filer,
        .target = form.filer_requirements[2].target,
        .value = .{
            .taxpayer_name = try field.TaxpayerName.parse(
                if (mixed_case_immutable_name)
                    "Mixed Case Filer"
                else
                    "SYNTHETIC FILER",
            ),
        },
        .provenance = provenance,
    });
    try snapshot.append(.{
        .role = .filer,
        .target = form.filer_requirements[3].target,
        .value = .{
            .registered_address = try field.RegisteredAddress.parse(
                "SYNTHETIC ADDRESS",
            ),
        },
        .provenance = provenance,
    });
    try snapshot.append(.{
        .role = .filer,
        .target = form.filer_requirements[4].target,
        .value = .{ .zip_code = try field.ZipCode.parse("1100") },
        .provenance = provenance,
    });
    try snapshot.append(.{
        .role = .filer,
        .target = form.filer_requirements[5].target,
        .value = .{
            .date_of_birth = try model.Date.parseIso("1990-01-01"),
        },
        .provenance = provenance,
    });
    try snapshot.append(.{
        .role = .filer,
        .target = form.filer_requirements[6].target,
        .value = .{
            .email_address = try field.EmailAddress.parse(
                "SYNTHETIC@EXAMPLE.TEST",
            ),
        },
        .provenance = provenance,
    });
    try snapshot.append(.{
        .role = .filer,
        .target = form.filer_requirements[7].target,
        .value = .{
            .citizenship = try field.Citizenship.parse("FILIPINO"),
        },
        .provenance = provenance,
    });
    return snapshot;
}

fn initNativeBlurTestState(
    state: *State,
    workspace_byte: u8,
    mixed_case_immutable_name: bool,
) !void {
    state.* = .{};
    state.attach(std.testing.allocator, .{
        .current_year = 2026,
        .schedule_date = .{
            .current_date = .{ .year = 2026, .month = 7, .day = 30 },
            .empty_default_input_was_later = false,
        },
    });
    var profile = try nativeBlurTestProfile(
        mixed_case_immutable_name,
    );
    defer sensitive_memory.wipeValue(@TypeOf(profile), &profile);
    const workspace_id = try draft.DraftWorkspaceId.init(
        [_]u8{workspace_byte} ** 16,
    );
    if (!try state.open(
        workspace_id,
        &profile,
        .{ .tax_year = 2026, .quarter = .second, .amended = false },
    )) {
        return error.UnexpectedProfileMappingBlock;
    }
}

fn nativeControlSlot(state: *const State, control_id: []const u8) !usize {
    for (state.rows(), 0..) |*row, slot| {
        if (std.mem.eql(u8, row.idLabel(), control_id)) return slot;
    }
    return error.UnknownTestControl;
}

fn expectNativeExactText(
    state: *State,
    control_id: []const u8,
    expected: []const u8,
) !void {
    const exact = state.exact orelse return error.ExactStateNotOpen;
    try exact.setControlRevealed(control_id, true);
    defer exact.setControlRevealed(control_id, false) catch {};
    const view = try exact.control(control_id);
    switch (view.display) {
        .revealed_text => |actual| {
            try std.testing.expectEqualStrings(expected, actual);
        },
        else => return error.ExpectedRevealedText,
    }
}

test "Native exact state exposes no persistence encryption or transport API" {
    try std.testing.expectEqual(
        key_custody.ProductionStorageState
            .unavailable_authenticated_storage_backend_unselected,
        SecurityBoundary.production_storage_state,
    );
    try std.testing.expectError(
        error.ProductionStorageUnavailable,
        key_custody.requireProductionStorage(),
    );
    try std.testing.expect(!@hasDecl(State, "persist"));
    try std.testing.expect(!@hasDecl(State, "encrypt"));
    try std.testing.expect(!@hasDecl(State, "submit"));
    try std.testing.expect(!@hasDecl(State, "queue"));
    try std.testing.expect(!@hasDecl(State, "upload"));
    try std.testing.expect(!@hasDecl(State, "stageImportedCiphertext"));
    try std.testing.expect(!@hasField(State, "store"));
    try std.testing.expect(!@hasField(State, "protocol_secret"));
    try std.testing.expect(!SecurityBoundary.row_list_is_serialization_authority);
    try std.testing.expect(!SecurityBoundary.durable_persistence_enabled);
    try std.testing.expect(!SecurityBoundary.outbound_encryption_enabled);
    try std.testing.expect(!SecurityBoundary.transport_enabled);
}

test "Native exact filer binding validates provenance and clears on close" {
    var state: State = .{};
    try initNativeBlurTestState(&state, 0x60, false);
    defer state.deinit();

    try std.testing.expect(state.filerProfileMatches(
        "native-blur-filer",
    ));
    try std.testing.expect(!state.filerProfileMatches(
        "different-filer",
    ));
    try std.testing.expectEqualStrings(
        "native-blur-filer",
        state.filerProfileId().?,
    );
    try std.testing.expectEqual(
        @as(u32, 1),
        state.filer_profile_binding.?.revision_sequence,
    );
    try std.testing.expectEqual(
        @as(u32, 1),
        state.filerRevisionSequence().?,
    );
    state.reportNewerProfileRevision();
    try std.testing.expectEqualStrings("secondary", state.noticeTone());
    try std.testing.expect(std.mem.indexOf(
        u8,
        state.noticeText(),
        "remains bound to the immutable profile revision",
    ) != null);

    state.close();
    try std.testing.expect(!state.ready());
    try std.testing.expect(state.filer_profile_binding == null);
    try std.testing.expect(state.filerProfileId() == null);
    try std.testing.expect(state.filerRevisionSequence() == null);
    try std.testing.expect(!state.filerProfileMatches(
        "native-blur-filer",
    ));

    var inconsistent = try nativeBlurTestProfile(false);
    defer sensitive_memory.wipeValue(@TypeOf(inconsistent), &inconsistent);
    inconsistent.entries[1].provenance.revision_id =
        try profile_model.RevisionId.parse("different-revision");
    const workspace_id = try draft.DraftWorkspaceId.init(
        [_]u8{0x5f} ** 16,
    );
    try std.testing.expectError(
        error.InconsistentFilerProfileProvenance,
        state.open(
            workspace_id,
            &inconsistent,
            .{
                .tax_year = 2026,
                .quarter = .second,
                .amended = false,
            },
        ),
    );
    try std.testing.expect(!state.ready());
    try std.testing.expect(state.filer_profile_binding == null);

    const form = @import("form_1701q.zig");
    const effective_on = try profile_model.Date.parseIso("2026-06-30");
    var missing = projection.Snapshot.init(
        form.revision,
        effective_on,
    );
    defer sensitive_memory.wipeValue(@TypeOf(missing), &missing);
    try std.testing.expectError(
        error.MissingFilerProfileProvenance,
        captureFilerProfileBinding(&missing),
    );
}

test "Native commit applies qualified blur and preserves disabled and error boundaries" {
    var state: State = .{};
    try initNativeBlurTestState(&state, 0x61, true);
    defer state.deinit();
    try std.testing.expectEqual(@as(u8, 7), state.blur_context
        .schedule_date.current_date.month);
    try std.testing.expectEqual(@as(u8, 30), state.blur_context
        .schedule_date.current_date.day);

    state.selectControl(try nativeControlSlot(
        &state,
        "frm1701q:txtLOB",
    ));
    state.toggleSelectedReveal();
    try std.testing.expect(state.selectedCanEdit());
    state.applyEditorInput(.{ .insert_text = "small shop" });
    try std.testing.expect(state.editor_dirty);
    state.commitSelected();
    try std.testing.expectEqualStrings(
        "SMALL SHOP",
        state.selectedEditorText(),
    );
    try std.testing.expectEqualStrings("primary", state.noticeTone());
    try std.testing.expect(std.mem.indexOf(
        u8,
        state.noticeText(),
        "qualified blur chain",
    ) != null);

    state.selectControl(try nativeControlSlot(
        &state,
        "frm1701q:txtDate32",
    ));
    try std.testing.expect(
        state.rows_storage[state.selected_slot.?].disabled,
    );
    state.commitSelected();
    try std.testing.expectEqualStrings("destructive", state.noticeTone());
    try std.testing.expect(std.mem.indexOf(
        u8,
        state.noticeText(),
        "enabled reviewed text control",
    ) != null);
    try expectNativeExactText(&state, "frm1701q:txtDate32", "");

    var error_state: State = .{};
    try initNativeBlurTestState(&error_state, 0x62, false);
    defer error_state.deinit();
    error_state.selectControl(try nativeControlSlot(
        &error_state,
        "frm1701q:txt64A",
    ));
    error_state.toggleSelectedReveal();
    try std.testing.expect(error_state.selectedCanEdit());
    error_state.applyEditorInput(.clear);
    error_state.applyEditorInput(.{
        .insert_text = "rejected-editor-bytes",
    });
    try std.testing.expect(error_state.editor_dirty);
    error_state.commitSelected();
    try std.testing.expectEqualStrings(
        "destructive",
        error_state.noticeTone(),
    );
    try std.testing.expect(std.mem.indexOf(
        u8,
        error_state.noticeText(),
        "InvalidMoney",
    ) != null);
    try expectNativeExactText(
        &error_state,
        "frm1701q:txt64A",
        "0.00",
    );
    try std.testing.expect(!error_state.canCalculate());
    try std.testing.expect(!error_state.canValidateSave());
    try std.testing.expect(
        !error_state.canGenerateEditableCandidate(),
    );
    try std.testing.expect(!error_state.canValidateFull());
    try std.testing.expect(!error_state.canGenerateFinalCandidate());

    // Dirty editor bytes block selection and every workflow path until the
    // user explicitly commits or discards them.
    const failed_slot = error_state.selected_slot.?;
    error_state.selectControl(try nativeControlSlot(
        &error_state,
        "frm1701q:txtSheets",
    ));
    try std.testing.expectEqual(
        failed_slot,
        error_state.selected_slot.?,
    );
    error_state.calculate();
    error_state.validateSave();
    error_state.generateEditableCandidate();
    error_state.validateFull();
    error_state.generateFinalCandidate();
    try std.testing.expect(!error_state.candidateVisible());
    try std.testing.expect(std.mem.indexOf(
        u8,
        error_state.noticeText(),
        "explicitly discard",
    ) != null);

    error_state.toggleSelectedReveal();
    try std.testing.expect(!error_state.editor_dirty);

    // A successful commit on a different, unbound control cannot clear the
    // failed interaction recorded against txt64A.
    error_state.selectControl(try nativeControlSlot(
        &error_state,
        "frm1701q:txtSheets",
    ));
    error_state.toggleSelectedReveal();
    try std.testing.expect(error_state.selectedCanEdit());
    error_state.applyEditorInput(.clear);
    error_state.applyEditorInput(.{ .insert_text = "1" });
    error_state.commitSelected();
    try std.testing.expectEqualStrings("primary", error_state.noticeTone());
    try std.testing.expect(!error_state.canCalculate());

    // Programmatic calls remain gated after that unrelated success.
    error_state.calculate();
    try std.testing.expectEqualStrings(
        "destructive",
        error_state.noticeTone(),
    );
    try std.testing.expect(std.mem.indexOf(
        u8,
        error_state.noticeText(),
        "successful corrective commit",
    ) != null);
    try std.testing.expectEqualStrings(
        "Editing",
        error_state.phaseLabel(),
    );
    error_state.validateSave();
    error_state.generateEditableCandidate();
    error_state.validateFull();
    error_state.generateFinalCandidate();
    try std.testing.expect(!error_state.candidateVisible());

    // Correcting that same control through the complete atomic commit/blur
    // boundary clears its sticky failure; unrelated commits never could.
    error_state.selectControl(try nativeControlSlot(
        &error_state,
        "frm1701q:txt64A",
    ));
    error_state.toggleSelectedReveal();
    error_state.applyEditorInput(.clear);
    error_state.applyEditorInput(.{ .insert_text = "1.00" });
    error_state.commitSelected();
    try std.testing.expectEqualStrings("primary", error_state.noticeTone());
    try std.testing.expect(error_state.canCalculate());
    try expectNativeExactText(
        &error_state,
        "frm1701q:txt64A",
        "1.00",
    );

    error_state.applyEditorInput(.clear);
    error_state.applyEditorInput(.{
        .insert_text = "second-rejected-value",
    });
    error_state.commitSelected();
    try std.testing.expect(!error_state.canCalculate());

    // Reopening discards the failed exact workspace and clears the gate.
    var clean_profile = try nativeBlurTestProfile(false);
    defer sensitive_memory.wipeValue(
        @TypeOf(clean_profile),
        &clean_profile,
    );
    try std.testing.expect(try error_state.open(
        try draft.DraftWorkspaceId.init([_]u8{0x64} ** 16),
        &clean_profile,
        .{ .tax_year = 2026, .quarter = .second, .amended = false },
    ));
    try std.testing.expect(error_state.canCalculate());
}

test "Native retained candidate reveal hides in one click after failed full validation" {
    var state: State = .{};
    try initNativeBlurTestState(&state, 0x63, false);
    defer state.deinit();

    state.calculate();
    try std.testing.expect(state.canValidateSave());
    state.validateSave();
    try std.testing.expect(state.canGenerateEditableCandidate());
    state.generateEditableCandidate();
    try std.testing.expect(state.candidateVisible());
    state.toggleGeneratedReveal();
    try std.testing.expect(state.generatedArtifactRevealed());

    state.validateFull();
    try std.testing.expectEqualStrings("destructive", state.noticeTone());
    try std.testing.expect(state.candidateVisible());
    try std.testing.expect(state.generatedArtifactRevealed());

    state.toggleGeneratedReveal();
    try std.testing.expect(!state.generatedArtifactRevealed());
}

test "Native dirty editor makes retained candidate unreachable until explicit discard" {
    var state: State = .{};
    try initNativeBlurTestState(&state, 0x65, false);
    defer state.deinit();

    state.calculate();
    state.validateSave();
    state.generateEditableCandidate();
    try std.testing.expect(state.candidateVisible());

    state.selectControl(try nativeControlSlot(
        &state,
        "frm1701q:txtLOB",
    ));
    state.toggleSelectedReveal();
    state.applyEditorInput(.{ .insert_text = "uncommitted" });
    try std.testing.expect(state.editor_dirty);
    try std.testing.expect(!state.candidateVisible());
    try std.testing.expect(!state.canValidateFull());

    // Direct action calls cannot bypass the disabled button projections.
    state.validateFull();
    state.generateFinalCandidate();
    state.toggleGeneratedReveal();
    try std.testing.expect(!state.candidateVisible());
    try std.testing.expect(!state.generatedArtifactRevealed());
    try std.testing.expect(std.mem.indexOf(
        u8,
        state.noticeText(),
        "explicitly discard",
    ) != null);

    state.toggleSelectedReveal();
    try std.testing.expect(!state.editor_dirty);
    try std.testing.expect(state.candidateVisible());
}

test "Native revision guards follow each exact shape history" {
    switch (try revisionGuard(0)) {
        .create => {},
        .match => return error.ExpectedRevisionCreate,
    }
    const guarded = try revisionGuard(7);
    switch (guarded) {
        .match => |revision| try std.testing.expectEqual(
            @as(u64, 7),
            revision.value,
        ),
        .create => return error.ExpectedRevisionMatch,
    }
}

test "Native fixed text overwrites and securely wipes prior content" {
    var value: FixedText(32) = .{};
    value.set("synthetic-sensitive-value");
    value.set("x");
    try std.testing.expectEqualStrings("x", value.text());
    for (value.storage[1..]) |byte| {
        try std.testing.expectEqual(@as(u8, 0), byte);
    }
    value.wipe();
    for (std.mem.asBytes(&value)) |byte| {
        try std.testing.expectEqual(@as(u8, 0), byte);
    }
}

fn expectSecureEditorTailZero(editor: anytype) !void {
    for (editor.storage[editor.len..]) |byte| {
        try std.testing.expectEqual(@as(u8, 0), byte);
    }
}

test "Native secure editor zeroes displaced bytes on shorten delete replace and clear" {
    var editor: SecureEditor(32) = .{};

    editor.set("synthetic-sensitive-long-value");
    editor.set("short");
    try std.testing.expectEqualStrings("short", editor.text());
    try expectSecureEditorTailZero(&editor);

    editor.apply(.delete_backward);
    try std.testing.expectEqualStrings("shor", editor.text());
    try expectSecureEditorTailZero(&editor);

    editor.apply(.{
        .set_selection = .{ .anchor = 1, .focus = 4 },
    });
    editor.apply(.{ .insert_text = "X" });
    try std.testing.expectEqualStrings("sX", editor.text());
    try std.testing.expectEqualDeep(
        canvas.TextSelection.collapsed(2),
        editor.selection,
    );
    try expectSecureEditorTailZero(&editor);

    editor.clear();
    try std.testing.expectEqual(@as(usize, 0), editor.len);
    try std.testing.expect(!editor.truncated);
    try expectSecureEditorTailZero(&editor);
}

test "Native secure editor preserves composition and UTF-8 truncation semantics" {
    var composition: SecureEditor(16) = .{};
    composition.set("ab");
    composition.apply(.{
        .set_selection = .{ .anchor = 1, .focus = 2 },
    });
    composition.apply(.{
        .set_composition = .{ .text = "XYZ", .cursor = 1 },
    });
    try std.testing.expectEqualStrings("aXYZ", composition.text());
    try std.testing.expectEqualDeep(
        canvas.TextSelection.collapsed(2),
        composition.selection,
    );
    try std.testing.expectEqualDeep(
        canvas.TextRange{ .start = 1, .end = 4 },
        composition.composition.?,
    );
    try expectSecureEditorTailZero(&composition);
    composition.apply(.commit_composition);
    try std.testing.expect(composition.composition == null);
    try expectSecureEditorTailZero(&composition);

    var bounded: SecureEditor(8) = .{};
    bounded.apply(.{ .insert_text = "hi" });
    bounded.apply(.{ .insert_text = " there!!" });
    try std.testing.expectEqualStrings("hi there", bounded.text());
    try std.testing.expect(bounded.truncated);
    try std.testing.expectEqualDeep(
        canvas.TextSelection.collapsed(8),
        bounded.selection,
    );
    try expectSecureEditorTailZero(&bounded);

    var utf8: SecureEditor(3) = .{};
    utf8.apply(.{ .insert_text = "ab" });
    utf8.apply(.{ .insert_text = "\xc3\xa9\xc3\xa9" });
    try std.testing.expectEqualStrings("ab", utf8.text());
    try std.testing.expect(utf8.truncated);
    try expectSecureEditorTailZero(&utf8);

    var set_bounded: SecureEditor(4) = .{};
    set_bounded.set("12345");
    try std.testing.expectEqualStrings("1234", set_bounded.text());
    try std.testing.expect(set_bounded.truncated);
    set_bounded.set("x");
    try std.testing.expectEqualStrings("x", set_bounded.text());
    try std.testing.expect(!set_bounded.truncated);
    try expectSecureEditorTailZero(&set_bounded);
    set_bounded.apply(.{ .insert_text = "overflow" });
    try std.testing.expect(set_bounded.truncated);
    set_bounded.clear();
    try std.testing.expect(!set_bounded.truncated);
    try expectSecureEditorTailZero(&set_bounded);
}
