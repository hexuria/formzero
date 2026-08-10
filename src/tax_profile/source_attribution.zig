//! Explicit source-unit attribution for read-only transaction workspaces.
//!
//! A workspace selection may filter records that already carry one of these
//! bindings. It must never create a binding, repair a legacy record, or choose
//! the Filing Unit. Filing scope remains the Filing Planner's responsibility.

const std = @import("std");
const registration = @import("registration_domain.zig");

pub const IdentifierError = error{
    Empty,
    TooLong,
    InvalidCharacter,
};

fn Identifier(comptime purpose: []const u8) type {
    _ = purpose;
    return struct {
        const Self = @This();

        bytes: [64]u8 = [_]u8{0} ** 64,
        len: u8 = 0,

        pub fn parse(raw: []const u8) IdentifierError!Self {
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

pub const SourceRecordId = Identifier("source record");
pub const EvidenceReference = Identifier("source evidence reference");
pub const DerivationRuleId = Identifier("source derivation rule");

/// Stable unit identity drives workspace filtering. The exact revision remains
/// bound beside it so provenance can reproduce the registration facts used
/// when the source attribution was entered or derived.
pub const SourceUnitBinding = struct {
    registration_unit_id: registration.RegistrationUnitId,
    registration_unit_revision_id: registration.RegistrationUnitRevisionId,

    pub fn eql(self: *const SourceUnitBinding, other: *const SourceUnitBinding) bool {
        return self.registration_unit_id.eql(&other.registration_unit_id) and
            self.registration_unit_revision_id.eql(&other.registration_unit_revision_id);
    }
};

pub const EnteredAttribution = struct {
    source_unit: SourceUnitBinding,
    evidence_reference: EvidenceReference,
};

pub const DerivedAttribution = struct {
    source_unit: SourceUnitBinding,
    rule_id: DerivationRuleId,
    rule_version: u32,
};

pub const LegacyUnknownReason = enum {
    missing_import_mapping,
    conflicting_source_evidence,
    historical_format_without_source_unit,

    pub fn label(self: LegacyUnknownReason) []const u8 {
        return switch (self) {
            .missing_import_mapping => "Missing import mapping",
            .conflicting_source_evidence => "Conflicting source evidence",
            .historical_format_without_source_unit => "Historical record has no Source Unit",
        };
    }
};

/// Only `entered` and `derived` records may appear under a selected source
/// workspace. `legacy_unknown` remains visible as a separate Review Required
/// count and is never silently assigned to the selected Registration Unit.
pub const Attribution = union(enum) {
    entered: EnteredAttribution,
    derived: DerivedAttribution,
    legacy_unknown: LegacyUnknownReason,

    pub fn sourceUnit(self: *const Attribution) ?*const SourceUnitBinding {
        return switch (self.*) {
            .entered => |*value| &value.source_unit,
            .derived => |*value| &value.source_unit,
            .legacy_unknown => null,
        };
    }

    pub fn methodLabel(self: *const Attribution) []const u8 {
        return switch (self.*) {
            .entered => "Entered from reviewed reference",
            .derived => "Derived by versioned rule",
            .legacy_unknown => "Legacy source unresolved",
        };
    }
};

pub const RecordKind = enum {
    transaction,
    schedule_fact,
    attachment,
    payment,

    pub fn label(self: RecordKind) []const u8 {
        return switch (self) {
            .transaction => "Transaction",
            .schedule_fact => "Schedule fact",
            .attachment => "Attachment",
            .payment => "Payment",
        };
    }
};

pub const ValidationError = error{
    EmptyRecordId,
    EmptyTaxpayerId,
    EmptyRegistrationUnitId,
    EmptyRegistrationUnitRevisionId,
    EmptyEvidenceReference,
    EmptyDerivationRuleId,
    InvalidDerivationRuleVersion,
};

/// Value-owned read-model input. It intentionally contains no filer, branch
/// selection, Forms Set preference, or Filing Plan field.
pub const SourceRecord = struct {
    id: SourceRecordId,
    taxpayer_id: registration.TaxpayerId,
    occurred_on: registration.Date,
    kind: RecordKind,
    attribution: Attribution,

    pub fn validate(self: *const SourceRecord) ValidationError!void {
        if (!self.id.isPresent()) return error.EmptyRecordId;
        if (!self.taxpayer_id.isPresent()) return error.EmptyTaxpayerId;

        switch (self.attribution) {
            .entered => |value| {
                try validateSourceUnit(&value.source_unit);
                if (!value.evidence_reference.isPresent()) {
                    return error.EmptyEvidenceReference;
                }
            },
            .derived => |value| {
                try validateSourceUnit(&value.source_unit);
                if (!value.rule_id.isPresent()) return error.EmptyDerivationRuleId;
                if (value.rule_version == 0) {
                    return error.InvalidDerivationRuleVersion;
                }
            },
            .legacy_unknown => {},
        }
    }

    pub fn belongsTo(
        self: *const SourceRecord,
        taxpayer_id: *const registration.TaxpayerId,
        registration_unit_id: *const registration.RegistrationUnitId,
    ) bool {
        if (!self.taxpayer_id.eql(taxpayer_id)) return false;
        const source_unit = self.attribution.sourceUnit() orelse return false;
        return source_unit.registration_unit_id.eql(registration_unit_id);
    }
};

/// Pure, allocation-free filter request for one source-record workspace.
/// The selected Registration Unit is only a visibility filter over attribution
/// that already exists on each record. It is never written back to a record
/// and it carries no Filing Unit authority.
pub const FilterRequest = struct {
    taxpayer_id: registration.TaxpayerId,
    registration_unit_id: registration.RegistrationUnitId,
    period: registration.EffectivePeriod,
};

pub const FilterResult = struct {
    /// Valid, explicitly attributed records that matched the request, whether
    /// or not the caller supplied enough output capacity for every row.
    matched_count: usize = 0,
    /// Number of matched records copied into `output`.
    visible_count: usize = 0,
    /// Valid records for this taxpayer and period whose source is unresolved.
    unresolved_count: usize = 0,
    /// Structurally invalid inputs. They cannot be repaired from selection.
    invalid_count: usize = 0,
    output_truncated: bool = false,
};

/// Filters source records without mutating them or invoking filing-scope
/// resolution. Legacy-unknown records are counted only for the requested
/// taxpayer and period, but never inherit the selected Registration Unit.
pub fn filterInto(
    records: []const SourceRecord,
    request: FilterRequest,
    output: []SourceRecord,
) FilterResult {
    var result: FilterResult = .{};

    for (records) |record| {
        // An invalid row only belongs to this workspace when its typed
        // taxpayer and occurrence date already place it inside the request.
        // Other taxpayers and periods are a source-load concern, not a reason
        // to contaminate this workspace's Review Required state.
        if (!record.taxpayer_id.eql(&request.taxpayer_id) or
            !request.period.contains(record.occurred_on))
        {
            continue;
        }
        record.validate() catch {
            result.invalid_count += 1;
            continue;
        };
        if (record.attribution.sourceUnit() == null) {
            result.unresolved_count += 1;
            continue;
        }
        if (!record.belongsTo(
            &request.taxpayer_id,
            &request.registration_unit_id,
        )) continue;

        result.matched_count += 1;
        if (result.visible_count == output.len) {
            result.output_truncated = true;
            continue;
        }
        output[result.visible_count] = record;
        result.visible_count += 1;
    }

    std.mem.sort(
        SourceRecord,
        output[0..result.visible_count],
        {},
        sourceRecordPrecedes,
    );
    return result;
}

fn sourceRecordPrecedes(_: void, left: SourceRecord, right: SourceRecord) bool {
    if (left.occurred_on.isBefore(right.occurred_on)) return true;
    if (right.occurred_on.isBefore(left.occurred_on)) return false;
    return std.mem.order(u8, left.id.asSlice(), right.id.asSlice()) == .lt;
}

fn validateSourceUnit(binding: *const SourceUnitBinding) ValidationError!void {
    if (!binding.registration_unit_id.isPresent()) {
        return error.EmptyRegistrationUnitId;
    }
    if (!binding.registration_unit_revision_id.isPresent()) {
        return error.EmptyRegistrationUnitRevisionId;
    }
}

test "explicit source attribution filters by stable Registration Unit identity" {
    const taxpayer_id = try registration.TaxpayerId.parse("taxpayer-a");
    const unit_id = try registration.RegistrationUnitId.parse("unit-a");
    const other_unit_id = try registration.RegistrationUnitId.parse("unit-b");
    const record = SourceRecord{
        .id = try SourceRecordId.parse("transaction-a"),
        .taxpayer_id = taxpayer_id,
        .occurred_on = try registration.Date.parseIso("2026-01-15"),
        .kind = .transaction,
        .attribution = .{ .entered = .{
            .source_unit = .{
                .registration_unit_id = unit_id,
                .registration_unit_revision_id = try registration.RegistrationUnitRevisionId.parse(
                    "unit-a-revision-1",
                ),
            },
            .evidence_reference = try EvidenceReference.parse("import-row-42"),
        } },
    };

    try record.validate();
    try std.testing.expect(record.belongsTo(&taxpayer_id, &unit_id));
    try std.testing.expect(!record.belongsTo(&taxpayer_id, &other_unit_id));
}

test "legacy unknown attribution never inherits current workspace selection" {
    const taxpayer_id = try registration.TaxpayerId.parse("taxpayer-a");
    const unit_id = try registration.RegistrationUnitId.parse("unit-a");
    const record = SourceRecord{
        .id = try SourceRecordId.parse("legacy-transaction-a"),
        .taxpayer_id = taxpayer_id,
        .occurred_on = try registration.Date.parseIso("2026-01-15"),
        .kind = .transaction,
        .attribution = .{ .legacy_unknown = .historical_format_without_source_unit },
    };

    try record.validate();
    try std.testing.expect(!record.belongsTo(&taxpayer_id, &unit_id));
}

test "source workspace filters explicit attribution by taxpayer unit and period" {
    const taxpayer_id = try registration.TaxpayerId.parse("taxpayer-a");
    const other_taxpayer_id = try registration.TaxpayerId.parse("taxpayer-b");
    const head_id = try registration.RegistrationUnitId.parse("unit-head");
    const branch_id = try registration.RegistrationUnitId.parse("unit-branch");
    const head_revision_id = try registration.RegistrationUnitRevisionId.parse(
        "unit-head-revision-1",
    );
    const branch_revision_id = try registration.RegistrationUnitRevisionId.parse(
        "unit-branch-revision-1",
    );
    const period = try registration.EffectivePeriod.init(
        try registration.Date.parseIso("2026-01-01"),
        try registration.Date.parseIso("2026-03-31"),
    );
    const records = [_]SourceRecord{
        .{
            .id = try SourceRecordId.parse("head-later"),
            .taxpayer_id = taxpayer_id,
            .occurred_on = try registration.Date.parseIso("2026-03-01"),
            .kind = .transaction,
            .attribution = .{ .entered = .{
                .source_unit = .{
                    .registration_unit_id = head_id,
                    .registration_unit_revision_id = head_revision_id,
                },
                .evidence_reference = try EvidenceReference.parse("import-2"),
            } },
        },
        .{
            .id = try SourceRecordId.parse("head-earlier"),
            .taxpayer_id = taxpayer_id,
            .occurred_on = try registration.Date.parseIso("2026-01-15"),
            .kind = .schedule_fact,
            .attribution = .{ .derived = .{
                .source_unit = .{
                    .registration_unit_id = head_id,
                    .registration_unit_revision_id = head_revision_id,
                },
                .rule_id = try DerivationRuleId.parse("import-location"),
                .rule_version = 1,
            } },
        },
        .{
            .id = try SourceRecordId.parse("branch-record"),
            .taxpayer_id = taxpayer_id,
            .occurred_on = try registration.Date.parseIso("2026-02-01"),
            .kind = .payment,
            .attribution = .{ .entered = .{
                .source_unit = .{
                    .registration_unit_id = branch_id,
                    .registration_unit_revision_id = branch_revision_id,
                },
                .evidence_reference = try EvidenceReference.parse("import-3"),
            } },
        },
        .{
            .id = try SourceRecordId.parse("legacy-record"),
            .taxpayer_id = taxpayer_id,
            .occurred_on = try registration.Date.parseIso("2026-02-10"),
            .kind = .attachment,
            .attribution = .{ .legacy_unknown = .missing_import_mapping },
        },
        .{
            .id = try SourceRecordId.parse("other-taxpayer"),
            .taxpayer_id = other_taxpayer_id,
            .occurred_on = try registration.Date.parseIso("2026-02-10"),
            .kind = .transaction,
            .attribution = .{ .legacy_unknown = .missing_import_mapping },
        },
        .{
            .id = try SourceRecordId.parse("outside-period"),
            .taxpayer_id = taxpayer_id,
            .occurred_on = try registration.Date.parseIso("2026-04-01"),
            .kind = .transaction,
            .attribution = .{ .legacy_unknown = .missing_import_mapping },
        },
    };

    var output: [records.len]SourceRecord = undefined;
    const result = filterInto(&records, .{
        .taxpayer_id = taxpayer_id,
        .registration_unit_id = head_id,
        .period = period,
    }, &output);

    try std.testing.expectEqual(@as(usize, 2), result.matched_count);
    try std.testing.expectEqual(@as(usize, 2), result.visible_count);
    try std.testing.expectEqual(@as(usize, 1), result.unresolved_count);
    try std.testing.expectEqual(@as(usize, 0), result.invalid_count);
    try std.testing.expect(!result.output_truncated);
    try std.testing.expectEqualStrings("head-earlier", output[0].id.asSlice());
    try std.testing.expectEqualStrings("head-later", output[1].id.asSlice());
    const retained_binding = output[0].attribution.sourceUnit().?;
    try std.testing.expect(
        retained_binding.registration_unit_revision_id.eql(&head_revision_id),
    );
}

test "source workspace reports invalid input and output truncation" {
    const taxpayer_id = try registration.TaxpayerId.parse("taxpayer-a");
    const unit_id = try registration.RegistrationUnitId.parse("unit-a");
    const unit_revision_id = try registration.RegistrationUnitRevisionId.parse(
        "unit-a-revision-1",
    );
    const source_unit = SourceUnitBinding{
        .registration_unit_id = unit_id,
        .registration_unit_revision_id = unit_revision_id,
    };
    const records = [_]SourceRecord{
        .{
            .id = .{},
            .taxpayer_id = taxpayer_id,
            .occurred_on = try registration.Date.parseIso("2026-01-05"),
            .kind = .transaction,
            .attribution = .{ .legacy_unknown = .missing_import_mapping },
        },
        .{
            .id = try SourceRecordId.parse("record-a"),
            .taxpayer_id = taxpayer_id,
            .occurred_on = try registration.Date.parseIso("2026-01-05"),
            .kind = .transaction,
            .attribution = .{ .entered = .{
                .source_unit = source_unit,
                .evidence_reference = try EvidenceReference.parse("reference-a"),
            } },
        },
        .{
            .id = try SourceRecordId.parse("record-b"),
            .taxpayer_id = taxpayer_id,
            .occurred_on = try registration.Date.parseIso("2026-01-06"),
            .kind = .transaction,
            .attribution = .{ .entered = .{
                .source_unit = source_unit,
                .evidence_reference = try EvidenceReference.parse("reference-b"),
            } },
        },
    };
    var output: [1]SourceRecord = undefined;
    const result = filterInto(&records, .{
        .taxpayer_id = taxpayer_id,
        .registration_unit_id = unit_id,
        .period = try registration.EffectivePeriod.init(
            try registration.Date.parseIso("2026-01-01"),
            try registration.Date.parseIso("2026-03-31"),
        ),
    }, &output);

    try std.testing.expectEqual(@as(usize, 2), result.matched_count);
    try std.testing.expectEqual(@as(usize, 1), result.visible_count);
    try std.testing.expectEqual(@as(usize, 1), result.invalid_count);
    try std.testing.expect(result.output_truncated);
}

test "invalid source rows only affect their taxpayer and period workspace" {
    const taxpayer_id = try registration.TaxpayerId.parse("taxpayer-a");
    const other_taxpayer_id = try registration.TaxpayerId.parse("taxpayer-b");
    const unit_id = try registration.RegistrationUnitId.parse("unit-a");
    const records = [_]SourceRecord{
        .{
            .id = .{},
            .taxpayer_id = taxpayer_id,
            .occurred_on = try registration.Date.parseIso("2026-01-05"),
            .kind = .transaction,
            .attribution = .{ .legacy_unknown = .missing_import_mapping },
        },
        .{
            .id = .{},
            .taxpayer_id = other_taxpayer_id,
            .occurred_on = try registration.Date.parseIso("2026-01-05"),
            .kind = .transaction,
            .attribution = .{ .legacy_unknown = .missing_import_mapping },
        },
        .{
            .id = .{},
            .taxpayer_id = taxpayer_id,
            .occurred_on = try registration.Date.parseIso("2026-04-05"),
            .kind = .transaction,
            .attribution = .{ .legacy_unknown = .missing_import_mapping },
        },
    };
    var output: [records.len]SourceRecord = undefined;

    const result = filterInto(&records, .{
        .taxpayer_id = taxpayer_id,
        .registration_unit_id = unit_id,
        .period = try registration.EffectivePeriod.init(
            try registration.Date.parseIso("2026-01-01"),
            try registration.Date.parseIso("2026-03-31"),
        ),
    }, &output);

    try std.testing.expectEqual(@as(usize, 1), result.invalid_count);
    try std.testing.expectEqual(@as(usize, 0), result.unresolved_count);
    try std.testing.expectEqual(@as(usize, 0), result.visible_count);
}
