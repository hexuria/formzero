//! Exact immutable registration-evidence authority selected for filing scope.
//!
//! A document ID alone is not enough provenance: the same document can have
//! several immutable assertions and an append-only stream of review decisions.
//! These bindings therefore name the fact, assertion, and exact accepted
//! review decision that authorized a registration snapshot.

const std = @import("std");
const registration = @import("../tax_profile/registration_domain.zig");

pub const FactSubject = union(enum) {
    taxpayer_identity_revision: registration.TaxpayerRevisionId,
    registration_unit_branch_code_revision: registration.RegistrationUnitRevisionId,
    registration_unit_lifecycle_revision: registration.RegistrationUnitRevisionId,
    registration_unit_contact_revision: registration.RegistrationUnitContactRevisionId,
    tax_type_registration_revision: registration.TaxTypeRegistrationRevisionId,

    pub fn idBytes(self: *const FactSubject) []const u8 {
        return switch (self.*) {
            inline else => |*id| id.asSlice(),
        };
    }
};

pub const EvidenceReviewReason = enum {
    missing,
    rejected,
    superseded,
};

/// Exact fact whose referenced registration evidence cannot authorize a
/// snapshot. The lineage subject is history-only and must never be mistaken
/// for a current filing fact.
pub const EvidenceReviewSubject = union(enum) {
    taxpayer_identity_revision: registration.TaxpayerRevisionId,
    registration_unit_branch_code_revision: registration.RegistrationUnitRevisionId,
    registration_unit_lifecycle_revision: registration.RegistrationUnitRevisionId,
    registration_unit_contact_revision: registration.RegistrationUnitContactRevisionId,
    tax_type_registration_revision: registration.TaxTypeRegistrationRevisionId,
    branch_code_lineage: struct {
        registration_unit_id: registration.RegistrationUnitId,
        code: registration.BranchCode5,
    },
};

pub const EvidenceReviewIssue = struct {
    reason: EvidenceReviewReason,
    evidence_id: ?registration.RegistrationEvidenceId,
    subject: EvidenceReviewSubject,
};

pub const ReviewedEvidenceBinding = struct {
    subject: FactSubject,
    evidence_id: registration.RegistrationEvidenceId,
    review_decision_id: registration.RegistrationEvidenceReviewDecisionId,
    review_decision_sequence: u32,
    assertion_id: registration.RegistrationEvidenceAssertionId,

    pub fn isValid(self: *const ReviewedEvidenceBinding) bool {
        return self.subject.idBytes().len != 0 and
            self.evidence_id.isPresent() and
            self.review_decision_id.isPresent() and
            self.review_decision_sequence != 0 and
            self.assertion_id.isPresent();
    }

    pub fn eql(
        self: *const ReviewedEvidenceBinding,
        other: *const ReviewedEvidenceBinding,
    ) bool {
        return std.meta.activeTag(self.subject) == std.meta.activeTag(other.subject) and
            std.mem.eql(u8, self.subject.idBytes(), other.subject.idBytes()) and
            self.evidence_id.eql(&other.evidence_id) and
            self.review_decision_id.eql(&other.review_decision_id) and
            self.review_decision_sequence == other.review_decision_sequence and
            self.assertion_id.eql(&other.assertion_id);
    }
};

pub fn lessThan(left: ReviewedEvidenceBinding, right: ReviewedEvidenceBinding) bool {
    const left_tag = @intFromEnum(std.meta.activeTag(left.subject));
    const right_tag = @intFromEnum(std.meta.activeTag(right.subject));
    if (left_tag != right_tag) return left_tag < right_tag;

    const subject_order = std.mem.order(u8, left.subject.idBytes(), right.subject.idBytes());
    if (subject_order != .eq) return subject_order == .lt;

    const evidence_order = std.mem.order(
        u8,
        left.evidence_id.asSlice(),
        right.evidence_id.asSlice(),
    );
    if (evidence_order != .eq) return evidence_order == .lt;

    const decision_order = std.mem.order(
        u8,
        left.review_decision_id.asSlice(),
        right.review_decision_id.asSlice(),
    );
    if (decision_order != .eq) return decision_order == .lt;
    if (left.review_decision_sequence != right.review_decision_sequence) {
        return left.review_decision_sequence < right.review_decision_sequence;
    }
    return std.mem.order(
        u8,
        left.assertion_id.asSlice(),
        right.assertion_id.asSlice(),
    ) == .lt;
}

pub fn sort(values: []ReviewedEvidenceBinding) void {
    var index: usize = 1;
    while (index < values.len) : (index += 1) {
        const value = values[index];
        var cursor = index;
        while (cursor > 0 and lessThan(value, values[cursor - 1])) {
            values[cursor] = values[cursor - 1];
            cursor -= 1;
        }
        values[cursor] = value;
    }
}

