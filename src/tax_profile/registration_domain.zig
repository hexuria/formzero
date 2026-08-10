//! Pure taxpayer and registration-unit vocabulary.
//!
//! This module deliberately owns no storage, UI state, Forms Set preference,
//! or filing-policy decision. It establishes the identity and lifecycle facts
//! a later registration ledger and Filing Planner must consume. In particular,
//! a branch-code suggestion is not registration evidence, and a pending or
//! legacy-unresolved unit is never a filing identity.

const std = @import("std");
const domain_date = @import("../domain/date.zig");
pub const field = @import("field.zig");

pub const Date = domain_date.Date;
pub const EffectivePeriod = domain_date.EffectivePeriod;

pub const IdError = error{
    Empty,
    TooLong,
    InvalidCharacter,
};

const IdKind = enum {
    taxpayer,
    taxpayer_revision,
    registration_unit,
    registration_unit_revision,
    registration_unit_contact_revision,
    tax_type_registration,
    tax_type_registration_revision,
    registered_facility,
    registration_evidence,
    registration_evidence_review_service_actor,
    registration_evidence_review_decision,
    registration_evidence_assertion,
};

fn OpaqueId(comptime kind: IdKind) type {
    _ = kind;
    return struct {
        const Self = @This();

        bytes: [64]u8 = undefined,
        len: u8 = 0,

        pub fn parse(raw: []const u8) IdError!Self {
            const value = std.mem.trim(u8, raw, " \t\r\n");
            if (value.len == 0) return error.Empty;
            if (value.len > 64) return error.TooLong;
            for (value) |byte| {
                if (!std.ascii.isAlphanumeric(byte) and
                    byte != '-' and byte != '_' and byte != '.' and
                    byte != ':')
                {
                    return error.InvalidCharacter;
                }
            }

            var result: Self = .{};
            @memcpy(result.bytes[0..value.len], value);
            result.len = @intCast(value.len);
            return result;
        }

        pub fn asSlice(self: *const Self) []const u8 {
            return self.bytes[0..self.len];
        }

        pub fn isPresent(self: *const Self) bool {
            return self.len != 0;
        }

        pub fn eql(self: *const Self, other: *const Self) bool {
            return std.mem.eql(u8, self.asSlice(), other.asSlice());
        }
    };
}

/// Identifies one legal taxpayer. It is intentionally distinct from a
/// registration-unit ID: multiple units may belong to this taxpayer.
pub const TaxpayerId = OpaqueId(.taxpayer);
pub const TaxpayerRevisionId = OpaqueId(.taxpayer_revision);
pub const RegistrationUnitId = OpaqueId(.registration_unit);
pub const RegistrationUnitRevisionId = OpaqueId(.registration_unit_revision);
pub const RegistrationUnitContactRevisionId = OpaqueId(.registration_unit_contact_revision);
pub const TaxTypeRegistrationId = OpaqueId(.tax_type_registration);
pub const TaxTypeRegistrationRevisionId = OpaqueId(.tax_type_registration_revision);
pub const RegisteredFacilityId = OpaqueId(.registered_facility);
pub const RegistrationEvidenceId = OpaqueId(.registration_evidence);
/// Stable identity for an automated or external service that records an
/// evidence-review decision. Human/local decisions instead cite the store's
/// singleton local-owner identity.
pub const RegistrationEvidenceReviewServiceActorId =
    OpaqueId(.registration_evidence_review_service_actor);
pub const RegistrationEvidenceReviewDecisionId =
    OpaqueId(.registration_evidence_review_decision);
/// Identifies one immutable reviewed assertion about a registration fact.
/// The document metadata it cites is deliberately a different identity: one
/// COR/eCOR can substantiate several separately reviewed facts.
pub const RegistrationEvidenceAssertionId = OpaqueId(.registration_evidence_assertion);

pub const Sha256DigestError = error{
    InvalidLength,
    InvalidCharacter,
};

/// Canonical lowercase SHA-256 text used by registration evidence.
///
/// The digest is deliberately strict: callers may trim user-interface input
/// before parsing, but persisted and cross-layer values must already be the
/// exact 64-character lowercase hexadecimal representation.
pub const Sha256Digest = struct {
    bytes: [64]u8,

    pub fn parse(raw: []const u8) Sha256DigestError!Sha256Digest {
        if (raw.len != 64) return error.InvalidLength;
        for (raw) |byte| {
            if (!std.ascii.isDigit(byte) and !(byte >= 'a' and byte <= 'f')) {
                return error.InvalidCharacter;
            }
        }
        return .{ .bytes = raw[0..64].* };
    }

    pub fn asSlice(self: *const Sha256Digest) []const u8 {
        return &self.bytes;
    }

    pub fn eql(self: *const Sha256Digest, other: *const Sha256Digest) bool {
        return std.mem.eql(u8, self.asSlice(), other.asSlice());
    }
};

pub const Tin9Error = error{
    InvalidLength,
    InvalidCharacter,
};

/// The canonical nine-digit taxpayer identifier. This type intentionally does
/// not accept a combined TIN-plus-branch identifier.
pub const Tin9 = struct {
    digits: [9]u8,

    /// ASCII whitespace and hyphens are accepted only as presentation
    /// separators. Exactly nine digits must remain after normalization.
    pub fn parse(raw: []const u8) Tin9Error!Tin9 {
        var result: Tin9 = undefined;
        var length: usize = 0;
        for (raw) |byte| {
            if (std.ascii.isDigit(byte)) {
                if (length == result.digits.len) return error.InvalidLength;
                result.digits[length] = byte;
                length += 1;
            } else if (byte == '-' or std.ascii.isWhitespace(byte)) {
                continue;
            } else {
                return error.InvalidCharacter;
            }
        }
        if (length != result.digits.len) return error.InvalidLength;
        return result;
    }

    pub fn asDigits(self: *const Tin9) []const u8 {
        return &self.digits;
    }

    pub fn write(self: *const Tin9, buffer: []u8) error{NoSpaceLeft}![]const u8 {
        return std.fmt.bufPrint(
            buffer,
            "{s}-{s}-{s}",
            .{ self.digits[0..3], self.digits[3..6], self.digits[6..9] },
        );
    }

    pub fn eql(self: *const Tin9, other: *const Tin9) bool {
        return std.mem.eql(u8, self.asDigits(), other.asDigits());
    }
};

pub const BranchCode5Error = error{
    InvalidLength,
    InvalidCharacter,
};

/// The exact five-digit BIR branch code for a Registration Unit.
///
/// Parsing never pads three- or four-digit input. Those legacy suffixes must
/// use `LegacyBranchSuffix` and remain unresolved until reviewed evidence
/// establishes a five-digit code.
pub const BranchCode5 = struct {
    digits: [5]u8,

    pub fn parse(raw: []const u8) BranchCode5Error!BranchCode5 {
        const value = std.mem.trim(u8, raw, " \t\r\n");
        if (value.len != 5) return error.InvalidLength;
        for (value) |byte| {
            if (!std.ascii.isDigit(byte)) return error.InvalidCharacter;
        }
        return .{ .digits = value[0..5].* };
    }

    pub fn headOffice() BranchCode5 {
        return .{ .digits = .{ '0', '0', '0', '0', '0' } };
    }

    pub fn asDigits(self: *const BranchCode5) []const u8 {
        return &self.digits;
    }

    pub fn isHeadOffice(self: *const BranchCode5) bool {
        return self.eql(&headOffice());
    }

    pub fn eql(self: *const BranchCode5, other: *const BranchCode5) bool {
        return std.mem.eql(u8, self.asDigits(), other.asDigits());
    }
};

pub const RdoCode3Error = error{
    InvalidLength,
    InvalidCharacter,
};

/// The three-digit BIR Revenue District Office jurisdiction code. This is a
/// registration-unit fact, not a branch-code suffix or display abbreviation.
pub const RdoCode3 = struct {
    digits: [3]u8,

    pub fn parse(raw: []const u8) RdoCode3Error!RdoCode3 {
        const value = std.mem.trim(u8, raw, " \t\r\n");
        if (value.len != 3) return error.InvalidLength;
        for (value) |byte| {
            if (!std.ascii.isDigit(byte)) return error.InvalidCharacter;
        }
        return .{ .digits = value[0..3].* };
    }

    pub fn asDigits(self: *const RdoCode3) []const u8 {
        return &self.digits;
    }

    pub fn eql(self: *const RdoCode3, other: *const RdoCode3) bool {
        return std.mem.eql(u8, self.asDigits(), other.asDigits());
    }
};

pub const LegacyBranchSuffixError = error{
    InvalidLength,
    InvalidCharacter,
};

/// A legacy 3- or 4-digit suffix preserved without zero-padding. It cannot be
/// projected as a Filing Unit until reviewed evidence supplies `BranchCode5`.
pub const LegacyBranchSuffix = struct {
    digits: [4]u8 = undefined,
    len: u8 = 0,

    pub fn parse(raw: []const u8) LegacyBranchSuffixError!LegacyBranchSuffix {
        const value = std.mem.trim(u8, raw, " \t\r\n");
        if (value.len < 3 or value.len > 4) return error.InvalidLength;
        for (value) |byte| {
            if (!std.ascii.isDigit(byte)) return error.InvalidCharacter;
        }
        var result: LegacyBranchSuffix = .{};
        @memcpy(result.digits[0..value.len], value);
        result.len = @intCast(value.len);
        return result;
    }

    pub fn asDigits(self: *const LegacyBranchSuffix) []const u8 {
        return self.digits[0..self.len];
    }

    pub fn eql(
        self: *const LegacyBranchSuffix,
        other: *const LegacyBranchSuffix,
    ) bool {
        return std.mem.eql(u8, self.asDigits(), other.asDigits());
    }
};

pub const FacilityCodeError = error{
    Empty,
    TooLong,
    InvalidUtf8,
    ControlCharacter,
};

/// An opaque facility code recorded from facility evidence. Its syntax is not
/// assumed to be a five-digit branch code, and this module intentionally offers
/// no conversion from `FacilityCode` to `BranchCode5`.
pub const FacilityCode = struct {
    bytes: [64]u8 = undefined,
    len: u8 = 0,

    pub fn parse(raw: []const u8) FacilityCodeError!FacilityCode {
        const value = std.mem.trim(u8, raw, " \t\r\n");
        if (value.len == 0) return error.Empty;
        if (value.len > 64) return error.TooLong;
        if (!std.unicode.utf8ValidateSlice(value)) return error.InvalidUtf8;
        for (value) |byte| {
            if (byte < 0x20 or byte == 0x7f) return error.ControlCharacter;
        }

        var result: FacilityCode = .{};
        @memcpy(result.bytes[0..value.len], value);
        result.len = @intCast(value.len);
        return result;
    }

    pub fn asSlice(self: *const FacilityCode) []const u8 {
        return self.bytes[0..self.len];
    }

    pub fn eql(self: *const FacilityCode, other: *const FacilityCode) bool {
        return std.mem.eql(u8, self.asSlice(), other.asSlice());
    }
};

/// A display-only suggestion. Possessing one does not record a Registration
/// Command, reserve a BIR branch code, or make a unit filing-capable.
pub const BranchCodeSuggestion = struct {
    code: BranchCode5,

    pub fn isAuthoritative(_: BranchCodeSuggestion) bool {
        return false;
    }
};

/// An explicit user-entered candidate. The UI may construct this from a
/// suggestion only after the user chooses to enter it; it is still not BIR
/// confirmation.
pub const CandidateBranchCode = struct {
    code: BranchCode5,

    pub fn entered(code: BranchCode5) CandidateBranchCode {
        return .{ .code = code };
    }
};

/// Suggests the lowest unused non-head-office code from a caller-provided,
/// complete historical/current lineage. The returned value has no side effect
/// and therefore repeated calls against the same lineage return the same value.
pub fn suggestLowestUnusedBranchCode(
    occupied_lineage: []const BranchCode5,
) ?BranchCodeSuggestion {
    var candidate_number: u32 = 1;
    while (candidate_number <= 99_999) : (candidate_number += 1) {
        const candidate = branchCodeFromSuggestionNumber(candidate_number);
        var occupied = false;
        for (occupied_lineage) |existing| {
            if (candidate.eql(&existing)) {
                occupied = true;
                break;
            }
        }
        if (!occupied) return .{ .code = candidate };
    }
    return null;
}

/// This is intentionally private: it creates presentation suggestions, never
/// normalizes user-entered branch-code input.
fn branchCodeFromSuggestionNumber(value: u32) BranchCode5 {
    std.debug.assert(value > 0 and value <= 99_999);
    var digits: [5]u8 = undefined;
    _ = std.fmt.bufPrint(&digits, "{d:0>5}", .{value}) catch unreachable;
    return .{ .digits = digits };
}

