//! Typed 1701Q January 2018 transaction state.
//!
//! This module is the ownership boundary between a frozen profile projection
//! and one form transaction. It deliberately does not encrypt, transport,
//! persist, or log taxpayer values.
//!
//! Grounding:
//! - exact live control order and artifact occurrence order: `occurrences.zig`;
//! - profile-produced controls: `profile_mapping.zig`;
//! - transaction elections that profiles must never select:
//!   `profile_mapping.transaction_owned_controls`;
//! - fixed-point inputs and outputs: `calculations.zig`;
//! - ordered validation input: `validation.zig`;
//! - exact package identity: `evidence.zig`;
//! - currency normalization: Offline eBIRForms 7.9.6
//!   `js/string-util.js`, `formatCurrency` lines 321-356 and
//!   `NumWithComma` lines 358-362.
//!
//! Currency parsing accepts only the normalized, printable ASCII subset
//! produced by `formatCurrency`: optional `-`, canonical comma grouping, and
//! exactly two decimal digits. Ambiguous/unformatted legacy input is rejected
//! instead of being guessed.

const std = @import("std");
const form = @import("../../../forms/form_1701q.zig");
const field = @import("../../../tax_profile/field.zig");
const model = @import("../../../tax_profile/model.zig");
const projection = @import("../../../tax_profile/projection.zig");
const occurrence = @import("../../occurrence.zig");
const identity = @import("../../identity.zig");
const occurrences = @import("occurrences.zig");
const control_contract = @import("control_contract.zig");
const profile_mapping = @import("profile_mapping.zig");
const rdo_options = @import("rdo_options.zig");
const calculations = @import("calculations.zig");
const validation = @import("validation.zig");
const document = @import("document.zig");
const evidence = @import("evidence.zig");
const sensitive_memory = @import("../../../security/sensitive_memory.zig");

pub const control_count = occurrences.control_seeds.len;
pub const editable_occurrence_count =
    occurrences.editable_occurrence_items.len;
pub const final_occurrence_count =
    occurrences.final_copy_occurrence_items.len;

pub const Origin = occurrence.OriginKind;

/// Defensive allocation-free storage ceiling. The much smaller exact
/// per-control limits are cataloged by `control_contract.zig` and enforced by
/// `State.setText`; this ceiling protects the two legacy text controls that
/// have no declaration-time `maxlength`.
pub const max_state_text_bytes: usize = 1024;

pub const Error = error{
    ControlClassificationMissing,
    ControlClassificationOverlap,
    ControlClassificationCountMismatch,
    UnknownControl,
    OriginMismatch,
    KindMismatch,
    ReservedOrigin,
    SensitiveValueForbidden,
    ValueTooLong,
    NonAsciiValue,
    ControlCharacter,
    MissingValue,
    InvalidYear,
    InvalidMoney,
    MoneyOverflow,
    InvalidRdoSelection,
    EvidenceMismatch,
    InvalidProfileSnapshot,
    ProfileNotApplied,
    CalculationSnapshotMismatch,
    MixedOccurrenceOrigin,
};

pub const Sensitivity = enum {
    ordinary,
    /// Submission credentials have no legitimate value in the offline
    /// artifact-lab state. These controls remain present and empty so exact
    /// legacy order can be represented without accepting a secret.
    credential_forbidden,
};

pub const StoredText = struct {
    const Self = @This();

    bytes: [max_state_text_bytes]u8 =
        [_]u8{0} ** max_state_text_bytes,
    len: u16 = 0,

    pub fn asSlice(self: *const StoredText) []const u8 {
        return self.bytes[0..self.len];
    }

    fn init(raw: []const u8) Error!StoredText {
        if (raw.len > max_state_text_bytes) return error.ValueTooLong;
        for (raw) |byte| {
            if (byte > 0x7f) return error.NonAsciiValue;
            if (byte < 0x20 or byte == 0x7f) {
                return error.ControlCharacter;
            }
        }

        var result: StoredText = .{};
        @memcpy(result.bytes[0..raw.len], raw);
        result.len = @intCast(raw.len);
        return result;
    }

    pub fn wipe(self: *Self) void {
        sensitive_memory.wipeValue(Self, self);
    }

    pub fn deinit(self: *Self) void {
        self.wipe();
    }
};

fn validateControlLength(control_id: []const u8, raw: []const u8) Error!void {
    const contract = control_contract.find(control_id) orelse
        return error.EvidenceMismatch;
    if (contract.kind == .radio) return error.KindMismatch;
    if (contract.max_length) |maximum| {
        if (raw.len > @as(usize, maximum)) return error.ValueTooLong;
    }
}

fn initControlText(control_id: []const u8, raw: []const u8) Error!StoredText {
    var stored = try StoredText.init(raw);
    errdefer stored.deinit();
    try validateControlLength(control_id, raw);
    const result = stored;
    stored.deinit();
    return result;
}

pub const Value = union(enum) {
    missing,
    text: StoredText,
    checked: bool,
};

pub const Slot = struct {
    id: []const u8,
    kind: occurrences.ControlKind,
    origin: Origin,
    sensitivity: Sensitivity = .ordinary,
    value: Value = .missing,
    /// Present only when this exact control value was produced by an entry in
    /// the accepted frozen profile snapshot. Optional absent profile fields
    /// have an explicit empty control value and null provenance.
    profile_provenance: ?projection.Provenance = null,

    fn erasePayload(self: *Slot) void {
        sensitive_memory.wipeValue(Value, &self.value);
        sensitive_memory.wipeValue(
            ?projection.Provenance,
            &self.profile_provenance,
        );
    }

    fn clearProfileProvenance(self: *Slot) void {
        self.profile_provenance = null;
        // A null optional aggregate may leave its payload padding undefined
        // on some target ABIs. Scrub after assigning the semantic null so the
        // representation cannot retain displaced provenance bytes.
        sensitive_memory.wipeValue(
            ?projection.Provenance,
            &self.profile_provenance,
        );
    }

    fn clearMissingValue(self: *Slot) void {
        self.value = .missing;
        // A union tag assignment may leave its inactive payload undefined on
        // some target ABIs. `missing` is the zero-valued first tag, so wiping
        // the complete representation preserves the semantic value while
        // removing any displaced text bytes and padding.
        sensitive_memory.wipeValue(Value, &self.value);
    }

    /// Consumes and wipes both prepared inputs after installing their active
    /// semantic values. Callers must pass storage distinct from this slot.
    fn replaceText(
        self: *Slot,
        replacement: *StoredText,
        replacement_provenance: ?*?projection.Provenance,
    ) void {
        self.erasePayload();
        self.value = .{ .text = replacement.* };
        replacement.deinit();
        if (replacement_provenance) |owned| {
            if (owned.*) |*provenance| {
                self.profile_provenance = provenance.*;
            } else {
                self.clearProfileProvenance();
            }
            sensitive_memory.wipeValue(
                ?projection.Provenance,
                owned,
            );
        } else {
            self.clearProfileProvenance();
        }
    }

    fn replaceChecked(self: *Slot, checked: bool) void {
        self.erasePayload();
        self.value = .{ .checked = checked };
        self.clearProfileProvenance();
    }

    fn replaceMissing(self: *Slot) void {
        self.erasePayload();
        self.clearMissingValue();
        self.clearProfileProvenance();
    }
};

pub const filing_context_controls = [_][]const u8{
    "frm1701q:txtYear",
    "frm1701q:DateQuarter_1",
    "frm1701q:DateQuarter_2",
    "frm1701q:DateQuarter_3",
    "frm1701q:AmendedRtn_1",
    "frm1701q:AmendedRtn_2",
    "frm1701q:txtSheets",
};

/// Transaction-owned text inputs. Radio elections are separately grounded by
/// `profile_mapping.transaction_owned_controls`.
pub const transaction_text_controls = [_][]const u8{
    "frm1701q:txtAgency32",
    "frm1701q:txtNumber32",
    "frm1701q:txtDate32",
    "frm1701q:txtAmount32",
    "frm1701q:txtAgency33",
    "frm1701q:txtNumber33",
    "frm1701q:txtDate33",
    "frm1701q:txtAmount33",
    "frm1701q:txtNumber34",
    "frm1701q:txtDate34",
    "frm1701q:txtAmount34",
    "frm1701q:txtParticular35",
    "frm1701q:txtAgency35",
    "frm1701q:txtNumber35",
    "frm1701q:txtDate35",
    "frm1701q:txtAmount35",

    "frm1701q:txt36A",
    "frm1701q:txt36B",
    "frm1701q:txt37A",
    "frm1701q:txt37B",
    "frm1701q:txt39A",
    "frm1701q:txt39B",
    "frm1701q:txt42A",
    "frm1701q:txt42B",
    "frm1701q:txt43Desc",
    "frm1701q:txt43A",
    "frm1701q:txt43B",
    "frm1701q:txt44A",
    "frm1701q:txt44B",
    "frm1701q:txt47A",
    "frm1701q:txt47B",
    "frm1701q:txt48Desc",
    "frm1701q:txt48A",
    "frm1701q:txt48B",
    "frm1701q:txt50A",
    "frm1701q:txt50B",
    "frm1701q:txt52A",
    "frm1701q:txt52B",
    "frm1701q:txt55A",
    "frm1701q:txt55B",
    "frm1701q:txt56A",
    "frm1701q:txt56B",
    "frm1701q:txt57A",
    "frm1701q:txt57B",
    "frm1701q:txt58A",
    "frm1701q:txt58B",
    "frm1701q:txt59A",
    "frm1701q:txt59B",
    "frm1701q:txt60A",
    "frm1701q:txt60B",
    "frm1701q:txt61Desc",
    "frm1701q:txt61A",
    "frm1701q:txt61B",
    "frm1701q:txt64A",
    "frm1701q:txt64B",
    "frm1701q:txt65A",
    "frm1701q:txt65B",
    "frm1701q:txt66A",
    "frm1701q:txt66B",
};

pub const derived_controls = [_][]const u8{
    "frm1701q:txt26A",
    "frm1701q:txt26B",
    "frm1701q:txt27A",
    "frm1701q:txt27B",
    "frm1701q:txt28A",
    "frm1701q:txt28B",
    "frm1701q:txt29A",
    "frm1701q:txt29B",
    "frm1701q:txt30A",
    "frm1701q:txt30B",
    "frm1701q:txt31",
    "frm1701q:txt38A",
    "frm1701q:txt38B",
    "frm1701q:txt40A",
    "frm1701q:txt40B",
    "frm1701q:txt41A",
    "frm1701q:txt41B",
    "frm1701q:txt45A",
    "frm1701q:txt45B",
    "frm1701q:txt46A",
    "frm1701q:txt46B",
    "frm1701q:txt49A",
    "frm1701q:txt49B",
    "frm1701q:txt51A",
    "frm1701q:txt51B",
    "frm1701q:txt53A",
    "frm1701q:txt53B",
    "frm1701q:txt54A",
    "frm1701q:txt54B",
    "frm1701q:txt62A",
    "frm1701q:txt62B",
    "frm1701q:txt63A",
    "frm1701q:txt63B",
    "frm1701q:txt67A",
    "frm1701q:txt67B",
    "frm1701q:txt68A",
    "frm1701q:txt68B",
};

