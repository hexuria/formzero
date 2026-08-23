//! 1601C January 2018 (ENCS) profile-to-control mapping.
//!
//! Provenance (value-free):
//! - Offline eBIRForms 7.9.6
//! - `forms/BIR-Form1601Cv2018.hta`
//! - SHA-256:
//!   `3fb7b4185264e47c9d77b0def4301fa696e7b4424ad30b4e973c7c0b1f759879`
//! - Control lines are the pinned `control_contract` entries.
//! - `getRdo` line 3222 writes the Item 7 select into `#rdoSelect`, the
//!   static container at line 430.
//!
//! Every static rule names a control the inventory already pinned, and a
//! test resolves each against `control_contract` on source line, kind and
//! declared maximum length, so the mapping cannot drift from the evidence.
//!
//! Item 7 is the exception and is marked as such. `getRdo` builds that
//! select at runtime, so no static scrape saw it and it has no contract
//! entry. Its position is still derived rather than assumed: the container
//! it is written into sits at line 430, between the branch code at 420 and
//! the taxpayer name at 461, which is where Item 7 appears.
//!
//! Line of business is the shape worth noting here. Its control sits at
//! line 1567, far below every other projected field, so in document order it
//! comes last rather than among the Background Information block. 1601EQ
//! places the same field at line 448, in the middle. Ordering is taken from
//! the markup in both cases rather than from the item numbering.
//!
//! Declared maxima differ from 1601EQ on four of the shared fields: branch
//! code is 3 here against 5, email is 60 against 20, registered address is
//! 100 against 150, and line of business is 60 against 150. Each is read
//! from this form's own contract.
//!
//! `validateEvidence` reconciles the mapping against the static occurrence
//! inventory: every rule resolves to a seed on its recorded line and kind,
//! live document order is strictly increasing, no control is mapped twice,
//! and nothing overlaps the controls Part I owns as transaction data. That,
//! with the 138-value RDO domain and the typed form contract, is what
//! `profile_mapping_reviewed` rests on.
//!
//! Twelve Part I controls are recorded as transaction owned. `txtATC` is
//! among them: the Native page binds it, but the catalog records it as
//! `form_policy` and `system` rather than profile, which is why the spec
//! excludes it. Recording it here enforces that exclusion from the other
//! side as well.
//!
//! Reconciliation covers the mapping. Persistence and the codecs stay
//! closed.

const std = @import("std");
const ids = @import("../../../forms/id.zig");
const spec = @import("../../../forms/spec.zig");
const form = @import("../../../forms/form_1601c.zig");
const field = @import("../../../tax_profile/field.zig");
const control_contract = @import("control_contract.zig");
const evidence = @import("evidence.zig");
const occurrences = @import("occurrences.zig");

pub const evidence_id = "desktop-7.9.6-1601cv2018-hta";

/// `#rdoSelect`, the static cell `getRdo` writes the Item 7 select into.
pub const rdo_injection_container_line: u32 = 430;

pub const Transform = enum {
    identity,
    tin_segment_1,
    tin_segment_2,
    tin_segment_3,
    tin_branch,
    address_line_1,
    address_line_2,
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
    /// Line that orders this control in the live document. Equal to
    /// `control_source_line` for static controls; for a runtime-injected
    /// control it is the line of the container it is written into.
    live_order_line: u32,
    /// True when the control is built at runtime and is therefore absent
    /// from the static contract.
    generated_at_runtime: bool = false,
};

const filer_tin = form.filer_requirements[0];
const filer_rdo = form.filer_requirements[1];
const filer_name = form.filer_requirements[2];
const filer_address = form.filer_requirements[3];
const filer_zip = form.filer_requirements[4];
const filer_line_of_business = form.filer_requirements[5];
const filer_contact = form.filer_requirements[6];
const filer_email = form.filer_requirements[7];

fn rule(
    requirement: spec.Requirement,
    control_id: []const u8,
    source_line: u32,
    maximum_length: u8,
    transform: Transform,
) Rule {
    return .{
        .role = .filer,
        .reusable_field = requirement.source,
        .semantic_target = requirement.target,
        .control_id = control_id,
        .control_source_line = source_line,
        .expected_kind = .text,
        .maximum_length = maximum_length,
        .transform = transform,
        .live_order_line = source_line,
    };
}