pub const RegistrationUnitKind = enum {
    head_office,
    branch,
};

pub const ConfirmedBranchCode = struct {
    code: BranchCode5,
    evidence_id: RegistrationEvidenceId,
};

/// Evidence acceptance is intentionally separate from the unit lifecycle.
pub const BranchCodeEvidenceState = union(enum) {
    /// A candidate supplied by a user or migration decision. It is not a BIR
    /// Branch Code Confirmation and cannot identify a Filing Unit.
    unconfirmed: BranchCode5,
    confirmed: ConfirmedBranchCode,
    legacy_unresolved: LegacyBranchSuffix,

    pub fn knownCode(self: BranchCodeEvidenceState) ?BranchCode5 {
        return switch (self) {
            .unconfirmed => |code| code,
            .confirmed => |value| value.code,
            .legacy_unresolved => null,
        };
    }

    pub fn confirmedCode(self: BranchCodeEvidenceState) ?ConfirmedBranchCode {
        return switch (self) {
            .confirmed => |value| value,
            else => null,
        };
    }

    pub fn isConfirmed(self: BranchCodeEvidenceState) bool {
        return self.confirmedCode() != null;
    }
};

/// The effective lifecycle of a Registration Unit. It is kept separate from
/// `BranchCodeEvidenceState` so callers cannot mistake a candidate code for a
/// confirmed active registration.
pub const RegistrationUnitStatus = enum {
    pending_evidence,
    confirmed_active,
    confirmed_closed,
    legacy_unresolved,
};

pub const RegistrationError = error{
    MissingIdentifier,
    InvalidSequence,
    InvalidEffectivePeriod,
    DuplicateTaxpayerId,
    DuplicateRegistrationUnitId,
    DuplicateTaxTypeRegistrationId,
    DuplicateTaxTypeRegistration,
    UnknownTaxpayer,
    StaleTaxpayerRevision,
    StaleRegistrationUnitRevision,
    StaleRegistrationUnitContactRevision,
    RegistrationUnitContactAlreadyExists,
    InvalidRegistrationUnitContact,
    Tin9AlreadyRegistered,
    TinRootConfirmationMismatch,
    NoTinRootChange,
    MultipleEffectiveHeadOffices,
    DuplicateEffectiveBranchCode,
    BranchCodeLineageCannotBeReused,
    UnresolvedBranchCodeRequiresReview,
    HeadOfficeCodeMustBe00000,
    BranchCode00000ReservedForHeadOffice,
    PendingEvidenceRequiresUnconfirmedCode,
    ConfirmedUnitRequiresConfirmedCode,
    LegacyUnitRequiresLegacySuffix,
    EvidenceRequired,
    NotPendingEvidence,
    NotConfirmedActive,
    NotLegacyUnresolved,
    NoBranchCodeChange,
    NoJurisdictionChange,
    NonIncreasingRevisionSequence,
    StaleTaxTypeRegistrationRevision,
    TaxTypeRegistrationAnchorMismatch,
    TaxTypeRegistrationTaxTypeCannotChange,
    TaxTypeRegistrationEvidenceStateMismatch,
    TaxTypeRegistrationRequiresActiveUnit,
    NotFilingCapable,
};

/// A taxpayer identity revision only carries the canonical root. Other
/// taxpayer-wide facts belong in the taxpayer profile layer added later.
pub const TaxpayerIdentityRevision = struct {
    taxpayer_id: TaxpayerId,
    id: TaxpayerRevisionId,
    sequence: u32,
    effective: EffectivePeriod,
    tin_root: Tin9,
    /// Present after reviewed evidence confirms the TIN root, whether the
    /// confirmation preserves the observed root or an audited correction
    /// replaces it. The initial identity revision is established by taxpayer
    /// creation and therefore has no confirmation evidence.
    evidence_id: ?RegistrationEvidenceId = null,

    pub fn validate(self: *const TaxpayerIdentityRevision) RegistrationError!void {
        if (!self.taxpayer_id.isPresent() or !self.id.isPresent()) {
            return error.MissingIdentifier;
        }
        if (self.sequence == 0) return error.InvalidSequence;
        try validateEffectivePeriod(self.effective);
        if (self.evidence_id) |evidence_id| {
            if (!evidence_id.isPresent()) return error.EvidenceRequired;
        }
    }
};

/// An immutable, effective-dated Registration Unit revision. The reviewed RDO
/// is stored here; address, facility, and tax-type facts remain separate so
/// later evidence-backed revisions can own those facts explicitly.
pub const RegistrationUnitRevision = struct {
    taxpayer_id: TaxpayerId,
    registration_unit_id: RegistrationUnitId,
    id: RegistrationUnitRevisionId,
    sequence: u32,
    effective: EffectivePeriod,
    kind: RegistrationUnitKind,
    branch_code_evidence: BranchCodeEvidenceState,
    status: RegistrationUnitStatus,
    /// Effective jurisdiction. A transfer must replace this with an explicit
    /// reviewed destination; it can remain unknown on pre-transfer records.
    rdo_code: ?RdoCode3 = null,
    /// The reviewed evidence that supports this lifecycle revision (creation
    /// confirmation, closure, transfer, or branch-code correction). It is
    /// separate from the evidence that confirms the branch code itself.
    lifecycle_evidence_id: ?RegistrationEvidenceId = null,

    pub fn validate(self: *const RegistrationUnitRevision) RegistrationError!void {
        if (!self.taxpayer_id.isPresent() or
            !self.registration_unit_id.isPresent() or !self.id.isPresent())
        {
            return error.MissingIdentifier;
        }
        if (self.sequence == 0) return error.InvalidSequence;
        try validateEffectivePeriod(self.effective);

        switch (self.status) {
            .pending_evidence => switch (self.branch_code_evidence) {
                .unconfirmed => {
                    if (self.lifecycle_evidence_id != null) {
                        return error.EvidenceRequired;
                    }
                },
                else => return error.PendingEvidenceRequiresUnconfirmedCode,
            },
            .confirmed_active, .confirmed_closed => switch (self.branch_code_evidence) {
                .confirmed => |confirmation| {
                    if (!confirmation.evidence_id.isPresent()) {
                        return error.EvidenceRequired;
                    }
                    const lifecycle = self.lifecycle_evidence_id orelse
                        return error.EvidenceRequired;
                    if (!lifecycle.isPresent()) return error.EvidenceRequired;
                },
                else => return error.ConfirmedUnitRequiresConfirmedCode,
            },
            .legacy_unresolved => switch (self.branch_code_evidence) {
                .legacy_unresolved => {},
                else => return error.LegacyUnitRequiresLegacySuffix,
            },
        }

        if (self.branch_code_evidence.knownCode()) |code| {
            switch (self.kind) {
                .head_office => if (!code.isHeadOffice()) {
                    return error.HeadOfficeCodeMustBe00000;
                },
                .branch => if (code.isHeadOffice()) {
                    return error.BranchCode00000ReservedForHeadOffice;
                },
            }
        }
    }

    pub fn isFilingCapable(self: *const RegistrationUnitRevision) bool {
        return self.status == .confirmed_active and
            self.branch_code_evidence.isConfirmed();
    }

    /// Returns a filer code only for a confirmed, active Registration Unit.
    pub fn filingCode(
        self: *const RegistrationUnitRevision,
    ) RegistrationError!BranchCode5 {
        try self.validate();
        if (!self.isFilingCapable()) return error.NotFilingCapable;
        return self.branch_code_evidence.confirmedCode().?.code;
    }
};

/// Contact facts recorded for one Registration Unit. These deliberately do
/// not live on `RegistrationUnitRevision`: closure, transfer, and branch-code
/// evidence must never reassert an address or communication detail.
pub const RegistrationUnitContact = struct {
    registered_address: field.RegisteredAddress,
    zip_code: ?field.ZipCode = null,
    contact_number: ?field.ContactNumber = null,
    email_address: ?field.EmailAddress = null,

    pub fn validate(self: *const RegistrationUnitContact) RegistrationError!void {
        _ = field.RegisteredAddress.parse(self.registered_address.asSlice()) catch {
            return error.InvalidRegistrationUnitContact;
        };
        if (self.zip_code) |value| {
            _ = field.ZipCode.parse(value.asSlice()) catch {
                return error.InvalidRegistrationUnitContact;
            };
        }
        if (self.contact_number) |value| {
            _ = field.ContactNumber.parse(value.asSlice()) catch {
                return error.InvalidRegistrationUnitContact;
            };
        }
        if (self.email_address) |value| {
            _ = field.EmailAddress.parse(value.asSlice()) catch {
                return error.InvalidRegistrationUnitContact;
            };
        }
    }
};

/// One immutable, effective-dated revision in a Registration Unit's contact
/// stream. The evidence is required independently of lifecycle evidence.
pub const RegistrationUnitContactRevision = struct {
    taxpayer_id: TaxpayerId,
    registration_unit_id: RegistrationUnitId,
    id: RegistrationUnitContactRevisionId,
    sequence: u32,
    effective: EffectivePeriod,
    contact: RegistrationUnitContact,
    evidence_id: RegistrationEvidenceId,

    pub fn validate(self: *const RegistrationUnitContactRevision) RegistrationError!void {
        if (!self.taxpayer_id.isPresent() or
            !self.registration_unit_id.isPresent() or
            !self.id.isPresent())
        {
            return error.MissingIdentifier;
        }
        if (self.sequence == 0) return error.InvalidSequence;
        try validateEffectivePeriod(self.effective);
        try self.contact.validate();
        try ensureEvidenceId(self.evidence_id);
    }
};

/// The tax families presently representable by the additive ledger schema.
/// A form workspace preference never constructs one of these values.
pub const TaxType = enum {
    vat,
    percentage_tax,
    income_tax,
    withholding,
    other,
};

/// The evidence lifecycle for one effective tax-type registration. This is
/// intentionally not the same type as a Registration Unit lifecycle: an
/// active unit can still have a pending or unresolved tax registration.
pub const TaxTypeRegistrationStatus = enum {
    pending_evidence,
    confirmed_active,
    confirmed_closed,
    legacy_unresolved,
};

/// One immutable, effective-dated registration of a tax type at one
/// Registration Unit. The shell ID remains stable across revisions; a change
/// of tax family needs a distinct shell rather than rewriting history.
pub const TaxTypeRegistrationRevision = struct {
    taxpayer_id: TaxpayerId,
    registration_unit_id: RegistrationUnitId,
    registration_id: TaxTypeRegistrationId,
    id: TaxTypeRegistrationRevisionId,
    sequence: u32,
    tax_type: TaxType,
    status: TaxTypeRegistrationStatus,
    effective: EffectivePeriod,
    evidence_id: ?RegistrationEvidenceId = null,

    pub fn validate(self: *const TaxTypeRegistrationRevision) RegistrationError!void {
        if (!self.taxpayer_id.isPresent() or
            !self.registration_unit_id.isPresent() or
            !self.registration_id.isPresent() or
            !self.id.isPresent())
        {
            return error.MissingIdentifier;
        }
        if (self.sequence == 0) return error.InvalidSequence;
        try validateEffectivePeriod(self.effective);

        switch (self.status) {
            .confirmed_active, .confirmed_closed => {
                const evidence_id = self.evidence_id orelse
                    return error.TaxTypeRegistrationEvidenceStateMismatch;
                if (!evidence_id.isPresent()) {
                    return error.TaxTypeRegistrationEvidenceStateMismatch;
                }
            },
            .pending_evidence, .legacy_unresolved => {
                if (self.evidence_id != null) {
                    return error.TaxTypeRegistrationEvidenceStateMismatch;
                }
            },
        }
    }
};

pub const BranchCodeLineageEntry = struct {
    taxpayer_id: TaxpayerId,
    registration_unit_id: RegistrationUnitId,
    code: BranchCode5,
    evidence_id: RegistrationEvidenceId,

    pub fn validate(self: *const BranchCodeLineageEntry) RegistrationError!void {
        if (!self.taxpayer_id.isPresent() or
            !self.registration_unit_id.isPresent() or
            !self.evidence_id.isPresent())
        {
            return error.MissingIdentifier;
        }
    }
};

/// Inputs that a persistence adapter has already resolved for the command's
/// effective date. This pure module neither queries SQLite nor picks a current
/// revision from history on behalf of its caller.
pub const RegistrationCommandContext = struct {
    taxpayer_identity_revisions: []const TaxpayerIdentityRevision,
    effective_units: []const RegistrationUnitRevision,
    confirmed_code_lineage: []const BranchCodeLineageEntry,
    effective_tax_type_registrations: []const TaxTypeRegistrationRevision = &.{},
    effective_registration_unit_contacts: []const RegistrationUnitContactRevision = &.{},
};

