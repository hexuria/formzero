//! Stable semantic identifiers for forms, revisions, fields, drafts, filings,
//! and filing-policy evidence. They remain strings at persistence boundaries
//! without becoming interchangeable `[]const u8` values inside the domain.

const std = @import("std");

pub const Error = error{
    Empty,
    TooLong,
    InvalidCharacter,
};

const Kind = enum {
    form_code,
    revision_label,
    field,
    draft,
    filing,
    filing_policy_revision,
    policy_evidence,
};

fn Identifier(comptime kind: Kind, comptime maximum: usize) type {
    return struct {
        const Self = @This();

        bytes: [maximum]u8 = undefined,
        len: std.math.IntFittingRange(0, maximum) = 0,

        pub fn parse(raw: []const u8) Error!Self {
            const value = std.mem.trim(u8, raw, " \t\r\n");
            if (value.len == 0) return error.Empty;
            if (value.len > maximum) return error.TooLong;
            for (value) |byte| {
                if (!std.ascii.isAlphanumeric(byte) and
                    byte != '-' and byte != '_' and byte != '.' and
                    byte != ':' and byte != '/')
                {
                    return error.InvalidCharacter;
                }
            }
            var result: Self = .{};
            @memcpy(result.bytes[0..value.len], value);
            result.len = @intCast(value.len);
            return result;
        }

        pub fn initComptime(comptime raw: []const u8) Self {
            if (raw.len == 0) {
                @compileError(@tagName(kind) ++ " literal cannot be empty");
            }
            if (raw.len > maximum) {
                @compileError(@tagName(kind) ++ " literal is too long");
            }
            inline for (raw) |byte| {
                if (comptime (!std.ascii.isAlphanumeric(byte) and
                    byte != '-' and byte != '_' and byte != '.' and
                    byte != ':' and byte != '/'))
                {
                    @compileError(
                        @tagName(kind) ++ " literal has an invalid character",
                    );
                }
            }
            var result: Self = .{};
            @memcpy(result.bytes[0..raw.len], raw);
            result.len = @intCast(raw.len);
            return result;
        }

        pub fn asSlice(self: *const Self) []const u8 {
            return self.bytes[0..self.len];
        }

        pub fn isEmpty(self: *const Self) bool {
            return self.len == 0;
        }

        pub fn eql(self: *const Self, other: *const Self) bool {
            return std.mem.eql(u8, self.asSlice(), other.asSlice());
        }
    };
}

pub const FormCode = Identifier(.form_code, 16);
pub const RevisionLabel = Identifier(.revision_label, 48);
pub const FieldId = Identifier(.field, 80);
pub const DraftId = Identifier(.draft, 64);
pub const FilingId = Identifier(.filing, 64);
pub const FilingPolicyRevisionId = Identifier(.filing_policy_revision, 64);
pub const PolicyEvidenceId = Identifier(.policy_evidence, 64);

comptime {
    if (FormCode == RevisionLabel) @compileError("form code and revision label must stay distinct");
    if (FilingPolicyRevisionId == PolicyEvidenceId) {
        @compileError("policy revision and evidence identifiers must stay distinct");
    }
}

pub const FormRevision = struct {
    code: FormCode,
    revision: RevisionLabel,

    pub fn parse(code: []const u8, revision: []const u8) Error!FormRevision {
        return .{
            .code = try FormCode.parse(code),
            .revision = try RevisionLabel.parse(revision),
        };
    }

    pub fn initComptime(
        comptime code: []const u8,
        comptime revision: []const u8,
    ) FormRevision {
        return .{
            .code = FormCode.initComptime(code),
            .revision = RevisionLabel.initComptime(revision),
        };
    }

    pub fn eql(self: *const FormRevision, other: *const FormRevision) bool {
        return self.code.eql(&other.code) and
            self.revision.eql(&other.revision);
    }

    pub fn isValid(self: *const FormRevision) bool {
        return !self.code.isEmpty() and !self.revision.isEmpty();
    }
};

pub const Role = enum {
    filer,
    spouse,
    employer,
    employee,
};

test "form and field identifier types remain distinct and stable" {
    const revision = FormRevision.initComptime("2551Q", "2018-01-ENCS");
    const field_id = FieldId.initComptime("2551q.part-1.tin");
    try std.testing.expectEqualStrings("2551Q", revision.code.asSlice());
    try std.testing.expectEqualStrings(
        "2551q.part-1.tin",
        field_id.asSlice(),
    );
}

test "form revision runtime parsing and validation use the canonical identity" {
    const revision = try FormRevision.parse(" 2550Q ", "2024-04-ENCS");
    try std.testing.expect(revision.isValid());
    try std.testing.expectEqualStrings("2550Q", revision.code.asSlice());
    try std.testing.expectError(error.Empty, FormRevision.parse("", "2024-04-ENCS"));

    const invalid: FormRevision = .{ .code = .{}, .revision = .{} };
    try std.testing.expect(!invalid.isValid());
}
