//! Selection-independent filing identity projection.
//!
//! The existing profile projection deliberately remains the compatibility
//! path for historical drafts.  This module is the new-path seam: a filing
//! identity can only come from a resolved Filing Obligation, which owns the
//! exact effective-dated taxpayer identity revision. A workspace-selected
//! Registration Unit is separate from evidence-backed Source Attribution;
//! neither can alter the Filing Unit rendered here.

const std = @import("std");
const form_ids = @import("../forms/id.zig");
const field = @import("../tax_profile/field.zig");
const registration = @import("../tax_profile/registration_domain.zig");
const planner = @import("planner.zig");
const policy = @import("policy.zig");

pub const ContextError = error{
    ResolutionHashMismatch,
    TaxpayerIdentityInvalid,
    TaxpayerIdentityNotEffective,
    MissingFilingUnitCoverage,
    ConflictingFilingUnitCoverage,
    FilingUnitCoverageDoesNotMatchObligation,
    InvalidFilingUnitContact,
    FilingUnitContactDoesNotMatchObligation,
    FilingUnitContactNotEffective,
    FormIdentityNotRepresentable,
    UnsupportedFormRepresentation,
};

/// Exact facts needed to render the filing identity for a resolved plan.
///
/// This is deliberately not an alias for the existing `ProfileRevision`:
/// legacy profiles have no reviewed mapping to a taxpayer/registration-unit
/// pair, so accepting one here would silently make the selected profile the
/// filer. Header facts come only from the exact evidence-reviewed Filing Unit
/// revision bound into the obligation.
pub const FilingProjectionContext = struct {
    taxpayer_identity: registration.TaxpayerIdentityRevision,
    form_revision: policy.FormRevisionKey,
    civil_period: planner.CivilPeriod,
    filing_unit_id: registration.RegistrationUnitId,
    filing_unit_revision_id: registration.RegistrationUnitRevisionId,
    filing_branch_code: registration.BranchCode5,
    filing_branch_evidence_id: registration.RegistrationEvidenceId,
    filing_unit_rdo_code: ?registration.RdoCode3,
    filing_unit_contact: registration.RegistrationUnitContactRevision,

    pub fn init(
        obligation: *const planner.FilingObligation,
    ) ContextError!FilingProjectionContext {
        if (!planner.verifyResolutionHash(obligation)) {
            return error.ResolutionHashMismatch;
        }
        const taxpayer_identity = obligation.taxpayer_identity;
        taxpayer_identity.validate() catch return error.TaxpayerIdentityInvalid;
        if (!effectiveCovers(
            taxpayer_identity.effective,
            obligation.civil_period,
        )) {
            return error.TaxpayerIdentityNotEffective;
        }

        var matches: usize = 0;
        for (obligation.coverage) |coverage| {
            if (!coverage.registration_unit_id.eql(&obligation.filing_unit_id)) {
                continue;
            }
            matches += 1;
            if (!coverage.registration_unit_revision_id.eql(
                &obligation.filing_unit_revision_id,
            ) or !coverage.branch_code.eql(&obligation.filing_branch_code) or
                !coverage.branch_code_evidence_id.eql(
                    &obligation.filing_branch_evidence_id,
                ))
            {
                return error.FilingUnitCoverageDoesNotMatchObligation;
            }
        }
        if (matches == 0) return error.MissingFilingUnitCoverage;
        if (matches != 1) return error.ConflictingFilingUnitCoverage;
        obligation.filing_unit_contact.validate() catch {
            return error.InvalidFilingUnitContact;
        };
        if (!obligation.filing_unit_contact.taxpayer_id.eql(
            &taxpayer_identity.taxpayer_id,
        ) or !obligation.filing_unit_contact.registration_unit_id.eql(
            &obligation.filing_unit_id,
        )) {
            return error.FilingUnitContactDoesNotMatchObligation;
        }
        if (!effectiveCovers(
            obligation.filing_unit_contact.effective,
            obligation.civil_period,
        )) {
            return error.FilingUnitContactNotEffective;
        }

        return .{
            .taxpayer_identity = taxpayer_identity,
            .form_revision = obligation.form_revision,
            .civil_period = obligation.civil_period,
            .filing_unit_id = obligation.filing_unit_id,
            .filing_unit_revision_id = obligation.filing_unit_revision_id,
            .filing_branch_code = obligation.filing_branch_code,
            .filing_branch_evidence_id = obligation.filing_branch_evidence_id,
            .filing_unit_rdo_code = obligation.filing_unit_rdo_code,
            .filing_unit_contact = obligation.filing_unit_contact,
        };
    }

    /// Renders the 14-digit taxpayer-root plus confirmed five-digit Branch
    /// Code representation supported by the exact 2550Q 2024-04 ENCS form.
    /// It is a preview identity only: the resolved obligation remains
    /// `not_fileable` until the later header/provenance/artifact gates pass.
    pub fn rdoCode(self: *const FilingProjectionContext) ?[]const u8 {
        const value = if (self.filing_unit_rdo_code) |*item| item else return null;
        return value.asDigits();
    }

    pub fn registeredAddress(self: *const FilingProjectionContext) []const u8 {
        return self.filing_unit_contact.contact.registered_address.asSlice();
    }

    pub fn zipCode(self: *const FilingProjectionContext) ?[]const u8 {
        const value = if (self.filing_unit_contact.contact.zip_code) |*item|
            item
        else
            return null;
        return value.asSlice();
    }

    pub fn contactNumber(self: *const FilingProjectionContext) ?[]const u8 {
        const value = if (self.filing_unit_contact.contact.contact_number) |*item|
            item
        else
            return null;
        return value.asSlice();
    }

    pub fn emailAddress(self: *const FilingProjectionContext) ?[]const u8 {
        const value = if (self.filing_unit_contact.contact.email_address) |*item|
            item
        else
            return null;
        return value.asSlice();
    }

    pub fn filerTin(self: FilingProjectionContext) ContextError!field.Tin {
        const exact_2550q = form_ids.FormRevision.initComptime(
            "2550Q",
            "2024-04-ENCS",
        );
        const editor_form = try self.editorFormRevision();
        if (!editor_form.eql(&exact_2550q)) {
            return error.UnsupportedFormRepresentation;
        }

        var digits: [14]u8 = undefined;
        @memcpy(digits[0..9], self.taxpayer_identity.tin_root.asDigits());
        @memcpy(digits[9..14], self.filing_branch_code.asDigits());
        return field.Tin.parse(&digits) catch unreachable;
    }

    /// Returns the canonical form identity shared by policy and form-engine
    /// code. There is no raw-string conversion seam or second identity type.
    pub fn editorFormRevision(
        self: FilingProjectionContext,
    ) ContextError!form_ids.FormRevision {
        if (!self.form_revision.isValid()) return error.FormIdentityNotRepresentable;
        return self.form_revision;
    }
};