pub const CreateTaxpayerCommand = struct {
    taxpayer_id: TaxpayerId,
    taxpayer_revision_id: TaxpayerRevisionId,
    tin_root: Tin9,
    effective_from: Date,
    head_office_unit_id: RegistrationUnitId,
    head_office_revision_id: RegistrationUnitRevisionId,
};

pub const TaxpayerCreated = struct {
    taxpayer_identity: TaxpayerIdentityRevision,
    head_office: RegistrationUnitRevision,
};

pub const CreateBranchCommand = struct {
    taxpayer_id: TaxpayerId,
    registration_unit_id: RegistrationUnitId,
    registration_unit_revision_id: RegistrationUnitRevisionId,
    effective_from: Date,
    candidate: CandidateBranchCode,
};

pub const UnitRevisionMetadata = struct {
    id: RegistrationUnitRevisionId,
    /// The caller's optimistic token for the full append-only unit history.
    /// The SQLite ledger validates it and assigns `sequence` inside its write
    /// transaction, so a backdated revision cannot reuse an old sequence.
    expected_history_sequence: u32 = 0,
    /// Pure-domain callers provide the exact sequence. The production ledger
    /// overwrites this value only after validating `expected_history_sequence`.
    sequence: u32,
    effective: EffectivePeriod,
};

pub const RegistrationUnitContactRevisionMetadata = struct {
    id: RegistrationUnitContactRevisionId,
    expected_history_sequence: u32 = 0,
    sequence: u32,
    effective: EffectivePeriod,
};

pub const CreateRegistrationUnitContactCommand = struct {
    taxpayer_id: TaxpayerId,
    registration_unit_id: RegistrationUnitId,
    next: RegistrationUnitContactRevisionMetadata,
    contact: RegistrationUnitContact,
    evidence_id: RegistrationEvidenceId,
};

pub const ReviseRegistrationUnitContactCommand = struct {
    current: RegistrationUnitContactRevision,
    next: RegistrationUnitContactRevisionMetadata,
    contact: RegistrationUnitContact,
    evidence_id: RegistrationEvidenceId,
};

pub const TaxpayerRevisionMetadata = struct {
    id: TaxpayerRevisionId,
    expected_history_sequence: u32 = 0,
    sequence: u32,
    effective: EffectivePeriod,
};

pub const CorrectTaxpayerTinRootCommand = struct {
    current: TaxpayerIdentityRevision,
    next: TaxpayerRevisionMetadata,
    evidence_id: RegistrationEvidenceId,
    corrected_tin_root: Tin9,
};

/// Records reviewed evidence that confirms the currently effective TIN root
/// without treating that confirmation as a correction. A later confirmation
/// appends another immutable identity revision and therefore preserves both
/// evidence events in history.
pub const ConfirmTaxpayerTinRootCommand = struct {
    current: TaxpayerIdentityRevision,
    next: TaxpayerRevisionMetadata,
    evidence_id: RegistrationEvidenceId,
    observed_tin_root: Tin9,
};

pub const CreateTaxTypeRegistrationCommand = struct {
    taxpayer_id: TaxpayerId,
    registration_unit_id: RegistrationUnitId,
    registration_id: TaxTypeRegistrationId,
    revision_id: TaxTypeRegistrationRevisionId,
    effective_from: Date,
    tax_type: TaxType,
    status: TaxTypeRegistrationStatus,
    evidence_id: ?RegistrationEvidenceId = null,
};

pub const TaxTypeRegistrationRevisionMetadata = struct {
    id: TaxTypeRegistrationRevisionId,
    expected_history_sequence: u32 = 0,
    sequence: u32,
    effective: EffectivePeriod,
};

pub const ReviseTaxTypeRegistrationCommand = struct {
    current: TaxTypeRegistrationRevision,
    next: TaxTypeRegistrationRevisionMetadata,
    status: TaxTypeRegistrationStatus,
    evidence_id: ?RegistrationEvidenceId = null,
};

pub const ReplaceCandidateBranchCodeCommand = struct {
    current: RegistrationUnitRevision,
    next: UnitRevisionMetadata,
    candidate: CandidateBranchCode,
};

pub const ConfirmRegistrationUnitCommand = struct {
    current: RegistrationUnitRevision,
    next: UnitRevisionMetadata,
    evidence_id: RegistrationEvidenceId,
    observed_code: BranchCode5,
    /// Jurisdiction observed in the same reviewed registration evidence. A
    /// null value means the accepted evidence explicitly leaves RDO unknown.
    observed_rdo_code: ?RdoCode3,
};

pub const CloseRegistrationUnitCommand = struct {
    current: RegistrationUnitRevision,
    next: UnitRevisionMetadata,
    evidence_id: RegistrationEvidenceId,
};

pub const TransferRegistrationUnitCommand = struct {
    current: RegistrationUnitRevision,
    next: UnitRevisionMetadata,
    evidence_id: RegistrationEvidenceId,
    destination_rdo_code: RdoCode3,
};

pub const CorrectBranchCodeCommand = struct {
    current: RegistrationUnitRevision,
    next: UnitRevisionMetadata,
    evidence_id: RegistrationEvidenceId,
    corrected_code: BranchCode5,
};

/// Migration-only data shape. Possessing this value is not cutover authority:
/// the production ledger rejects it until a separate reviewed authority design
/// is implemented. A legacy suffix is retained unresolved because evidence
/// cannot become a normal candidate by padding or inference.
pub const ImportLegacyRegistrationUnitCommand = struct {
    taxpayer_id: TaxpayerId,
    registration_unit_id: RegistrationUnitId,
    registration_unit_revision_id: RegistrationUnitRevisionId,
    effective_from: Date,
    kind: RegistrationUnitKind,
    suffix: LegacyBranchSuffix,
};

/// Resolves an imported legacy suffix only from an explicit reviewed code.
/// The stored suffix is neither inspected nor padded into the observed code.
pub const ResolveLegacyRegistrationUnitCommand = struct {
    current: RegistrationUnitRevision,
    next: UnitRevisionMetadata,
    evidence_id: RegistrationEvidenceId,
    observed_code: BranchCode5,
    observed_rdo_code: ?RdoCode3,
};

pub const RegistrationCommand = union(enum) {
    create_taxpayer: CreateTaxpayerCommand,
    confirm_taxpayer_tin_root: ConfirmTaxpayerTinRootCommand,
    correct_taxpayer_tin_root: CorrectTaxpayerTinRootCommand,
    create_branch: CreateBranchCommand,
    replace_candidate_branch_code: ReplaceCandidateBranchCodeCommand,
    confirm_registration_unit: ConfirmRegistrationUnitCommand,
    close_registration_unit: CloseRegistrationUnitCommand,
    transfer_registration_unit: TransferRegistrationUnitCommand,
    correct_branch_code: CorrectBranchCodeCommand,
    import_legacy_registration_unit: ImportLegacyRegistrationUnitCommand,
    resolve_legacy_registration_unit: ResolveLegacyRegistrationUnitCommand,
    create_registration_unit_contact: CreateRegistrationUnitContactCommand,
    revise_registration_unit_contact: ReviseRegistrationUnitContactCommand,
    create_tax_type_registration: CreateTaxTypeRegistrationCommand,
    revise_tax_type_registration: ReviseTaxTypeRegistrationCommand,
};

pub const RegistrationWriteResult = union(enum) {
    taxpayer_created: TaxpayerCreated,
    taxpayer_revised: TaxpayerIdentityRevision,
    unit_created: RegistrationUnitRevision,
    unit_revised: RegistrationUnitRevision,
    registration_unit_contact_created: RegistrationUnitContactRevision,
    registration_unit_contact_revised: RegistrationUnitContactRevision,
    tax_type_registration_created: TaxTypeRegistrationRevision,
    tax_type_registration_revised: TaxTypeRegistrationRevision,
};

/// Applies one domain command without mutating caller-owned state. A storage
/// adapter may persist the returned immutable revision atomically with its
/// evidence/provenance rows.
pub fn apply(
    command: RegistrationCommand,
    context: RegistrationCommandContext,
) RegistrationError!RegistrationWriteResult {
    return switch (command) {
        .create_taxpayer => |value| .{ .taxpayer_created = try createTaxpayer(
            value,
            context,
        ) },
        .confirm_taxpayer_tin_root => |value| .{
            .taxpayer_revised = try confirmTaxpayerTinRoot(value, context),
        },
        .correct_taxpayer_tin_root => |value| .{
            .taxpayer_revised = try correctTaxpayerTinRoot(value, context),
        },
        .create_branch => |value| .{ .unit_created = try createBranch(
            value,
            context,
        ) },
        .replace_candidate_branch_code => |value| .{ .unit_revised = try replaceCandidateBranchCode(value, context) },
        .confirm_registration_unit => |value| .{ .unit_revised = try confirmRegistrationUnit(value, context) },
        .close_registration_unit => |value| .{ .unit_revised = try closeRegistrationUnit(value, context) },
        .transfer_registration_unit => |value| .{ .unit_revised = try transferRegistrationUnit(value, context) },
        .correct_branch_code => |value| .{ .unit_revised = try correctBranchCode(value, context) },
        .import_legacy_registration_unit => |value| .{ .unit_created = try importLegacyRegistrationUnit(value, context) },
        .resolve_legacy_registration_unit => |value| .{ .unit_revised = try resolveLegacyRegistrationUnit(value, context) },
        .create_registration_unit_contact => |value| .{ .registration_unit_contact_created = try createRegistrationUnitContact(value, context) },
        .revise_registration_unit_contact => |value| .{ .registration_unit_contact_revised = try reviseRegistrationUnitContact(value, context) },
        .create_tax_type_registration => |value| .{ .tax_type_registration_created = try createTaxTypeRegistration(value, context) },
        .revise_tax_type_registration => |value| .{ .tax_type_registration_revised = try reviseTaxTypeRegistration(value, context) },
    };
}

fn confirmTaxpayerTinRoot(
    command: ConfirmTaxpayerTinRootCommand,
    context: RegistrationCommandContext,
) RegistrationError!TaxpayerIdentityRevision {
    try ensureCurrentTaxpayerIdentity(
        command.current,
        command.next.effective.from,
        context,
    );
    if (!command.next.id.isPresent()) return error.MissingIdentifier;
    if (command.next.sequence <= command.current.sequence) {
        return error.NonIncreasingRevisionSequence;
    }
    try validateEffectivePeriod(command.next.effective);
    try ensureEvidenceId(command.evidence_id);
    if (!command.current.tin_root.eql(&command.observed_tin_root)) {
        return error.TinRootConfirmationMismatch;
    }

    const revision: TaxpayerIdentityRevision = .{
        .taxpayer_id = command.current.taxpayer_id,
        .id = command.next.id,
        .sequence = command.next.sequence,
        .effective = command.next.effective,
        .tin_root = command.current.tin_root,
        .evidence_id = command.evidence_id,
    };
    try revision.validate();
    return revision;
}

fn correctTaxpayerTinRoot(
    command: CorrectTaxpayerTinRootCommand,
    context: RegistrationCommandContext,
) RegistrationError!TaxpayerIdentityRevision {
    try ensureCurrentTaxpayerIdentity(
        command.current,
        command.next.effective.from,
        context,
    );
    if (!command.next.id.isPresent()) return error.MissingIdentifier;
    if (command.next.sequence <= command.current.sequence) {
        return error.NonIncreasingRevisionSequence;
    }
    try validateEffectivePeriod(command.next.effective);
    try ensureEvidenceId(command.evidence_id);
    if (command.current.tin_root.eql(&command.corrected_tin_root)) {
        return error.NoTinRootChange;
    }
    for (context.taxpayer_identity_revisions) |existing| {
        if (!existing.taxpayer_id.eql(&command.current.taxpayer_id) and
            existing.tin_root.eql(&command.corrected_tin_root))
        {
            return error.Tin9AlreadyRegistered;
        }
    }

    const revision: TaxpayerIdentityRevision = .{
        .taxpayer_id = command.current.taxpayer_id,
        .id = command.next.id,
        .sequence = command.next.sequence,
        .effective = command.next.effective,
        .tin_root = command.corrected_tin_root,
        .evidence_id = command.evidence_id,
    };
    try revision.validate();
    return revision;
}