pub const system_controls = [_][]const u8{
    "frm1701q:txtCurrentPage",
    "frm1701q:txtMaxPage",
    "txtFinalFlag",
    "txtEnroll",
    "driveSelectTPExport",
};

pub const preparer_credential_controls = [_][]const u8{
    "ebirOnlineConfirmUsername",
    "ebirOnlineUsername",
    "ebirOnlineSecret",
};

/// These two values were populated by legacy background state, but no
/// reviewed 1701Q reusable-profile rule currently produces them. They remain
/// explicit external evidence instead of being inferred from another field.
pub const external_evidence_controls = [_][]const u8{
    "frm1701q:txtLOB",
    "frm1701q:txtTelno",
};

pub const ClassificationCounts = struct {
    profile: usize = 0,
    transaction: usize = 0,
    preparer: usize = 0,
    filing_context: usize = 0,
    external_evidence: usize = 0,
    derived: usize = 0,
    system: usize = 0,
};

pub const expected_classification_counts: ClassificationCounts = .{
    .profile = 28,
    .transaction = 91,
    .preparer = 3,
    .filing_context = 7,
    .external_evidence = 2,
    .derived = 37,
    .system = 5,
};

/// Remaining evidence gaps are explicit and do not silently relax a gate.
pub const evidence_gaps = [_][]const u8{
    "arbitrary pre-blur NumWithComma input is intentionally not accepted",
    "txtLOB and txtTelno lack reviewed reusable-profile mappings",
    "credential-bearing preparer controls are intentionally locked empty",
};

pub fn classifyControl(control_id: []const u8) ?Origin {
    if (inProfileControls(control_id)) return .profile;
    if (inTransactionControls(control_id)) return .transaction;
    if (inList(&preparer_credential_controls, control_id)) return .preparer;
    if (inList(&filing_context_controls, control_id)) return .filing_context;
    if (inList(&external_evidence_controls, control_id)) {
        return .external_evidence;
    }
    if (inList(&derived_controls, control_id)) return .derived;
    if (inList(&system_controls, control_id)) return .system;
    return null;
}

pub fn validateControlClassification() Error!ClassificationCounts {
    var counts: ClassificationCounts = .{};
    for (occurrences.control_seeds) |seed| {
        const memberships = classificationMembershipCount(seed.id);
        if (memberships == 0) return error.ControlClassificationMissing;
        if (memberships != 1) return error.ControlClassificationOverlap;
        const origin = classifyControl(seed.id) orelse
            return error.ControlClassificationMissing;
        switch (origin) {
            .profile => counts.profile += 1,
            .transaction => counts.transaction += 1,
            .preparer => counts.preparer += 1,
            .filing_context => counts.filing_context += 1,
            .external_evidence => counts.external_evidence += 1,
            .derived => counts.derived += 1,
            .system => counts.system += 1,
            .unreviewed => return error.ControlClassificationMissing,
        }
    }

    if (!std.meta.eql(counts, expected_classification_counts)) {
        return error.ControlClassificationCountMismatch;
    }
    return counts;
}

fn classificationMembershipCount(control_id: []const u8) u8 {
    var result: u8 = 0;
    result += @intFromBool(inProfileControls(control_id));
    result += @intFromBool(inTransactionControls(control_id));
    result += @intFromBool(inList(
        &preparer_credential_controls,
        control_id,
    ));
    result += @intFromBool(inList(&filing_context_controls, control_id));
    result += @intFromBool(inList(&external_evidence_controls, control_id));
    result += @intFromBool(inList(&derived_controls, control_id));
    result += @intFromBool(inList(&system_controls, control_id));
    return result;
}

fn inProfileControls(control_id: []const u8) bool {
    for (profile_mapping.profile_control_rules) |rule| {
        if (std.mem.eql(u8, rule.control_id, control_id)) return true;
    }
    return false;
}

fn inTransactionControls(control_id: []const u8) bool {
    for (profile_mapping.transaction_owned_controls) |control| {
        if (std.mem.eql(u8, control.control_id, control_id)) return true;
    }
    return inList(&transaction_text_controls, control_id);
}

fn inList(list: []const []const u8, control_id: []const u8) bool {
    for (list) |candidate| {
        if (std.mem.eql(u8, candidate, control_id)) return true;
    }
    return false;
}

pub const DigestBundle = struct {
    package: identity.Sha256Digest,
    profile_snapshot: identity.Sha256Digest,
    transaction_state: identity.Sha256Digest,
};