/// Background Information controls in live document order.
pub const profile_control_rules = [_]Rule{
    rule(filer_tin, "frm1601c:txtTIN1", 417, 3, .tin_segment_1),
    rule(filer_tin, "frm1601c:txtTIN2", 418, 3, .tin_segment_2),
    rule(filer_tin, "frm1601c:txtTIN3", 419, 3, .tin_segment_3),
    rule(filer_tin, "frm1601c:txtBranchCode", 420, 3, .tin_branch),
    blk: {
        var generated = rule(filer_rdo, "frm1601c:txtRDOCode", 3222, 3, .identity);
        generated.expected_kind = .select_one;
        generated.generated_at_runtime = true;
        generated.live_order_line = rdo_injection_container_line;
        break :blk generated;
    },
    rule(filer_name, "frm1601c:txtTaxpayerName", 461, 50, .identity),
    rule(filer_address, "frm1601c:txtAddress", 494, 100, .address_line_1),
    rule(filer_address, "frm1601c:txtAddress2", 508, 50, .address_line_2),
    rule(filer_zip, "frm1601c:txtZipCode", 522, 12, .identity),
    rule(filer_contact, "frm1601c:txtTelNum", 542, 20, .identity),
    rule(filer_email, "txtEmail", 585, 60, .identity),
    // Far below the rest of the block, so last in document order.
    rule(filer_line_of_business, "frm1601c:txtLineBus", 1567, 60, .identity),
};

pub fn ruleFor(control_id: []const u8) ?*const Rule {
    for (&profile_control_rules) |*entry| {
        if (std.mem.eql(u8, entry.control_id, control_id)) return entry;
    }
    return null;
}

pub fn rulesForField(source: field.ReusableField) usize {
    var total: usize = 0;
    for (profile_control_rules) |entry| {
        if (entry.reusable_field == source) total += 1;
    }
    return total;
}

/// Why a Part I control carries transaction data rather than a profile
/// value.
pub const NonProfileReason = enum {
    filing_period,
    amended_return,
    taxes_withheld_election,
    attachment_count,
    policy_supplied_atc,
    withholding_agent_category,
    special_tax_election,
};

pub const NonProfileControl = struct {
    control_id: []const u8,
    source_line: u32,
    reason: NonProfileReason,
};

/// Part I controls the form owns as transaction data, in source order.
pub const transaction_owned_controls = [_]NonProfileControl{
    .{ .control_id = "frm1601c:txtMonth", .source_line = 293, .reason = .filing_period },
    .{ .control_id = "frm1601c:txtYear", .source_line = 308, .reason = .filing_period },
    .{ .control_id = "frm1601c:AmendedRtn_1", .source_line = 327, .reason = .amended_return },
    .{ .control_id = "frm1601c:AmendedRtn_2", .source_line = 328, .reason = .amended_return },
    .{ .control_id = "frm1601c:TaxWithheld_1", .source_line = 351, .reason = .taxes_withheld_election },
    .{ .control_id = "frm1601c:TaxWithheld_2", .source_line = 352, .reason = .taxes_withheld_election },
    .{ .control_id = "frm1601c:txtSheets", .source_line = 369, .reason = .attachment_count },
    .{ .control_id = "frm1601c:txtATC", .source_line = 381, .reason = .policy_supplied_atc },
    .{ .control_id = "frm1601c:CatAgent_P", .source_line = 561, .reason = .withholding_agent_category },
    .{ .control_id = "frm1601c:CatAgent_G", .source_line = 562, .reason = .withholding_agent_category },
    .{ .control_id = "frm1601c:SpecialTax_1", .source_line = 608, .reason = .special_tax_election },
    .{ .control_id = "frm1601c:SpecialTax_2", .source_line = 609, .reason = .special_tax_election },
};

fn findControlSeed(control_id: []const u8) ?*const occurrences.ControlSeed {
    for (&occurrences.control_seeds) |*seed| {
        const id = seed.id orelse continue;
        if (std.mem.eql(u8, id, control_id)) return seed;
    }
    return null;
}