fn createTaxpayer(
    command: CreateTaxpayerCommand,
    context: RegistrationCommandContext,
) RegistrationError!TaxpayerCreated {
    const taxpayer_identity: TaxpayerIdentityRevision = .{
        .taxpayer_id = command.taxpayer_id,
        .id = command.taxpayer_revision_id,
        .sequence = 1,
        .effective = .{ .from = command.effective_from },
        .tin_root = command.tin_root,
    };
    try taxpayer_identity.validate();
    try validateContext(context, command.effective_from);
    try validateNewTaxpayerIdentity(&taxpayer_identity, context);

    const head_office: RegistrationUnitRevision = .{
        .taxpayer_id = command.taxpayer_id,
        .registration_unit_id = command.head_office_unit_id,
        .id = command.head_office_revision_id,
        .sequence = 1,
        .effective = .{ .from = command.effective_from },
        .kind = .head_office,
        .branch_code_evidence = .{ .unconfirmed = BranchCode5.headOffice() },
        .status = .pending_evidence,
    };
    try head_office.validate();
    try ensureUnitIdAvailable(
        command.head_office_unit_id,
        context.effective_units,
    );
    try ensureNoOtherHeadOffice(
        command.taxpayer_id,
        command.head_office_unit_id,
        command.effective_from,
        context.effective_units,
    );

    return .{
        .taxpayer_identity = taxpayer_identity,
        .head_office = head_office,
    };
}

fn createBranch(
    command: CreateBranchCommand,
    context: RegistrationCommandContext,
) RegistrationError!RegistrationUnitRevision {
    try validateContext(context, command.effective_from);
    try ensureKnownTaxpayer(command.taxpayer_id, context);
    try ensureUnitIdAvailable(command.registration_unit_id, context.effective_units);
    try ensureNoLegacyUnitRequiresReview(
        command.taxpayer_id,
        command.effective_from,
        null,
        context.effective_units,
    );
    const revision: RegistrationUnitRevision = .{
        .taxpayer_id = command.taxpayer_id,
        .registration_unit_id = command.registration_unit_id,
        .id = command.registration_unit_revision_id,
        .sequence = 1,
        .effective = .{ .from = command.effective_from },
        .kind = .branch,
        .branch_code_evidence = .{ .unconfirmed = command.candidate.code },
        .status = .pending_evidence,
    };
    try revision.validate();
    return revision;
}

fn replaceCandidateBranchCode(
    command: ReplaceCandidateBranchCodeCommand,
    context: RegistrationCommandContext,
) RegistrationError!RegistrationUnitRevision {
    try ensureCurrentUnit(command.current, command.next.effective.from, context);
    if (command.current.status != .pending_evidence) {
        return error.NotPendingEvidence;
    }
    const current_candidate = switch (command.current.branch_code_evidence) {
        .unconfirmed => |code| code,
        else => return error.NotPendingEvidence,
    };
    if (current_candidate.eql(&command.candidate.code)) {
        return error.NoBranchCodeChange;
    }
    try ensureNoLegacyUnitRequiresReview(
        command.current.taxpayer_id,
        command.next.effective.from,
        command.current.registration_unit_id,
        context.effective_units,
    );
    const revision = try nextUnitRevision(
        command.current,
        command.next,
        .{ .unconfirmed = command.candidate.code },
        .pending_evidence,
        command.current.rdo_code,
        null,
    );
    try revision.validate();
    return revision;
}

fn confirmRegistrationUnit(
    command: ConfirmRegistrationUnitCommand,
    context: RegistrationCommandContext,
) RegistrationError!RegistrationUnitRevision {
    try ensureCurrentUnit(command.current, command.next.effective.from, context);
    if (command.current.status != .pending_evidence) {
        return error.NotPendingEvidence;
    }
    try ensureEvidenceId(command.evidence_id);
    try ensureNoLegacyUnitRequiresReview(
        command.current.taxpayer_id,
        command.next.effective.from,
        command.current.registration_unit_id,
        context.effective_units,
    );
    try ensureCodeAvailable(
        command.current.taxpayer_id,
        command.current.registration_unit_id,
        command.observed_code,
        command.next.effective.from,
        context,
    );
    const revision = try nextUnitRevision(
        command.current,
        command.next,
        .{ .confirmed = .{
            .code = command.observed_code,
            .evidence_id = command.evidence_id,
        } },
        .confirmed_active,
        command.observed_rdo_code,
        command.evidence_id,
    );
    try revision.validate();
    return revision;
}

fn closeRegistrationUnit(
    command: CloseRegistrationUnitCommand,
    context: RegistrationCommandContext,
) RegistrationError!RegistrationUnitRevision {
    try ensureCurrentUnit(command.current, command.next.effective.from, context);
    if (command.current.status != .confirmed_active) {
        return error.NotConfirmedActive;
    }
    try ensureEvidenceId(command.evidence_id);
    const revision = try nextUnitRevision(
        command.current,
        command.next,
        command.current.branch_code_evidence,
        .confirmed_closed,
        command.current.rdo_code,
        command.evidence_id,
    );
    try revision.validate();
    return revision;
}

fn transferRegistrationUnit(
    command: TransferRegistrationUnitCommand,
    context: RegistrationCommandContext,
) RegistrationError!RegistrationUnitRevision {
    try ensureCurrentUnit(command.current, command.next.effective.from, context);
    if (command.current.status != .confirmed_active) {
        return error.NotConfirmedActive;
    }
    try ensureEvidenceId(command.evidence_id);
    if (command.current.rdo_code) |current_rdo| {
        if (current_rdo.eql(&command.destination_rdo_code)) {
            return error.NoJurisdictionChange;
        }
    }
    const revision = try nextUnitRevision(
        command.current,
        command.next,
        command.current.branch_code_evidence,
        .confirmed_active,
        command.destination_rdo_code,
        command.evidence_id,
    );
    try revision.validate();
    return revision;
}

fn correctBranchCode(
    command: CorrectBranchCodeCommand,
    context: RegistrationCommandContext,
) RegistrationError!RegistrationUnitRevision {
    try ensureCurrentUnit(command.current, command.next.effective.from, context);
    switch (command.current.status) {
        .confirmed_active, .confirmed_closed => {},
        else => return error.NotConfirmedActive,
    }
    const current_confirmation = command.current.branch_code_evidence
        .confirmedCode() orelse return error.ConfirmedUnitRequiresConfirmedCode;
    if (current_confirmation.code.eql(&command.corrected_code)) {
        return error.NoBranchCodeChange;
    }
    try ensureEvidenceId(command.evidence_id);
    try ensureNoLegacyUnitRequiresReview(
        command.current.taxpayer_id,
        command.next.effective.from,
        command.current.registration_unit_id,
        context.effective_units,
    );
    try ensureCodeAvailable(
        command.current.taxpayer_id,
        command.current.registration_unit_id,
        command.corrected_code,
        command.next.effective.from,
        context,
    );
    const revision = try nextUnitRevision(
        command.current,
        command.next,
        .{ .confirmed = .{
            .code = command.corrected_code,
            .evidence_id = command.evidence_id,
        } },
        command.current.status,
        command.current.rdo_code,
        command.evidence_id,
    );
    try revision.validate();
    return revision;
}

fn importLegacyRegistrationUnit(
    command: ImportLegacyRegistrationUnitCommand,
    context: RegistrationCommandContext,
) RegistrationError!RegistrationUnitRevision {
    try validateContext(context, command.effective_from);
    try ensureKnownTaxpayer(command.taxpayer_id, context);
    try ensureUnitIdAvailable(command.registration_unit_id, context.effective_units);
    const revision: RegistrationUnitRevision = .{
        .taxpayer_id = command.taxpayer_id,
        .registration_unit_id = command.registration_unit_id,
        .id = command.registration_unit_revision_id,
        .sequence = 1,
        .effective = .{ .from = command.effective_from },
        .kind = command.kind,
        .branch_code_evidence = .{ .legacy_unresolved = command.suffix },
        .status = .legacy_unresolved,
    };
    try revision.validate();
    return revision;
}

fn resolveLegacyRegistrationUnit(
    command: ResolveLegacyRegistrationUnitCommand,
    context: RegistrationCommandContext,
) RegistrationError!RegistrationUnitRevision {
    try ensureCurrentUnit(command.current, command.next.effective.from, context);
    if (command.current.status != .legacy_unresolved) {
        return error.NotLegacyUnresolved;
    }
    switch (command.current.branch_code_evidence) {
        .legacy_unresolved => {},
        else => return error.NotLegacyUnresolved,
    }
    try ensureEvidenceId(command.evidence_id);
    if (command.current.kind == .head_office) {
        try ensureNoOtherHeadOffice(
            command.current.taxpayer_id,
            command.current.registration_unit_id,
            command.next.effective.from,
            context.effective_units,
        );
    }
    try ensureCodeAvailable(
        command.current.taxpayer_id,
        command.current.registration_unit_id,
        command.observed_code,
        command.next.effective.from,
        context,
    );

    const revision = try nextUnitRevision(
        command.current,
        command.next,
        .{ .confirmed = .{
            .code = command.observed_code,
            .evidence_id = command.evidence_id,
        } },
        .confirmed_active,
        command.observed_rdo_code,
        command.evidence_id,
    );
    try revision.validate();
    return revision;
}

fn createRegistrationUnitContact(
    command: CreateRegistrationUnitContactCommand,
    context: RegistrationCommandContext,
) RegistrationError!RegistrationUnitContactRevision {
    try validateContext(context, command.next.effective.from);
    try ensureKnownTaxpayer(command.taxpayer_id, context);
    try ensureKnownUnit(
        command.taxpayer_id,
        command.registration_unit_id,
        command.next.effective.from,
        context.effective_units,
    );
    if (command.next.sequence != 1) return error.InvalidSequence;
    for (context.effective_registration_unit_contacts) |existing| {
        if (existing.taxpayer_id.eql(&command.taxpayer_id) and
            existing.registration_unit_id.eql(&command.registration_unit_id))
        {
            return error.RegistrationUnitContactAlreadyExists;
        }
    }

    const revision: RegistrationUnitContactRevision = .{
        .taxpayer_id = command.taxpayer_id,
        .registration_unit_id = command.registration_unit_id,
        .id = command.next.id,
        .sequence = command.next.sequence,
        .effective = command.next.effective,
        .contact = command.contact,
        .evidence_id = command.evidence_id,
    };
    try revision.validate();
    return revision;
}

fn reviseRegistrationUnitContact(
    command: ReviseRegistrationUnitContactCommand,
    context: RegistrationCommandContext,
) RegistrationError!RegistrationUnitContactRevision {
    try ensureCurrentRegistrationUnitContact(
        command.current,
        command.next.effective.from,
        context,
    );
    if (command.next.sequence <= command.current.sequence) {
        return error.NonIncreasingRevisionSequence;
    }

    const revision: RegistrationUnitContactRevision = .{
        .taxpayer_id = command.current.taxpayer_id,
        .registration_unit_id = command.current.registration_unit_id,
        .id = command.next.id,
        .sequence = command.next.sequence,
        .effective = command.next.effective,
        .contact = command.contact,
        .evidence_id = command.evidence_id,
    };
    try revision.validate();
    return revision;
}

fn createTaxTypeRegistration(
    command: CreateTaxTypeRegistrationCommand,
    context: RegistrationCommandContext,
) RegistrationError!TaxTypeRegistrationRevision {
    try validateContext(context, command.effective_from);
    try ensureKnownTaxpayer(command.taxpayer_id, context);
    try ensureKnownUnit(
        command.taxpayer_id,
        command.registration_unit_id,
        command.effective_from,
        context.effective_units,
    );
    try ensureTaxTypeRegistrationCanBeActive(
        command.taxpayer_id,
        command.registration_unit_id,
        command.effective_from,
        command.status,
        context.effective_units,
    );

    for (context.effective_tax_type_registrations) |existing| {
        if (existing.registration_id.eql(&command.registration_id)) {
            return error.DuplicateTaxTypeRegistrationId;
        }
        if (existing.registration_unit_id.eql(&command.registration_unit_id) and
            existing.tax_type == command.tax_type)
        {
            return error.DuplicateTaxTypeRegistration;
        }
    }

    const revision: TaxTypeRegistrationRevision = .{
        .taxpayer_id = command.taxpayer_id,
        .registration_unit_id = command.registration_unit_id,
        .registration_id = command.registration_id,
        .id = command.revision_id,
        .sequence = 1,
        .tax_type = command.tax_type,
        .status = command.status,
        .effective = .{ .from = command.effective_from },
        .evidence_id = command.evidence_id,
    };
    try revision.validate();
    return revision;
}

