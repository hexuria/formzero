//! Profile-subset adapter for BIR Form 1701Q January 2018 (ENCS).
//!
//! This module bridges the reusable, immutable profile projection to exact
//! legacy controls. It does not own storage, UI, calculation, validation, or
//! serialization. Every emitted control value is copied by value and carries
//! the profile/revision provenance copied from `projection.Snapshot`.
//!
//! Grounding:
//! - semantic requirements and role constraints:
//!   `src/forms/form_1701q.zig`;
//! - exact source controls and live `frmMain.elements` order:
//!   `occurrences.zig`;
//! - exact HTA source:
//!   `forms/BIR-Form1701Qv2018.hta`, SHA-256
//!   `5f164dde6154b96f28e23656ed2ef29406010ee3f94333e88ea6eb107fe589a0`;
//! - address split: HTA lines 4761-4769 (100 code units, no separator);
//! - filer/page-2 name and TIN fan-out: HTA lines 4735-4753;
//! - RDO selection: HTA lines 4755-4756 and exact `rdo_options.zig`.
//!
//! The qualified byte layer is ASCII-only. Rejecting non-ASCII here makes the
//! byte/code-unit address split deterministic and avoids inventing an ANSI
//! code-page conversion. Values exceeding an exact legacy `maxlength` are
//! rejected, never truncated.

const std = @import("std");
const domain_date = @import("../../../domain/date.zig");
const ids = @import("../../../forms/id.zig");
const spec = @import("../../../forms/spec.zig");
const compose = @import("../../../forms/compose.zig");
const form = @import("../../../forms/form_1701q.zig");
const field = @import("../../../tax_profile/field.zig");
const model = @import("../../../tax_profile/model.zig");
const projection = @import("../../../tax_profile/projection.zig");
const evolution = @import("../../../tax_profile/evolution.zig");
const occurrences = @import("occurrences.zig");
const rdo_options = @import("rdo_options.zig");

pub const evidence_id = "desktop-7.9.6-1701qv2018-hta";
pub const max_control_value_bytes: usize = 100;

pub const Transform = enum {
    identity,
    tin_segment_1,
    tin_segment_2,
    tin_segment_3,
    tin_branch,
    address_line_1,
    address_line_2,
    dob_month,
    dob_day,
    dob_year,
    taxpayer_name_before_comma,
};

pub const Rule = struct {
    role: ids.Role,
    reusable_field: field.ReusableField,
    semantic_target: ids.FieldId,
    control_id: []const u8,
    control_source_line: u32,
    expected_kind: occurrences.ControlKind,
    maximum_length: u8,
    transform: Transform,
    transform_evidence_first_line: u32,
    transform_evidence_last_line: u32,
};

const filer_tin = form.filer_requirements[0];
const filer_rdo = form.filer_requirements[1];
const filer_name = form.filer_requirements[2];
const filer_address = form.filer_requirements[3];
const filer_zip = form.filer_requirements[4];
const filer_dob = form.filer_requirements[5];
const filer_email = form.filer_requirements[6];
const filer_citizenship = form.filer_requirements[7];
const filer_foreign_tax_number = form.filer_requirements[8];

const spouse_tin = form.spouse_requirements[0];
const spouse_rdo = form.spouse_requirements[1];
const spouse_name = form.spouse_requirements[2];
const spouse_citizenship = form.spouse_requirements[3];
const spouse_foreign_tax_number = form.spouse_requirements[4];

/// Exact profile-produced controls in live DOM order. The page-2 controls are
/// intentional fan-out from the same filer semantic values.
pub const profile_control_rules = [_]Rule{
    rule(.filer, filer_tin, "frm1701q:txtTIN1", 370, 3, .tin_segment_1, 4739, 4741),
    rule(.filer, filer_tin, "frm1701q:txtTIN2", 371, 3, .tin_segment_2, 4743, 4745),
    rule(.filer, filer_tin, "frm1701q:txtTIN3", 372, 3, .tin_segment_3, 4747, 4749),
    rule(.filer, filer_tin, "frm1701q:txtBranchCode", 373, 3, .tin_branch, 4751, 4753),
    selectRule(.filer, filer_rdo, "frm1701q:txtRDOCode", 3708, 3, .identity, 4755, 4756),
    rule(.filer, filer_name, "frm1701q:txtTaxpayerName", 482, 50, .identity, 4735, 4736),
    rule(.filer, filer_address, "frm1701q:txtAddress", 511, 100, .address_line_1, 4761, 4769),
    rule(.filer, filer_address, "frm1701q:txtAddress2", 525, 50, .address_line_2, 4761, 4769),
    rule(.filer, filer_zip, "frm1701q:txtZipCode", 539, 4, .identity, 4772, 4773),
    rule(.filer, filer_dob, "frm1701q:txtBirthMonth", 563, 2, .dob_month, 557, 565),
    rule(.filer, filer_dob, "frm1701q:txtBirthDay", 564, 2, .dob_day, 557, 565),
    rule(.filer, filer_dob, "frm1701q:txtBirthYear", 565, 4, .dob_year, 557, 565),
    rule(.filer, filer_email, "txtEmail", 580, 60, .identity, 574, 580),
    rule(.filer, filer_citizenship, "frm1701q:txtCitizenship", 602, 20, .identity, 596, 602),
    rule(.filer, filer_foreign_tax_number, "frm1701q:txtForeignTaxNumber", 616, 20, .identity, 610, 616),

    rule(.spouse, spouse_tin, "frm1701q:txtSpouseTIN1", 734, 3, .tin_segment_1, 728, 737),
    rule(.spouse, spouse_tin, "frm1701q:txtSpouseTIN2", 735, 3, .tin_segment_2, 728, 737),
    rule(.spouse, spouse_tin, "frm1701q:txtSpouseTIN3", 736, 3, .tin_segment_3, 728, 737),
    rule(.spouse, spouse_tin, "frm1701q:txtSpouseBranchCode", 737, 5, .tin_branch, 728, 737),
    selectRule(.spouse, spouse_rdo, "frm1701q:txtSpouseRDOCode", 3709, 3, .identity, 3707, 3719),
    rule(.spouse, spouse_name, "frm1701q:txtSpouseName", 846, 50, .identity, 841, 846),
    rule(.spouse, spouse_citizenship, "frm1701q:txtSpouseCitizenship", 867, 20, .identity, 861, 867),
    rule(.spouse, spouse_foreign_tax_number, "frm1701q:txtSpouseForeignTaxNum", 881, 20, .identity, 875, 881),

    rule(.filer, filer_tin, "frm1701q:txtPg2TIN1", 1220, 3, .tin_segment_1, 4739, 4741),
    rule(.filer, filer_tin, "frm1701q:txtPg2TIN2", 1221, 3, .tin_segment_2, 4743, 4745),
    rule(.filer, filer_tin, "frm1701q:txtPg2TIN3", 1222, 3, .tin_segment_3, 4747, 4749),
    rule(.filer, filer_tin, "frm1701q:txtPg2BranchCode", 1223, 5, .tin_branch, 4751, 4753),
    rule(.filer, filer_name, "frm1701q:txtPg2TaxpayerName", 1226, 50, .taxpayer_name_before_comma, 4735, 4737),
};

