//! 1601EQ January 2018 (ENCS) profile-to-control mapping.
//!
//! Provenance (value-free):
//! - Offline eBIRForms 7.9.6
//! - `forms/BIR-Form1601EQ.hta`
//! - SHA-256:
//!   `cd56bf18d1da2127d578af611fe8005fe49913a65781bb603b22b31bbe548b96`
//! - Control lines are the pinned `control_contract` entries.
//! - `getRdo` line 3409 emits the Item 7 select.
//!
//! Every rule below names a control the static inventory already pinned, so
//! the mapping cannot drift from the evidence: a test resolves each rule
//! against `control_contract` and compares source line, kind and declared
//! maximum length.
//!
//! Item 7 is the one exception and is marked as such. `getRdo` builds that
//! select at runtime, so no static scrape ever saw it and it has no contract
//! entry. Its option domain is pinned separately in `rdo_options`.
//!
//! Two shapes are worth noting because they are invisible on the rendered
//! form:
//!
//! - `txtLineBus` carries the line of business and sits inside a
//!   `display:none` cell. The value is projected and submitted but never
//!   shown, so a taxpayer cannot see or correct it.
//! - `txtEmail` is the only mapped control without the `frm1601EQ:` prefix,
//!   and its declared maximum is 20 characters, which is shorter than many
//!   real addresses.
//!
//! This module maps values onto controls. It does not save, and
//! `profile_mapping_reviewed` stays false until the projection is exercised
//! against a live revision.

const std = @import("std");
const ids = @import("../../../forms/id.zig");
const spec = @import("../../../forms/spec.zig");
const form = @import("../../../forms/form_1601eq.zig");
const field = @import("../../../tax_profile/field.zig");
const control_contract = @import("control_contract.zig");
const evidence = @import("evidence.zig");
const occurrences = @import("occurrences.zig");
const rdo_options = @import("rdo_options.zig");

pub const evidence_id = "desktop-7.9.6-1601eq-hta";

/// How a reusable value reaches one control.
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
    /// True when the control is generated at runtime and therefore absent
    /// from the static contract.
    generated_at_runtime: bool = false,
    /// True when the control is present but never rendered.
    hidden_from_the_taxpayer: bool = false,
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
    };
}