fn reviseTaxTypeRegistration(
    command: ReviseTaxTypeRegistrationCommand,
    context: RegistrationCommandContext,
) RegistrationError!TaxTypeRegistrationRevision {
    try command.current.validate();
    try validateContext(context, command.next.effective.from);

    var resolved: ?*const TaxTypeRegistrationRevision = null;
    for (context.effective_tax_type_registrations) |*effective_registration| {
        if (!command.current.registration_id.eql(&effective_registration.registration_id)) {
            continue;
        }
        if (resolved != null) return error.StaleTaxTypeRegistrationRevision;
        resolved = effective_registration;
    }
    const effective_registration = resolved orelse
        return error.StaleTaxTypeRegistrationRevision;
    if (!command.current.id.eql(&effective_registration.id) or
        command.current.sequence != effective_registration.sequence)
    {
        return error.StaleTaxTypeRegistrationRevision;
    }
    if (!command.current.taxpayer_id.eql(&effective_registration.taxpayer_id) or
        !command.current.registration_unit_id.eql(&effective_registration.registration_unit_id) or
        command.current.tax_type != effective_registration.tax_type)
    {
        return error.TaxTypeRegistrationAnchorMismatch;
    }
    if (!command.next.id.isPresent()) return error.MissingIdentifier;
    if (command.next.sequence <= command.current.sequence) {
        return error.NonIncreasingRevisionSequence;
    }
    try validateEffectivePeriod(command.next.effective);
    try ensureTaxTypeRegistrationCanBeActive(
        command.current.taxpayer_id,
        command.current.registration_unit_id,
        command.next.effective.from,
        command.status,
        context.effective_units,
    );

    const revision: TaxTypeRegistrationRevision = .{
        .taxpayer_id = command.current.taxpayer_id,
        .registration_unit_id = command.current.registration_unit_id,
        .registration_id = command.current.registration_id,
        .id = command.next.id,
        .sequence = command.next.sequence,
        .tax_type = command.current.tax_type,
        .status = command.status,
        .effective = command.next.effective,
        .evidence_id = command.evidence_id,
    };
    try revision.validate();
    return revision;
}

fn nextUnitRevision(
    current: RegistrationUnitRevision,
    metadata: UnitRevisionMetadata,
    branch_code_evidence: BranchCodeEvidenceState,
    status: RegistrationUnitStatus,
    rdo_code: ?RdoCode3,
    lifecycle_evidence_id: ?RegistrationEvidenceId,
) RegistrationError!RegistrationUnitRevision {
    try current.validate();
    if (!metadata.id.isPresent()) return error.MissingIdentifier;
    if (metadata.sequence <= current.sequence) {
        return error.NonIncreasingRevisionSequence;
    }
    try validateEffectivePeriod(metadata.effective);
    return .{
        .taxpayer_id = current.taxpayer_id,
        .registration_unit_id = current.registration_unit_id,
        .id = metadata.id,
        .sequence = metadata.sequence,
        .effective = metadata.effective,
        .kind = current.kind,
        .branch_code_evidence = branch_code_evidence,
        .status = status,
        .rdo_code = rdo_code,
        .lifecycle_evidence_id = lifecycle_evidence_id,
    };
}

fn validateContext(
    context: RegistrationCommandContext,
    at: Date,
) RegistrationError!void {
    for (context.taxpayer_identity_revisions) |existing_identity| {
        try existing_identity.validate();
    }
    try validateEffectiveUnits(context.effective_units, at);
    for (context.confirmed_code_lineage) |entry| {
        try entry.validate();
    }
    for (context.effective_tax_type_registrations) |revision| {
        try revision.validate();
    }
    for (context.effective_registration_unit_contacts) |revision| {
        try revision.validate();
    }
}

/// Validates the caller's resolved effective view. It is intentionally a
/// separate helper so a ledger can test its own snapshot logic independently.
pub fn validateEffectiveUnits(
    units: []const RegistrationUnitRevision,
    at: Date,
) RegistrationError!void {
    for (units, 0..) |left, left_index| {
        try left.validate();
        if (!left.effective.contains(at)) continue;
        for (units[left_index + 1 ..]) |right| {
            try right.validate();
            if (!right.effective.contains(at) or
                !left.taxpayer_id.eql(&right.taxpayer_id) or
                left.registration_unit_id.eql(&right.registration_unit_id))
            {
                continue;
            }
            if (left.kind == .head_office and right.kind == .head_office) {
                return error.MultipleEffectiveHeadOffices;
            }
            const left_code = left.branch_code_evidence.confirmedCode() orelse
                continue;
            const right_code = right.branch_code_evidence.confirmedCode() orelse
                continue;
            if (left_code.code.eql(&right_code.code)) {
                return error.DuplicateEffectiveBranchCode;
            }
        }
    }
}

fn validateNewTaxpayerIdentity(
    candidate: *const TaxpayerIdentityRevision,
    context: RegistrationCommandContext,
) RegistrationError!void {
    for (context.taxpayer_identity_revisions) |existing| {
        if (candidate.taxpayer_id.eql(&existing.taxpayer_id)) {
            return error.DuplicateTaxpayerId;
        }
        if (candidate.tin_root.eql(&existing.tin_root)) {
            return error.Tin9AlreadyRegistered;
        }
    }
}

fn ensureKnownTaxpayer(
    taxpayer_id: TaxpayerId,
    context: RegistrationCommandContext,
) RegistrationError!void {
    for (context.taxpayer_identity_revisions) |existing_identity| {
        if (taxpayer_id.eql(&existing_identity.taxpayer_id)) return;
    }
    return error.UnknownTaxpayer;
}

fn ensureCurrentTaxpayerIdentity(
    current: TaxpayerIdentityRevision,
    at: Date,
    context: RegistrationCommandContext,
) RegistrationError!void {
    try current.validate();
    try validateContext(context, at);

    var resolved: ?*const TaxpayerIdentityRevision = null;
    for (context.taxpayer_identity_revisions) |*effective_identity| {
        if (!current.taxpayer_id.eql(&effective_identity.taxpayer_id)) continue;
        if (resolved != null) return error.StaleTaxpayerRevision;
        resolved = effective_identity;
    }
    const effective_identity = resolved orelse return error.StaleTaxpayerRevision;
    if (!current.id.eql(&effective_identity.id) or
        current.sequence != effective_identity.sequence or
        !current.tin_root.eql(&effective_identity.tin_root))
    {
        return error.StaleTaxpayerRevision;
    }
}

fn ensureCurrentUnit(
    current: RegistrationUnitRevision,
    at: Date,
    context: RegistrationCommandContext,
) RegistrationError!void {
    try current.validate();
    try validateContext(context, at);
    try ensureKnownTaxpayer(current.taxpayer_id, context);

    var resolved: ?*const RegistrationUnitRevision = null;
    for (context.effective_units) |*effective_unit| {
        if (!current.taxpayer_id.eql(&effective_unit.taxpayer_id) or
            !current.registration_unit_id.eql(&effective_unit.registration_unit_id))
        {
            continue;
        }
        if (resolved != null) return error.StaleRegistrationUnitRevision;
        resolved = effective_unit;
    }
    const effective_unit = resolved orelse return error.StaleRegistrationUnitRevision;
    if (!current.id.eql(&effective_unit.id) or
        current.sequence != effective_unit.sequence)
    {
        return error.StaleRegistrationUnitRevision;
    }
}

fn ensureCurrentRegistrationUnitContact(
    current: RegistrationUnitContactRevision,
    at: Date,
    context: RegistrationCommandContext,
) RegistrationError!void {
    try current.validate();
    try validateContext(context, at);
    try ensureKnownUnit(
        current.taxpayer_id,
        current.registration_unit_id,
        at,
        context.effective_units,
    );

    var resolved: ?*const RegistrationUnitContactRevision = null;
    for (context.effective_registration_unit_contacts) |*effective_contact| {
        if (!current.taxpayer_id.eql(&effective_contact.taxpayer_id) or
            !current.registration_unit_id.eql(&effective_contact.registration_unit_id))
        {
            continue;
        }
        if (resolved != null) return error.StaleRegistrationUnitContactRevision;
        resolved = effective_contact;
    }
    const effective_contact = resolved orelse
        return error.StaleRegistrationUnitContactRevision;
    if (!current.id.eql(&effective_contact.id) or
        current.sequence != effective_contact.sequence)
    {
        return error.StaleRegistrationUnitContactRevision;
    }
}

fn ensureUnitIdAvailable(
    candidate: RegistrationUnitId,
    effective_units: []const RegistrationUnitRevision,
) RegistrationError!void {
    for (effective_units) |unit| {
        if (candidate.eql(&unit.registration_unit_id)) {
            return error.DuplicateRegistrationUnitId;
        }
    }
}

fn ensureKnownUnit(
    taxpayer_id: TaxpayerId,
    registration_unit_id: RegistrationUnitId,
    at: Date,
    effective_units: []const RegistrationUnitRevision,
) RegistrationError!void {
    for (effective_units) |unit| {
        if (taxpayer_id.eql(&unit.taxpayer_id) and
            registration_unit_id.eql(&unit.registration_unit_id) and
            unit.effective.contains(at))
        {
            return;
        }
    }
    return error.StaleRegistrationUnitRevision;
}

fn ensureTaxTypeRegistrationCanBeActive(
    taxpayer_id: TaxpayerId,
    registration_unit_id: RegistrationUnitId,
    at: Date,
    status: TaxTypeRegistrationStatus,
    effective_units: []const RegistrationUnitRevision,
) RegistrationError!void {
    if (status != .confirmed_active) return;

    var resolved: ?*const RegistrationUnitRevision = null;
    for (effective_units) |*unit| {
        if (taxpayer_id.eql(&unit.taxpayer_id) and
            registration_unit_id.eql(&unit.registration_unit_id) and
            unit.effective.contains(at))
        {
            if (resolved == null or
                resolved.?.effective.from.isBefore(unit.effective.from) or
                (resolved.?.effective.from.eql(unit.effective.from) and
                    resolved.?.sequence < unit.sequence))
            {
                resolved = unit;
            }
        }
    }
    const unit = resolved orelse return error.StaleRegistrationUnitRevision;
    if (unit.status != .confirmed_active) {
        return error.TaxTypeRegistrationRequiresActiveUnit;
    }
}

fn ensureNoOtherHeadOffice(
    taxpayer_id: TaxpayerId,
    registration_unit_id: RegistrationUnitId,
    at: Date,
    effective_units: []const RegistrationUnitRevision,
) RegistrationError!void {
    for (effective_units) |unit| {
        if (!unit.effective.contains(at) or
            !taxpayer_id.eql(&unit.taxpayer_id) or
            registration_unit_id.eql(&unit.registration_unit_id))
        {
            continue;
        }
        if (unit.kind == .head_office) return error.MultipleEffectiveHeadOffices;
    }
}

fn ensureNoLegacyUnitRequiresReview(
    taxpayer_id: TaxpayerId,
    at: Date,
    excluded_unit_id: ?RegistrationUnitId,
    effective_units: []const RegistrationUnitRevision,
) RegistrationError!void {
    for (effective_units) |unit| {
        if (!unit.effective.contains(at) or
            !taxpayer_id.eql(&unit.taxpayer_id))
        {
            continue;
        }
        if (excluded_unit_id) |excluded| {
            if (excluded.eql(&unit.registration_unit_id)) continue;
        }
        if (unit.status == .legacy_unresolved) {
            return error.UnresolvedBranchCodeRequiresReview;
        }
    }
}

fn ensureCodeAvailable(
    taxpayer_id: TaxpayerId,
    registration_unit_id: RegistrationUnitId,
    code: BranchCode5,
    at: Date,
    context: RegistrationCommandContext,
) RegistrationError!void {
    for (context.effective_units) |unit| {
        if (!unit.effective.contains(at) or
            !taxpayer_id.eql(&unit.taxpayer_id) or
            registration_unit_id.eql(&unit.registration_unit_id))
        {
            continue;
        }
        const existing_code = unit.branch_code_evidence.confirmedCode() orelse
            continue;
        if (code.eql(&existing_code.code)) return error.DuplicateEffectiveBranchCode;
    }
    for (context.confirmed_code_lineage) |entry| {
        if (!taxpayer_id.eql(&entry.taxpayer_id) or
            registration_unit_id.eql(&entry.registration_unit_id))
        {
            continue;
        }
        if (code.eql(&entry.code)) {
            return error.BranchCodeLineageCannotBeReused;
        }
    }
}

fn ensureEvidenceId(evidence_id: RegistrationEvidenceId) RegistrationError!void {
    if (!evidence_id.isPresent()) return error.EvidenceRequired;
}

fn validateEffectivePeriod(effective: EffectivePeriod) RegistrationError!void {
    if (effective.until) |until| {
        if (until.isBefore(effective.from)) {
            return error.InvalidEffectivePeriod;
        }
    }
}

fn date(year: u16, month: u8, day: u8) Date {
    return Date.init(year, month, day) catch unreachable;
}

fn taxpayerId(raw: []const u8) TaxpayerId {
    return TaxpayerId.parse(raw) catch unreachable;
}

fn taxpayerRevisionId(raw: []const u8) TaxpayerRevisionId {
    return TaxpayerRevisionId.parse(raw) catch unreachable;
}

fn unitId(raw: []const u8) RegistrationUnitId {
    return RegistrationUnitId.parse(raw) catch unreachable;
}

fn unitRevisionId(raw: []const u8) RegistrationUnitRevisionId {
    return RegistrationUnitRevisionId.parse(raw) catch unreachable;
}