test "reviewed evidence bindings are ordered by typed fact subject" {
    const testId = struct {
        fn parse(comptime Id: type, raw: []const u8) Id {
            return Id.parse(raw) catch unreachable;
        }
    }.parse;
    var values = [_]ReviewedEvidenceBinding{
        .{
            .subject = .{ .tax_type_registration_revision = testId(
                registration.TaxTypeRegistrationRevisionId,
                "tax-rev-a",
            ) },
            .evidence_id = testId(registration.RegistrationEvidenceId, "evidence-a"),
            .review_decision_id = testId(
                registration.RegistrationEvidenceReviewDecisionId,
                "decision-a",
            ),
            .review_decision_sequence = 1,
            .assertion_id = testId(
                registration.RegistrationEvidenceAssertionId,
                "assertion-a",
            ),
        },
        .{
            .subject = .{ .taxpayer_identity_revision = testId(
                registration.TaxpayerRevisionId,
                "taxpayer-rev-a",
            ) },
            .evidence_id = testId(registration.RegistrationEvidenceId, "evidence-b"),
            .review_decision_id = testId(
                registration.RegistrationEvidenceReviewDecisionId,
                "decision-b",
            ),
            .review_decision_sequence = 2,
            .assertion_id = testId(
                registration.RegistrationEvidenceAssertionId,
                "assertion-b",
            ),
        },
    };
    sort(&values);
    try std.testing.expectEqual(
        @as(std.meta.Tag(FactSubject), .taxpayer_identity_revision),
        std.meta.activeTag(values[0].subject),
    );
    try std.testing.expect(values[0].isValid());
}

test "binding validity requires every provenance component" {
    const testId = struct {
        fn parse(comptime Id: type, raw: []const u8) Id {
            return Id.parse(raw) catch unreachable;
        }
    }.parse;
    const binding = ReviewedEvidenceBinding{
        .subject = .{ .taxpayer_identity_revision = testId(
            registration.TaxpayerRevisionId,
            "taxpayer-rev-a",
        ) },
        .evidence_id = testId(registration.RegistrationEvidenceId, "evidence-a"),
        .review_decision_id = testId(
            registration.RegistrationEvidenceReviewDecisionId,
            "decision-a",
        ),
        .review_decision_sequence = 1,
        .assertion_id = testId(
            registration.RegistrationEvidenceAssertionId,
            "assertion-a",
        ),
    };
    try std.testing.expect(binding.isValid());

    // A zero review sequence is the nullary transition marker, never valid.
    var missing_sequence = binding;
    missing_sequence.review_decision_sequence = 0;
    try std.testing.expect(!missing_sequence.isValid());

    // Empty opaque ids parse to length zero and fail every presence check.
    var missing_evidence = binding;
    missing_evidence.evidence_id = .{};
    try std.testing.expect(!missing_evidence.isValid());

    var missing_assertion = binding;
    missing_assertion.assertion_id = .{};
    try std.testing.expect(!missing_assertion.isValid());

    // An unset revision id removes the fact bytes that ground the binding.
    var missing_subject = binding;
    missing_subject.subject = .{ .taxpayer_identity_revision = .{} };
    try std.testing.expect(!missing_subject.isValid());
}

test "binding ordering resolves ties down to the assertion id" {
    const testId = struct {
        fn parse(comptime Id: type, raw: []const u8) Id {
            return Id.parse(raw) catch unreachable;
        }
    }.parse;
    const base = ReviewedEvidenceBinding{
        .subject = .{ .taxpayer_identity_revision = testId(
            registration.TaxpayerRevisionId,
            "taxpayer-rev-a",
        ) },
        .evidence_id = testId(registration.RegistrationEvidenceId, "evidence-a"),
        .review_decision_id = testId(
            registration.RegistrationEvidenceReviewDecisionId,
            "decision-a",
        ),
        .review_decision_sequence = 1,
        .assertion_id = testId(
            registration.RegistrationEvidenceAssertionId,
            "assertion-a",
        ),
    };
    var values = [_]ReviewedEvidenceBinding{
        base,
        base,
    };
    values[1].assertion_id = testId(
        registration.RegistrationEvidenceAssertionId,
        "assertion-z",
    );
    sort(&values);
    try std.testing.expectEqualStrings(
        "assertion-a",
        values[0].assertion_id.asSlice(),
    );

    // Same subject and evidence, later review decision: later sequence wins.
    var by_sequence = [_]ReviewedEvidenceBinding{ base, base };
    by_sequence[0].review_decision_sequence = 2;
    by_sequence[1].review_decision_sequence = 1;
    sort(&by_sequence);
    try std.testing.expectEqual(
        @as(u32, 1),
        by_sequence[0].review_decision_sequence,
    );

    // A later evidence id orders after the same subject with earlier evidence.
    var by_evidence = [_]ReviewedEvidenceBinding{
        base,
        base,
    };
    by_evidence[1].evidence_id = testId(
        registration.RegistrationEvidenceId,
        "evidence-b",
    );
    sort(&by_evidence);
    try std.testing.expectEqualStrings(
        "evidence-a",
        by_evidence[0].evidence_id.asSlice(),
    );

    // Equal components compare equal: sorting is stable and reversible.
    try std.testing.expect(lessThan(base, base) == false);
    try std.testing.expect(base.eql(&base));
}