fn rule(
    role: ids.Role,
    requirement: spec.Requirement,
    control_id: []const u8,
    source_line: u32,
    maximum_length: u8,
    transform: Transform,
    transform_first_line: u32,
    transform_last_line: u32,
) Rule {
    return .{
        .role = role,
        .reusable_field = requirement.source,
        .semantic_target = requirement.target,
        .control_id = control_id,
        .control_source_line = source_line,
        .expected_kind = .text,
        .maximum_length = maximum_length,
        .transform = transform,
        .transform_evidence_first_line = transform_first_line,
        .transform_evidence_last_line = transform_last_line,
    };
}

fn selectRule(
    role: ids.Role,
    requirement: spec.Requirement,
    control_id: []const u8,
    source_line: u32,
    maximum_length: u8,
    transform: Transform,
    transform_first_line: u32,
    transform_last_line: u32,
) Rule {
    var result = rule(
        role,
        requirement,
        control_id,
        source_line,
        maximum_length,
        transform,
        transform_first_line,
        transform_last_line,
    );
    result.expected_kind = .select_one;
    return result;
}

pub const NonProfileReason = enum {
    filer_type,
    atc,
    foreign_tax_credit_election,
    income_tax_rate_election,
    deduction_method_election,
    spouse_type,
};

pub const NonProfileControl = struct {
    control_id: []const u8,
    source_line: u32,
    reason: NonProfileReason,
};

/// These controls stay transaction-owned. A profile subject, activity, civil
/// status, or relationship never auto-checks them.
pub const transaction_owned_controls = [_]NonProfileControl{
    .{ .control_id = "frm1701q:optType_1", .source_line = 408, .reason = .filer_type },
    .{ .control_id = "frm1701q:optType_2", .source_line = 411, .reason = .filer_type },
    .{ .control_id = "frm1701q:optType_3", .source_line = 414, .reason = .filer_type },
    .{ .control_id = "frm1701q:optType_4", .source_line = 417, .reason = .filer_type },
    .{ .control_id = "frm1701q:optATC_1", .source_line = 441, .reason = .atc },
    .{ .control_id = "frm1701q:optATC_2", .source_line = 444, .reason = .atc },
    .{ .control_id = "frm1701q:optATC_3", .source_line = 447, .reason = .atc },
    .{ .control_id = "frm1701q:optATC_4", .source_line = 454, .reason = .atc },
    .{ .control_id = "frm1701q:optATC_5", .source_line = 457, .reason = .atc },
    .{ .control_id = "frm1701q:optATC_6", .source_line = 460, .reason = .atc },
    .{ .control_id = "frm1701q:optForeignTaxCredits_1", .source_line = 633, .reason = .foreign_tax_credit_election },
    .{ .control_id = "frm1701q:optForeignTaxCredits_2", .source_line = 636, .reason = .foreign_tax_credit_election },
    .{ .control_id = "frm1701q:optTaxRate_1", .source_line = 665, .reason = .income_tax_rate_election },
    .{ .control_id = "frm1701q:optMethodOfDeduction:_1", .source_line = 677, .reason = .deduction_method_election },
    .{ .control_id = "frm1701q:optMethodOfDeduction:_2", .source_line = 681, .reason = .deduction_method_election },
    .{ .control_id = "frm1701q:optTaxRate_2", .source_line = 693, .reason = .income_tax_rate_election },
    .{ .control_id = "frm1701q:optSpouseType_1", .source_line = 772, .reason = .spouse_type },
    .{ .control_id = "frm1701q:optSpouseType_2", .source_line = 775, .reason = .spouse_type },
    .{ .control_id = "frm1701q:optSpouseType_3", .source_line = 778, .reason = .spouse_type },
    .{ .control_id = "frm1701q:optSpouseATC_1", .source_line = 802, .reason = .atc },
    .{ .control_id = "frm1701q:optSpouseATC_2", .source_line = 805, .reason = .atc },
    .{ .control_id = "frm1701q:optSpouseATC_3", .source_line = 808, .reason = .atc },
    .{ .control_id = "frm1701q:optSpouseATC_4", .source_line = 811, .reason = .atc },
    .{ .control_id = "frm1701q:optSpouseATC_5", .source_line = 818, .reason = .atc },
    .{ .control_id = "frm1701q:optSpouseATC_6", .source_line = 821, .reason = .atc },
    .{ .control_id = "frm1701q:optSpouseATC_7", .source_line = 824, .reason = .atc },
    .{ .control_id = "frm1701q:optSpouseForeignTaxCred_1", .source_line = 898, .reason = .foreign_tax_credit_election },
    .{ .control_id = "frm1701q:optSpouseForeignTaxCred_2", .source_line = 901, .reason = .foreign_tax_credit_election },
    .{ .control_id = "frm1701q:optSpouseTaxRate_1", .source_line = 930, .reason = .income_tax_rate_election },
    .{ .control_id = "frm1701q:optSpouseMethod:_1", .source_line = 942, .reason = .deduction_method_election },
    .{ .control_id = "frm1701q:optSpouseMethod:_2", .source_line = 946, .reason = .deduction_method_election },
    .{ .control_id = "frm1701q:optSpouseTaxRate_2", .source_line = 958, .reason = .income_tax_rate_election },
};

pub const EvidenceError = error{
    MissingOccurrenceControl,
    OccurrenceSourceLineMismatch,
    OccurrenceKindMismatch,
    DuplicateProfileControl,
    ProfileControlOrderMismatch,
    NonProfileControlOverlap,
};