/// Unique inline owner of all normalized transaction and profile-projected
/// control bytes. Call `deinit` exactly once unless ownership is transferred
/// to a workflow consuming transition.
pub const State = struct {
    slots: [control_count]Slot,
    applied_profile_digest: ?identity.Sha256Digest = null,

    pub fn init() Error!State {
        _ = try validateControlClassification();

        var result: State = undefined;
        errdefer sensitive_memory.wipeValue(State, &result);
        result.applied_profile_digest = null;
        for (occurrences.control_seeds, 0..) |seed, index| {
            const origin = classifyControl(seed.id) orelse
                return error.ControlClassificationMissing;
            result.slots[index] = .{
                .id = seed.id,
                .kind = seed.kind,
                .origin = origin,
                .sensitivity = if (origin == .preparer)
                    .credential_forbidden
                else
                    .ordinary,
            };
            if (origin == .preparer) {
                // Exact serializers still require a typed value at this
                // position. The only permitted value is empty.
                var empty = try initControlText(seed.id, "");
                result.slots[index].value = .{
                    .text = empty,
                };
                empty.deinit();
            }
        }
        return result;
    }

    pub fn wipe(self: *State) void {
        sensitive_memory.wipeValue(State, self);
    }

    pub fn deinit(self: *State) void {
        self.wipe();
    }

    pub fn originFor(
        self: *const State,
        control_id: []const u8,
    ) Error!Origin {
        const index = self.findIndex(control_id) orelse
            return error.UnknownControl;
        return self.slots[index].origin;
    }

    pub fn setText(
        self: *State,
        expected_origin: Origin,
        control_id: []const u8,
        raw: []const u8,
    ) Error!void {
        const slot = try self.mutableForWrite(expected_origin, control_id);
        if (slot.kind == .radio) return error.KindMismatch;
        var replacement = try initControlText(control_id, raw);
        slot.replaceText(&replacement, null);
    }

    pub fn setChecked(
        self: *State,
        expected_origin: Origin,
        control_id: []const u8,
        checked_value: bool,
    ) Error!void {
        const slot = try self.mutableForWrite(expected_origin, control_id);
        if (slot.kind != .radio) return error.KindMismatch;
        slot.replaceChecked(checked_value);
    }

    pub fn unset(
        self: *State,
        expected_origin: Origin,
        control_id: []const u8,
    ) Error!void {
        const index = self.findIndex(control_id) orelse
            return error.UnknownControl;
        const slot = &self.slots[index];
        if (slot.origin != expected_origin) return error.OriginMismatch;
        if (slot.origin == .profile or slot.origin == .derived) {
            return error.ReservedOrigin;
        }
        if (slot.sensitivity == .credential_forbidden) {
            var replacement = try initControlText(control_id, "");
            slot.replaceText(&replacement, null);
            return;
        }
        slot.replaceMissing();
    }

    pub fn text(
        self: *const State,
        expected_origin: Origin,
        control_id: []const u8,
    ) Error![]const u8 {
        const slot = try self.forRead(expected_origin, control_id);
        if (slot.kind == .radio) return error.KindMismatch;
        if (slot.sensitivity == .credential_forbidden) {
            return error.SensitiveValueForbidden;
        }
        return textFromValue(&slot.value);
    }

    pub fn checked(
        self: *const State,
        expected_origin: Origin,
        control_id: []const u8,
    ) Error!bool {
        const slot = try self.forRead(expected_origin, control_id);
        if (slot.kind != .radio) return error.KindMismatch;
        return checkedFromValue(&slot.value);
    }

    pub fn profileProvenance(
        self: *const State,
        control_id: []const u8,
    ) Error!?projection.Provenance {
        const slot = try self.forRead(.profile, control_id);
        return slot.profile_provenance;
    }

    /// Atomically replaces only profile-produced controls. Transaction
    /// elections and every other origin remain byte-for-byte unchanged.
    pub fn applyProfile(
        self: *State,
        supplied: *const profile_mapping.ControlSnapshot,
    ) Error!void {
        var remapped = try validateAndRemapProfile(supplied);
        defer sensitive_memory.wipeValue(
            profile_mapping.ControlSnapshot,
            &remapped,
        );

        var staged_values: [profile_mapping.profile_control_rules.len]StoredText = undefined;
        defer sensitive_memory.wipeValue(
            [profile_mapping.profile_control_rules.len]StoredText,
            &staged_values,
        );
        var staged_provenance: [profile_mapping.profile_control_rules.len]?projection.Provenance =
            [_]?projection.Provenance{null} **
            profile_mapping.profile_control_rules.len;
        defer sensitive_memory.wipeValue(
            [profile_mapping.profile_control_rules.len]?projection.Provenance,
            &staged_provenance,
        );

        for (profile_mapping.profile_control_rules, 0..) |rule, index| {
            const seed = controlSeed(rule.control_id) orelse
                return error.EvidenceMismatch;
            const default_value = if (seed.kind == .select_one) "000" else "";
            if (remapped.get(rule.control_id)) |entry| {
                var prepared = try initControlText(
                    rule.control_id,
                    entry.value.asSlice(),
                );
                defer prepared.deinit();
                staged_values[index] = prepared;
                staged_provenance[index] = entry.provenance;
            } else {
                var prepared = try initControlText(
                    rule.control_id,
                    default_value,
                );
                defer prepared.deinit();
                staged_values[index] = prepared;
            }
        }
        const replacement_digest = digestProfileSnapshot(
            &remapped.profile,
        );

        // No fallible work occurs after this point.
        for (profile_mapping.profile_control_rules, 0..) |rule, index| {
            const slot_index = self.findIndex(rule.control_id).?;
            self.slots[slot_index].replaceText(
                &staged_values[index],
                &staged_provenance[index],
            );
        }
        sensitive_memory.wipeValue(
            ?identity.Sha256Digest,
            &self.applied_profile_digest,
        );
        self.applied_profile_digest = replacement_digest;
    }

    /// Builds the exact fixed-point input state. All participating controls
    /// must have a value of the evidenced kind; missing and malformed values
    /// are never treated as zero.
    pub fn toCalculationState(
        self: *const State,
    ) Error!calculations.FormState {
        const year_raw = try self.requiredText("frm1701q:txtYear");
        const parsed_year = parseYear(year_raw);

        return .{
            .year = try parsed_year,
            .taxpayer = .{
                .selections = try self.personSelections(.taxpayer),
                .inputs = try self.personInputs(.taxpayer),
            },
            .spouse = .{
                .selections = try self.personSelections(.spouse),
                .inputs = try self.personInputs(.spouse),
            },
        };
    }

    /// Applies a result only when its year, elections, and transaction inputs
    /// exactly match this state. A result calculated for another draft cannot
    /// be attached accidentally.
    pub fn applyCalculated(
        self: *State,
        calculated: calculations.FormState,
    ) Error!void {
        var current = try self.toCalculationState();
        defer sensitive_memory.wipeValue(
            calculations.FormState,
            &current,
        );
        if (!calculationInputsEqual(&current, &calculated)) {
            return error.CalculationSnapshotMismatch;
        }

        const Pair = struct {
            id: []const u8,
            money: calculations.Money,
        };
        var pairs = [_]Pair{
            .{ .id = "frm1701q:txt26A", .money = calculated.taxpayer.derived.txt26 },
            .{ .id = "frm1701q:txt26B", .money = calculated.spouse.derived.txt26 },
            .{ .id = "frm1701q:txt27A", .money = calculated.taxpayer.derived.txt27 },
            .{ .id = "frm1701q:txt27B", .money = calculated.spouse.derived.txt27 },
            .{ .id = "frm1701q:txt28A", .money = calculated.taxpayer.derived.txt28 },
            .{ .id = "frm1701q:txt28B", .money = calculated.spouse.derived.txt28 },
            .{ .id = "frm1701q:txt29A", .money = calculated.taxpayer.derived.txt29 },
            .{ .id = "frm1701q:txt29B", .money = calculated.spouse.derived.txt29 },
            .{ .id = "frm1701q:txt30A", .money = calculated.taxpayer.derived.txt30 },
            .{ .id = "frm1701q:txt30B", .money = calculated.spouse.derived.txt30 },
            .{ .id = "frm1701q:txt31", .money = calculated.txt31 },
            .{ .id = "frm1701q:txt38A", .money = calculated.taxpayer.derived.txt38 },
            .{ .id = "frm1701q:txt38B", .money = calculated.spouse.derived.txt38 },
            .{ .id = "frm1701q:txt40A", .money = calculated.taxpayer.derived.txt40 },
            .{ .id = "frm1701q:txt40B", .money = calculated.spouse.derived.txt40 },
            .{ .id = "frm1701q:txt41A", .money = calculated.taxpayer.derived.txt41 },
            .{ .id = "frm1701q:txt41B", .money = calculated.spouse.derived.txt41 },
            .{ .id = "frm1701q:txt45A", .money = calculated.taxpayer.derived.txt45 },
            .{ .id = "frm1701q:txt45B", .money = calculated.spouse.derived.txt45 },
            .{ .id = "frm1701q:txt46A", .money = calculated.taxpayer.derived.txt46 },
            .{ .id = "frm1701q:txt46B", .money = calculated.spouse.derived.txt46 },
            .{ .id = "frm1701q:txt49A", .money = calculated.taxpayer.derived.txt49 },
            .{ .id = "frm1701q:txt49B", .money = calculated.spouse.derived.txt49 },
            .{ .id = "frm1701q:txt51A", .money = calculated.taxpayer.derived.txt51 },
            .{ .id = "frm1701q:txt51B", .money = calculated.spouse.derived.txt51 },
            .{ .id = "frm1701q:txt53A", .money = calculated.taxpayer.derived.txt53 },
            .{ .id = "frm1701q:txt53B", .money = calculated.spouse.derived.txt53 },
            .{ .id = "frm1701q:txt54A", .money = calculated.taxpayer.derived.txt54 },
            .{ .id = "frm1701q:txt54B", .money = calculated.spouse.derived.txt54 },
            .{ .id = "frm1701q:txt62A", .money = calculated.taxpayer.derived.txt62 },
            .{ .id = "frm1701q:txt62B", .money = calculated.spouse.derived.txt62 },
            .{ .id = "frm1701q:txt63A", .money = calculated.taxpayer.derived.txt63 },
            .{ .id = "frm1701q:txt63B", .money = calculated.spouse.derived.txt63 },
            .{ .id = "frm1701q:txt67A", .money = calculated.taxpayer.derived.txt67 },
            .{ .id = "frm1701q:txt67B", .money = calculated.spouse.derived.txt67 },
            .{ .id = "frm1701q:txt68A", .money = calculated.taxpayer.derived.txt68 },
            .{ .id = "frm1701q:txt68B", .money = calculated.spouse.derived.txt68 },
        };
        defer sensitive_memory.wipeValue(
            [derived_controls.len]Pair,
            &pairs,
        );
        var staged: [derived_controls.len]StoredText = undefined;
        defer sensitive_memory.wipeValue(
            [derived_controls.len]StoredText,
            &staged,
        );
        for (pairs, 0..) |pair, index| {
            var prepared = try formatMoney(pair.money);
            defer prepared.deinit();
            try validateControlLength(pair.id, prepared.asSlice());
            staged[index] = prepared;
        }

        for (pairs, 0..) |pair, index| {
            const slot_index = self.findIndex(pair.id).?;
            self.slots[slot_index].replaceText(&staged[index], null);
        }
    }

    pub fn recalculateAndApply(
        self: *State,
    ) (Error || calculations.CalculationError)!calculations.FormState {
        var input = try self.toCalculationState();
        defer sensitive_memory.wipeValue(
            calculations.FormState,
            &input,
        );
        var calculated = try calculations.recalculate(input);
        defer sensitive_memory.wipeValue(
            calculations.FormState,
            &calculated,
        );
        try self.applyCalculated(calculated);
        // `computePartIII()` always reaches `computetxt31()`, whose final
        // source action is the effective zero-argument `capital()` from
        // string-util.js. That function uppercases every text control except
        // the unprefixed `txtEmail`, including disabled/profile-produced form
        // controls. This mutates only the form-owned rendered bytes: semantic
        // profile provenance and the frozen profile digest remain unchanged.
        _ = self.applyLegacyCapital();
        return calculated;
    }

    /// Applies the effective Desktop `capital()` mutation in place.
    ///
    /// ASCII uppercasing is length preserving and all stored text has already
    /// passed the transaction grammar, so no fallible work is required. In
    /// particular, profile slots retain both their origin and provenance:
    /// this is a form-representation side effect, not a profile revision.
    pub fn applyLegacyCapital(self: *State) bool {
        var changed = false;
        for (&self.slots) |*slot| {
            if (slot.kind != .text or
                std.mem.eql(u8, slot.id, "txtEmail"))
            {
                continue;
            }
            switch (slot.value) {
                .text => |*stored| {
                    for (stored.bytes[0..stored.len]) |*byte| {
                        const upper = std.ascii.toUpper(byte.*);
                        if (upper != byte.*) changed = true;
                        byte.* = upper;
                    }
                },
                .missing, .checked => {},
            }
        }
        return changed;
    }

    /// Produces the exact ordered validation input without running a rule.
    /// The spouse TIN checksum is deliberately supplied by the caller because
    /// the grounded validation module models that external legacy result.
    pub fn toValidationInput(
        self: *const State,
        current_year: i32,
        spouse_tin_checksum: validation.TinChecksumStatus,
    ) Error!validation.FormValidationInput {
        const taxpayer_rdo =
            try self.requiredText("frm1701q:txtRDOCode");
        const spouse_rdo =
            try self.requiredText("frm1701q:txtSpouseRDOCode");
        return .{
            .current_year = current_year,
            .year = try self.requiredText("frm1701q:txtYear"),
            .quarter_checked = .{
                try self.requiredChecked("frm1701q:DateQuarter_1"),
                try self.requiredChecked("frm1701q:DateQuarter_2"),
                try self.requiredChecked("frm1701q:DateQuarter_3"),
            },
            .taxpayer_tin = .{
                try self.requiredText("frm1701q:txtTIN1"),
                try self.requiredText("frm1701q:txtTIN2"),
                try self.requiredText("frm1701q:txtTIN3"),
            },
            .taxpayer_branch_code = try self.requiredText("frm1701q:txtBranchCode"),
            .taxpayer_rdo_selected_index = try rdoSelectedIndex(
                taxpayer_rdo,
            ),
            .taxpayer_rdo_value = taxpayer_rdo,
            .taxpayer_name = try self.requiredText("frm1701q:txtTaxpayerName"),
            .taxpayer_address = try self.requiredText("frm1701q:txtAddress"),
            .taxpayer_birth_month = try self.requiredText("frm1701q:txtBirthMonth"),
            .taxpayer_birth_day = try self.requiredText("frm1701q:txtBirthDay"),
            .taxpayer_birth_year = try self.requiredText("frm1701q:txtBirthYear"),
            .taxpayer_zip = try self.requiredText("frm1701q:txtZipCode"),
            .spouse_tin = .{
                try self.requiredText("frm1701q:txtSpouseTIN1"),
                try self.requiredText("frm1701q:txtSpouseTIN2"),
                try self.requiredText("frm1701q:txtSpouseTIN3"),
            },
            .spouse_branch_code = try self.requiredText("frm1701q:txtSpouseBranchCode"),
            .spouse_tin_checksum = spouse_tin_checksum,
            .spouse_rdo_selected_index = try rdoSelectedIndex(spouse_rdo),
            .spouse_name = try self.requiredText("frm1701q:txtSpouseName"),
            .taxpayer_type_checked = .{
                try self.requiredChecked("frm1701q:optType_1"),
                try self.requiredChecked("frm1701q:optType_2"),
                try self.requiredChecked("frm1701q:optType_3"),
                try self.requiredChecked("frm1701q:optType_4"),
            },
            .taxpayer_atc_checked = .{
                try self.requiredChecked("frm1701q:optATC_1"),
                try self.requiredChecked("frm1701q:optATC_2"),
                try self.requiredChecked("frm1701q:optATC_3"),
                try self.requiredChecked("frm1701q:optATC_4"),
                try self.requiredChecked("frm1701q:optATC_5"),
                try self.requiredChecked("frm1701q:optATC_6"),
            },
            .taxpayer_tax_rate_checked = .{
                try self.requiredChecked("frm1701q:optTaxRate_1"),
                try self.requiredChecked("frm1701q:optTaxRate_2"),
            },
            .taxpayer_deduction_method_checked = .{
                try self.requiredChecked(
                    "frm1701q:optMethodOfDeduction:_1",
                ),
                try self.requiredChecked(
                    "frm1701q:optMethodOfDeduction:_2",
                ),
            },
            .spouse_type_checked = .{
                try self.requiredChecked("frm1701q:optSpouseType_1"),
                try self.requiredChecked("frm1701q:optSpouseType_2"),
                try self.requiredChecked("frm1701q:optSpouseType_3"),
            },
            .spouse_atc_checked = .{
                try self.requiredChecked("frm1701q:optSpouseATC_1"),
                try self.requiredChecked("frm1701q:optSpouseATC_2"),
                try self.requiredChecked("frm1701q:optSpouseATC_3"),
                try self.requiredChecked("frm1701q:optSpouseATC_4"),
                try self.requiredChecked("frm1701q:optSpouseATC_5"),
                try self.requiredChecked("frm1701q:optSpouseATC_6"),
                try self.requiredChecked("frm1701q:optSpouseATC_7"),
            },
            .spouse_tax_rate_checked = .{
                try self.requiredChecked("frm1701q:optSpouseTaxRate_1"),
                try self.requiredChecked("frm1701q:optSpouseTaxRate_2"),
            },
        };
    }

    /// Exact codec input in live `frmMain.elements` order. Returned text
    /// slices borrow this state.
    pub fn toCodecControls(
        self: *const State,
    ) Error![control_count]document.ControlInput {
        var result: [control_count]document.ControlInput = undefined;
        errdefer sensitive_memory.wipeValue(
            [control_count]document.ControlInput,
            &result,
        );
        for (occurrences.control_seeds, 0..) |seed, index| {
            const slot = &self.slots[index];
            if (!std.mem.eql(u8, seed.id, slot.id) or
                seed.kind != slot.kind)
            {
                return error.EvidenceMismatch;
            }
            result[index] = .{
                .id = seed.id,
                .value = try self.codecValue(slot),
            };
        }
        return result;
    }

    pub fn editableOccurrenceValues(
        self: *const State,
    ) Error![editable_occurrence_count]OccurrenceValue {
        var result: [editable_occurrence_count]OccurrenceValue = undefined;
        errdefer sensitive_memory.wipeValue(
            [editable_occurrence_count]OccurrenceValue,
            &result,
        );
        for (occurrences.editable_occurrence_items, 0..) |metadata, index| {
            result[index] = try self.occurrenceValue(metadata);
        }
        return result;
    }

    pub fn finalOccurrenceValues(
        self: *const State,
    ) Error![final_occurrence_count]OccurrenceValue {
        var result: [final_occurrence_count]OccurrenceValue = undefined;
        errdefer sensitive_memory.wipeValue(
            [final_occurrence_count]OccurrenceValue,
            &result,
        );
        for (occurrences.final_copy_occurrence_items, 0..) |metadata, index| {
            result[index] = try self.occurrenceValue(metadata);
        }
        return result;
    }

    /// Hashes all non-profile state in exact control order. Credential-bearing
    /// preparer controls are omitted entirely, even if a caller corrupts the
    /// public struct representation.
    pub fn transactionDigest(
        self: *const State,
    ) identity.Sha256Digest {
        var hash = std.crypto.hash.sha2.Sha256.init(.{});
        defer sensitive_memory.wipeValue(
            std.crypto.hash.sha2.Sha256,
            &hash,
        );
        hash.update("ebirforms.1701q-2018.transaction-state.v1");
        const package_digest = evidence.package_key.canonicalDigest();
        hash.update(package_digest.asBytes());
        for (&self.slots) |*slot| {
            if (slot.origin == .profile or
                slot.sensitivity == .credential_forbidden)
            {
                continue;
            }
            hashLengthPrefixed(&hash, slot.id);
            hash.update(&.{
                @as(u8, @intCast(@intFromEnum(slot.kind))),
                @as(u8, @intCast(@intFromEnum(slot.origin))),
                @as(u8, @intCast(@intFromEnum(slot.sensitivity))),
            });
            hashValue(&hash, &slot.value);
        }
        return finishDigest(&hash);
    }

    pub fn digestBundle(self: *const State) Error!DigestBundle {
        return .{
            .package = evidence.package_key.canonicalDigest(),
            .profile_snapshot = self.applied_profile_digest orelse
                return error.ProfileNotApplied,
            .transaction_state = self.transactionDigest(),
        };
    }

    fn personSelections(
        self: *const State,
        person: calculations.Person,
    ) Error!calculations.SelectionState {
        return switch (person) {
            .taxpayer => .{
                .graduated_rate_checked = try self.requiredChecked("frm1701q:optTaxRate_1"),
                .eight_percent_rate_checked = try self.requiredChecked("frm1701q:optTaxRate_2"),
                .itemized_deduction_checked = try self.requiredChecked(
                    "frm1701q:optMethodOfDeduction:_1",
                ),
                .optional_deduction_checked = try self.requiredChecked(
                    "frm1701q:optMethodOfDeduction:_2",
                ),
            },
            .spouse => .{
                .graduated_rate_checked = try self.requiredChecked(
                    "frm1701q:optSpouseTaxRate_1",
                ),
                .eight_percent_rate_checked = try self.requiredChecked(
                    "frm1701q:optSpouseTaxRate_2",
                ),
                .itemized_deduction_checked = try self.requiredChecked(
                    "frm1701q:optSpouseMethod:_1",
                ),
                .optional_deduction_checked = try self.requiredChecked(
                    "frm1701q:optSpouseMethod:_2",
                ),
            },
        };
    }

    fn personInputs(
        self: *const State,
        person: calculations.Person,
    ) Error!calculations.PersonInputs {
        const suffix: u8 = switch (person) {
            .taxpayer => 'A',
            .spouse => 'B',
        };
        var id_buffer: [32]u8 = undefined;
        return .{
            .txt36 = try self.controlMoney(
                moneyControlId(&id_buffer, 36, suffix),
            ),
            .txt37 = try self.controlMoney(
                moneyControlId(&id_buffer, 37, suffix),
            ),
            .txt39 = try self.controlMoney(
                moneyControlId(&id_buffer, 39, suffix),
            ),
            .txt42 = try self.controlMoney(
                moneyControlId(&id_buffer, 42, suffix),
            ),
            .txt43 = try self.controlMoney(
                moneyControlId(&id_buffer, 43, suffix),
            ),
            .txt44 = try self.controlMoney(
                moneyControlId(&id_buffer, 44, suffix),
            ),
            .txt47 = try self.controlMoney(
                moneyControlId(&id_buffer, 47, suffix),
            ),
            .txt48 = try self.controlMoney(
                moneyControlId(&id_buffer, 48, suffix),
            ),
            .txt50 = try self.controlMoney(
                moneyControlId(&id_buffer, 50, suffix),
            ),
            .txt52 = try self.controlMoney(
                moneyControlId(&id_buffer, 52, suffix),
            ),
            .txt55_through_61 = .{
                try self.controlMoney(
                    moneyControlId(&id_buffer, 55, suffix),
                ),
                try self.controlMoney(
                    moneyControlId(&id_buffer, 56, suffix),
                ),
                try self.controlMoney(
                    moneyControlId(&id_buffer, 57, suffix),
                ),
                try self.controlMoney(
                    moneyControlId(&id_buffer, 58, suffix),
                ),
                try self.controlMoney(
                    moneyControlId(&id_buffer, 59, suffix),
                ),
                try self.controlMoney(
                    moneyControlId(&id_buffer, 60, suffix),
                ),
                try self.controlMoney(
                    moneyControlId(&id_buffer, 61, suffix),
                ),
            },
            .txt64_through_66 = .{
                try self.controlMoney(
                    moneyControlId(&id_buffer, 64, suffix),
                ),
                try self.controlMoney(
                    moneyControlId(&id_buffer, 65, suffix),
                ),
                try self.controlMoney(
                    moneyControlId(&id_buffer, 66, suffix),
                ),
            },
        };
    }

    fn controlMoney(
        self: *const State,
        control_id: []const u8,
    ) Error!calculations.Money {
        return parseMoney(try self.requiredText(control_id));
    }

    fn requiredText(
        self: *const State,
        control_id: []const u8,
    ) Error![]const u8 {
        const index = self.findIndex(control_id) orelse
            return error.UnknownControl;
        const slot = &self.slots[index];
        if (slot.kind == .radio) return error.KindMismatch;
        if (slot.sensitivity == .credential_forbidden) {
            return error.SensitiveValueForbidden;
        }
        return textFromValue(&slot.value);
    }

    fn requiredChecked(
        self: *const State,
        control_id: []const u8,
    ) Error!bool {
        const index = self.findIndex(control_id) orelse
            return error.UnknownControl;
        const slot = &self.slots[index];
        if (slot.kind != .radio) return error.KindMismatch;
        return checkedFromValue(&slot.value);
    }

    fn codecValue(
        self: *const State,
        slot: *const Slot,
    ) Error!document.ControlValue {
        _ = self;
        if (slot.sensitivity == .credential_forbidden) {
            return switch (slot.value) {
                .text => |*stored| if (stored.asSlice().len == 0)
                    .{ .text = "" }
                else
                    error.SensitiveValueForbidden,
                .missing, .checked => error.SensitiveValueForbidden,
            };
        }
        return switch (slot.kind) {
            .radio => .{
                .checked = try checkedFromValue(&slot.value),
            },
            .text, .select_one => .{
                .text = try textFromValue(&slot.value),
            },
        };
    }

    fn occurrenceValue(
        self: *const State,
        metadata: occurrence.OccurrenceMetadata,
    ) Error!OccurrenceValue {
        const first_id = metadata.source_controls.at(0) orelse
            return error.EvidenceMismatch;
        const first_index = self.findIndex(first_id) orelse
            return error.EvidenceMismatch;
        const first = &self.slots[first_index];

        if (metadata.source_controls.len() == 1) {
            const source: OccurrenceSource = switch (metadata.emission) {
                .checked_boolean => .{
                    .checked = try checkedFromValue(&first.value),
                },
                .constant => blk: {
                    _ = try self.codecValue(first);
                    break :blk .{ .constant_text = "1" };
                },
                .raw, .legacy_escape => .{
                    .text = try occurrenceText(first),
                },
                else => return error.EvidenceMismatch,
            };
            return .{
                .metadata = metadata,
                .origin = first.origin,
                .source = source,
            };
        }

        if (metadata.source_controls.len() != 2 or
            metadata.emission != .concatenated_legacy_escape)
        {
            return error.EvidenceMismatch;
        }
        const second_id = metadata.source_controls.at(1).?;
        const second_index = self.findIndex(second_id) orelse
            return error.EvidenceMismatch;
        const second = &self.slots[second_index];
        if (first.origin != second.origin) {
            return error.MixedOccurrenceOrigin;
        }
        return .{
            .metadata = metadata,
            .origin = first.origin,
            .source = .{ .concatenated_text = .{
                try occurrenceText(first),
                try occurrenceText(second),
            } },
        };
    }

    fn mutableForWrite(
        self: *State,
        expected_origin: Origin,
        control_id: []const u8,
    ) Error!*Slot {
        const index = self.findIndex(control_id) orelse
            return error.UnknownControl;
        const slot = &self.slots[index];
        if (slot.origin != expected_origin) return error.OriginMismatch;
        if (slot.origin == .profile or slot.origin == .derived) {
            return error.ReservedOrigin;
        }
        if (slot.origin == .unreviewed) return error.ReservedOrigin;
        if (slot.sensitivity == .credential_forbidden) {
            return error.SensitiveValueForbidden;
        }
        return slot;
    }

    fn forRead(
        self: *const State,
        expected_origin: Origin,
        control_id: []const u8,
    ) Error!*const Slot {
        const index = self.findIndex(control_id) orelse
            return error.UnknownControl;
        const slot = &self.slots[index];
        if (slot.origin != expected_origin) return error.OriginMismatch;
        return slot;
    }

    fn findIndex(
        self: *const State,
        control_id: []const u8,
    ) ?usize {
        for (self.slots, 0..) |slot, index| {
            if (std.mem.eql(u8, slot.id, control_id)) return index;
        }
        return null;
    }
};