fn evidenceId(raw: []const u8) RegistrationEvidenceId {
    return RegistrationEvidenceId.parse(raw) catch unreachable;
}

fn contextFor(
    identities: []const TaxpayerIdentityRevision,
    units: []const RegistrationUnitRevision,
    lineage: []const BranchCodeLineageEntry,
) RegistrationCommandContext {
    return .{
        .taxpayer_identity_revisions = identities,
        .effective_units = units,
        .confirmed_code_lineage = lineage,
    };
}

fn identity(taxpayer_id: TaxpayerId, tin: []const u8) TaxpayerIdentityRevision {
    return .{
        .taxpayer_id = taxpayer_id,
        .id = taxpayerRevisionId("taxpayer-revision-1"),
        .sequence = 1,
        .effective = .{ .from = date(2026, 1, 1) },
        .tin_root = Tin9.parse(tin) catch unreachable,
    };
}

fn pendingBranch(
    taxpayer_id: TaxpayerId,
    registration_unit_id: RegistrationUnitId,
    revision_id: RegistrationUnitRevisionId,
    code: []const u8,
) RegistrationUnitRevision {
    return .{
        .taxpayer_id = taxpayer_id,
        .registration_unit_id = registration_unit_id,
        .id = revision_id,
        .sequence = 1,
        .effective = .{ .from = date(2026, 1, 1) },
        .kind = .branch,
        .branch_code_evidence = .{ .unconfirmed = BranchCode5.parse(code) catch unreachable },
        .status = .pending_evidence,
    };
}

fn confirmedUnit(
    taxpayer_id: TaxpayerId,
    registration_unit_id: RegistrationUnitId,
    revision_id: RegistrationUnitRevisionId,
    kind: RegistrationUnitKind,
    code: []const u8,
    status: RegistrationUnitStatus,
) RegistrationUnitRevision {
    const evidence = evidenceId("registration-evidence-1");
    return .{
        .taxpayer_id = taxpayer_id,
        .registration_unit_id = registration_unit_id,
        .id = revision_id,
        .sequence = 1,
        .effective = .{ .from = date(2026, 1, 1) },
        .kind = kind,
        .branch_code_evidence = .{ .confirmed = .{
            .code = BranchCode5.parse(code) catch unreachable,
            .evidence_id = evidence,
        } },
        .status = status,
        .lifecycle_evidence_id = evidence,
    };
}

test "SHA-256 digest accepts only canonical lowercase hexadecimal text" {
    const raw = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef";
    const digest = try Sha256Digest.parse(raw);
    try std.testing.expectEqualStrings(raw, digest.asSlice());

    try std.testing.expectError(
        error.InvalidLength,
        Sha256Digest.parse(raw[0..63]),
    );
    try std.testing.expectError(
        error.InvalidCharacter,
        Sha256Digest.parse("0123456789ABCDEF0123456789abcdef0123456789abcdef0123456789abcdef"),
    );
}

test "Tin9 and BranchCode5 retain separate exact identity lengths" {
    const tin = try Tin9.parse("123-456-789");
    try std.testing.expectEqualStrings("123456789", tin.asDigits());
    var buffer: [11]u8 = undefined;
    try std.testing.expectEqualStrings("123-456-789", try tin.write(&buffer));

    try std.testing.expectError(
        error.InvalidLength,
        Tin9.parse("123-456-789-00000"),
    );
    try std.testing.expectEqualStrings(
        "00001",
        (try BranchCode5.parse("00001")).asDigits(),
    );
    try std.testing.expectError(error.InvalidLength, BranchCode5.parse("1"));
    try std.testing.expectError(error.InvalidLength, BranchCode5.parse("0001"));
    try std.testing.expectError(error.InvalidLength, BranchCode5.parse("000001"));
    try std.testing.expectError(error.InvalidLength, BranchCode5.parse("000-01"));
}

test "empty optional evidence cannot authorize a taxpayer filing identity" {
    var revision = identity(taxpayerId("taxpayer-1"), "123456789");
    revision.evidence_id = RegistrationEvidenceId{};

    try std.testing.expectError(error.EvidenceRequired, revision.validate());
}

test "creating a taxpayer atomically creates a pending 00000 head office" {
    const command: RegistrationCommand = .{ .create_taxpayer = .{
        .taxpayer_id = taxpayerId("taxpayer-1"),
        .taxpayer_revision_id = taxpayerRevisionId("taxpayer-revision-1"),
        .tin_root = try Tin9.parse("123456789"),
        .effective_from = date(2026, 1, 1),
        .head_office_unit_id = unitId("unit-head"),
        .head_office_revision_id = unitRevisionId("unit-head-revision-1"),
    } };
    const result = try apply(command, contextFor(&.{}, &.{}, &.{}));
    const created = switch (result) {
        .taxpayer_created => |value| value,
        else => unreachable,
    };

    try std.testing.expectEqual(RegistrationUnitKind.head_office, created.head_office.kind);
    try std.testing.expectEqual(
        RegistrationUnitStatus.pending_evidence,
        created.head_office.status,
    );
    try std.testing.expect(!created.head_office.isFilingCapable());
    try std.testing.expectError(
        error.NotFilingCapable,
        created.head_office.filingCode(),
    );
    const candidate = switch (created.head_office.branch_code_evidence) {
        .unconfirmed => |code| code,
        else => unreachable,
    };
    try std.testing.expect(candidate.isHeadOffice());
}

test "confirmation accepts the observed reviewed code before a unit becomes filing-capable" {
    const taxpayer = taxpayerId("taxpayer-1");
    const current = pendingBranch(
        taxpayer,
        unitId("unit-branch-1"),
        unitRevisionId("unit-branch-revision-1"),
        "00001",
    );
    const identities = [_]TaxpayerIdentityRevision{identity(taxpayer, "123456789")};
    const units = [_]RegistrationUnitRevision{current};
    const context = contextFor(&identities, &units, &.{});

    var missing_evidence: RegistrationEvidenceId = .{};
    _ = &missing_evidence;
    try std.testing.expectError(
        error.EvidenceRequired,
        apply(.{ .confirm_registration_unit = .{
            .current = current,
            .next = .{
                .id = unitRevisionId("unit-branch-revision-2"),
                .sequence = 2,
                .effective = .{ .from = date(2026, 2, 1) },
            },
            .evidence_id = missing_evidence,
            .observed_code = try BranchCode5.parse("00001"),
            .observed_rdo_code = null,
        } }, context),
    );

    const result = try apply(.{ .confirm_registration_unit = .{
        .current = current,
        .next = .{
            .id = unitRevisionId("unit-branch-revision-2"),
            .sequence = 2,
            .effective = .{ .from = date(2026, 2, 1) },
        },
        .evidence_id = evidenceId("evidence-1"),
        .observed_code = try BranchCode5.parse("00002"),
        .observed_rdo_code = try RdoCode3.parse("123"),
    } }, context);
    const confirmed = switch (result) {
        .unit_revised => |value| value,
        else => unreachable,
    };
    try std.testing.expectEqual(RegistrationUnitStatus.confirmed_active, confirmed.status);
    try std.testing.expect(confirmed.isFilingCapable());
    try std.testing.expectEqualStrings("00002", (try confirmed.filingCode()).asDigits());
    try std.testing.expectEqualStrings("123", confirmed.rdo_code.?.asDigits());
}

test "confirmation records an explicitly unknown reviewed RDO" {
    const taxpayer = taxpayerId("taxpayer-null-rdo");
    const current = pendingBranch(
        taxpayer,
        unitId("unit-null-rdo"),
        unitRevisionId("unit-null-rdo-revision-1"),
        "00003",
    );
    const identities = [_]TaxpayerIdentityRevision{identity(taxpayer, "987654321")};
    const units = [_]RegistrationUnitRevision{current};

    const result = try apply(.{ .confirm_registration_unit = .{
        .current = current,
        .next = .{
            .id = unitRevisionId("unit-null-rdo-revision-2"),
            .sequence = 2,
            .effective = .{ .from = date(2026, 2, 1) },
        },
        .evidence_id = evidenceId("null-rdo-confirmation-evidence"),
        .observed_code = try BranchCode5.parse("00003"),
        .observed_rdo_code = null,
    } }, contextFor(&identities, &units, &.{}));
    const confirmed = switch (result) {
        .unit_revised => |value| value,
        else => unreachable,
    };

    try std.testing.expect(confirmed.rdo_code == null);
}

test "revision commands reject stale caller facts at the command effective date" {
    const taxpayer = taxpayerId("taxpayer-1");
    const stale = pendingBranch(
        taxpayer,
        unitId("unit-branch-1"),
        unitRevisionId("unit-branch-revision-1"),
        "00001",
    );
    var effective = stale;
    effective.id = unitRevisionId("unit-branch-revision-2");
    effective.sequence = 2;
    effective.effective = .{ .from = date(2026, 2, 1) };
    effective.branch_code_evidence = .{ .unconfirmed = try BranchCode5.parse("00002") };

    const identities = [_]TaxpayerIdentityRevision{identity(taxpayer, "123456789")};
    const units = [_]RegistrationUnitRevision{effective};
    const context = contextFor(&identities, &units, &.{});

    try std.testing.expectError(
        error.StaleRegistrationUnitRevision,
        apply(.{ .confirm_registration_unit = .{
            .current = stale,
            .next = .{
                .id = unitRevisionId("unit-branch-revision-3"),
                .sequence = 3,
                .effective = .{ .from = date(2026, 3, 1) },
            },
            .evidence_id = evidenceId("confirmation-evidence"),
            .observed_code = try BranchCode5.parse("00001"),
            .observed_rdo_code = null,
        } }, context),
    );
}

test "suggestions are non-authoritative and do not reserve branch codes" {
    const head = BranchCode5.headOffice();
    const first = try BranchCode5.parse("00001");
    const occupied = [_]BranchCode5{ head, first };
    const suggestion = suggestLowestUnusedBranchCode(&occupied).?;
    const repeated = suggestLowestUnusedBranchCode(&occupied).?;

    try std.testing.expect(!suggestion.isAuthoritative());
    try std.testing.expectEqualStrings("00002", suggestion.code.asDigits());
    try std.testing.expect(suggestion.code.eql(&repeated.code));

    const candidate = CandidateBranchCode.entered(suggestion.code);
    try std.testing.expect(@TypeOf(suggestion) != @TypeOf(candidate));

    const taxpayer = taxpayerId("taxpayer-1");
    const identities = [_]TaxpayerIdentityRevision{identity(taxpayer, "123456789")};
    const result = try apply(.{ .create_branch = .{
        .taxpayer_id = taxpayer,
        .registration_unit_id = unitId("unit-branch-2"),
        .registration_unit_revision_id = unitRevisionId("unit-branch-2-revision-1"),
        .effective_from = date(2026, 1, 1),
        .candidate = candidate,
    } }, contextFor(&identities, &.{}, &.{}));
    const branch = switch (result) {
        .unit_created => |value| value,
        else => unreachable,
    };
    try std.testing.expectEqual(RegistrationUnitStatus.pending_evidence, branch.status);
    try std.testing.expect(!branch.isFilingCapable());

    const same_candidate = pendingBranch(
        taxpayer,
        unitId("unit-branch-3"),
        unitRevisionId("unit-branch-3-revision-1"),
        "00002",
    );
    const candidates = [_]RegistrationUnitRevision{ branch, same_candidate };
    try validateEffectiveUnits(&candidates, date(2026, 1, 1));
}

test "head office and branch code rules fail closed" {
    const taxpayer = taxpayerId("taxpayer-1");
    const invalid_head = confirmedUnit(
        taxpayer,
        unitId("unit-head"),
        unitRevisionId("unit-head-revision-1"),
        .head_office,
        "00001",
        .confirmed_active,
    );
    try std.testing.expectError(error.HeadOfficeCodeMustBe00000, invalid_head.validate());

    const invalid_branch = pendingBranch(
        taxpayer,
        unitId("unit-branch"),
        unitRevisionId("unit-branch-revision-1"),
        "00000",
    );
    try std.testing.expectError(
        error.BranchCode00000ReservedForHeadOffice,
        invalid_branch.validate(),
    );
}

test "facility codes remain distinct from branch codes" {
    const facility = try FacilityCode.parse("00001");
    const branch = try BranchCode5.parse("00001");
    try std.testing.expect(@TypeOf(facility) != @TypeOf(branch));
    try std.testing.expectEqualStrings("00001", facility.asSlice());
    try std.testing.expectEqualStrings("00001", branch.asDigits());
}