pub fn validateEvidence() EvidenceError!void {
    var previous_live_ordinal: u16 = 0;
    for (profile_control_rules, 0..) |mapping, index| {
        const seed = findControlSeed(mapping.control_id) orelse
            return error.MissingOccurrenceControl;
        if (seed.source_line != mapping.control_source_line) {
            return error.OccurrenceSourceLineMismatch;
        }
        if (seed.kind != mapping.expected_kind) {
            return error.OccurrenceKindMismatch;
        }
        const live_ordinal = seed.runtimeFormElementOrdinal();
        if (live_ordinal <= previous_live_ordinal) {
            return error.ProfileControlOrderMismatch;
        }
        previous_live_ordinal = live_ordinal;
        for (profile_control_rules[0..index]) |earlier| {
            if (std.mem.eql(u8, earlier.control_id, mapping.control_id)) {
                return error.DuplicateProfileControl;
            }
        }
    }

    for (transaction_owned_controls) |excluded| {
        const seed = findControlSeed(excluded.control_id) orelse
            return error.MissingOccurrenceControl;
        if (seed.source_line != excluded.source_line) {
            return error.OccurrenceSourceLineMismatch;
        }
        if (seed.kind != .radio) return error.OccurrenceKindMismatch;
        for (profile_control_rules) |mapping| {
            if (std.mem.eql(u8, excluded.control_id, mapping.control_id)) {
                return error.NonProfileControlOverlap;
            }
        }
    }
}

pub const SemanticError = error{
    MissingRequirementMapping,
    MappingWithoutRequirement,
    MappingTargetMismatch,
};

pub fn validateSemantics() SemanticError!void {
    for (form.profile_spec.roles) |role_spec| {
        for (role_spec.requirements) |requirement| {
            var found = false;
            for (profile_control_rules) |mapping| {
                if (mapping.role == role_spec.role and
                    mapping.reusable_field == requirement.source and
                    mapping.semantic_target.eql(&requirement.target))
                {
                    found = true;
                    break;
                }
            }
            if (!found) return error.MissingRequirementMapping;
        }
    }

    for (profile_control_rules) |mapping| {
        const role_spec = form.profile_spec.role(mapping.role) orelse
            return error.MappingWithoutRequirement;
        var found = false;
        for (role_spec.requirements) |requirement| {
            if (requirement.source != mapping.reusable_field) continue;
            if (!requirement.target.eql(&mapping.semantic_target)) {
                return error.MappingTargetMismatch;
            }
            found = true;
            break;
        }
        if (!found) return error.MappingWithoutRequirement;
    }
}

fn findControlSeed(control_id: []const u8) ?occurrences.ControlSeed {
    for (occurrences.control_seeds) |seed| {
        if (std.mem.eql(u8, seed.id, control_id)) return seed;
    }
    return null;
}

pub const ControlValue = struct {
    bytes: [max_control_value_bytes]u8 = undefined,
    len: u8 = 0,

    pub fn asSlice(self: *const ControlValue) []const u8 {
        return self.bytes[0..self.len];
    }

    fn init(raw: []const u8, maximum_length: u8) RenderError!ControlValue {
        try ensureAscii(raw);
        if (raw.len > maximum_length or raw.len > max_control_value_bytes) {
            return error.ValueExceedsLegacyControl;
        }
        var result: ControlValue = .{};
        @memcpy(result.bytes[0..raw.len], raw);
        result.len = @intCast(raw.len);
        return result;
    }
};

pub const TinParts = struct {
    root_segments: [3][3]u8,
    branch: [5]u8 = undefined,
    branch_len: u8 = 0,

    pub fn segment(self: *const TinParts, index: u8) []const u8 {
        std.debug.assert(index < self.root_segments.len);
        return &self.root_segments[index];
    }

    pub fn branchSlice(self: *const TinParts) []const u8 {
        return self.branch[0..self.branch_len];
    }
};

pub const TinMappingError = field.TinError || error{
    UnsupportedRole,
    InvalidTinSegment,
    FilerBranchRequired,
    FilerBranchExceedsLegacyControl,
    SpouseBranchExceedsLegacyControl,
};

pub fn splitTin(
    role: ids.Role,
    value: *const field.Tin,
) TinMappingError!TinParts {
    const branch = value.branch();
    switch (role) {
        .filer => {
            if (branch == null) return error.FilerBranchRequired;
            if (branch.?.len > 5) {
                return error.FilerBranchExceedsLegacyControl;
            }
        },
        .spouse => if (branch) |present| {
            if (present.len > 5) {
                return error.SpouseBranchExceedsLegacyControl;
            }
        },
        else => return error.UnsupportedRole,
    }

    const root = value.root();
    var result: TinParts = .{
        .root_segments = .{
            root[0..3].*,
            root[3..6].*,
            root[6..9].*,
        },
    };
    if (branch) |present| {
        @memcpy(result.branch[0..present.len], present);
        result.branch_len = @intCast(present.len);
    }
    return result;
}

fn clipTinBranch(
    branch: []const u8,
    maximum_length: u8,
    role: ids.Role,
) RenderError![]const u8 {
    if (branch.len <= maximum_length) return branch;
    const extra = branch.len - maximum_length;
    if (!std.mem.allEqual(u8, branch[0..extra], '0')) {
        return switch (role) {
            .filer => error.FilerBranchExceedsLegacyControl,
            .spouse => error.SpouseBranchExceedsLegacyControl,
            else => error.UnsupportedRole,
        };
    }
    return branch[extra..];
}

pub fn joinTin(
    role: ids.Role,
    segment_1: []const u8,
    segment_2: []const u8,
    segment_3: []const u8,
    branch: []const u8,
) TinMappingError!field.Tin {
    if (segment_1.len != 3 or
        segment_2.len != 3 or
        segment_3.len != 3)
    {
        return error.InvalidTinSegment;
    }
    switch (role) {
        .filer => {
            if (branch.len == 0) return error.FilerBranchRequired;
            if (branch.len > 3) {
                return error.FilerBranchExceedsLegacyControl;
            }
        },
        .spouse => {
            if (branch.len > 5) {
                return error.SpouseBranchExceedsLegacyControl;
            }
        },
        else => return error.UnsupportedRole,
    }

    var raw: [14]u8 = undefined;
    @memcpy(raw[0..3], segment_1);
    @memcpy(raw[3..6], segment_2);
    @memcpy(raw[6..9], segment_3);
    @memcpy(raw[9 .. 9 + branch.len], branch);
    return field.Tin.parse(raw[0 .. 9 + branch.len]);
}