/// Raw source-stage value plus the exact metadata that tells a codec how to
/// emit it. Keeping this as an ordered array (never a key map) preserves
/// repeated `serialized_key` occurrences and their counters.
pub const OccurrenceSource = union(enum) {
    text: []const u8,
    checked: bool,
    concatenated_text: [2][]const u8,
    constant_text: []const u8,
};

pub const OccurrenceValue = struct {
    metadata: occurrence.OccurrenceMetadata,
    origin: Origin,
    source: OccurrenceSource,
};

fn validateAndRemapProfile(
    supplied: *const profile_mapping.ControlSnapshot,
) Error!profile_mapping.ControlSnapshot {
    profile_mapping.validateEvidence() catch return error.EvidenceMismatch;
    profile_mapping.validateSemantics() catch return error.EvidenceMismatch;
    if (!supplied.profile.form.eql(&evidence.package_key.revision) or
        supplied.profile.len > projection.max_snapshot_entries or
        supplied.len > profile_mapping.profile_control_rules.len)
    {
        return error.InvalidProfileSnapshot;
    }
    const checked_date = model.Date.init(
        supplied.profile.effective_on.year,
        supplied.profile.effective_on.month,
        supplied.profile.effective_on.day,
    ) catch return error.InvalidProfileSnapshot;
    if (!checked_date.eql(supplied.profile.effective_on)) {
        return error.InvalidProfileSnapshot;
    }
    try validateSemanticSnapshot(&supplied.profile);

    var outcome = profile_mapping.mapProfileSnapshot(supplied.profile);
    defer sensitive_memory.wipeValue(@TypeOf(outcome), &outcome);
    const remapped = switch (outcome) {
        .accepted => |*accepted| accepted,
        .blocked => return error.InvalidProfileSnapshot,
    };
    if (!controlSnapshotsEqual(remapped, supplied)) {
        return error.InvalidProfileSnapshot;
    }
    return remapped.*;
}

