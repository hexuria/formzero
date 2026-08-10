//! Presentation-only helpers for registration and filing-scope status.
//!
//! This module deliberately does not resolve a Registration Unit, Branch Code,
//! Filing Unit, or filing obligation from a selected legacy workspace. It only
//! turns canonical registration-domain states into fail-closed UI language and
//! masks the nine-digit taxpayer root found in legacy combined-TIN text.

const std = @import("std");
const registration = @import("registration_domain.zig");

pub const MaskedTinRootError = error{
    Empty,
    InvalidLength,
    InvalidCharacter,
    NoSpaceLeft,
};

/// Writes `***-***-NNN` for a legacy TIN value containing either the nine-digit
/// taxpayer root alone or a 3-5 digit legacy suffix. The suffix is validated as
/// legacy text only and is never returned or promoted to a Branch Code.
pub fn writeMaskedTinRoot(
    legacy_tin: []const u8,
    output: []u8,
) MaskedTinRootError![]const u8 {
    var digits: [14]u8 = undefined;
    var count: usize = 0;

    for (legacy_tin) |byte| {
        if (std.ascii.isDigit(byte)) {
            if (count == digits.len) return error.InvalidLength;
            digits[count] = byte;
            count += 1;
            continue;
        }
        if (byte == '-' or std.ascii.isWhitespace(byte)) continue;
        return error.InvalidCharacter;
    }

    if (count == 0) return error.Empty;
    if (count != 9 and (count < 12 or count > 14)) {
        return error.InvalidLength;
    }

    const root = registration.Tin9.parse(digits[0..9]) catch |err| switch (err) {
        error.InvalidLength => return error.InvalidLength,
        error.InvalidCharacter => return error.InvalidCharacter,
    };
    return std.fmt.bufPrint(
        output,
        "***-***-{s}",
        .{root.asDigits()[6..9]},
    ) catch error.NoSpaceLeft;
}

const RegistrationStatusPresentation = struct {
    status_label: []const u8,
    review_required: bool,
    evidence_title: []const u8,
    evidence_action_label: []const u8,
    evidence_recordable: bool,
    planner_capability_label: []const u8,
    can_request_filing_plan: bool,
};

/// Owns every lifecycle-derived label and capability in one exhaustive map.
/// Public helpers below keep their narrow interfaces while sharing this source
/// of truth, so adding a status cannot leave one UI surface stale.
fn registrationStatusPresentation(
    status: registration.RegistrationUnitStatus,
) RegistrationStatusPresentation {
    return switch (status) {
        .pending_evidence => .{
            .status_label = "Pending evidence",
            .review_required = true,
            .evidence_title = "Confirm the selected Registration Unit",
            .evidence_action_label = "Record reviewed evidence & confirm",
            .evidence_recordable = true,
            .planner_capability_label = "Blocked - confirm registration evidence before planning",
            .can_request_filing_plan = false,
        },
        .confirmed_active => .{
            .status_label = "Confirmed active",
            .review_required = false,
            .evidence_title = "Registration evidence already confirmed",
            .evidence_action_label = "Reviewed evidence action unavailable",
            .evidence_recordable = false,
            .planner_capability_label = "Planning available - the Filing Planner must still resolve this return",
            .can_request_filing_plan = true,
        },
        .confirmed_closed => .{
            .status_label = "Confirmed closed",
            .review_required = false,
            .evidence_title = "This Registration Unit is closed",
            .evidence_action_label = "Reviewed evidence action unavailable",
            .evidence_recordable = false,
            .planner_capability_label = "Blocked - this Registration Unit is closed",
            .can_request_filing_plan = false,
        },
        .legacy_unresolved => .{
            .status_label = "Legacy unresolved",
            .review_required = true,
            .evidence_title = "Resolve the selected legacy Registration Unit",
            .evidence_action_label = "Record reviewed evidence & resolve legacy unit",
            .evidence_recordable = true,
            .planner_capability_label = "Blocked - Review Required before filing-scope planning",
            .can_request_filing_plan = false,
        },
    };
}

pub fn statusLabel(status: registration.RegistrationUnitStatus) []const u8 {
    return registrationStatusPresentation(status).status_label;
}