pub const DateParts = struct {
    month: [2]u8,
    day: [2]u8,
    year: [4]u8,
};

pub fn splitDate(value: model.Date) DateParts {
    var result: DateParts = undefined;
    _ = std.fmt.bufPrint(&result.month, "{d:0>2}", .{value.month}) catch
        unreachable;
    _ = std.fmt.bufPrint(&result.day, "{d:0>2}", .{value.day}) catch
        unreachable;
    _ = std.fmt.bufPrint(&result.year, "{d:0>4}", .{value.year}) catch
        unreachable;
    return result;
}

pub const DateMappingError = domain_date.Error || error{
    InvalidDatePart,
};

pub fn joinDate(
    month: []const u8,
    day: []const u8,
    year: []const u8,
) DateMappingError!model.Date {
    if (month.len != 2 or day.len != 2 or year.len != 4) {
        return error.InvalidDatePart;
    }
    const parsed_month = std.fmt.parseInt(u8, month, 10) catch
        return error.InvalidDatePart;
    const parsed_day = std.fmt.parseInt(u8, day, 10) catch
        return error.InvalidDatePart;
    const parsed_year = std.fmt.parseInt(u16, year, 10) catch
        return error.InvalidDatePart;
    return model.Date.init(parsed_year, parsed_month, parsed_day);
}

pub const AddressParts = struct {
    line_1: [100]u8 = undefined,
    line_1_len: u8 = 0,
    line_2: [50]u8 = undefined,
    line_2_len: u8 = 0,

    pub fn firstLine(self: *const AddressParts) []const u8 {
        return self.line_1[0..self.line_1_len];
    }

    pub fn secondLine(self: *const AddressParts) []const u8 {
        return self.line_2[0..self.line_2_len];
    }
};

pub const AddressMappingError = field.TextError || error{
    AddressExceedsLegacyControls,
    UnqualifiedTextEncoding,
};

pub fn splitAddress(
    value: *const field.RegisteredAddress,
) AddressMappingError!AddressParts {
    const raw = value.asSlice();
    try ensureAscii(raw);
    if (raw.len > 150) return error.AddressExceedsLegacyControls;

    const first_len = @min(raw.len, 100);
    const second_len = raw.len - first_len;
    var result: AddressParts = .{};
    @memcpy(result.line_1[0..first_len], raw[0..first_len]);
    result.line_1_len = @intCast(first_len);
    @memcpy(result.line_2[0..second_len], raw[first_len..]);
    result.line_2_len = @intCast(second_len);
    return result;
}

pub fn joinAddress(
    line_1: []const u8,
    line_2: []const u8,
) AddressMappingError!field.RegisteredAddress {
    try ensureAscii(line_1);
    try ensureAscii(line_2);
    if (line_1.len > 100 or line_2.len > 50) {
        return error.AddressExceedsLegacyControls;
    }
    var raw: [150]u8 = undefined;
    @memcpy(raw[0..line_1.len], line_1);
    @memcpy(raw[line_1.len .. line_1.len + line_2.len], line_2);
    return field.RegisteredAddress.parse(raw[0 .. line_1.len + line_2.len]);
}

fn ensureAscii(raw: []const u8) error{UnqualifiedTextEncoding}!void {
    for (raw) |byte| {
        if (byte > 0x7f) return error.UnqualifiedTextEncoding;
    }
}

pub const MappingBlockReason = enum {
    wrong_form_revision,
    evidence_not_reconciled,
    missing_projected_field,
    unreviewed_projected_field,
    unexpected_value_kind,
    unsupported_role,
    filer_branch_required,
    value_exceeds_legacy_control,
    unqualified_text_encoding,
    rdo_not_in_exact_option_domain,
    duplicate_control,
    too_many_controls,
};

pub const MappingBlock = struct {
    reason: MappingBlockReason,
    role: ?ids.Role = null,
    reusable_field: ?field.ReusableField = null,
    control_id: ?[]const u8 = null,
};

pub const ControlEntry = struct {
    live_form_element_ordinal: u16,
    role: ids.Role,
    reusable_field: field.ReusableField,
    semantic_target: ids.FieldId,
    control_id: []const u8,
    value: ControlValue,
    provenance: projection.Provenance,
    transform: Transform,
    control_source_line: u32,
    transform_evidence_first_line: u32,
    transform_evidence_last_line: u32,
    source_evidence_id: []const u8 = evidence_id,
};

pub const ControlSnapshot = struct {
    profile: projection.Snapshot,
    entries: [profile_control_rules.len]ControlEntry = undefined,
    len: u8 = 0,

    pub fn slice(self: *const ControlSnapshot) []const ControlEntry {
        return self.entries[0..self.len];
    }

    pub fn get(
        self: *const ControlSnapshot,
        control_id: []const u8,
    ) ?*const ControlEntry {
        for (self.slice()) |*entry| {
            if (std.mem.eql(u8, entry.control_id, control_id)) return entry;
        }
        return null;
    }

    fn append(
        self: *ControlSnapshot,
        entry: ControlEntry,
    ) error{ DuplicateControl, TooManyControls }!void {
        if (self.get(entry.control_id) != null) {
            return error.DuplicateControl;
        }
        if (self.len == self.entries.len) return error.TooManyControls;
        self.entries[self.len] = entry;
        self.len += 1;
    }
};

pub const MappingOutcome = union(enum) {
    accepted: ControlSnapshot,
    blocked: MappingBlock,
};

pub const Result = union(enum) {
    accepted: ControlSnapshot,
    rejected: compose.Rejection,
    blocked: MappingBlock,
};

/// Qualifies named roles with the reviewed `form_1701q` spec, freezes an owned
/// semantic snapshot, then fans that snapshot into exact legacy controls.
pub fn composeProfileControls(
    bindings: []const projection.Binding,
    effective_on: model.Date,
) compose.Error!Result {
    const composed = try form.composeProfiles(bindings, effective_on);
    return switch (composed) {
        .rejected => |rejection| .{ .rejected = rejection },
        .accepted => |profile_snapshot| switch (mapProfileSnapshot(
            profile_snapshot,
        )) {
            .accepted => |mapped| .{ .accepted = mapped },
            .blocked => |block| .{ .blocked = block },
        },
    };
}