fn validateSemanticSnapshot(snapshot: *const projection.Snapshot) Error!void {
    for (snapshot.slice(), 0..) |entry, index| {
        var reviewed = false;
        for (profile_mapping.profile_control_rules) |rule| {
            if (rule.role == entry.role and
                rule.semantic_target.eql(&entry.target))
            {
                if (entry.value.field() != rule.reusable_field) {
                    return error.InvalidProfileSnapshot;
                }
                reviewed = true;
                break;
            }
        }
        if (!reviewed or
            entry.provenance.profile_id.asSlice().len == 0 or
            entry.provenance.revision_id.asSlice().len == 0 or
            entry.provenance.revision_sequence == 0)
        {
            return error.InvalidProfileSnapshot;
        }
        switch (entry.provenance.revision_source) {
            .manual_entry => {},
            .imported => |reference| if (reference.asSlice().len == 0) {
                return error.InvalidProfileSnapshot;
            },
            .migrated => |reference| if (reference.asSlice().len == 0) {
                return error.InvalidProfileSnapshot;
            },
        }
        for (snapshot.slice()[0..index]) |earlier| {
            if (earlier.target.eql(&entry.target)) {
                return error.InvalidProfileSnapshot;
            }
        }
    }
}

fn controlSnapshotsEqual(
    expected: *const profile_mapping.ControlSnapshot,
    supplied: *const profile_mapping.ControlSnapshot,
) bool {
    if (expected.len != supplied.len) return false;
    for (expected.slice(), supplied.slice()) |left, right| {
        if (left.live_form_element_ordinal !=
            right.live_form_element_ordinal or
            left.role != right.role or
            left.reusable_field != right.reusable_field or
            !left.semantic_target.eql(&right.semantic_target) or
            !std.mem.eql(u8, left.control_id, right.control_id) or
            !std.mem.eql(
                u8,
                left.value.asSlice(),
                right.value.asSlice(),
            ) or
            !provenanceEql(&left.provenance, &right.provenance) or
            left.transform != right.transform or
            left.control_source_line != right.control_source_line or
            left.transform_evidence_first_line !=
                right.transform_evidence_first_line or
            left.transform_evidence_last_line !=
                right.transform_evidence_last_line or
            !std.mem.eql(
                u8,
                left.source_evidence_id,
                right.source_evidence_id,
            ))
        {
            return false;
        }
    }
    return true;
}

fn provenanceEql(
    left: *const projection.Provenance,
    right: *const projection.Provenance,
) bool {
    return left.profile_id.eql(&right.profile_id) and
        left.revision_id.eql(&right.revision_id) and
        left.revision_sequence == right.revision_sequence and
        revisionSourceEql(&left.revision_source, &right.revision_source) and
        optionalBusinessActivityIdEql(
            left.business_activity_id,
            right.business_activity_id,
        ) and
        optionalRegistrationFactIdEql(
            left.registration_fact_id,
            right.registration_fact_id,
        );
}

fn revisionSourceEql(
    left: *const model.RevisionSource,
    right: *const model.RevisionSource,
) bool {
    if (std.meta.activeTag(left.*) != std.meta.activeTag(right.*)) {
        return false;
    }
    return switch (left.*) {
        .manual_entry => true,
        .imported => |value| std.mem.eql(
            u8,
            value.asSlice(),
            right.imported.asSlice(),
        ),
        .migrated => |value| std.mem.eql(
            u8,
            value.asSlice(),
            right.migrated.asSlice(),
        ),
    };
}

fn optionalBusinessActivityIdEql(
    left: ?model.BusinessActivityId,
    right: ?model.BusinessActivityId,
) bool {
    if (left) |left_id| {
        if (right) |right_id| return left_id.eql(&right_id);
        return false;
    }
    return right == null;
}

fn optionalRegistrationFactIdEql(
    left: ?model.RegistrationFactId,
    right: ?model.RegistrationFactId,
) bool {
    if (left) |left_id| {
        if (right) |right_id| return left_id.eql(&right_id);
        return false;
    }
    return right == null;
}

fn controlSeed(control_id: []const u8) ?occurrences.ControlSeed {
    for (occurrences.control_seeds) |seed| {
        if (std.mem.eql(u8, seed.id, control_id)) return seed;
    }
    return null;
}

fn occurrenceText(slot: *const Slot) Error![]const u8 {
    if (slot.kind == .radio) return error.KindMismatch;
    if (slot.sensitivity == .credential_forbidden) {
        return switch (slot.value) {
            .text => |*stored| if (stored.asSlice().len == 0)
                ""
            else
                error.SensitiveValueForbidden,
            .missing, .checked => error.SensitiveValueForbidden,
        };
    }
    return textFromValue(&slot.value);
}

fn textFromValue(value: *const Value) Error![]const u8 {
    return switch (value.*) {
        .missing => error.MissingValue,
        .checked => error.KindMismatch,
        .text => |*stored| stored.asSlice(),
    };
}

fn checkedFromValue(value: *const Value) Error!bool {
    return switch (value.*) {
        .missing => error.MissingValue,
        .text => error.KindMismatch,
        .checked => |stored| stored,
    };
}

fn parseYear(raw: []const u8) Error!i32 {
    if (raw.len != 4) return error.InvalidYear;
    for (raw) |byte| {
        if (!std.ascii.isDigit(byte)) return error.InvalidYear;
    }
    return std.fmt.parseInt(i32, raw, 10) catch error.InvalidYear;
}

fn moneyControlId(
    buffer: *[32]u8,
    item: u8,
    suffix: u8,
) []const u8 {
    return std.fmt.bufPrint(
        buffer,
        "frm1701q:txt{d}{c}",
        .{ item, suffix },
    ) catch unreachable;
}

/// Parses the canonical `formatCurrency` representation. In particular,
/// `1234.56`, `1,23.45`, `.50`, `1.5`, and `$1.00` are rejected.
pub fn parseMoney(raw: []const u8) Error!calculations.Money {
    if (raw.len < 4) return error.InvalidMoney;
    var start: usize = 0;
    var negative = false;
    if (raw[0] == '-') {
        negative = true;
        start = 1;
    } else if (raw[0] == '+') {
        return error.InvalidMoney;
    }
    if (start + 4 > raw.len) return error.InvalidMoney;

    const dot = raw.len - 3;
    if (raw[dot] != '.' or
        !std.ascii.isDigit(raw[dot + 1]) or
        !std.ascii.isDigit(raw[dot + 2]))
    {
        return error.InvalidMoney;
    }
    const integer = raw[start..dot];
    if (integer.len == 0) return error.InvalidMoney;

    const has_comma = std.mem.indexOfScalar(u8, integer, ',') != null;
    var groups = std.mem.splitScalar(u8, integer, ',');
    var first = true;
    var digit_count: usize = 0;
    var pesos: i128 = 0;
    while (groups.next()) |group| {
        if (group.len == 0) return error.InvalidMoney;
        if (first) {
            if (group.len > 3) return error.InvalidMoney;
            if (group.len > 1 and group[0] == '0') {
                return error.InvalidMoney;
            }
        } else if (group.len != 3) {
            return error.InvalidMoney;
        }
        for (group) |byte| {
            if (!std.ascii.isDigit(byte)) return error.InvalidMoney;
            pesos = std.math.mul(i128, pesos, 10) catch
                return error.MoneyOverflow;
            pesos = std.math.add(i128, pesos, byte - '0') catch
                return error.MoneyOverflow;
            digit_count += 1;
        }
        first = false;
    }
    if (!has_comma and integer.len > 3) return error.InvalidMoney;
    if (has_comma and integer.len <= 3) return error.InvalidMoney;
    if (digit_count == 0 or digit_count > 15) return error.InvalidMoney;

    const cents: i128 =
        @as(i128, raw[dot + 1] - '0') * 10 +
        @as(i128, raw[dot + 2] - '0');
    var total = std.math.mul(i128, pesos, 100) catch
        return error.MoneyOverflow;
    total = std.math.add(i128, total, cents) catch
        return error.MoneyOverflow;
    if (negative) {
        if (total == 0) return error.InvalidMoney;
        total = -total;
    }
    if (total < std.math.minInt(i64) or
        total > std.math.maxInt(i64))
    {
        return error.MoneyOverflow;
    }
    return calculations.Money.fromCentavos(@intCast(total));
}