fn effectiveCovers(
    effective: registration.EffectivePeriod,
    period: planner.CivilPeriod,
) bool {
    if (effective.from.isAfter(period.from)) return false;
    if (effective.until) |until| {
        if (until.isBefore(period.until)) return false;
    }
    return true;
}

fn testDate(year: u16, month: u8, day: u8) registration.Date {
    return registration.Date.init(year, month, day) catch unreachable;
}

fn testId(comptime Id: type, raw: []const u8) Id {
    return Id.parse(raw) catch unreachable;
}

fn testPeriod(
    from: registration.Date,
    until: ?registration.Date,
) registration.EffectivePeriod {
    return registration.EffectivePeriod.init(from, until) catch unreachable;
}

fn testIdentity() registration.TaxpayerIdentityRevision {
    return .{
        .taxpayer_id = testId(registration.TaxpayerId, "taxpayer-a"),
        .id = testId(registration.TaxpayerRevisionId, "taxpayer-revision-a"),
        .sequence = 1,
        .effective = testPeriod(testDate(2024, 1, 1), null),
        .tin_root = registration.Tin9.parse("123456789") catch unreachable,
        .evidence_id = testId(
            registration.RegistrationEvidenceId,
            "evidence-taxpayer-tin",
        ),
    };
}

fn testObligation() !planner.FilingObligation {
    const taxpayer_id = testId(registration.TaxpayerId, "taxpayer-a");
    const head_unit_id = testId(registration.RegistrationUnitId, "unit-head");
    const branch_evidence_id = testId(
        registration.RegistrationEvidenceId,
        "branch-evidence-head",
    );
    const policy_revisions = [_]policy.FilingPolicyRevision{policy.testing.fixture2550Q()};
    const filing_planner = planner.FilingPlanner.init(.{ .revisions = &policy_revisions });
    const units = [_]registration.RegistrationUnitRevision{.{
        .taxpayer_id = taxpayer_id,
        .registration_unit_id = head_unit_id,
        .id = testId(
            registration.RegistrationUnitRevisionId,
            "unit-head-revision-a",
        ),
        .sequence = 1,
        .effective = testPeriod(testDate(2024, 1, 1), null),
        .kind = .head_office,
        .branch_code_evidence = .{ .confirmed = .{
            .code = registration.BranchCode5.headOffice(),
            .evidence_id = branch_evidence_id,
        } },
        .status = .confirmed_active,
        .lifecycle_evidence_id = branch_evidence_id,
        .rdo_code = registration.RdoCode3.parse("047") catch unreachable,
    }};
    const contacts = [_]registration.RegistrationUnitContactRevision{.{
        .taxpayer_id = taxpayer_id,
        .registration_unit_id = head_unit_id,
        .id = testId(
            registration.RegistrationUnitContactRevisionId,
            "unit-contact-revision-a",
        ),
        .sequence = 1,
        .effective = testPeriod(testDate(2024, 1, 1), null),
        .contact = .{
            .registered_address = registration.field.RegisteredAddress.parse(
                "100 Example Street",
            ) catch unreachable,
            .zip_code = registration.field.ZipCode.parse("1000") catch unreachable,
            .contact_number = registration.field.ContactNumber.parse(
                "+639171234567",
            ) catch unreachable,
            .email_address = registration.field.EmailAddress.parse(
                "filing-unit@example.test",
            ) catch unreachable,
        },
        .evidence_id = testId(
            registration.RegistrationEvidenceId,
            "unit-contact-evidence-a",
        ),
    }};
    const vat = [_]registration.TaxTypeRegistrationRevision{.{
        .taxpayer_id = taxpayer_id,
        .registration_unit_id = head_unit_id,
        .registration_id = testId(
            registration.TaxTypeRegistrationId,
            "vat-registration-a",
        ),
        .id = testId(
            registration.TaxTypeRegistrationRevisionId,
            "vat-registration-revision-a",
        ),
        .sequence = 1,
        .tax_type = .vat,
        .status = .confirmed_active,
        .effective = testPeriod(testDate(2024, 1, 1), null),
        .evidence_id = testId(registration.RegistrationEvidenceId, "vat-evidence-a"),
    }};

    const plan = try planner.testing.planForSnapshot(filing_planner, std.testing.allocator, .{
        .taxpayer_id = taxpayer_id,
        .form_revision = policy.FormRevisionKey.initComptime(
            "2550Q",
            "2024-04-ENCS",
        ),
        .civil_period = try planner.CivilPeriod.init(
            testDate(2024, 4, 1),
            testDate(2024, 6, 30),
        ),
    }, .{
        .taxpayer_identity = testIdentity(),
        .unit_revisions = &units,
        .registration_unit_contacts = &contacts,
        .tax_type_registrations = &vat,
    });
    return switch (plan) {
        .obligations => |obligations| blk: {
            if (obligations.len != 1) {
                for (obligations) |obligation| {
                    obligation.deinit(std.testing.allocator);
                }
                std.testing.allocator.free(obligations);
                return error.TestUnexpectedResult;
            }
            const obligation = obligations[0];
            std.testing.allocator.free(obligations);
            break :blk obligation;
        },
        .not_applicable => error.TestUnexpectedResult,
        .review_required => |review| {
            review.deinit(std.testing.allocator);
            return error.TestUnexpectedResult;
        },
    };
}

