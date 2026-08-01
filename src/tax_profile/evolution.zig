//! Identity-safe tax-profile evolution.
//!
//! A `ProfileId` identifies one legal taxpayer. Ordinary immutable revisions
//! may update facts about that taxpayer, but they cannot silently replace the
//! canonical TIN or cross the broad natural/juridical/estate/trust boundary.
//!
//! Grounding: `docs/core-logic/ARCHITECTURE_AND_EXECUTION_PLAN.md`,
//! sections 5.1-5.4. These rules are data-integrity boundaries; they are not
//! a legal classification engine.

const std = @import("std");
const field = @import("field.zig");
const model = @import("model.zig");

pub const Jurisdiction = enum {
    philippines,
};

pub const TaxAuthority = enum {
    bureau_of_internal_revenue,
};

/// Broad identity classes only. Business registrations and activities do not
/// turn a natural person into a juridical person.
pub const LegalPersonClass = enum {
    natural_person,
    juridical_person,
    estate,
    trust,
    reviewed_other,
};

pub const TaxpayerIdentityAnchor = struct {
    profile_id: model.ProfileId,
    jurisdiction: Jurisdiction = .philippines,
    authority: TaxAuthority = .bureau_of_internal_revenue,
    canonical_taxpayer_identifier: field.Tin,
    legal_person_class: LegalPersonClass,

    pub fn fromRevision(
        revision: *const model.ProfileRevision,
    ) TaxpayerIdentityAnchor {
        return .{
            .profile_id = revision.profile_id,
            .canonical_taxpayer_identifier = revision.identity.tin,
            .legal_person_class = legalPersonClass(&revision.subject),
        };
    }

    pub fn validateRevision(
        self: *const TaxpayerIdentityAnchor,
        revision: *const model.ProfileRevision,
    ) TransitionError!void {
        if (!self.profile_id.eql(&revision.profile_id)) {
            return error.WrongProfile;
        }
        if (!self.canonical_taxpayer_identifier.eql(
            &revision.identity.tin,
        )) {
            return error.CanonicalTaxpayerIdentifierChanged;
        }
        if (self.legal_person_class != legalPersonClass(&revision.subject)) {
            return error.LegalPersonClassChanged;
        }
    }
};

pub fn legalPersonClass(subject: *const model.Subject) LegalPersonClass {
    return switch (subject.kind()) {
        .individual, .sole_proprietor => .natural_person,
        .corporation, .partnership => .juridical_person,
        .estate => .estate,
        .trust => .trust,
        .other_legal_entity => .reviewed_other,
    };
}

pub const TransitionError = error{
    WrongProfile,
    CanonicalTaxpayerIdentifierChanged,
    LegalPersonClassChanged,
    NonIncreasingRevisionSequence,
};

/// The normal append path must call this before persistence. A rejected
/// transition is never auto-corrected: TIN corrections use an explicit audit
/// event, while a new juridical taxpayer uses a new profile.
pub fn validateOrdinaryTransition(
    anchor: *const TaxpayerIdentityAnchor,
    current: *const model.ProfileRevision,
    next: *const model.ProfileRevision,
) TransitionError!void {
    try anchor.validateRevision(current);
    try anchor.validateRevision(next);
    if (!current.profile_id.eql(&next.profile_id)) {
        return error.WrongProfile;
    }
    if (next.sequence <= current.sequence) {
        return error.NonIncreasingRevisionSequence;
    }
}

pub const IdentityCorrectionEvent = struct {
    profile_id: model.ProfileId,
    before: TaxpayerIdentityAnchor,
    after: TaxpayerIdentityAnchor,
    reason: field.SourceReference,
    actor_reference: field.SourceReference,
    provenance: field.SourceReference,
    recorded_at_unix_seconds: i64,

    pub fn validate(
        self: *const IdentityCorrectionEvent,
    ) CorrectionError!void {
        if (!self.profile_id.eql(&self.before.profile_id) or
            !self.profile_id.eql(&self.after.profile_id))
        {
            return error.WrongProfile;
        }
        if (self.before.jurisdiction != self.after.jurisdiction or
            self.before.authority != self.after.authority)
        {
            return error.AuthorityChanged;
        }
        if (self.before.canonical_taxpayer_identifier.eql(
            &self.after.canonical_taxpayer_identifier,
        ) and self.before.legal_person_class ==
            self.after.legal_person_class)
        {
            return error.NoIdentityCorrection;
        }
    }
};

pub const CorrectionError = error{
    WrongProfile,
    AuthorityChanged,
    NoIdentityCorrection,
};