pub fn formatMoney(money: calculations.Money) Error!StoredText {
    const wide: i128 = money.centavos;
    const absolute: i128 = if (wide < 0) -wide else wide;
    const pesos = @divTrunc(absolute, 100);
    const cents = @mod(absolute, 100);

    var digits_buffer: [40]u8 = undefined;
    defer sensitive_memory.wipeValue([40]u8, &digits_buffer);
    const digits = std.fmt.bufPrint(
        &digits_buffer,
        "{d}",
        .{pesos},
    ) catch unreachable;
    var output: [64]u8 = undefined;
    defer sensitive_memory.wipeValue([64]u8, &output);
    var output_len: usize = 0;
    if (wide < 0) {
        output[output_len] = '-';
        output_len += 1;
    }
    for (digits, 0..) |byte, index| {
        if (index != 0 and (digits.len - index) % 3 == 0) {
            output[output_len] = ',';
            output_len += 1;
        }
        output[output_len] = byte;
        output_len += 1;
    }
    output[output_len] = '.';
    output[output_len + 1] = @intCast(@divTrunc(cents, 10) + '0');
    output[output_len + 2] = @intCast(@mod(cents, 10) + '0');
    output_len += 3;
    return StoredText.init(output[0..output_len]);
}

fn rdoSelectedIndex(raw: []const u8) Error!usize {
    if (std.mem.eql(u8, raw, "000")) return 0;
    for (rdo_options.values, 0..) |candidate, index| {
        if (std.mem.eql(u8, raw, candidate)) return index + 1;
    }
    return error.InvalidRdoSelection;
}

fn calculationInputsEqual(
    left: *const calculations.FormState,
    right: *const calculations.FormState,
) bool {
    return left.year == right.year and
        std.meta.eql(left.taxpayer.selections, right.taxpayer.selections) and
        std.meta.eql(left.taxpayer.inputs, right.taxpayer.inputs) and
        std.meta.eql(left.spouse.selections, right.spouse.selections) and
        std.meta.eql(left.spouse.inputs, right.spouse.inputs);
}

pub fn digestProfileSnapshot(
    snapshot: *const projection.Snapshot,
) identity.Sha256Digest {
    var hash = std.crypto.hash.sha2.Sha256.init(.{});
    defer sensitive_memory.wipeValue(
        std.crypto.hash.sha2.Sha256,
        &hash,
    );
    hash.update("ebirforms.1701q-2018.profile-snapshot.v1");
    hashLengthPrefixed(&hash, snapshot.form.code.asSlice());
    hashLengthPrefixed(&hash, snapshot.form.revision.asSlice());
    hashDate(&hash, snapshot.effective_on);
    hashU32(&hash, snapshot.len);
    for (snapshot.slice()) |*entry| {
        hash.update(&.{
            @as(u8, @intCast(@intFromEnum(entry.role))),
        });
        hashLengthPrefixed(&hash, entry.target.asSlice());
        hashProfileValue(&hash, &entry.value);
        hashProvenance(&hash, &entry.provenance);
    }
    return finishDigest(&hash);
}

fn hashProfileValue(
    hash: *std.crypto.hash.sha2.Sha256,
    value: *const field.Value,
) void {
    hash.update(&.{
        @as(u8, @intCast(@intFromEnum(std.meta.activeTag(value.*)))),
    });
    switch (value.*) {
        .tin => |stored| hashLengthPrefixed(hash, stored.asDigits()),
        .rdo_code => |stored| hashLengthPrefixed(hash, stored.asSlice()),
        .taxpayer_name => |stored| {
            hashLengthPrefixed(hash, stored.asSlice());
        },
        .registered_name => |stored| {
            hashLengthPrefixed(hash, stored.asSlice());
        },
        .registered_address => |stored| {
            hashLengthPrefixed(hash, stored.asSlice());
        },
        .zip_code => |stored| hashLengthPrefixed(hash, stored.asSlice()),
        .contact_number => |stored| {
            hashLengthPrefixed(hash, stored.asSlice());
        },
        .email_address => |stored| {
            hashLengthPrefixed(hash, stored.asSlice());
        },
        .date_of_birth => |stored| hashDate(hash, stored),
        .citizenship => |stored| {
            hashLengthPrefixed(hash, stored.asSlice());
        },
        .foreign_tax_number => |stored| {
            hashLengthPrefixed(hash, stored.asSlice());
        },
        .line_of_business => |stored| {
            hashLengthPrefixed(hash, stored.asSlice());
        },
        .atc => |stored| hashLengthPrefixed(hash, stored.asSlice()),
        .tax_type => |stored| hashLengthPrefixed(hash, stored.asSlice()),
        .government_withholding_agent => |stored| {
            hash.update(&.{
                @as(u8, @intCast(@intFromEnum(stored))),
            });
        },
        .special_rate_basis => |stored| {
            hashLengthPrefixed(hash, stored.asSlice());
        },
    }
}

fn hashProvenance(
    hash: *std.crypto.hash.sha2.Sha256,
    provenance: *const projection.Provenance,
) void {
    hashLengthPrefixed(hash, provenance.profile_id.asSlice());
    hashLengthPrefixed(hash, provenance.revision_id.asSlice());
    hashU32(hash, provenance.revision_sequence);
    switch (provenance.revision_source) {
        .manual_entry => hash.update(&.{0}),
        .imported => |reference| {
            hash.update(&.{1});
            hashLengthPrefixed(hash, reference.asSlice());
        },
        .migrated => |reference| {
            hash.update(&.{2});
            hashLengthPrefixed(hash, reference.asSlice());
        },
    }
    if (provenance.business_activity_id) |activity_id| {
        hash.update(&.{1});
        hashLengthPrefixed(hash, activity_id.asSlice());
    } else {
        hash.update(&.{0});
    }
    if (provenance.registration_fact_id) |fact_id| {
        hash.update(&.{1});
        hashLengthPrefixed(hash, fact_id.asSlice());
    } else {
        hash.update(&.{0});
    }
}

fn hashValue(
    hash: *std.crypto.hash.sha2.Sha256,
    value: *const Value,
) void {
    switch (value.*) {
        .missing => hash.update(&.{0}),
        .text => |*stored| {
            hash.update(&.{1});
            hashLengthPrefixed(hash, stored.asSlice());
        },
        .checked => |stored| hash.update(&.{
            2,
            @as(u8, @intFromBool(stored)),
        }),
    }
}

fn hashDate(
    hash: *std.crypto.hash.sha2.Sha256,
    date: model.Date,
) void {
    hashU16(hash, date.year);
    hash.update(&.{ date.month, date.day });
}

fn hashLengthPrefixed(
    hash: *std.crypto.hash.sha2.Sha256,
    value: []const u8,
) void {
    std.debug.assert(value.len <= std.math.maxInt(u32));
    hashU32(hash, @intCast(value.len));
    hash.update(value);
}

fn hashU16(hash: *std.crypto.hash.sha2.Sha256, value: u16) void {
    hash.update(&.{
        @intCast(value >> 8),
        @intCast(value & 0xff),
    });
}

fn hashU32(hash: *std.crypto.hash.sha2.Sha256, value: u32) void {
    hash.update(&.{
        @intCast(value >> 24),
        @intCast((value >> 16) & 0xff),
        @intCast((value >> 8) & 0xff),
        @intCast(value & 0xff),
    });
}

fn finishDigest(
    hash: *std.crypto.hash.sha2.Sha256,
) identity.Sha256Digest {
    var result: identity.Sha256Digest = .{ .bytes = undefined };
    hash.final(&result.bytes);
    return result;
}

fn syntheticProfileControlSnapshot(
    email_raw: []const u8,
) !profile_mapping.ControlSnapshot {
    return syntheticProfileControlSnapshotWithName(
        email_raw,
        "SYNTHETIC TAXPAYER",
    );
}