test "filing projection context renders a resolved 2550Q filing identity" {
    var obligation = try testObligation();
    defer obligation.deinit(std.testing.allocator);
    const context = try FilingProjectionContext.init(&obligation);
    const form = try context.editorFormRevision();
    try std.testing.expectEqualStrings("2550Q", form.code.asSlice());
    try std.testing.expectEqualStrings("2024-04-ENCS", form.revision.asSlice());
    const tin = try context.filerTin();
    try std.testing.expectEqualStrings("12345678900000", tin.asDigits());
}

test "filing projection context does not consume a newer workspace identity" {
    var obligation = try testObligation();
    defer obligation.deinit(std.testing.allocator);
    var newer_workspace_identity = testIdentity();
    newer_workspace_identity.id = testId(
        registration.TaxpayerRevisionId,
        "taxpayer-revision-newer",
    );
    newer_workspace_identity.sequence = 2;
    newer_workspace_identity.effective = testPeriod(
        testDate(2025, 1, 1),
        null,
    );
    newer_workspace_identity.tin_root = registration.Tin9.parse(
        "987654321",
    ) catch unreachable;
    try std.testing.expect(!newer_workspace_identity.id.eql(
        &obligation.taxpayer_identity.id,
    ));

    const context = try FilingProjectionContext.init(&obligation);
    const tin = try context.filerTin();
    try std.testing.expectEqualStrings("12345678900000", tin.asDigits());
}