/// Only states named by the approved evolution policy are executable here.
/// A wider legal-status option domain requires its own reviewed evidence.
pub const CivilStatus = enum {
    single,
    married,
};

pub const CivilStatusRevision = struct {
    profile_id: model.ProfileId,
    sequence: u32,
    effective: model.EffectivePeriod,
    status: CivilStatus,
    source: model.RevisionSource,
};

pub const CivilStatusHistoryError = error{
    EmptyHistory,
    WrongProfile,
    InvalidSequence,
    DuplicateSequence,
    NoEffectiveStatus,
};

pub const CivilStatusHistory = struct {
    profile_id: model.ProfileId,
    revisions: []const CivilStatusRevision,

    pub fn validate(
        self: *const CivilStatusHistory,
    ) CivilStatusHistoryError!void {
        if (self.revisions.len == 0) return error.EmptyHistory;
        for (self.revisions, 0..) |revision, index| {
            if (!self.profile_id.eql(&revision.profile_id)) {
                return error.WrongProfile;
            }
            if (revision.sequence == 0) return error.InvalidSequence;
            for (self.revisions[index + 1 ..]) |other| {
                if (revision.sequence == other.sequence) {
                    return error.DuplicateSequence;
                }
            }
        }
    }

    /// Corrections may overlap older effective periods. The greatest sequence
    /// effective on the requested date wins without mutating history.
    pub fn resolve(
        self: *const CivilStatusHistory,
        on: model.Date,
    ) CivilStatusHistoryError!*const CivilStatusRevision {
        try self.validate();
        var found: ?*const CivilStatusRevision = null;
        for (self.revisions) |*revision| {
            if (!revision.effective.contains(on)) continue;
            if (found == null or revision.sequence > found.?.sequence) {
                found = revision;
            }
        }
        return found orelse error.NoEffectiveStatus;
    }
};

pub const RelationshipKind = enum {
    spouse_of,
    predecessor_of,
    successor_of,
    business_converted_to,
};

pub const ProfileRelationship = struct {
    from_profile_id: model.ProfileId,
    to_profile_id: model.ProfileId,
    kind: RelationshipKind,
    effective: model.EffectivePeriod,
    provenance: field.SourceReference,

    pub fn validate(
        self: *const ProfileRelationship,
        from_anchor: *const TaxpayerIdentityAnchor,
        to_anchor: *const TaxpayerIdentityAnchor,
    ) RelationshipError!void {
        if (self.from_profile_id.eql(&self.to_profile_id)) {
            return error.SelfRelationship;
        }
        if (!self.from_profile_id.eql(&from_anchor.profile_id) or
            !self.to_profile_id.eql(&to_anchor.profile_id))
        {
            return error.AnchorMismatch;
        }
        switch (self.kind) {
            .spouse_of => {
                if (from_anchor.legal_person_class != .natural_person or
                    to_anchor.legal_person_class != .natural_person)
                {
                    return error.InvalidRelationshipClasses;
                }
            },
            .business_converted_to => {
                if (from_anchor.legal_person_class != .natural_person or
                    to_anchor.legal_person_class != .juridical_person)
                {
                    return error.InvalidRelationshipClasses;
                }
            },
            .predecessor_of, .successor_of => {},
        }
    }
};

pub const RelationshipError = error{
    SelfRelationship,
    AnchorMismatch,
    InvalidRelationshipClasses,
};

fn syntheticRevision(
    profile_id: []const u8,
    revision_id: []const u8,
    sequence: u32,
    tin: []const u8,
    subject: model.Subject,
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
            .rdo_code = try field.RdoCode.parse("019"),
        },
        .contact = .{
            .address = try field.RegisteredAddress.parse(
                "SYNTHETIC ADDRESS",
            ),
        },
        .subject = subject,
    };
}

fn syntheticPerson(name: []const u8) !model.Individual {
    return .{
        .name = try field.TaxpayerName.parse(name),
    };
}

test "individual starting a sole proprietorship remains one natural person" {
    const first = try syntheticRevision(
        "profile-natural",
        "revision-1",
        1,
        "123-456-789-000",
        .{ .individual = try syntheticPerson("SYNTHETIC PERSON") },
    );
    const second = try syntheticRevision(
        "profile-natural",
        "revision-2",
        2,
        "123-456-789-000",
        .{ .sole_proprietor = .{
            .person = try syntheticPerson("SYNTHETIC PERSON"),
            .trade_name = try field.RegisteredName.parse(
                "SYNTHETIC TRADE NAME",
            ),
        } },
    );
    const anchor = TaxpayerIdentityAnchor.fromRevision(&first);

    try validateOrdinaryTransition(&anchor, &first, &second);
    try std.testing.expectEqual(
        LegalPersonClass.natural_person,
        anchor.legal_person_class,
    );
}