/// Background Information controls in HTA source order.
pub const profile_control_rules = [_]Rule{
    rule(filer_tin, "frm1601EQ:txtTIN1", 391, 3, .tin_segment_1),
    rule(filer_tin, "frm1601EQ:txtTIN2", 392, 3, .tin_segment_2),
    rule(filer_tin, "frm1601EQ:txtTIN3", 393, 3, .tin_segment_3),
    rule(filer_tin, "frm1601EQ:txtBranchCode", 394, 5, .tin_branch),
    rule(filer_name, "frm1601EQ:txtTaxpayerName", 435, 50, .identity),
    blk: {
        var hidden = rule(filer_line_of_business, "frm1601EQ:txtLineBus", 448, 150, .identity);
        hidden.hidden_from_the_taxpayer = true;
        break :blk hidden;
    },
    rule(filer_address, "frm1601EQ:txtAddress", 472, 150, .address_line_1),
    rule(filer_address, "frm1601EQ:txtAddress2", 488, 150, .address_line_2),
    rule(filer_zip, "frm1601EQ:txtZipCode", 495, 12, .identity),
    rule(filer_contact, "frm1601EQ:txtTelNum", 513, 20, .identity),
    rule(filer_email, "txtEmail", 539, 20, .identity),
    blk: {
        var generated = rule(filer_rdo, "frm1601EQ:txtRDOCode", 3409, 3, .identity);
        generated.expected_kind = .select_one;
        generated.generated_at_runtime = true;
        break :blk generated;
    },
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

pub const MappingError = error{
    ControlMissingFromContract,
    ControlSourceLineMismatch,
    ControlKindMismatch,
    ControlMaximumLengthMismatch,
    RequirementNotMapped,
};

/// Resolves every static rule against the pinned contract.
pub fn validateAgainstContract() MappingError!void {
    for (profile_control_rules) |entry| {
        if (entry.generated_at_runtime) continue;
        const found = control_contract.find(entry.control_id) orelse
            return error.ControlMissingFromContract;
        if (found.source_line != entry.control_source_line) {
            return error.ControlSourceLineMismatch;
        }
        if (found.kind != entry.expected_kind) return error.ControlKindMismatch;
        const declared = found.max_length orelse return error.ControlMaximumLengthMismatch;
        if (declared != entry.maximum_length) {
            return error.ControlMaximumLengthMismatch;
        }
    }
}

/// Every declared requirement reaches at least one control.
pub fn validateRequirementCoverage() MappingError!void {
    for (form.filer_requirements) |requirement| {
        if (rulesForField(requirement.source) == 0) return error.RequirementNotMapped;
    }
}

test "1601EQ every static rule resolves against the pinned contract" {
    try validateAgainstContract();
    try validateRequirementCoverage();
    try std.testing.expectEqual(@as(usize, 12), profile_control_rules.len);
}

test "1601EQ the eight declared requirements are all reached" {
    try std.testing.expectEqual(@as(usize, 8), form.filer_requirements.len);
    // The TIN fans out across four controls; the address across two.
    try std.testing.expectEqual(@as(usize, 4), rulesForField(.tin));
    try std.testing.expectEqual(@as(usize, 2), rulesForField(.registered_address));
    for ([_]field.ReusableField{
        .rdo_code,         .taxpayer_name,  .zip_code,
        .line_of_business, .contact_number, .email_address,
    }) |single| {
        try std.testing.expectEqual(@as(usize, 1), rulesForField(single));
    }
}

test "1601EQ Item 7 is the only rule with no contract entry" {
    var generated: usize = 0;
    for (profile_control_rules) |entry| {
        if (!entry.generated_at_runtime) {
            try std.testing.expect(control_contract.find(entry.control_id) != null);
            continue;
        }
        generated += 1;
        // getRdo builds it, so the static inventory never saw it.
        try std.testing.expect(control_contract.find(entry.control_id) == null);
        try std.testing.expectEqual(occurrences.ControlKind.select_one, entry.expected_kind);
        try std.testing.expectEqual(field.ReusableField.rdo_code, entry.reusable_field);
    }
    try std.testing.expectEqual(@as(usize, 1), generated);
    // Its domain is pinned elsewhere.
    try std.testing.expectEqual(@as(usize, 138), rdo_options.values.len);
}

test "1601EQ the line of business is mapped but never rendered" {
    const hidden = ruleFor("frm1601EQ:txtLineBus").?;
    try std.testing.expect(hidden.hidden_from_the_taxpayer);
    try std.testing.expectEqual(field.ReusableField.line_of_business, hidden.reusable_field);
    // It is a real control the contract carries, not an invention.
    try std.testing.expect(control_contract.find("frm1601EQ:txtLineBus") != null);

    // Nothing else is hidden.
    var hidden_count: usize = 0;
    for (profile_control_rules) |entry| {
        if (entry.hidden_from_the_taxpayer) hidden_count += 1;
    }
    try std.testing.expectEqual(@as(usize, 1), hidden_count);
}

test "1601EQ the email control keeps its unprefixed id and short maximum" {
    const email = ruleFor("txtEmail").?;
    try std.testing.expect(!std.mem.startsWith(u8, email.control_id, "frm1601EQ:"));
    try std.testing.expectEqual(@as(u8, 20), email.maximum_length);
    // Every other mapped control carries the prefix.
    for (profile_control_rules) |entry| {
        if (std.mem.eql(u8, entry.control_id, "txtEmail")) continue;
        try std.testing.expect(std.mem.startsWith(u8, entry.control_id, "frm1601EQ:"));
    }
}

test "1601EQ mapping does not claim review or enable saving" {
    try std.testing.expect(!evidence.readiness.profile_mapping_reviewed);
    try std.testing.expect(!evidence.readiness.persistence_integrated);
    try std.testing.expectEqualStrings("desktop-7.9.6-1601eq-hta", evidence_id);
}