/// Consumes a semantic snapshot by value. Neither this function nor a later
/// call can mutate a previously returned draft snapshot.
pub fn mapProfileSnapshot(
    profile_snapshot: projection.Snapshot,
) MappingOutcome {
    if (!profile_snapshot.form.eql(&form.revision)) {
        return blocked(.wrong_form_revision, null, null, null);
    }
    validateEvidence() catch {
        return blocked(.evidence_not_reconciled, null, null, null);
    };
    validateSemantics() catch {
        return blocked(.evidence_not_reconciled, null, null, null);
    };

    var result: ControlSnapshot = .{ .profile = profile_snapshot };
    for (profile_control_rules) |mapping| {
        const projected = findProjectedEntry(
            &profile_snapshot,
            mapping.role,
            mapping.semantic_target,
        ) orelse {
            if (!roleIsPresent(&profile_snapshot, mapping.role)) continue;
            const requirement = requirementFor(
                mapping.role,
                mapping.reusable_field,
            ) orelse return blocked(
                .unreviewed_projected_field,
                mapping.role,
                mapping.reusable_field,
                mapping.control_id,
            );
            if (requirement.presence == .required) {
                return blocked(
                    .missing_projected_field,
                    mapping.role,
                    mapping.reusable_field,
                    mapping.control_id,
                );
            }
            continue;
        };

        const rendered = renderControl(mapping, &projected.value) catch |err| {
            return blocked(
                renderBlockReason(err),
                mapping.role,
                mapping.reusable_field,
                mapping.control_id,
            );
        };
        const seed = findControlSeed(mapping.control_id).?;
        result.append(.{
            .live_form_element_ordinal = seed.runtimeFormElementOrdinal(),
            .role = mapping.role,
            .reusable_field = mapping.reusable_field,
            .semantic_target = mapping.semantic_target,
            .control_id = mapping.control_id,
            .value = rendered,
            .provenance = projected.provenance,
            .transform = mapping.transform,
            .control_source_line = mapping.control_source_line,
            .transform_evidence_first_line = mapping.transform_evidence_first_line,
            .transform_evidence_last_line = mapping.transform_evidence_last_line,
        }) catch |err| {
            return blocked(
                switch (err) {
                    error.DuplicateControl => .duplicate_control,
                    error.TooManyControls => .too_many_controls,
                },
                mapping.role,
                mapping.reusable_field,
                mapping.control_id,
            );
        };
    }

    for (profile_snapshot.slice()) |projected| {
        var found = false;
        for (profile_control_rules) |mapping| {
            if (mapping.role == projected.role and
                mapping.semantic_target.eql(&projected.target))
            {
                found = true;
                break;
            }
        }
        if (!found) {
            return blocked(
                .unreviewed_projected_field,
                projected.role,
                projected.value.field(),
                null,
            );
        }
    }
    return .{ .accepted = result };
}

fn blocked(
    reason: MappingBlockReason,
    role: ?ids.Role,
    reusable_field: ?field.ReusableField,
    control_id: ?[]const u8,
) MappingOutcome {
    return .{ .blocked = .{
        .reason = reason,
        .role = role,
        .reusable_field = reusable_field,
        .control_id = control_id,
    } };
}

fn findProjectedEntry(
    snapshot: *const projection.Snapshot,
    role: ids.Role,
    target: ids.FieldId,
) ?*const projection.SnapshotEntry {
    for (snapshot.slice()) |*entry| {
        if (entry.role == role and entry.target.eql(&target)) return entry;
    }
    return null;
}

fn roleIsPresent(
    snapshot: *const projection.Snapshot,
    role: ids.Role,
) bool {
    for (snapshot.slice()) |entry| {
        if (entry.role == role) return true;
    }
    return false;
}

fn requirementFor(
    role: ids.Role,
    reusable_field: field.ReusableField,
) ?spec.Requirement {
    const role_spec = form.profile_spec.role(role) orelse return null;
    for (role_spec.requirements) |requirement| {
        if (requirement.source == reusable_field) return requirement;
    }
    return null;
}

const RenderError = error{
    UnexpectedValueKind,
    UnsupportedRole,
    FilerBranchRequired,
    FilerBranchExceedsLegacyControl,
    SpouseBranchExceedsLegacyControl,
    AddressExceedsLegacyControls,
    ValueExceedsLegacyControl,
    UnqualifiedTextEncoding,
    RdoNotInExactOptionDomain,
};

fn renderControl(
    mapping: Rule,
    value: *const field.Value,
) RenderError!ControlValue {
    if (value.field() != mapping.reusable_field) {
        return error.UnexpectedValueKind;
    }

    const raw: []const u8 = switch (mapping.transform) {
        .identity => switch (value.*) {
            .rdo_code => |rdo| blk: {
                if (!rdo_options.contains(&rdo)) {
                    return error.RdoNotInExactOptionDomain;
                }
                break :blk rdo.asSlice();
            },
            .taxpayer_name => |text| text.asSlice(),
            .zip_code => |text| text.asSlice(),
            .email_address => |text| text.asSlice(),
            .citizenship => |text| text.asSlice(),
            .foreign_tax_number => |text| text.asSlice(),
            else => return error.UnexpectedValueKind,
        },
        .tin_segment_1,
        .tin_segment_2,
        .tin_segment_3,
        .tin_branch,
        => blk: {
            const parts = splitTin(mapping.role, &value.tin) catch |err| {
                return switch (err) {
                    error.UnsupportedRole => error.UnsupportedRole,
                    error.FilerBranchRequired => error.FilerBranchRequired,
                    error.FilerBranchExceedsLegacyControl => error.FilerBranchExceedsLegacyControl,
                    error.SpouseBranchExceedsLegacyControl => error.SpouseBranchExceedsLegacyControl,
                    else => error.UnexpectedValueKind,
                };
            };
            break :blk switch (mapping.transform) {
                .tin_segment_1 => parts.segment(0),
                .tin_segment_2 => parts.segment(1),
                .tin_segment_3 => parts.segment(2),
                .tin_branch => clipTinBranch(
                    parts.branchSlice(),
                    mapping.maximum_length,
                    mapping.role,
                ) catch |err| return err,
                else => unreachable,
            };
        },
        .address_line_1, .address_line_2 => blk: {
            const parts = splitAddress(
                &value.registered_address,
            ) catch |err| {
                return switch (err) {
                    error.AddressExceedsLegacyControls => error.AddressExceedsLegacyControls,
                    error.UnqualifiedTextEncoding => error.UnqualifiedTextEncoding,
                    else => error.UnexpectedValueKind,
                };
            };
            break :blk if (mapping.transform == .address_line_1)
                parts.firstLine()
            else
                parts.secondLine();
        },
        .dob_month, .dob_day, .dob_year => blk: {
            const parts = splitDate(value.date_of_birth);
            break :blk switch (mapping.transform) {
                .dob_month => &parts.month,
                .dob_day => &parts.day,
                .dob_year => &parts.year,
                else => unreachable,
            };
        },
        .taxpayer_name_before_comma => blk: {
            const name = value.taxpayer_name.asSlice();
            const comma = std.mem.indexOfScalar(u8, name, ',');
            break :blk if (comma) |index| name[0..index] else name;
        },
    };
    return ControlValue.init(raw, mapping.maximum_length);
}