test "confirmed branch-code lineage blocks confirmation but not a pending candidate" {
    const taxpayer = taxpayerId("taxpayer-1");
    const identities = [_]TaxpayerIdentityRevision{identity(taxpayer, "123456789")};
    const lineage = [_]BranchCodeLineageEntry{.{
        .taxpayer_id = taxpayer,
        .registration_unit_id = unitId("closed-unit"),
        .code = try BranchCode5.parse("00001"),
        .evidence_id = evidenceId("evidence-closed"),
    }};

    const pending_result = try apply(.{ .create_branch = .{
        .taxpayer_id = taxpayer,
        .registration_unit_id = unitId("new-unit"),
        .registration_unit_revision_id = unitRevisionId("new-unit-revision-1"),
        .effective_from = date(2026, 1, 1),
        .candidate = CandidateBranchCode.entered(
            try BranchCode5.parse("00001"),
        ),
    } }, contextFor(&identities, &.{}, &lineage));
    const pending = switch (pending_result) {
        .unit_created => |value| value,
        else => unreachable,
    };
    try std.testing.expect(!pending.isFilingCapable());

    const units = [_]RegistrationUnitRevision{pending};
    try std.testing.expectError(
        error.BranchCodeLineageCannotBeReused,
        apply(.{ .confirm_registration_unit = .{
            .current = pending,
            .next = .{
                .id = unitRevisionId("new-unit-revision-2"),
                .sequence = 2,
                .effective = .{ .from = date(2026, 2, 1) },
            },
            .evidence_id = evidenceId("new-confirmation-evidence"),
            .observed_code = try BranchCode5.parse("00001"),
            .observed_rdo_code = null,
        } }, contextFor(&identities, &units, &lineage)),
    );
}

test "legacy suffixes are preserved without padding and block filing identity" {
    const three = try LegacyBranchSuffix.parse("001");
    const four = try LegacyBranchSuffix.parse("0001");
    try std.testing.expectEqualStrings("001", three.asDigits());
    try std.testing.expectEqualStrings("0001", four.asDigits());
    try std.testing.expectError(error.InvalidLength, LegacyBranchSuffix.parse("00001"));

    const taxpayer = taxpayerId("taxpayer-1");
    const legacy: RegistrationUnitRevision = .{
        .taxpayer_id = taxpayer,
        .registration_unit_id = unitId("legacy-unit"),
        .id = unitRevisionId("legacy-unit-revision-1"),
        .sequence = 1,
        .effective = .{ .from = date(2026, 1, 1) },
        .kind = .branch,
        .branch_code_evidence = .{ .legacy_unresolved = three },
        .status = .legacy_unresolved,
    };
    try legacy.validate();
    try std.testing.expect(!legacy.isFilingCapable());
    try std.testing.expectError(error.NotFilingCapable, legacy.filingCode());
}

test "unit closure and correction preserve independent effective lifecycle evidence" {
    const taxpayer = taxpayerId("taxpayer-1");
    const current = confirmedUnit(
        taxpayer,
        unitId("unit-branch-1"),
        unitRevisionId("unit-branch-revision-1"),
        .branch,
        "00001",
        .confirmed_active,
    );
    const identities = [_]TaxpayerIdentityRevision{identity(taxpayer, "123456789")};
    const units = [_]RegistrationUnitRevision{current};
    const context = contextFor(&identities, &units, &.{});

    const closed_result = try apply(.{ .close_registration_unit = .{
        .current = current,
        .next = .{
            .id = unitRevisionId("unit-branch-revision-2"),
            .sequence = 2,
            .effective = .{ .from = date(2026, 3, 1) },
        },
        .evidence_id = evidenceId("closure-evidence"),
    } }, context);
    const closed = switch (closed_result) {
        .unit_revised => |value| value,
        else => unreachable,
    };
    try std.testing.expectEqual(RegistrationUnitStatus.confirmed_closed, closed.status);
    try std.testing.expectError(error.NotFilingCapable, closed.filingCode());

    const closed_units = [_]RegistrationUnitRevision{closed};
    const closed_context = contextFor(&identities, &closed_units, &.{});
    const corrected_result = try apply(.{ .correct_branch_code = .{
        .current = closed,
        .next = .{
            .id = unitRevisionId("unit-branch-revision-3"),
            .sequence = 3,
            .effective = .{ .from = date(2026, 3, 2) },
        },
        .evidence_id = evidenceId("correction-evidence"),
        .corrected_code = try BranchCode5.parse("00002"),
    } }, closed_context);
    const corrected = switch (corrected_result) {
        .unit_revised => |value| value,
        else => unreachable,
    };
    try std.testing.expectEqual(RegistrationUnitStatus.confirmed_closed, corrected.status);
    try std.testing.expectEqualStrings(
        "00002",
        corrected.branch_code_evidence.confirmedCode().?.code.asDigits(),
    );
}

test "effective registry rejects duplicate head offices and unresolved branch ambiguity" {
    const taxpayer = taxpayerId("taxpayer-1");
    const first = confirmedUnit(
        taxpayer,
        unitId("unit-head-1"),
        unitRevisionId("unit-head-1-revision-1"),
        .head_office,
        "00000",
        .confirmed_active,
    );
    const second = confirmedUnit(
        taxpayer,
        unitId("unit-head-2"),
        unitRevisionId("unit-head-2-revision-1"),
        .head_office,
        "00000",
        .confirmed_active,
    );
    const heads = [_]RegistrationUnitRevision{ first, second };
    try std.testing.expectError(
        error.MultipleEffectiveHeadOffices,
        validateEffectiveUnits(&heads, date(2026, 1, 1)),
    );

    const identities = [_]TaxpayerIdentityRevision{identity(taxpayer, "123456789")};
    const legacy: RegistrationUnitRevision = .{
        .taxpayer_id = taxpayer,
        .registration_unit_id = unitId("legacy-unit"),
        .id = unitRevisionId("legacy-unit-revision-1"),
        .sequence = 1,
        .effective = .{ .from = date(2026, 1, 1) },
        .kind = .branch,
        .branch_code_evidence = .{ .legacy_unresolved = try LegacyBranchSuffix.parse("001") },
        .status = .legacy_unresolved,
    };
    const units = [_]RegistrationUnitRevision{legacy};
    try std.testing.expectError(
        error.UnresolvedBranchCodeRequiresReview,
        apply(.{ .create_branch = .{
            .taxpayer_id = taxpayer,
            .registration_unit_id = unitId("new-unit"),
            .registration_unit_revision_id = unitRevisionId("new-unit-revision-1"),
            .effective_from = date(2026, 1, 1),
            .candidate = CandidateBranchCode.entered(
                try BranchCode5.parse("00001"),
            ),
        } }, contextFor(&identities, &units, &.{})),
    );
}

test "TIN root correction revises the identity stream without replacing taxpayer shell" {
    const taxpayer = taxpayerId("tin-correction-taxpayer");
    const current = identity(taxpayer, "123456789");
    const identities = [_]TaxpayerIdentityRevision{current};
    const result = try apply(.{ .correct_taxpayer_tin_root = .{
        .current = current,
        .next = .{
            .id = taxpayerRevisionId("tin-correction-revision-2"),
            .sequence = 2,
            .effective = .{ .from = date(2026, 2, 1) },
        },
        .evidence_id = evidenceId("tin-correction-evidence"),
        .corrected_tin_root = try Tin9.parse("987654321"),
    } }, contextFor(&identities, &.{}, &.{}));
    const corrected = switch (result) {
        .taxpayer_revised => |value| value,
        else => unreachable,
    };
    try std.testing.expect(corrected.taxpayer_id.eql(&taxpayer));
    try std.testing.expectEqual(@as(u32, 2), corrected.sequence);
    try std.testing.expectEqualStrings("987654321", corrected.tin_root.asDigits());
    const correction_evidence = evidenceId("tin-correction-evidence");
    try std.testing.expect(corrected.evidence_id.?.eql(&correction_evidence));
}

test "TIN root confirmation appends evidence without masquerading as correction" {
    const taxpayer = taxpayerId("tin-confirmation-taxpayer");
    const current = identity(taxpayer, "123456789");
    const identities = [_]TaxpayerIdentityRevision{current};
    const context = contextFor(&identities, &.{}, &.{});
    const confirmation_evidence = evidenceId("tin-confirmation-evidence");

    const result = try apply(.{ .confirm_taxpayer_tin_root = .{
        .current = current,
        .next = .{
            .id = taxpayerRevisionId("tin-confirmation-revision-2"),
            .sequence = 2,
            .effective = .{ .from = date(2026, 2, 1) },
        },
        .evidence_id = confirmation_evidence,
        .observed_tin_root = try Tin9.parse("123456789"),
    } }, context);
    const confirmed = switch (result) {
        .taxpayer_revised => |value| value,
        else => unreachable,
    };
    try std.testing.expectEqualStrings("123456789", confirmed.tin_root.asDigits());
    try std.testing.expect(confirmed.evidence_id.?.eql(&confirmation_evidence));

    try std.testing.expectError(
        error.TinRootConfirmationMismatch,
        apply(.{ .confirm_taxpayer_tin_root = .{
            .current = current,
            .next = .{
                .id = taxpayerRevisionId("tin-confirmation-mismatch-revision"),
                .sequence = 2,
                .effective = .{ .from = date(2026, 2, 1) },
            },
            .evidence_id = evidenceId("tin-confirmation-mismatch-evidence"),
            .observed_tin_root = try Tin9.parse("987654321"),
        } }, context),
    );
    try std.testing.expectError(
        error.NoTinRootChange,
        apply(.{ .correct_taxpayer_tin_root = .{
            .current = current,
            .next = .{
                .id = taxpayerRevisionId("tin-noop-correction-revision"),
                .sequence = 2,
                .effective = .{ .from = date(2026, 2, 1) },
            },
            .evidence_id = evidenceId("tin-noop-correction-evidence"),
            .corrected_tin_root = try Tin9.parse("123456789"),
        } }, context),
    );
}

test "registration-unit transfer requires and records a changed destination RDO" {
    const taxpayer = taxpayerId("transfer-taxpayer");
    const current = confirmedUnit(
        taxpayer,
        unitId("transfer-branch"),
        unitRevisionId("transfer-branch-revision-1"),
        .branch,
        "00001",
        .confirmed_active,
    );
    const identities = [_]TaxpayerIdentityRevision{identity(taxpayer, "123456789")};
    const units = [_]RegistrationUnitRevision{current};
    const transferred_result = try apply(.{ .transfer_registration_unit = .{
        .current = current,
        .next = .{
            .id = unitRevisionId("transfer-branch-revision-2"),
            .sequence = 2,
            .effective = .{ .from = date(2026, 2, 1) },
        },
        .evidence_id = evidenceId("transfer-evidence"),
        .destination_rdo_code = try RdoCode3.parse("123"),
    } }, contextFor(&identities, &units, &.{}));
    const transferred = switch (transferred_result) {
        .unit_revised => |value| value,
        else => unreachable,
    };
    try std.testing.expectEqualStrings("123", transferred.rdo_code.?.asDigits());

    const transferred_units = [_]RegistrationUnitRevision{transferred};
    try std.testing.expectError(
        error.NoJurisdictionChange,
        apply(.{ .transfer_registration_unit = .{
            .current = transferred,
            .next = .{
                .id = unitRevisionId("transfer-branch-revision-3"),
                .sequence = 3,
                .effective = .{ .from = date(2026, 3, 1) },
            },
            .evidence_id = evidenceId("repeat-transfer-evidence"),
            .destination_rdo_code = try RdoCode3.parse("123"),
        } }, contextFor(&identities, &transferred_units, &.{})),
    );
}

test "registration-unit contact is an independent evidence-backed revision stream" {
    const taxpayer = taxpayerId("contact-taxpayer");
    const registration_unit = confirmedUnit(
        taxpayer,
        unitId("contact-unit"),
        unitRevisionId("contact-unit-revision-1"),
        .branch,
        "00017",
        .confirmed_active,
    );
    const identities = [_]TaxpayerIdentityRevision{identity(taxpayer, "123456789")};
    const units = [_]RegistrationUnitRevision{registration_unit};
    try std.testing.expectError(
        error.InvalidSequence,
        apply(.{ .create_registration_unit_contact = .{
            .taxpayer_id = taxpayer,
            .registration_unit_id = registration_unit.registration_unit_id,
            .next = .{
                .id = try RegistrationUnitContactRevisionId.parse("contact-invalid-sequence"),
                .sequence = 2,
                .effective = .{ .from = date(2026, 2, 1) },
            },
            .contact = .{
                .registered_address = try field.RegisteredAddress.parse("17 Evidence Street"),
            },
            .evidence_id = evidenceId("contact-invalid-sequence-evidence"),
        } }, contextFor(&identities, &units, &.{})),
    );
    const result = try apply(.{ .create_registration_unit_contact = .{
        .taxpayer_id = taxpayer,
        .registration_unit_id = registration_unit.registration_unit_id,
        .next = .{
            .id = try RegistrationUnitContactRevisionId.parse("contact-revision-1"),
            .sequence = 1,
            .effective = .{ .from = date(2026, 2, 1) },
        },
        .contact = .{
            .registered_address = try field.RegisteredAddress.parse("17 Evidence Street"),
            .zip_code = try field.ZipCode.parse("1200"),
            .contact_number = try field.ContactNumber.parse("+639171234567"),
            .email_address = try field.EmailAddress.parse("branch17@example.test"),
        },
        .evidence_id = evidenceId("contact-evidence-1"),
    } }, contextFor(&identities, &units, &.{}));

    const created = switch (result) {
        .registration_unit_contact_created => |value| value,
        else => unreachable,
    };
    try std.testing.expectEqual(@as(u32, 1), created.sequence);
    try std.testing.expectEqualStrings(
        "17 Evidence Street",
        created.contact.registered_address.asSlice(),
    );
    try std.testing.expectEqualStrings("1200", created.contact.zip_code.?.asSlice());
    try std.testing.expectEqualStrings(
        "+639171234567",
        created.contact.contact_number.?.asSlice(),
    );
    try std.testing.expectEqualStrings(
        "branch17@example.test",
        created.contact.email_address.?.asSlice(),
    );
}

