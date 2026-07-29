//! Typestate-style builder for complete profile revisions.
//!
//! `Start` has no `build` method. A caller must choose one truthful subject
//! variant first; `Ready` then accepts cohesive repeated components and can
//! produce a validated immutable revision. There is no giant optional field
//! bag and no placeholder/default taxpayer data.

const std = @import("std");
const model = @import("model.zig");

pub const Base = struct {
    profile_id: model.ProfileId,
    revision_id: model.RevisionId,
    sequence: u32,
    effective: model.EffectivePeriod,
    source: model.RevisionSource,
    identity: model.Identity,
    contact: model.RegisteredContact,
};

pub const Start = struct {
    base: Base,

    pub fn individual(self: Start, person: model.Individual) Ready {
        return Ready.init(self.base, .{ .individual = person });
    }

    pub fn soleProprietor(
        self: Start,
        proprietor: model.SoleProprietor,
    ) Ready {
        return Ready.init(self.base, .{ .sole_proprietor = proprietor });
    }

    pub fn legalEntity(self: Start, entity: model.LegalEntity) Ready {
        return Ready.init(self.base, .{ .legal_entity = entity });
    }
};

pub const Ready = struct {
    base: Base,
    subject: model.Subject,
    business_activities: []const model.BusinessActivity = &.{},
    registration_facts: []const model.RegistrationFact = &.{},

    fn init(base: Base, subject: model.Subject) Ready {
        return .{ .base = base, .subject = subject };
    }

    pub fn withBusinessActivities(
        self: Ready,
        activities: []const model.BusinessActivity,
    ) Ready {
        var next = self;
        next.business_activities = activities;
        return next;
    }

    pub fn withRegistrationFacts(
        self: Ready,
        facts: []const model.RegistrationFact,
    ) Ready {
        var next = self;
        next.registration_facts = facts;
        return next;
    }

    pub fn build(self: Ready) model.RevisionError!model.ProfileRevision {
        const revision: model.ProfileRevision = .{
            .profile_id = self.base.profile_id,
            .id = self.base.revision_id,
            .sequence = self.base.sequence,
            .effective = self.base.effective,
            .source = self.base.source,
            .identity = self.base.identity,
            .contact = self.base.contact,
            .subject = self.subject,
            .business_activities = self.business_activities,
            .registration_facts = self.registration_facts,
        };
        try revision.validate();
        return revision;
    }
};

pub fn begin(base: Base) Start {
    return .{ .base = base };
}

test "builder requires a subject before a revision can be built" {
    const field = @import("field.zig");
    const base: Base = .{
        .profile_id = try model.ProfileId.parse("profile-maria"),
        .revision_id = try model.RevisionId.parse("revision-1"),
        .sequence = 1,
        .effective = try model.EffectivePeriod.init(
            try model.Date.parseIso("2026-01-01"),
            null,
        ),
        .source = .manual_entry,
        .identity = .{
            .tin = try field.Tin.parse("123-456-789-000"),
            .rdo_code = try field.RdoCode.parse("019"),
        },
        .contact = .{
            .address = try field.RegisteredAddress.parse("1 Taxpayer Street"),
            .zip_code = try field.ZipCode.parse("1000"),
            .contact_number = try field.ContactNumber.parse("09171234567"),
            .email_address = try field.EmailAddress.parse("maria@example.ph"),
        },
    };
    const activity = [_]model.BusinessActivity{.{
        .id = try model.BusinessActivityId.parse("activity-retail"),
        .line_of_business = try field.LineOfBusiness.parse("Retail"),
        .atc = try field.Atc.parse("PT010"),
        .effective = try model.EffectivePeriod.init(
            try model.Date.parseIso("2026-01-01"),
            null,
        ),
    }};

    // `begin(base).build()` cannot compile: only `Ready` exposes `build`.
    const revision = try begin(base)
        .soleProprietor(.{ .person = .{
            .name = try field.TaxpayerName.parse("MARIA SANTOS"),
            .date_of_birth = try model.Date.parseIso("1995-06-01"),
            .citizenship = try field.Citizenship.parse("Filipino"),
        } })
        .withBusinessActivities(&activity)
        .build();
    try std.testing.expectEqual(@as(usize, 1), revision.business_activities.len);
}

test "builder never hides an invalid revision behind defaults" {
    const field = @import("field.zig");
    const base: Base = .{
        .profile_id = try model.ProfileId.parse("profile-corp"),
        .revision_id = try model.RevisionId.parse("revision-1"),
        .sequence = 0,
        .effective = try model.EffectivePeriod.init(
            try model.Date.parseIso("2026-01-01"),
            null,
        ),
        .source = .manual_entry,
        .identity = .{
            .tin = try field.Tin.parse("123-456-789-000"),
            .rdo_code = try field.RdoCode.parse("019"),
        },
        .contact = .{
            .address = try field.RegisteredAddress.parse("1 Corporate Way"),
            .zip_code = try field.ZipCode.parse("1000"),
            .contact_number = try field.ContactNumber.parse("81234567"),
            .email_address = try field.EmailAddress.parse("tax@corp.example"),
        },
    };
    try std.testing.expectError(
        error.InvalidSequence,
        begin(base).legalEntity(.{
            .registered_name = try field.RegisteredName.parse(
                "EXAMPLE CORPORATION",
            ),
            .kind = .corporation,
        }).build(),
    );
}