/// Evidence review is required for pending and migrated legacy identities.
/// A closed unit is blocked for a different, already-known reason.
pub fn reviewRequired(status: registration.RegistrationUnitStatus) bool {
    return registrationStatusPresentation(status).review_required;
}

pub const EvidenceReviewPresentation = struct {
    badge: []const u8,
    title: []const u8,
    action_label: []const u8,
    recordable: bool,
};

/// Keeps the badge, heading, action copy, and eligibility for one lifecycle
/// state together so page wiring cannot present conflicting status language.
pub fn evidenceReviewPresentation(
    status: registration.RegistrationUnitStatus,
) EvidenceReviewPresentation {
    const presentation = registrationStatusPresentation(status);
    return .{
        .badge = presentation.status_label,
        .title = presentation.evidence_title,
        .action_label = presentation.evidence_action_label,
        .recordable = presentation.evidence_recordable,
    };
}

/// Both states accept the same reviewed-evidence form, but the workspace maps
/// them to different domain commands. In particular, legacy state must never
/// be treated as an unconfirmed candidate Branch Code.
pub fn canRecordReviewedEvidence(status: registration.RegistrationUnitStatus) bool {
    return evidenceReviewPresentation(status).recordable;
}

pub fn evidenceReviewActionLabel(status: registration.RegistrationUnitStatus) []const u8 {
    return evidenceReviewPresentation(status).action_label;
}

/// Eligibility to ask the Filing Planner for a decision is intentionally not
/// called fileability: revision fidelity and release gates remain separate.
pub fn plannerCapabilityLabel(
    status: registration.RegistrationUnitStatus,
) []const u8 {
    return registrationStatusPresentation(status).planner_capability_label;
}

pub fn canRequestFilingPlan(status: registration.RegistrationUnitStatus) bool {
    return registrationStatusPresentation(status).can_request_filing_plan;
}

test "masked TIN root never exposes or promotes the legacy suffix" {
    var first: [11]u8 = undefined;
    var second: [11]u8 = undefined;
    var third: [11]u8 = undefined;

    try std.testing.expectEqualStrings(
        "***-***-789",
        try writeMaskedTinRoot("123-456-789", &first),
    );
    try std.testing.expectEqualStrings(
        "***-***-789",
        try writeMaskedTinRoot("123-456-789-001", &second),
    );
    try std.testing.expectEqualStrings(
        "***-***-789",
        try writeMaskedTinRoot("12345678900001", &third),
    );
}

test "masked TIN root rejects ambiguous malformed legacy text" {
    var output: [11]u8 = undefined;
    try std.testing.expectError(
        error.Empty,
        writeMaskedTinRoot("  ", &output),
    );
    try std.testing.expectError(
        error.InvalidLength,
        writeMaskedTinRoot("1234567890", &output),
    );
    try std.testing.expectError(
        error.InvalidCharacter,
        writeMaskedTinRoot("123-456-78X-001", &output),
    );
}

test "registration status language stays fail closed" {
    try std.testing.expectEqualStrings(
        "Legacy unresolved",
        statusLabel(.legacy_unresolved),
    );
    try std.testing.expect(reviewRequired(.legacy_unresolved));
    try std.testing.expect(reviewRequired(.pending_evidence));
    try std.testing.expect(canRecordReviewedEvidence(.legacy_unresolved));
    try std.testing.expect(canRecordReviewedEvidence(.pending_evidence));
    try std.testing.expect(!canRecordReviewedEvidence(.confirmed_active));
    try std.testing.expectEqualStrings(
        "Record reviewed evidence & resolve legacy unit",
        evidenceReviewActionLabel(.legacy_unresolved),
    );
    const pending = evidenceReviewPresentation(.pending_evidence);
    try std.testing.expectEqualStrings("Pending evidence", pending.badge);
    try std.testing.expectEqualStrings(
        "Confirm the selected Registration Unit",
        pending.title,
    );
    try std.testing.expect(!reviewRequired(.confirmed_closed));
    try std.testing.expect(!canRequestFilingPlan(.legacy_unresolved));
    try std.testing.expect(!canRequestFilingPlan(.confirmed_closed));
    try std.testing.expect(canRequestFilingPlan(.confirmed_active));
    try std.testing.expect(std.mem.indexOf(
        u8,
        plannerCapabilityLabel(.confirmed_active),
        "Filing Planner",
    ) != null);
}