test "filing projection context rejects a forged form revision" {
    var obligation = try testObligation();
    defer obligation.deinit(std.testing.allocator);
    obligation.form_revision = policy.FormRevisionKey.initComptime(
        "1701Q",
        "2018-01-ENCS",
    );
    try std.testing.expectError(
        error.ResolutionHashMismatch,
        FilingProjectionContext.init(&obligation),
    );
}

test "filing projection context rejects forged taxpayer TIN root" {
    var obligation = try testObligation();
    defer obligation.deinit(std.testing.allocator);
    obligation.taxpayer_identity.tin_root = registration.Tin9.parse(
        "987654321",
    ) catch unreachable;
    try std.testing.expectError(
        error.ResolutionHashMismatch,
        FilingProjectionContext.init(&obligation),
    );
}

test "filing projection context snapshots resolved obligation facts" {
    var obligation = try testObligation();
    defer obligation.deinit(std.testing.allocator);
    const context = try FilingProjectionContext.init(&obligation);
    obligation.filing_branch_code = registration.BranchCode5.parse("00001") catch unreachable;
    const tin = try context.filerTin();
    try std.testing.expectEqualStrings("12345678900000", tin.asDigits());
}

test "filing projection context retains exact RDO and contact revision facts" {
    var obligation = try testObligation();
    defer obligation.deinit(std.testing.allocator);

    const context = try FilingProjectionContext.init(&obligation);
    try std.testing.expectEqualStrings("047", context.rdoCode() orelse return error.MissingRdo);
    try std.testing.expectEqualStrings("100 Example Street", context.registeredAddress());
    try std.testing.expectEqualStrings("1000", context.zipCode() orelse return error.MissingZip);
    try std.testing.expectEqualStrings(
        "+639171234567",
        context.contactNumber() orelse return error.MissingContactNumber,
    );
    try std.testing.expectEqualStrings(
        "filing-unit@example.test",
        context.emailAddress() orelse return error.MissingEmail,
    );
    try std.testing.expectEqualStrings(
        "unit-contact-revision-a",
        context.filing_unit_contact.id.asSlice(),
    );
    try std.testing.expectEqual(@as(u32, 1), context.filing_unit_contact.sequence);
    try std.testing.expectEqual(
        testPeriod(testDate(2024, 1, 1), null),
        context.filing_unit_contact.effective,
    );
    try std.testing.expectEqualStrings(
        "unit-contact-evidence-a",
        context.filing_unit_contact.evidence_id.asSlice(),
    );
}
