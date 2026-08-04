//! Closed subject/classification applicability policy for Tax Profile fields.
//!
//! UI visibility, profile validation, persistence migration review, and form
//! projection must consume this module instead of growing independent tests
//! for "individual" or "business" in each surface.

const std = @import("std");
const model = @import("model.zig");

pub const FieldGroup = enum {
    natural_person_details,
    trade_name,
    business_activities,
    line_of_business,
    registration_obligations,
};

pub const Context = struct {
    subject_kind: model.SubjectKind,
    natural_person_classification: model.NaturalPersonClassification =
        .classification_unknown,
    /// Preserves a truthful migrated activity while classification is being
    /// reviewed. It never manufactures an activity for an unknown taxpayer.
    has_business_activity: bool = false,
    /// Keeps an existing trade name reachable during classification review so
    /// the user is never trapped with a hidden value that blocks Save.
    has_trade_name: bool = false,
};

pub fn isNaturalPerson(context: Context) bool {
    return switch (context.subject_kind) {
        .individual, .sole_proprietor => true,
        .corporation,
        .partnership,
        .cooperative,
        .estate,
        .trust,
        .other_legal_entity,
        => false,
    };
}

pub fn hasBusinessCapacity(context: Context) bool {
    return switch (context.subject_kind) {
        // `sole_proprietor` remains a compatibility input while persisted
        // profiles migrate to Individual + self_employed classification.
        .sole_proprietor => true,
        .individual => switch (context.natural_person_classification) {
            .self_employed, .mixed_income => true,
            .pure_compensation => context.has_business_activity,
            .classification_unknown => context.has_business_activity,
        },
        .corporation, .partnership, .cooperative, .other_legal_entity => true,
        // The prior implementation and current form evidence do not establish
        // a generic business-activity editor for estates or trusts.
        .estate, .trust => context.has_business_activity,
    };
}

pub fn fieldGroupVisible(context: Context, group: FieldGroup) bool {
    return switch (group) {
        .natural_person_details => isNaturalPerson(context),
        .trade_name => switch (context.subject_kind) {
            .sole_proprietor => true,
            .individual => switch (context.natural_person_classification) {
                .self_employed, .mixed_income => true,
                .pure_compensation => context.has_trade_name,
                .classification_unknown => context.has_business_activity or
                    context.has_trade_name,
            },
            .corporation,
            .partnership,
            .cooperative,
            .other_legal_entity,
            => true,
            .estate, .trust => false,
        },
        .business_activities, .line_of_business => hasBusinessCapacity(context),
        // Registration obligations are meaningful for business-capable
        // taxpayers. An existing obligation keeps the section visible through
        // a migration review in the same way as an existing activity.
        .registration_obligations => hasBusinessCapacity(context),
    };
}

test "applicability enumerates every subject classification and field group" {
    inline for (std.meta.tags(model.SubjectKind)) |subject_kind| {
        inline for (std.meta.tags(model.NaturalPersonClassification)) |classification| {
            inline for (std.meta.tags(FieldGroup)) |group| {
                _ = fieldGroupVisible(.{
                    .subject_kind = subject_kind,
                    .natural_person_classification = classification,
                }, group);
            }
        }
    }
}

test "corporation hides natural-person details but exposes business facts" {
    const context: Context = .{ .subject_kind = .corporation };
    try std.testing.expect(!fieldGroupVisible(context, .natural_person_details));
    try std.testing.expect(fieldGroupVisible(context, .trade_name));
    try std.testing.expect(fieldGroupVisible(context, .line_of_business));
}

test "cooperative is juridical and exposes business profile facts" {
    const context: Context = .{ .subject_kind = .cooperative };
    try std.testing.expect(!isNaturalPerson(context));
    try std.testing.expect(fieldGroupVisible(context, .trade_name));
    try std.testing.expect(fieldGroupVisible(context, .line_of_business));
    try std.testing.expect(fieldGroupVisible(
        context,
        .registration_obligations,
    ));
}

test "self-employed and mixed-income individuals expose business facts" {
    for ([_]model.NaturalPersonClassification{
        .self_employed,
        .mixed_income,
    }) |classification| {
        const context: Context = .{
            .subject_kind = .individual,
            .natural_person_classification = classification,
        };
        try std.testing.expect(fieldGroupVisible(context, .natural_person_details));
        try std.testing.expect(fieldGroupVisible(context, .trade_name));
        try std.testing.expect(fieldGroupVisible(context, .line_of_business));
    }
}

test "pure compensation hides business facts unless migrated activity exists" {
    const clean: Context = .{
        .subject_kind = .individual,
        .natural_person_classification = .pure_compensation,
    };
    try std.testing.expect(!fieldGroupVisible(clean, .trade_name));
    try std.testing.expect(!fieldGroupVisible(clean, .line_of_business));

    const review: Context = .{
        .subject_kind = .individual,
        .natural_person_classification = .pure_compensation,
        .has_business_activity = true,
    };
    try std.testing.expect(!fieldGroupVisible(review, .trade_name));
    try std.testing.expect(fieldGroupVisible(review, .line_of_business));
}

test "existing trade name stays reachable during compensation review" {
    const review: Context = .{
        .subject_kind = .individual,
        .natural_person_classification = .pure_compensation,
        .has_trade_name = true,
    };
    try std.testing.expect(fieldGroupVisible(review, .trade_name));
}

test "classification change policy never erases existing business activity" {
    const review: Context = .{
        .subject_kind = .individual,
        .natural_person_classification = .classification_unknown,
        .has_business_activity = true,
    };
    try std.testing.expect(fieldGroupVisible(review, .business_activities));
    try std.testing.expect(fieldGroupVisible(review, .line_of_business));
}