test "registration-unit contact validation rejects invalid direct construction" {
    const valid: RegistrationUnitContact = .{
        .registered_address = try field.RegisteredAddress.parse("100 Example Street"),
        .zip_code = try field.ZipCode.parse("1000"),
        .contact_number = try field.ContactNumber.parse("+639171234567"),
        .email_address = try field.EmailAddress.parse("filing-unit@example.test"),
    };
    try valid.validate();

    var invalid_address = valid;
    invalid_address.registered_address.len = 0;
    try std.testing.expectError(
        error.InvalidRegistrationUnitContact,
        invalid_address.validate(),
    );

    var invalid_zip = valid;
    var malformed_zip = invalid_zip.zip_code.?;
    malformed_zip.digits[0] = 'X';
    invalid_zip.zip_code = malformed_zip;
    try std.testing.expectError(
        error.InvalidRegistrationUnitContact,
        invalid_zip.validate(),
    );

    var invalid_number = valid;
    var malformed_number = invalid_number.contact_number.?;
    malformed_number.bytes[0] = 'X';
    invalid_number.contact_number = malformed_number;
    try std.testing.expectError(
        error.InvalidRegistrationUnitContact,
        invalid_number.validate(),
    );

    var invalid_email = valid;
    var malformed_email = invalid_email.email_address.?;
    malformed_email.value.len = 0;
    invalid_email.email_address = malformed_email;
    try std.testing.expectError(
        error.InvalidRegistrationUnitContact,
        invalid_email.validate(),
    );
}

test "tax-type registration duplicate reports its own identity kind" {
    const taxpayer = taxpayerId("tax-type-duplicate-taxpayer");
    const registration_unit_id = unitId("tax-type-duplicate-unit");
    const registration_id = try TaxTypeRegistrationId.parse(
        "tax-type-registration-vat",
    );
    const identities = [_]TaxpayerIdentityRevision{
        identity(taxpayer, "987654321"),
    };
    const units = [_]RegistrationUnitRevision{
        confirmedUnit(
            taxpayer,
            registration_unit_id,
            unitRevisionId("tax-type-duplicate-unit-revision-1"),
            .branch,
            "00017",
            .confirmed_active,
        ),
    };
    const registrations = [_]TaxTypeRegistrationRevision{.{
        .taxpayer_id = taxpayer,
        .registration_unit_id = registration_unit_id,
        .registration_id = registration_id,
        .id = try TaxTypeRegistrationRevisionId.parse(
            "tax-type-registration-vat-revision-1",
        ),
        .sequence = 1,
        .tax_type = .vat,
        .status = .pending_evidence,
        .effective = .{ .from = date(2026, 1, 1) },
    }};

    try std.testing.expectError(
        error.DuplicateTaxTypeRegistrationId,
        apply(.{ .create_tax_type_registration = .{
            .taxpayer_id = taxpayer,
            .registration_unit_id = registration_unit_id,
            .registration_id = registration_id,
            .revision_id = try TaxTypeRegistrationRevisionId.parse(
                "tax-type-registration-vat-revision-2",
            ),
            .effective_from = date(2026, 2, 1),
            .tax_type = .vat,
            .status = .pending_evidence,
        } }, .{
            .taxpayer_identity_revisions = &identities,
            .effective_units = &units,
            .confirmed_code_lineage = &.{},
            .effective_tax_type_registrations = &registrations,
        }),
    );
    try std.testing.expectError(
        error.DuplicateTaxTypeRegistration,
        apply(.{ .create_tax_type_registration = .{
            .taxpayer_id = taxpayer,
            .registration_unit_id = registration_unit_id,
            .registration_id = try TaxTypeRegistrationId.parse(
                "another-vat-shell",
            ),
            .revision_id = try TaxTypeRegistrationRevisionId.parse(
                "another-vat-shell-revision-1",
            ),
            .effective_from = date(2026, 2, 1),
            .tax_type = .vat,
            .status = .pending_evidence,
        } }, .{
            .taxpayer_identity_revisions = &identities,
            .effective_units = &units,
            .confirmed_code_lineage = &.{},
            .effective_tax_type_registrations = &registrations,
        }),
    );
}

test "confirmed-active tax-type registration requires confirmed-active unit" {
    const taxpayer = taxpayerId("tax-type-active-unit-taxpayer");
    const registration_unit_id = unitId("tax-type-active-unit");
    const identities = [_]TaxpayerIdentityRevision{
        identity(taxpayer, "987654321"),
    };
    const blocked_units = [_]RegistrationUnitRevision{
        pendingBranch(
            taxpayer,
            registration_unit_id,
            unitRevisionId("tax-type-pending-unit-revision"),
            "00018",
        ),
        .{
            .taxpayer_id = taxpayer,
            .registration_unit_id = registration_unit_id,
            .id = unitRevisionId("tax-type-legacy-unit-revision"),
            .sequence = 1,
            .effective = .{ .from = date(2026, 1, 1) },
            .kind = .branch,
            .branch_code_evidence = .{
                .legacy_unresolved = LegacyBranchSuffix.parse("018") catch unreachable,
            },
            .status = .legacy_unresolved,
        },
        confirmedUnit(
            taxpayer,
            registration_unit_id,
            unitRevisionId("tax-type-closed-unit-revision"),
            .branch,
            "00018",
            .confirmed_closed,
        ),
    };
    const active_evidence = evidenceId("tax-type-active-unit-evidence");
    const registration_id = try TaxTypeRegistrationId.parse(
        "tax-type-active-unit-registration",
    );
    const create_command: RegistrationCommand = .{
        .create_tax_type_registration = .{
            .taxpayer_id = taxpayer,
            .registration_unit_id = registration_unit_id,
            .registration_id = registration_id,
            .revision_id = try TaxTypeRegistrationRevisionId.parse(
                "tax-type-active-unit-revision-1",
            ),
            .effective_from = date(2026, 1, 1),
            .tax_type = .vat,
            .status = .confirmed_active,
            .evidence_id = active_evidence,
        },
    };

    for (blocked_units) |blocked_unit| {
        const units = [_]RegistrationUnitRevision{blocked_unit};
        try std.testing.expectError(
            error.TaxTypeRegistrationRequiresActiveUnit,
            apply(create_command, .{
                .taxpayer_identity_revisions = &identities,
                .effective_units = &units,
                .confirmed_code_lineage = &.{},
            }),
        );
    }

    const same_day_active = confirmedUnit(
        taxpayer,
        registration_unit_id,
        unitRevisionId("tax-type-same-day-active-unit-revision"),
        .branch,
        "00018",
        .confirmed_active,
    );
    var same_day_closed = same_day_active;
    same_day_closed.id = unitRevisionId("tax-type-same-day-closed-unit-revision");
    same_day_closed.sequence = 2;
    same_day_closed.status = .confirmed_closed;
    const same_day_units = [_]RegistrationUnitRevision{
        same_day_active,
        same_day_closed,
    };
    try std.testing.expectError(
        error.TaxTypeRegistrationRequiresActiveUnit,
        apply(create_command, .{
            .taxpayer_identity_revisions = &identities,
            .effective_units = &same_day_units,
            .confirmed_code_lineage = &.{},
        }),
    );

    const pending_result = try apply(.{ .create_tax_type_registration = .{
        .taxpayer_id = taxpayer,
        .registration_unit_id = registration_unit_id,
        .registration_id = registration_id,
        .revision_id = try TaxTypeRegistrationRevisionId.parse(
            "tax-type-pending-registration-revision-1",
        ),
        .effective_from = date(2026, 1, 1),
        .tax_type = .vat,
        .status = .pending_evidence,
    } }, .{
        .taxpayer_identity_revisions = &identities,
        .effective_units = blocked_units[0..1],
        .confirmed_code_lineage = &.{},
    });
    try std.testing.expectEqual(
        TaxTypeRegistrationStatus.pending_evidence,
        pending_result.tax_type_registration_created.status,
    );

    const current: TaxTypeRegistrationRevision = .{
        .taxpayer_id = taxpayer,
        .registration_unit_id = registration_unit_id,
        .registration_id = registration_id,
        .id = try TaxTypeRegistrationRevisionId.parse(
            "tax-type-active-unit-revision-1",
        ),
        .sequence = 1,
        .tax_type = .vat,
        .status = .confirmed_active,
        .effective = .{ .from = date(2026, 1, 1) },
        .evidence_id = active_evidence,
    };
    const registrations = [_]TaxTypeRegistrationRevision{current};
    const revise_command: RegistrationCommand = .{
        .revise_tax_type_registration = .{
            .current = current,
            .next = .{
                .id = try TaxTypeRegistrationRevisionId.parse(
                    "tax-type-active-unit-revision-2",
                ),
                .sequence = 2,
                .effective = .{ .from = date(2026, 2, 1) },
            },
            .status = .confirmed_active,
            .evidence_id = active_evidence,
        },
    };

    for (blocked_units) |blocked_unit| {
        const units = [_]RegistrationUnitRevision{blocked_unit};
        try std.testing.expectError(
            error.TaxTypeRegistrationRequiresActiveUnit,
            apply(revise_command, .{
                .taxpayer_identity_revisions = &identities,
                .effective_units = &units,
                .confirmed_code_lineage = &.{},
                .effective_tax_type_registrations = &registrations,
            }),
        );
    }
}

test "legacy registration unit resolves only from explicit observed identity" {
    const taxpayer = taxpayerId("legacy-resolution-taxpayer");
    const current: RegistrationUnitRevision = .{
        .taxpayer_id = taxpayer,
        .registration_unit_id = unitId("legacy-resolution-unit"),
        .id = unitRevisionId("legacy-resolution-unit-revision-1"),
        .sequence = 1,
        .effective = .{ .from = date(2025, 1, 1) },
        .kind = .branch,
        .branch_code_evidence = .{
            .legacy_unresolved = try LegacyBranchSuffix.parse("001"),
        },
        .status = .legacy_unresolved,
    };
    const another_unresolved: RegistrationUnitRevision = .{
        .taxpayer_id = taxpayer,
        .registration_unit_id = unitId("another-legacy-unit"),
        .id = unitRevisionId("another-legacy-unit-revision-1"),
        .sequence = 1,
        .effective = .{ .from = date(2025, 1, 1) },
        .kind = .branch,
        .branch_code_evidence = .{
            .legacy_unresolved = try LegacyBranchSuffix.parse("002"),
        },
        .status = .legacy_unresolved,
    };
    const identities = [_]TaxpayerIdentityRevision{identity(taxpayer, "987654321")};
    const units = [_]RegistrationUnitRevision{ current, another_unresolved };
    const result = try apply(.{ .resolve_legacy_registration_unit = .{
        .current = current,
        .next = .{
            .id = unitRevisionId("legacy-resolution-unit-revision-2"),
            .sequence = 2,
            .effective = .{ .from = date(2026, 3, 1) },
        },
        .evidence_id = evidenceId("legacy-resolution-evidence"),
        .observed_code = try BranchCode5.parse("00019"),
        .observed_rdo_code = try RdoCode3.parse("047"),
    } }, contextFor(&identities, &units, &.{}));

    const resolved = switch (result) {
        .unit_revised => |value| value,
        else => unreachable,
    };
    try std.testing.expectEqual(RegistrationUnitStatus.confirmed_active, resolved.status);
    try std.testing.expectEqualStrings("00019", (try resolved.filingCode()).asDigits());
    try std.testing.expectEqualStrings("047", resolved.rdo_code.?.asDigits());
    try std.testing.expectEqualStrings(
        "001",
        current.branch_code_evidence.legacy_unresolved.asDigits(),
    );
}