fn renderBlockReason(err: RenderError) MappingBlockReason {
    return switch (err) {
        error.UnexpectedValueKind => .unexpected_value_kind,
        error.UnsupportedRole => .unsupported_role,
        error.FilerBranchRequired => .filer_branch_required,
        error.FilerBranchExceedsLegacyControl,
        error.SpouseBranchExceedsLegacyControl,
        error.AddressExceedsLegacyControls,
        error.ValueExceedsLegacyControl,
        => .value_exceeds_legacy_control,
        error.UnqualifiedTextEncoding => .unqualified_text_encoding,
        error.RdoNotInExactOptionDomain => .rdo_not_in_exact_option_domain,
    };
}

fn individualRevision(
    profile_id: []const u8,
    revision_id: []const u8,
    sequence: u32,
    tin: []const u8,
    rdo: []const u8,
    name: []const u8,
    address: []const u8,
) !model.ProfileRevision {
    return .{
        .profile_id = try model.ProfileId.parse(profile_id),
        .id = try model.RevisionId.parse(revision_id),
        .sequence = sequence,
        .effective = try model.EffectivePeriod.init(
            try model.Date.parseIso("2026-01-01"),
            null,
        ),
        .source = .manual_entry,
        .identity = .{
            .tin = try field.Tin.parse(tin),
            .rdo_code = try field.RdoCode.parse(rdo),
        },
        .contact = .{
            .address = try field.RegisteredAddress.parse(address),
            .zip_code = try field.ZipCode.parse("1000"),
            .email_address = try field.EmailAddress.parse(
                "person@example.ph",
            ),
        },
        .subject = .{ .individual = .{
            .name = try field.TaxpayerName.parse(name),
            .date_of_birth = try model.Date.parseIso("1995-06-01"),
            .citizenship = try field.Citizenship.parse("Filipino"),
            .foreign_tax_number = try field.ForeignTaxNumber.parse(
                "SYNTHETIC-FTN",
            ),
        } },
    };
}

fn corporationRevision() !model.ProfileRevision {
    return .{
        .profile_id = try model.ProfileId.parse("profile-corporation"),
        .id = try model.RevisionId.parse("revision-corporation-1"),
        .sequence = 1,
        .effective = try model.EffectivePeriod.init(
            try model.Date.parseIso("2026-01-01"),
            null,
        ),
        .source = .manual_entry,
        .identity = .{
            .tin = try field.Tin.parse("987-654-321-000"),
            .rdo_code = try field.RdoCode.parse("019"),
        },
        .contact = .{
            .address = try field.RegisteredAddress.parse(
                "SYNTHETIC CORPORATE ADDRESS",
            ),
            .zip_code = try field.ZipCode.parse("1000"),
            .email_address = try field.EmailAddress.parse(
                "tax@corp.example",
            ),
        },
        .subject = .{ .legal_entity = .{
            .registered_name = try field.RegisteredName.parse(
                "SYNTHETIC CORPORATION",
            ),
            .kind = .corporation,
        } },
    };
}

test "mapping rules reconcile every semantic requirement and exact occurrence" {
    try validateEvidence();
    try validateSemantics();
    try std.testing.expectEqual(@as(usize, 9), form.filer_requirements.len);
    try std.testing.expectEqual(@as(usize, 5), form.spouse_requirements.len);
    try std.testing.expectEqual(@as(usize, 28), profile_control_rules.len);
    try std.testing.expectEqual(
        @as(usize, 32),
        transaction_owned_controls.len,
    );
}

test "TIN DOB and address transforms are explicit lossless round trips" {
    const filer_value = try field.Tin.parse("123-456-789-000");
    const filer_parts = try splitTin(.filer, &filer_value);
    try std.testing.expectEqualStrings("123", filer_parts.segment(0));
    try std.testing.expectEqualStrings("456", filer_parts.segment(1));
    try std.testing.expectEqualStrings("789", filer_parts.segment(2));
    try std.testing.expectEqualStrings("000", filer_parts.branchSlice());
    const joined_filer = try joinTin(
        .filer,
        filer_parts.segment(0),
        filer_parts.segment(1),
        filer_parts.segment(2),
        filer_parts.branchSlice(),
    );
    try std.testing.expect(filer_value.eql(&joined_filer));

    const spouse_value = try field.Tin.parse("987-654-321");
    const spouse_parts = try splitTin(.spouse, &spouse_value);
    try std.testing.expectEqualStrings("", spouse_parts.branchSlice());
    const joined_spouse = try joinTin(
        .spouse,
        spouse_parts.segment(0),
        spouse_parts.segment(1),
        spouse_parts.segment(2),
        spouse_parts.branchSlice(),
    );
    try std.testing.expect(spouse_value.eql(&joined_spouse));

    const dob = try model.Date.parseIso("1995-06-01");
    const date_parts = splitDate(dob);
    try std.testing.expectEqualStrings("06", &date_parts.month);
    try std.testing.expectEqualStrings("01", &date_parts.day);
    try std.testing.expectEqualStrings("1995", &date_parts.year);
    try std.testing.expect(dob.eql(try joinDate(
        &date_parts.month,
        &date_parts.day,
        &date_parts.year,
    )));

    const raw_address =
        "12345678901234567890123456789012345678901234567890" ++
        "12345678901234567890123456789012345678901234567890" ++
        "SECOND LINE";
    const address = try field.RegisteredAddress.parse(raw_address);
    const address_parts = try splitAddress(&address);
    try std.testing.expectEqual(@as(usize, 100), address_parts.firstLine().len);
    try std.testing.expectEqualStrings(
        "SECOND LINE",
        address_parts.secondLine(),
    );
    const joined_address = try joinAddress(
        address_parts.firstLine(),
        address_parts.secondLine(),
    );
    try std.testing.expect(address.eql(&joined_address));
}