test "ordinary revisions reject TIN changes and natural-to-corporation changes" {
    const natural = try syntheticRevision(
        "profile-natural",
        "revision-1",
        1,
        "123-456-789-000",
        .{ .sole_proprietor = .{
            .person = try syntheticPerson("SYNTHETIC PERSON"),
        } },
    );
    const changed_tin = try syntheticRevision(
        "profile-natural",
        "revision-2",
        2,
        "987-654-321-000",
        natural.subject,
    );
    const corporation = try syntheticRevision(
        "profile-natural",
        "revision-2",
        2,
        "123-456-789-000",
        .{ .legal_entity = .{
            .registered_name = try field.RegisteredName.parse(
                "SYNTHETIC CORPORATION",
            ),
            .kind = .corporation,
        } },
    );
    const anchor = TaxpayerIdentityAnchor.fromRevision(&natural);

    try std.testing.expectError(
        error.CanonicalTaxpayerIdentifierChanged,
        validateOrdinaryTransition(&anchor, &natural, &changed_tin),
    );
    try std.testing.expectError(
        error.LegalPersonClassChanged,
        validateOrdinaryTransition(&anchor, &natural, &corporation),
    );
}

test "single-to-married is effective dated and does not rewrite history" {
    const profile_id = try model.ProfileId.parse("profile-natural");
    const statuses = [_]CivilStatusRevision{
        .{
            .profile_id = profile_id,
            .sequence = 1,
            .effective = try model.EffectivePeriod.init(
                try model.Date.parseIso("2025-01-01"),
                null,
            ),
            .status = .single,
            .source = .manual_entry,
        },
        .{
            .profile_id = profile_id,
            .sequence = 2,
            .effective = try model.EffectivePeriod.init(
                try model.Date.parseIso("2026-06-01"),
                null,
            ),
            .status = .married,
            .source = .manual_entry,
        },
    };
    const history: CivilStatusHistory = .{
        .profile_id = profile_id,
        .revisions = &statuses,
    };

    const before = try history.resolve(
        try model.Date.parseIso("2026-05-31"),
    );
    const after = try history.resolve(
        try model.Date.parseIso("2026-06-01"),
    );
    try std.testing.expectEqual(CivilStatus.single, before.status);
    try std.testing.expectEqual(CivilStatus.married, after.status);
    try std.testing.expectEqual(CivilStatus.single, statuses[0].status);
}

test "sole proprietor conversion links a distinct corporation profile" {
    const proprietor = try syntheticRevision(
        "profile-natural",
        "revision-1",
        1,
        "123-456-789-000",
        .{ .sole_proprietor = .{
            .person = try syntheticPerson("SYNTHETIC PERSON"),
        } },
    );
    const corporation = try syntheticRevision(
        "profile-corporation",
        "revision-1",
        1,
        "987-654-321-000",
        .{ .legal_entity = .{
            .registered_name = try field.RegisteredName.parse(
                "SYNTHETIC CORPORATION",
            ),
            .kind = .corporation,
        } },
    );
    const proprietor_anchor =
        TaxpayerIdentityAnchor.fromRevision(&proprietor);
    const corporation_anchor =
        TaxpayerIdentityAnchor.fromRevision(&corporation);
    const relationship: ProfileRelationship = .{
        .from_profile_id = proprietor.profile_id,
        .to_profile_id = corporation.profile_id,
        .kind = .business_converted_to,
        .effective = try model.EffectivePeriod.init(
            try model.Date.parseIso("2026-07-01"),
            null,
        ),
        .provenance = try field.SourceReference.parse(
            "synthetic reviewed conversion",
        ),
    };

    try relationship.validate(&proprietor_anchor, &corporation_anchor);
}

test "identity corrections require an actual audited change" {
    const revision = try syntheticRevision(
        "profile-natural",
        "revision-1",
        1,
        "123-456-789-000",
        .{ .individual = try syntheticPerson("SYNTHETIC PERSON") },
    );
    const before = TaxpayerIdentityAnchor.fromRevision(&revision);
    const event: IdentityCorrectionEvent = .{
        .profile_id = revision.profile_id,
        .before = before,
        .after = before,
        .reason = try field.SourceReference.parse("synthetic correction"),
        .actor_reference = try field.SourceReference.parse(
            "synthetic actor",
        ),
        .provenance = try field.SourceReference.parse(
            "synthetic reviewed source",
        ),
        .recorded_at_unix_seconds = 1,
    };
    try std.testing.expectError(
        error.NoIdentityCorrection,
        event.validate(),
    );
}
