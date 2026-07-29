//! Coarse, typed filing lifecycle.
//!
//! Fine-grained form completeness belongs to each form payload. These types
//! prevent mutation after preparation and prevent acknowledgement before a
//! draft has been prepared and queued. They deliberately do not implement
//! transport, tax calculations, or filing-service policy.

const std = @import("std");
const ids = @import("id.zig");
const model = @import("../tax_profile/model.zig");
const field = @import("../tax_profile/field.zig");
const projection = @import("../tax_profile/projection.zig");

pub const Intent = union(enum) {
    original,
    amended: ids.FilingId,
};

pub const ValidationEvidence = struct {
    validated_on: model.Date,
    /// Version of the external form/rule validator used to prepare the data.
    policy_revision: ids.RevisionLabel,
};

pub const QueueEvidence = struct {
    queued_on: model.Date,
    queue_reference: ids.FilingId,
};

pub const Accepted = struct {
    acknowledged_on: model.Date,
    acknowledgement_reference: ids.FilingId,
};

pub const Rejected = struct {
    acknowledged_on: model.Date,
    reason: field.SourceReference,
};

pub const Outcome = union(enum) {
    accepted: Accepted,
    rejected: Rejected,
};

pub fn Editing(comptime Payload: type) type {
    return struct {
        const Self = @This();

        draft_id: ids.DraftId,
        intent: Intent,
        snapshot: projection.Snapshot,
        payload: Payload,

        pub fn prepare(
            self: Self,
            evidence: ValidationEvidence,
        ) Prepared(Payload) {
            return .{
                .draft_id = self.draft_id,
                .intent = self.intent,
                .snapshot = self.snapshot,
                .payload = self.payload,
                .validation = evidence,
            };
        }
    };
}

pub fn Prepared(comptime Payload: type) type {
    return struct {
        const Self = @This();

        draft_id: ids.DraftId,
        intent: Intent,
        snapshot: projection.Snapshot,
        payload: Payload,
        validation: ValidationEvidence,

        pub fn queue(self: Self, evidence: QueueEvidence) Queued(Payload) {
            return .{
                .draft_id = self.draft_id,
                .intent = self.intent,
                .snapshot = self.snapshot,
                .payload = self.payload,
                .validation = self.validation,
                .queue_evidence = evidence,
            };
        }
    };
}

pub fn Queued(comptime Payload: type) type {
    return struct {
        const Self = @This();

        draft_id: ids.DraftId,
        intent: Intent,
        snapshot: projection.Snapshot,
        payload: Payload,
        validation: ValidationEvidence,
        queue_evidence: QueueEvidence,

        pub fn acknowledge(
            self: Self,
            outcome: Outcome,
        ) Acknowledged(Payload) {
            return .{
                .draft_id = self.draft_id,
                .intent = self.intent,
                .snapshot = self.snapshot,
                .payload = self.payload,
                .validation = self.validation,
                .queue_evidence = self.queue_evidence,
                .outcome = outcome,
            };
        }
    };
}

pub fn Acknowledged(comptime Payload: type) type {
    return struct {
        draft_id: ids.DraftId,
        intent: Intent,
        snapshot: projection.Snapshot,
        payload: Payload,
        validation: ValidationEvidence,
        queue_evidence: QueueEvidence,
        outcome: Outcome,
    };
}

test "coarse typestate preserves payload, snapshot, and evidence" {
    const Payload = struct {
        amount: i64,
    };
    const effective_on = try model.Date.parseIso("2026-03-31");
    const editing: Editing(Payload) = .{
        .draft_id = try ids.DraftId.parse("draft-2551q-q1"),
        .intent = .original,
        .snapshot = projection.Snapshot.init(
            ids.FormRevision.initComptime("2551Q", "2018-01-ENCS"),
            effective_on,
        ),
        .payload = .{ .amount = 45_000_000 },
    };
    const prepared = editing.prepare(.{
        .validated_on = try model.Date.parseIso("2026-04-24"),
        .policy_revision = ids.RevisionLabel.initComptime("rules-2026-q1"),
    });
    const queued = prepared.queue(.{
        .queued_on = try model.Date.parseIso("2026-04-25"),
        .queue_reference = try ids.FilingId.parse("queue-123"),
    });
    const acknowledged = queued.acknowledge(.{ .accepted = .{
        .acknowledged_on = try model.Date.parseIso("2026-04-25"),
        .acknowledgement_reference = try ids.FilingId.parse("ack-123"),
    } });

    try std.testing.expectEqual(
        @as(i64, 45_000_000),
        acknowledged.payload.amount,
    );
    try std.testing.expectEqual(
        @as(u8, 0),
        acknowledged.snapshot.len,
    );
    try std.testing.expectEqualStrings(
        "ack-123",
        acknowledged.outcome.accepted.acknowledgement_reference.asSlice(),
    );
}

test "amendment intent retains the original filing relationship" {
    const original_id = try ids.FilingId.parse("filing-original");
    const editing: Editing(void) = .{
        .draft_id = try ids.DraftId.parse("draft-amendment"),
        .intent = .{ .amended = original_id },
        .snapshot = projection.Snapshot.init(
            ids.FormRevision.initComptime("1701Q", "2018-01-ENCS"),
            try model.Date.parseIso("2026-03-31"),
        ),
        .payload = {},
    };
    try std.testing.expectEqualStrings(
        "filing-original",
        editing.intent.amended.asSlice(),
    );
}