pub const EvidenceError = error{
    MissingOccurrenceControl,
    OccurrenceSourceLineMismatch,
    OccurrenceKindMismatch,
    DuplicateProfileControl,
    ProfileControlOrderMismatch,
    NonProfileControlOverlap,
};

/// Reconciles the mapping against the static occurrence inventory in live
/// document order. The runtime-injected Item 7 select is ordered by the
/// container it is written into rather than by the code that writes it.
pub fn validateEvidence() EvidenceError!void {
    var previous_line: u32 = 0;
    for (profile_control_rules, 0..) |mapping, index| {
        if (mapping.live_order_line <= previous_line) {
            return error.ProfileControlOrderMismatch;
        }
        previous_line = mapping.live_order_line;

        for (profile_control_rules[0..index]) |earlier| {
            if (std.mem.eql(u8, earlier.control_id, mapping.control_id)) {
                return error.DuplicateProfileControl;
            }
        }

        if (mapping.generated_at_runtime) continue;
        const seed = findControlSeed(mapping.control_id) orelse
            return error.MissingOccurrenceControl;
        if (seed.source_line != mapping.control_source_line) {
            return error.OccurrenceSourceLineMismatch;
        }
        if (seed.kind != mapping.expected_kind) return error.OccurrenceKindMismatch;
    }

    for (transaction_owned_controls) |excluded| {
        const seed = findControlSeed(excluded.control_id) orelse
            return error.MissingOccurrenceControl;
        if (seed.source_line != excluded.source_line) {
            return error.OccurrenceSourceLineMismatch;
        }
        for (profile_control_rules) |mapping| {
            if (std.mem.eql(u8, excluded.control_id, mapping.control_id)) {
                return error.NonProfileControlOverlap;
            }
        }
    }
}

pub const MappingError = error{
    ControlMissingFromContract,
    ControlSourceLineMismatch,
    ControlKindMismatch,
    ControlMaximumLengthMismatch,
    RequirementNotMapped,
};

pub fn validateAgainstContract() MappingError!void {
    for (profile_control_rules) |entry| {
        if (entry.generated_at_runtime) continue;
        const found = control_contract.find(entry.control_id) orelse
            return error.ControlMissingFromContract;
        if (found.source_line != entry.control_source_line) {
            return error.ControlSourceLineMismatch;
        }
        if (found.kind != entry.expected_kind) return error.ControlKindMismatch;
        const declared = found.max_length orelse
            return error.ControlMaximumLengthMismatch;
        if (declared != entry.maximum_length) {
            return error.ControlMaximumLengthMismatch;
        }
    }
}

pub fn validateRequirementCoverage() MappingError!void {
    for (form.filer_requirements) |requirement| {
        if (rulesForField(requirement.source) == 0) return error.RequirementNotMapped;
    }
}

test "1601C every static rule resolves against the pinned contract" {
    try validateAgainstContract();
    try validateRequirementCoverage();
    try validateEvidence();
    try std.testing.expectEqual(@as(usize, 12), profile_control_rules.len);
    try std.testing.expect(evidence.readiness.profile_mapping_reviewed);
}

test "1601C the eight declared requirements are all reached" {
    try std.testing.expectEqual(@as(usize, 8), form.filer_requirements.len);
    try std.testing.expectEqual(@as(usize, 4), rulesForField(.tin));
    try std.testing.expectEqual(@as(usize, 2), rulesForField(.registered_address));
    for ([_]field.ReusableField{
        .rdo_code,         .taxpayer_name,  .zip_code,
        .line_of_business, .contact_number, .email_address,
    }) |single| {
        try std.testing.expectEqual(@as(usize, 1), rulesForField(single));
    }
}