test "one filer maps an owned exact-control snapshot with provenance" {
    var filer = try individualRevision(
        "profile-filer",
        "revision-filer-1",
        1,
        "123-456-789-000",
        "019",
        "DELA CRUZ, JUAN M",
        "SYNTHETIC FILER ADDRESS",
    );
    const on = try model.Date.parseIso("2026-03-31");
    const result = try composeProfileControls(
        &.{.{ .role = .filer, .revision = &filer }},
        on,
    );
    const snapshot = result.accepted;
    try std.testing.expectEqual(@as(u8, 9), snapshot.profile.len);
    try std.testing.expectEqual(@as(u8, 20), snapshot.len);
    try std.testing.expectEqualStrings(
        "123",
        snapshot.get("frm1701q:txtTIN1").?.value.asSlice(),
    );
    try std.testing.expectEqualStrings(
        "000",
        snapshot.get("frm1701q:txtPg2BranchCode").?.value.asSlice(),
    );
    try std.testing.expectEqualStrings(
        "DELA CRUZ",
        snapshot.get("frm1701q:txtPg2TaxpayerName").?.value.asSlice(),
    );
    try std.testing.expectEqualStrings(
        "revision-filer-1",
        snapshot.get("frm1701q:txtTaxpayerName").?
            .provenance.revision_id.asSlice(),
    );
}

test "five-digit head-office branch maps into the 3-char page-1 control" {
    var filer = try individualRevision(
        "profile-filer",
        "revision-filer-1",
        1,
        "123-456-789-00000",
        "019",
        "DELA CRUZ, JUAN M",
        "SYNTHETIC FILER ADDRESS",
    );
    const on = try model.Date.parseIso("2026-03-31");
    const result = try composeProfileControls(
        &.{.{ .role = .filer, .revision = &filer }},
        on,
    );
    const snapshot = result.accepted;
    try std.testing.expectEqualStrings(
        "000",
        snapshot.get("frm1701q:txtBranchCode").?.value.asSlice(),
    );
    try std.testing.expectEqualStrings(
        "00000",
        snapshot.get("frm1701q:txtPg2BranchCode").?.value.asSlice(),
    );
}

test "optional distinct spouse maps only when explicitly bound" {
    var filer = try individualRevision(
        "profile-filer",
        "revision-filer-1",
        1,
        "123-456-789-000",
        "019",
        "SYNTHETIC FILER",
        "SYNTHETIC FILER ADDRESS",
    );
    var spouse = try individualRevision(
        "profile-spouse",
        "revision-spouse-1",
        1,
        "987-654-321-000",
        "020",
        "SYNTHETIC SPOUSE",
        "SYNTHETIC SPOUSE ADDRESS",
    );
    const on = try model.Date.parseIso("2026-03-31");
    const no_spouse = (try composeProfileControls(
        &.{.{ .role = .filer, .revision = &filer }},
        on,
    )).accepted;
    try std.testing.expect(
        no_spouse.get("frm1701q:txtSpouseTIN1") == null,
    );

    const bindings = [_]projection.Binding{
        .{ .role = .filer, .revision = &filer },
        .{ .role = .spouse, .revision = &spouse },
    };
    const with_spouse = (try composeProfileControls(
        &bindings,
        on,
    )).accepted;
    try std.testing.expectEqual(@as(u8, 14), with_spouse.profile.len);
    try std.testing.expectEqual(@as(u8, 28), with_spouse.len);
    try std.testing.expectEqualStrings(
        "987",
        with_spouse.get("frm1701q:txtSpouseTIN1").?.value.asSlice(),
    );
    try std.testing.expectEqualStrings(
        "Filipino",
        with_spouse.get(
            "frm1701q:txtSpouseCitizenship",
        ).?.value.asSlice(),
    );
}

test "same profile cannot fill filer and spouse roles" {
    var filer = try individualRevision(
        "profile-filer",
        "revision-filer-1",
        1,
        "123-456-789-000",
        "019",
        "SYNTHETIC FILER",
        "SYNTHETIC FILER ADDRESS",
    );
    const bindings = [_]projection.Binding{
        .{ .role = .filer, .revision = &filer },
        .{ .role = .spouse, .revision = &filer },
    };
    const result = try composeProfileControls(
        &bindings,
        try model.Date.parseIso("2026-03-31"),
    );
    try std.testing.expectEqual(@as(u8, 1), result.rejected.len);
    try std.testing.expectEqual(
        std.meta.activeTag(compose.Issue{
            .same_profile_in_distinct_roles = .{
                .left = .filer,
                .right = .spouse,
            },
        }),
        std.meta.activeTag(result.rejected.slice()[0]),
    );
}

test "single to married never infers a spouse role binding" {
    var filer = try individualRevision(
        "profile-filer",
        "revision-filer-1",
        1,
        "123-456-789-000",
        "019",
        "SYNTHETIC FILER",
        "SYNTHETIC FILER ADDRESS",
    );
    const statuses = [_]evolution.CivilStatusRevision{
        .{
            .profile_id = filer.profile_id,
            .sequence = 1,
            .effective = try model.EffectivePeriod.init(
                try model.Date.parseIso("2025-01-01"),
                null,
            ),
            .status = .single,
            .source = .manual_entry,
        },
        .{
            .profile_id = filer.profile_id,
            .sequence = 2,
            .effective = try model.EffectivePeriod.init(
                try model.Date.parseIso("2026-02-01"),
                null,
            ),
            .status = .married,
            .source = .manual_entry,
        },
    };
    const history: evolution.CivilStatusHistory = .{
        .profile_id = filer.profile_id,
        .revisions = &statuses,
    };
    const on = try model.Date.parseIso("2026-03-31");
    try std.testing.expectEqual(
        evolution.CivilStatus.married,
        (try history.resolve(on)).status,
    );

    const snapshot = (try composeProfileControls(
        &.{.{ .role = .filer, .revision = &filer }},
        on,
    )).accepted;
    try std.testing.expect(
        snapshot.get("frm1701q:txtSpouseName") == null,
    );
    try std.testing.expect(snapshot.profile.get(
        spouse_name.target,
    ) == null);
}