fn syntheticProfileControlSnapshotWithName(
    email_raw: []const u8,
    taxpayer_name: []const u8,
) !profile_mapping.ControlSnapshot {
    const effective_on = try model.Date.init(2025, 3, 31);
    var snapshot = projection.Snapshot.init(form.revision, effective_on);
    const provenance: projection.Provenance = .{
        .profile_id = try model.ProfileId.parse("synthetic-profile"),
        .revision_id = try model.RevisionId.parse("synthetic-revision-1"),
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
        .value = .{ .rdo_code = try field.RdoCode.parse("019") },
        .provenance = provenance,
    });
    try snapshot.append(.{
        .role = .filer,
        .target = form.filer_requirements[2].target,
        .value = .{
            .taxpayer_name = try field.TaxpayerName.parse(
                taxpayer_name,
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
        .value = .{ .zip_code = try field.ZipCode.parse("1000") },
        .provenance = provenance,
    });
    try snapshot.append(.{
        .role = .filer,
        .target = form.filer_requirements[6].target,
        .value = .{
            .email_address = try field.EmailAddress.parse(email_raw),
        },
        .provenance = provenance,
    });

    return switch (profile_mapping.mapProfileSnapshot(snapshot)) {
        .accepted => |accepted| accepted,
        .blocked => error.UnexpectedProfileMappingBlock,
    };
}

fn populateNonProfileControls(state: *State) !void {
    for (occurrences.control_seeds) |seed| {
        const origin = try state.originFor(seed.id);
        switch (origin) {
            .profile, .derived, .preparer => {},
            .transaction => switch (seed.kind) {
                .radio => try state.setChecked(.transaction, seed.id, false),
                .text, .select_one => try state.setText(
                    .transaction,
                    seed.id,
                    "0.00",
                ),
            },
            .filing_context => switch (seed.kind) {
                .radio => try state.setChecked(
                    .filing_context,
                    seed.id,
                    false,
                ),
                .text, .select_one => try state.setText(
                    .filing_context,
                    seed.id,
                    if (std.mem.eql(
                        u8,
                        seed.id,
                        "frm1701q:txtYear",
                    ))
                        "2025"
                    else
                        "0",
                ),
            },
            .external_evidence => try state.setText(
                .external_evidence,
                seed.id,
                "",
            ),
            .system => try state.setText(
                .system,
                seed.id,
                if (std.mem.eql(
                    u8,
                    seed.id,
                    "frm1701q:txtCurrentPage",
                ))
                    "1"
                else
                    "",
            ),
            .unreviewed => unreachable,
        }
    }
}

fn completeSyntheticState(email_raw: []const u8) !State {
    var state = try State.init();
    const profile = try syntheticProfileControlSnapshot(email_raw);
    try state.applyProfile(&profile);
    try populateNonProfileControls(&state);
    _ = try state.recalculateAndApply();
    return state;
}

fn expectAllZero(bytes: []const u8) !void {
    for (bytes) |byte| {
        try std.testing.expectEqual(@as(u8, 0), byte);
    }
}

test "StoredText has deterministic tails and explicit erasure" {
    var stored = try StoredText.init("SENSITIVE");
    try std.testing.expectEqualStrings("SENSITIVE", stored.asSlice());
    try expectAllZero(stored.bytes[stored.len..]);

    stored.deinit();
    try expectAllZero(std.mem.asBytes(&stored));

    var money = try formatMoney(.{ .centavos = 123_456 });
    try std.testing.expectEqualStrings("1,234.56", money.asSlice());
    try expectAllZero(money.bytes[money.len..]);
    money.deinit();
    try expectAllZero(std.mem.asBytes(&money));
}

test "slot replacement erases displaced text and provenance" {
    var state = try State.init();
    const text_id = "frm1701q:txtLOB";
    try state.setText(
        .external_evidence,
        text_id,
        "OLD-SENSITIVE-TEXT",
    );
    const text_index = state.findIndex(text_id).?;
    state.slots[text_index].profile_provenance = .{
        .profile_id = try model.ProfileId.parse(
            "old-sensitive-profile-id",
        ),
        .revision_id = try model.RevisionId.parse(
            "old-sensitive-revision-id",
        ),
        .revision_sequence = 1,
        .revision_source = .manual_entry,
    };

    try state.setText(.external_evidence, text_id, "NEW");
    try std.testing.expect(std.mem.indexOf(
        u8,
        std.mem.asBytes(&state.slots[text_index].value),
        "OLD-SENSITIVE-TEXT",
    ) == null);
    try std.testing.expect(
        state.slots[text_index].profile_provenance == null,
    );
    try expectAllZero(std.mem.asBytes(
        &state.slots[text_index].profile_provenance,
    ));
    const replacement = switch (state.slots[text_index].value) {
        .text => |*value| value,
        else => return error.TestUnexpectedResult,
    };
    try expectAllZero(replacement.bytes[replacement.len..]);

    var moved_text = try StoredText.init("MOVED-SENSITIVE-TEXT");
    var moved_provenance: ?projection.Provenance = .{
        .profile_id = try model.ProfileId.parse(
            "moved-sensitive-profile-id",
        ),
        .revision_id = try model.RevisionId.parse(
            "moved-sensitive-revision-id",
        ),
        .revision_sequence = 2,
        .revision_source = .manual_entry,
    };
    state.slots[text_index].replaceText(
        &moved_text,
        &moved_provenance,
    );
    try expectAllZero(std.mem.asBytes(&moved_text));
    try expectAllZero(std.mem.asBytes(&moved_provenance));
    try std.testing.expectEqualStrings(
        "MOVED-SENSITIVE-TEXT",
        try state.text(.external_evidence, text_id),
    );

    try state.unset(.external_evidence, text_id);
    try std.testing.expect(std.mem.indexOf(
        u8,
        std.mem.asBytes(&state.slots[text_index].value),
        "MOVED-SENSITIVE-TEXT",
    ) == null);
    try expectAllZero(std.mem.asBytes(
        &state.slots[text_index].value,
    ));

    const radio_id = "frm1701q:DateQuarter_1";
    const radio_index = state.findIndex(radio_id).?;
    state.slots[radio_index].value = .{
        .text = try StoredText.init("DISPLACED-RADIO-TEXT"),
    };
    try state.setChecked(.filing_context, radio_id, true);
    try std.testing.expect(std.mem.indexOf(
        u8,
        std.mem.asBytes(&state.slots[radio_index].value),
        "DISPLACED-RADIO-TEXT",
    ) == null);

    state.deinit();
    try expectAllZero(std.mem.asBytes(&state));
}

test "profile replacement erases displaced inline values" {
    var state = try State.init();
    var first = try syntheticProfileControlSnapshot(
        "old-sensitive-email@example.test",
    );
    defer sensitive_memory.wipeValue(
        profile_mapping.ControlSnapshot,
        &first,
    );
    try state.applyProfile(&first);
    const email_index = state.findIndex("txtEmail").?;
    try std.testing.expect(std.mem.indexOf(
        u8,
        std.mem.asBytes(&state.slots[email_index].value),
        "old-sensitive-email@example.test",
    ) != null);

    var second = try syntheticProfileControlSnapshot("new@example.test");
    defer sensitive_memory.wipeValue(
        profile_mapping.ControlSnapshot,
        &second,
    );
    try state.applyProfile(&second);
    try std.testing.expect(std.mem.indexOf(
        u8,
        std.mem.asBytes(&state.slots[email_index].value),
        "old-sensitive-email@example.test",
    ) == null);
    try std.testing.expectEqualStrings(
        "new@example.test",
        try state.text(.profile, "txtEmail"),
    );
    state.deinit();
}

test "calculated replacement erases displaced derived text" {
    var state = try completeSyntheticState(
        "derived-erasure@example.test",
    );
    defer state.deinit();
    var input = try state.toCalculationState();
    defer sensitive_memory.wipeValue(
        calculations.FormState,
        &input,
    );
    var calculated = try calculations.recalculate(input);
    defer sensitive_memory.wipeValue(
        calculations.FormState,
        &calculated,
    );

    const derived_index = state.findIndex("frm1701q:txt38A").?;
    state.slots[derived_index].value = .{
        .text = try StoredText.init("OLD-DERIVED-SENSITIVE-TEXT"),
    };
    try state.applyCalculated(calculated);
    try std.testing.expect(std.mem.indexOf(
        u8,
        std.mem.asBytes(&state.slots[derived_index].value),
        "OLD-DERIVED-SENSITIVE-TEXT",
    ) == null);
}

test "fallible setters and snapshot checks leave prior bytes intact" {
    var state = try State.init();
    defer state.deinit();
    try state.setText(
        .external_evidence,
        "frm1701q:txtLOB",
        "STABLE-SENSITIVE-VALUE",
    );

    var before = state;
    defer before.deinit();
    const too_long = [_]u8{'X'} ** (max_state_text_bytes + 1);
    try std.testing.expectError(
        error.ValueTooLong,
        state.setText(
            .external_evidence,
            "frm1701q:txtLOB",
            &too_long,
        ),
    );
    try std.testing.expectEqualSlices(
        u8,
        std.mem.asBytes(&before),
        std.mem.asBytes(&state),
    );

    var calculated_state = try completeSyntheticState(
        "atomic@example.test",
    );
    defer calculated_state.deinit();
    const calculated = try calculated_state.toCalculationState();
    try calculated_state.setText(
        .transaction,
        "frm1701q:txt36A",
        "1.00",
    );
    var before_mismatch = calculated_state;
    defer before_mismatch.deinit();
    try std.testing.expectError(
        error.CalculationSnapshotMismatch,
        calculated_state.applyCalculated(calculated),
    );
    try std.testing.expectEqualSlices(
        u8,
        std.mem.asBytes(&before_mismatch),
        std.mem.asBytes(&calculated_state),
    );

    var profile_state = try State.init();
    defer profile_state.deinit();
    var valid_profile = try syntheticProfileControlSnapshot(
        "stable-profile@example.test",
    );
    defer sensitive_memory.wipeValue(
        profile_mapping.ControlSnapshot,
        &valid_profile,
    );
    try profile_state.applyProfile(&valid_profile);
    var before_profile_error = profile_state;
    defer before_profile_error.deinit();
    var forged_profile = valid_profile;
    defer sensitive_memory.wipeValue(
        profile_mapping.ControlSnapshot,
        &forged_profile,
    );
    forged_profile.entries[0].control_id = "forged-control";
    try std.testing.expectError(
        error.InvalidProfileSnapshot,
        profile_state.applyProfile(&forged_profile),
    );
    try std.testing.expectEqualSlices(
        u8,
        std.mem.asBytes(&before_profile_error),
        std.mem.asBytes(&profile_state),
    );
}

test "all 173 controls have one reviewed origin and exact counts" {
    const counts = try validateControlClassification();
    try std.testing.expectEqual(@as(usize, 173), control_count);
    try std.testing.expectEqual(expected_classification_counts, counts);
    for (occurrences.control_seeds) |seed| {
        try std.testing.expectEqual(
            @as(u8, 1),
            classificationMembershipCount(seed.id),
        );
        try std.testing.expect(classifyControl(seed.id) != null);
    }
}

test "typed setters and getters reject cross-origin and wrong-kind access" {
    var state = try State.init();
    try std.testing.expectError(
        error.OriginMismatch,
        state.setText(
            .transaction,
            "frm1701q:txtYear",
            "2025",
        ),
    );
    try std.testing.expectError(
        error.KindMismatch,
        state.setText(
            .filing_context,
            "frm1701q:DateQuarter_1",
            "true",
        ),
    );
    try std.testing.expectError(
        error.ReservedOrigin,
        state.setText(.profile, "frm1701q:txtTIN1", "123"),
    );
    try std.testing.expectError(
        error.SensitiveValueForbidden,
        state.setText(.preparer, "ebirOnlineSecret", "not-stored"),
    );
    try std.testing.expectError(
        error.MissingValue,
        state.text(.filing_context, "frm1701q:txtYear"),
    );
    try std.testing.expectError(
        error.NonAsciiValue,
        state.setText(
            .filing_context,
            "frm1701q:txtYear",
            "\xc3\xa9",
        ),
    );
    try std.testing.expectError(
        error.ControlCharacter,
        state.setText(
            .filing_context,
            "frm1701q:txtYear",
            "20\n25",
        ),
    );

    try state.setText(.filing_context, "frm1701q:txtYear", "2025");
    try state.setChecked(
        .filing_context,
        "frm1701q:DateQuarter_1",
        true,
    );
    try std.testing.expectEqualStrings(
        "2025",
        try state.text(.filing_context, "frm1701q:txtYear"),
    );
    try std.testing.expect(
        try state.checked(.filing_context, "frm1701q:DateQuarter_1"),
    );
}

test "profile application is exact and cannot overwrite elections" {
    var state = try State.init();
    try state.setChecked(
        .transaction,
        "frm1701q:optTaxRate_1",
        true,
    );
    const first = try syntheticProfileControlSnapshot(
        "first@example.test",
    );
    try state.applyProfile(&first);
    try std.testing.expect(
        try state.checked(.transaction, "frm1701q:optTaxRate_1"),
    );
    try std.testing.expectEqualStrings(
        "123",
        try state.text(.profile, "frm1701q:txtTIN1"),
    );
    try std.testing.expectEqualStrings(
        "000",
        try state.text(.profile, "frm1701q:txtSpouseRDOCode"),
    );
    try std.testing.expect(
        (try state.profileProvenance("frm1701q:txtTIN1")) != null,
    );
    try std.testing.expect(
        (try state.profileProvenance("frm1701q:txtBirthMonth")) == null,
    );

    const first_digest = state.applied_profile_digest.?;
    const transaction_before = state.transactionDigest();
    const second = try syntheticProfileControlSnapshot(
        "second@example.test",
    );
    try state.applyProfile(&second);
    try std.testing.expect(
        try state.checked(.transaction, "frm1701q:optTaxRate_1"),
    );
    try std.testing.expect(
        !first_digest.eql(&state.applied_profile_digest.?),
    );
    const transaction_after = state.transactionDigest();
    try std.testing.expect(transaction_before.eql(&transaction_after));

    var forged = second;
    forged.entries[0].control_id = "forged-control";
    try std.testing.expectError(
        error.InvalidProfileSnapshot,
        state.applyProfile(&forged),
    );
}

test "money bridge accepts only canonical formatCurrency output" {
    try std.testing.expectEqual(
        @as(i64, 123_456),
        (try parseMoney("1,234.56")).centavos,
    );
    try std.testing.expectEqual(
        @as(i64, -50),
        (try parseMoney("-0.50")).centavos,
    );
    try std.testing.expectEqualStrings(
        "1,234.56",
        (try formatMoney(.{ .centavos = 123_456 })).asSlice(),
    );
    try std.testing.expectEqualStrings(
        "-0.50",
        (try formatMoney(.{ .centavos = -50 })).asSlice(),
    );
    const invalid = [_][]const u8{
        "",
        "0",
        ".50",
        "1.5",
        "1234.56",
        "1,23.45",
        "01.00",
        "+1.00",
        "-0.00",
        "$1.00",
    };
    for (invalid) |raw| {
        try std.testing.expectError(error.InvalidMoney, parseMoney(raw));
    }
}

test "calculation conversion and derived application are snapshot-bound" {
    var state = try State.init();
    const profile = try syntheticProfileControlSnapshot(
        "calc@example.test",
    );
    try state.applyProfile(&profile);
    try populateNonProfileControls(&state);
    try state.setText(
        .transaction,
        "frm1701q:txt36A",
        "1,234.56",
    );
    try state.setText(
        .transaction,
        "frm1701q:txt37A",
        "234.56",
    );
    try state.setChecked(
        .transaction,
        "frm1701q:optTaxRate_1",
        true,
    );

    const input = try state.toCalculationState();
    try std.testing.expectEqual(@as(i32, 2025), input.year);
    try std.testing.expectEqual(
        @as(i64, 123_456),
        input.taxpayer.inputs.txt36.centavos,
    );
    try std.testing.expect(input.taxpayer.selections.graduated_rate_checked);

    const calculated = try state.recalculateAndApply();
    const expected_38 = try formatMoney(calculated.taxpayer.derived.txt38);
    try std.testing.expectEqualStrings(
        expected_38.asSlice(),
        try state.text(.derived, "frm1701q:txt38A"),
    );
    try state.setText(
        .transaction,
        "frm1701q:txt36A",
        "2,000.00",
    );
    try std.testing.expectError(
        error.CalculationSnapshotMismatch,
        state.applyCalculated(calculated),
    );

    const missing = try State.init();
    try std.testing.expectError(
        error.MissingValue,
        missing.toCalculationState(),
    );
}

test "calculation capitalizes rendered profile bytes without changing profile provenance or email" {
    var state = try State.init();
    const profile = try syntheticProfileControlSnapshotWithName(
        "Mixed.Email@example.test",
        "Mixed Case Taxpayer",
    );
    try state.applyProfile(&profile);
    try populateNonProfileControls(&state);
    try state.setText(
        .external_evidence,
        "frm1701q:txtLOB",
        "small shop",
    );

    const profile_digest_before = state.applied_profile_digest.?;
    const provenance_before = try state.profileProvenance(
        "frm1701q:txtTaxpayerName",
    );
    _ = try state.recalculateAndApply();

    try std.testing.expectEqualStrings(
        "MIXED CASE TAXPAYER",
        try state.text(.profile, "frm1701q:txtTaxpayerName"),
    );
    try std.testing.expectEqualStrings(
        "SMALL SHOP",
        try state.text(.external_evidence, "frm1701q:txtLOB"),
    );
    try std.testing.expectEqualStrings(
        "Mixed.Email@example.test",
        try state.text(.profile, "txtEmail"),
    );
    try std.testing.expect(profile_digest_before.eql(
        &state.applied_profile_digest.?,
    ));
    const provenance_after = try state.profileProvenance(
        "frm1701q:txtTaxpayerName",
    );
    try std.testing.expect(std.meta.eql(
        provenance_before,
        provenance_after,
    ));
    try std.testing.expect(!state.applyLegacyCapital());
}

test "validation conversion preserves exact control group order" {
    var state = try completeSyntheticState("validation@example.test");
    try state.setChecked(
        .filing_context,
        "frm1701q:DateQuarter_2",
        true,
    );
    try state.setChecked(.transaction, "frm1701q:optType_3", true);
    try state.setChecked(.transaction, "frm1701q:optATC_2", true);
    try state.setChecked(
        .transaction,
        "frm1701q:optTaxRate_1",
        true,
    );
    try state.setChecked(
        .transaction,
        "frm1701q:optMethodOfDeduction:_2",
        true,
    );
    const input = try state.toValidationInput(2026, .valid);
    try std.testing.expectEqualStrings("2025", input.year);
    try std.testing.expectEqual(
        [3]bool{ false, true, false },
        input.quarter_checked,
    );
    try std.testing.expectEqualStrings("019", input.taxpayer_rdo_value);
    try std.testing.expect(input.taxpayer_rdo_selected_index > 0);
    try std.testing.expectEqual(@as(usize, 0), input.spouse_rdo_selected_index);
    try std.testing.expect(input.taxpayer_type_checked[2]);
    try std.testing.expect(input.taxpayer_atc_checked[1]);
    try std.testing.expect(input.taxpayer_tax_rate_checked[0]);
    try std.testing.expect(input.taxpayer_deduction_method_checked[1]);
    try std.testing.expectEqual(
        validation.TinChecksumStatus.valid,
        input.spouse_tin_checksum,
    );

    const missing = try State.init();
    try std.testing.expectError(
        error.MissingValue,
        missing.toValidationInput(2026, .not_evaluated),
    );
}

test "codec and occurrence bridges preserve all source positions" {
    var state = try completeSyntheticState("codec@example.test");
    const controls = try state.toCodecControls();
    try std.testing.expectEqual(@as(usize, 173), controls.len);
    for (controls, occurrences.control_seeds) |input, seed| {
        try std.testing.expectEqualStrings(seed.id, input.id);
        switch (seed.kind) {
            .radio => try std.testing.expect(input.value == .checked),
            .text, .select_one => {
                try std.testing.expect(input.value == .text);
            },
        }
    }

    const editable = try state.editableOccurrenceValues();
    const final_copy = try state.finalOccurrenceValues();
    try std.testing.expectEqual(@as(usize, 172), editable.len);
    try std.testing.expectEqual(@as(usize, 173), final_copy.len);
    var found_joined_address = false;
    for (editable, occurrences.editable_occurrence_items) |actual, expected| {
        try std.testing.expectEqual(expected.ordinal, actual.metadata.ordinal);
        try std.testing.expectEqual(
            expected.same_key_occurrence,
            actual.metadata.same_key_occurrence,
        );
        try std.testing.expectEqualStrings(
            expected.serialized_key,
            actual.metadata.serialized_key,
        );
        if (std.mem.eql(
            u8,
            actual.metadata.serialized_key,
            "frm1701q:txtAddress",
        )) {
            try std.testing.expect(actual.source == .concatenated_text);
            found_joined_address = true;
        }
    }
    try std.testing.expect(found_joined_address);
    for (final_copy, occurrences.final_copy_occurrence_items) |actual, expected| {
        try std.testing.expectEqual(expected.ordinal, actual.metadata.ordinal);
        try std.testing.expectEqualStrings(
            expected.serialized_key,
            actual.metadata.serialized_key,
        );
    }

    try state.unset(.transaction, "frm1701q:txtAmount32");
    try std.testing.expectError(
        error.MissingValue,
        state.toCodecControls(),
    );
}

test "digests separate package profile and transaction without credentials" {
    var first = try completeSyntheticState("one@example.test");
    var second = try completeSyntheticState("two@example.test");
    const first_bundle = try first.digestBundle();
    const second_bundle = try second.digestBundle();
    const expected_package = evidence.package_key.canonicalDigest();
    try std.testing.expect(first_bundle.package.eql(&expected_package));
    try std.testing.expect(
        !first_bundle.profile_snapshot.eql(&second_bundle.profile_snapshot),
    );
    try std.testing.expect(
        first_bundle.transaction_state.eql(
            &second_bundle.transaction_state,
        ),
    );

    try second.setChecked(
        .filing_context,
        "frm1701q:AmendedRtn_1",
        true,
    );
    const changed_transaction = second.transactionDigest();
    try std.testing.expect(
        !first_bundle.transaction_state.eql(&changed_transaction),
    );

    const secret_index = first.findIndex("ebirOnlineSecret").?;
    const before_corruption = first.transactionDigest();
    first.slots[secret_index].value = .{
        .text = try StoredText.init("synthetic-secret"),
    };
    const after_corruption = first.transactionDigest();
    try std.testing.expect(before_corruption.eql(&after_corruption));
    try std.testing.expectError(
        error.SensitiveValueForbidden,
        first.toCodecControls(),
    );

    const no_profile = try State.init();
    try std.testing.expectError(
        error.ProfileNotApplied,
        no_profile.digestBundle(),
    );
}

test "state writes enforce exact declaration maxlengths without truncation" {
    var state = try State.init();
    try state.setText(
        .filing_context,
        "frm1701q:txtSheets",
        "12",
    );
    try std.testing.expectEqualStrings(
        "12",
        try state.text(.filing_context, "frm1701q:txtSheets"),
    );
    try std.testing.expectError(
        error.ValueTooLong,
        state.setText(
            .filing_context,
            "frm1701q:txtSheets",
            "123",
        ),
    );
    // A rejected replacement is atomic: the prior valid value survives.
    try std.testing.expectEqualStrings(
        "12",
        try state.text(.filing_context, "frm1701q:txtSheets"),
    );

    const exactly_fifty = "12345678901234567890123456789012345678901234567890";
    try state.setText(
        .external_evidence,
        "frm1701q:txtLOB",
        exactly_fifty,
    );
    try std.testing.expectError(
        error.ValueTooLong,
        state.setText(
            .external_evidence,
            "frm1701q:txtLOB",
            exactly_fifty ++ "X",
        ),
    );
}