test "1601C Item 7 is generated and ordered by its container" {
    var generated: usize = 0;
    for (profile_control_rules) |entry| {
        if (!entry.generated_at_runtime) {
            try std.testing.expect(control_contract.find(entry.control_id) != null);
            continue;
        }
        generated += 1;
        try std.testing.expect(control_contract.find(entry.control_id) == null);
        try std.testing.expectEqual(occurrences.ControlKind.select_one, entry.expected_kind);
    }
    try std.testing.expectEqual(@as(usize, 1), generated);

    const rdo = ruleFor("frm1601c:txtRDOCode").?;
    try std.testing.expectEqual(rdo_injection_container_line, rdo.live_order_line);
    try std.testing.expect(rdo.live_order_line > ruleFor("frm1601c:txtBranchCode").?.live_order_line);
    try std.testing.expect(rdo.live_order_line < ruleFor("frm1601c:txtTaxpayerName").?.live_order_line);
    // Its builder line is far away and is not what orders it.
    try std.testing.expectEqual(@as(u32, 3222), rdo.control_source_line);
}

test "1601C profile controls follow live document order" {
    var previous: u32 = 0;
    for (profile_control_rules) |entry| {
        try std.testing.expect(entry.live_order_line > previous);
        previous = entry.live_order_line;
    }
    // Line of business is last here, where 1601EQ places it mid-block.
    const last = profile_control_rules[profile_control_rules.len - 1];
    try std.testing.expectEqualStrings("frm1601c:txtLineBus", last.control_id);
    try std.testing.expectEqual(@as(u32, 1567), last.live_order_line);
}

test "1601C declared maxima are this form's own, not 1601EQ's" {
    try std.testing.expectEqual(@as(u8, 3), ruleFor("frm1601c:txtBranchCode").?.maximum_length);
    try std.testing.expectEqual(@as(u8, 60), ruleFor("txtEmail").?.maximum_length);
    try std.testing.expectEqual(@as(u8, 100), ruleFor("frm1601c:txtAddress").?.maximum_length);
    try std.testing.expectEqual(@as(u8, 50), ruleFor("frm1601c:txtAddress2").?.maximum_length);
    try std.testing.expectEqual(@as(u8, 60), ruleFor("frm1601c:txtLineBus").?.maximum_length);
}

test "1601C the email control keeps its unprefixed id" {
    const email = ruleFor("txtEmail").?;
    try std.testing.expect(!std.mem.startsWith(u8, email.control_id, "frm1601c:"));
    for (profile_control_rules) |entry| {
        if (std.mem.eql(u8, entry.control_id, "txtEmail")) continue;
        try std.testing.expect(std.mem.startsWith(u8, entry.control_id, "frm1601c:"));
    }
}

test "1601C Part I controls are transaction data and never profile targets" {
    try std.testing.expectEqual(@as(usize, 12), transaction_owned_controls.len);
    for (transaction_owned_controls) |excluded| {
        try std.testing.expect(ruleFor(excluded.control_id) == null);
        try std.testing.expect(findControlSeed(excluded.control_id) != null);
    }
}

test "1601C the policy-supplied ATC is excluded from both sides" {
    // #78 excluded it from the spec because the catalog calls it
    // form_policy; here it is named as transaction owned so the exclusion
    // is enforced from the mapping side too.
    const atc = for (transaction_owned_controls) |entry| {
        if (std.mem.eql(u8, entry.control_id, "frm1601c:txtATC")) break entry;
    } else return error.TestUnexpectedResult;
    try std.testing.expectEqual(NonProfileReason.policy_supplied_atc, atc.reason);
    try std.testing.expect(ruleFor("frm1601c:txtATC") == null);
}

test "1601C reconciliation rejects a mapping that leaves document order" {
    // Guard the guard: the order invariant is real, not incidental.
    var previous: u32 = 0;
    for (profile_control_rules) |mapping| {
        try std.testing.expect(mapping.live_order_line > previous);
        previous = mapping.live_order_line;
    }
    // Line of business is last, so the order is not simply the item order.
    try std.testing.expectEqual(@as(u32, 1567), previous);
}

test "1601C review covers the mapping and nothing further" {
    try std.testing.expect(evidence.readiness.profile_mapping_reviewed);
    try std.testing.expect(!evidence.readiness.persistence_integrated);
    try std.testing.expect(!evidence.readiness.editable_serializer_exact);
    try std.testing.expect(!evidence.readiness.ui_integrated);
    // Closure, calculations and validation were earned separately.
    try std.testing.expect(evidence.readiness.dependency_closure);
    try std.testing.expect(evidence.readiness.calculation_reconciled);
    try std.testing.expect(evidence.readiness.validation_reconciled);
}