test "individual to sole proprietor keeps one identity and remains eligible" {
    const first = try individualRevision(
        "profile-natural",
        "revision-natural-1",
        1,
        "123-456-789-000",
        "019",
        "SYNTHETIC PERSON",
        "SYNTHETIC ADDRESS",
    );
    var second = try individualRevision(
        "profile-natural",
        "revision-natural-2",
        2,
        "123-456-789-000",
        "019",
        "SYNTHETIC PERSON",
        "SYNTHETIC ADDRESS",
    );
    const person = second.subject.individual;
    second.subject = .{ .sole_proprietor = .{
        .person = person,
        .trade_name = try field.RegisteredName.parse(
            "SYNTHETIC TRADE NAME",
        ),
    } };
    const anchor = evolution.TaxpayerIdentityAnchor.fromRevision(&first);
    try evolution.validateOrdinaryTransition(&anchor, &first, &second);

    const snapshot = (try composeProfileControls(
        &.{.{ .role = .filer, .revision = &second }},
        try model.Date.parseIso("2026-03-31"),
    )).accepted;
    try std.testing.expectEqualStrings(
        "profile-natural",
        snapshot.get("frm1701q:txtTIN1").?
            .provenance.profile_id.asSlice(),
    );
}

test "distinct successor corporation is not an eligible 1701Q filer" {
    const natural = try individualRevision(
        "profile-natural",
        "revision-natural-1",
        1,
        "123-456-789-000",
        "019",
        "SYNTHETIC PERSON",
        "SYNTHETIC ADDRESS",
    );
    var corporation = try corporationRevision();
    const natural_anchor =
        evolution.TaxpayerIdentityAnchor.fromRevision(&natural);
    const corporation_anchor =
        evolution.TaxpayerIdentityAnchor.fromRevision(&corporation);
    const relationship: evolution.ProfileRelationship = .{
        .from_profile_id = natural.profile_id,
        .to_profile_id = corporation.profile_id,
        .kind = .business_converted_to,
        .effective = try model.EffectivePeriod.init(
            try model.Date.parseIso("2026-02-01"),
            null,
        ),
        .provenance = try field.SourceReference.parse(
            "synthetic reviewed conversion",
        ),
    };
    try relationship.validate(&natural_anchor, &corporation_anchor);

    const result = try composeProfileControls(
        &.{.{ .role = .filer, .revision = &corporation }},
        try model.Date.parseIso("2026-03-31"),
    );
    var found_subject_rejection = false;
    for (result.rejected.slice()) |issue| {
        switch (issue) {
            .qualification => |qualification| switch (qualification) {
                .subject_not_allowed => |not_allowed| {
                    try std.testing.expectEqual(
                        model.SubjectKind.corporation,
                        not_allowed.subject,
                    );
                    found_subject_rejection = true;
                },
                else => {},
            },
            else => {},
        }
    }
    try std.testing.expect(found_subject_rejection);
}

test "refresh builds a new snapshot without mutating the old draft" {
    const first = try individualRevision(
        "profile-filer",
        "revision-filer-1",
        1,
        "123-456-789-000",
        "019",
        "SYNTHETIC OLD NAME",
        "SYNTHETIC OLD ADDRESS",
    );
    const second = try individualRevision(
        "profile-filer",
        "revision-filer-2",
        2,
        "123-456-789-000",
        "019",
        "SYNTHETIC NEW NAME",
        "SYNTHETIC NEW ADDRESS",
    );
    const anchor = evolution.TaxpayerIdentityAnchor.fromRevision(&first);
    try evolution.validateOrdinaryTransition(&anchor, &first, &second);
    const on = try model.Date.parseIso("2026-03-31");

    const old_snapshot = (try composeProfileControls(
        &.{.{ .role = .filer, .revision = &first }},
        on,
    )).accepted;
    const refreshed_snapshot = (try composeProfileControls(
        &.{.{ .role = .filer, .revision = &second }},
        on,
    )).accepted;

    try std.testing.expectEqualStrings(
        "SYNTHETIC OLD NAME",
        old_snapshot.get("frm1701q:txtTaxpayerName").?.value.asSlice(),
    );
    try std.testing.expectEqualStrings(
        "SYNTHETIC NEW NAME",
        refreshed_snapshot.get(
            "frm1701q:txtTaxpayerName",
        ).?.value.asSlice(),
    );
    try std.testing.expectEqualStrings(
        "revision-filer-1",
        old_snapshot.get("frm1701q:txtTaxpayerName").?
            .provenance.revision_id.asSlice(),
    );
    try std.testing.expectEqualStrings(
        "revision-filer-2",
        refreshed_snapshot.get("frm1701q:txtTaxpayerName").?
            .provenance.revision_id.asSlice(),
    );
}

test "missing required capability is a composition rejection" {
    var filer = try individualRevision(
        "profile-filer",
        "revision-filer-1",
        1,
        "123-456-789-000",
        "019",
        "SYNTHETIC FILER",
        "SYNTHETIC ADDRESS",
    );
    filer.contact.zip_code = null;
    const result = try composeProfileControls(
        &.{.{ .role = .filer, .revision = &filer }},
        try model.Date.parseIso("2026-03-31"),
    );
    var found_missing_zip = false;
    for (result.rejected.slice()) |issue| {
        switch (issue) {
            .qualification => |qualification| switch (qualification) {
                .missing_required_field => |missing| {
                    if (missing.reusable_field == .zip_code) {
                        found_missing_zip = true;
                    }
                },
                else => {},
            },
            else => {},
        }
    }
    try std.testing.expect(found_missing_zip);
}

test "unlisted RDO and unqualified text fail closed" {
    var bad_rdo = try individualRevision(
        "profile-filer",
        "revision-filer-1",
        1,
        "123-456-789-000",
        "ABC",
        "SYNTHETIC FILER",
        "SYNTHETIC ADDRESS",
    );
    const on = try model.Date.parseIso("2026-03-31");
    const rdo_result = try composeProfileControls(
        &.{.{ .role = .filer, .revision = &bad_rdo }},
        on,
    );
    try std.testing.expectEqual(
        MappingBlockReason.rdo_not_in_exact_option_domain,
        rdo_result.blocked.reason,
    );

    var unicode = try individualRevision(
        "profile-unicode",
        "revision-unicode-1",
        1,
        "987-654-321-000",
        "019",
        "\xC3\x89XAMPLE PERSON",
        "SYNTHETIC ADDRESS",
    );
    const unicode_result = try composeProfileControls(
        &.{.{ .role = .filer, .revision = &unicode }},
        on,
    );
    try std.testing.expectEqual(
        MappingBlockReason.unqualified_text_encoding,
        unicode_result.blocked.reason,
    );
}
