//! HTA-local exclusive choice among 1601EQ over-remittance marks.
//!
//! Provenance (value-free):
//! - Offline eBIRForms 7.9.6
//! - `forms/BIR-Form1601EQ.hta`
//! - SHA-256:
//!   `cd56bf18d1da2127d578af611fe8005fe49913a65781bb603b22b31bbe548b96`
//! - `checkRefund` lines 3116-3121
//! - `checkIssueCert` lines 3124-3129
//! - `checkCarriedOver` lines 3132-3137
//! - `computeOfTotalAmtDue` else-branch uncheck, lines 3088-3094
//!
//! Checking one mark unchecks the other two. Unchecking a mark does not
//! check another. When choices are not enabled (Item 30 is not negative),
//! every mark is cleared. This is not a handler implementation:
//! `handlers_implemented` stays false. Markup disable/enable is still the
//! calculations comparison flag.

const std = @import("std");
const evidence = @import("evidence.zig");
const event_contract = @import("event_contract.zig");

/// Full UI interaction is not ready. Exclusive over-remittance choice is.
pub const ready = false;
pub const exclusive_choice_ready = true;

pub const Mark = enum {
    refund,
    issue_cert,
    carried_over,
};

pub const OverRemittanceMarks = struct {
    refund: bool = false,
    issue_cert: bool = false,
    carried_over: bool = false,

    pub const none: OverRemittanceMarks = .{};

    pub fn isChecked(self: OverRemittanceMarks, mark: Mark) bool {
        return switch (mark) {
            .refund => self.refund,
            .issue_cert => self.issue_cert,
            .carried_over => self.carried_over,
        };
    }
};

/// Post-click exclusive choice. `marks` is the post-toggle checkbox state.
/// Disabled choices follow `computeOfTotalAmtDue`: all three unchecked.
pub fn applyClickedMark(
    enabled: bool,
    clicked: Mark,
    marks: OverRemittanceMarks,
) OverRemittanceMarks {
    if (!enabled) return OverRemittanceMarks.none;
    if (!marks.isChecked(clicked)) return marks;
    return switch (clicked) {
        .refund => .{ .refund = true },
        .issue_cert => .{ .issue_cert = true },
        .carried_over => .{ .carried_over = true },
    };
}

/// HTA `checkRefund` lines 3116-3121.
pub fn applyCheckRefund(enabled: bool, marks: OverRemittanceMarks) OverRemittanceMarks {
    return applyClickedMark(enabled, .refund, marks);
}

/// HTA `checkIssueCert` lines 3124-3129.
pub fn applyCheckIssueCert(enabled: bool, marks: OverRemittanceMarks) OverRemittanceMarks {
    return applyClickedMark(enabled, .issue_cert, marks);
}

/// HTA `checkCarriedOver` lines 3132-3137.
pub fn applyCheckCarriedOver(enabled: bool, marks: OverRemittanceMarks) OverRemittanceMarks {
    return applyClickedMark(enabled, .carried_over, marks);
}

test "1601EQ over-remittance exclusive choice stays unreconciled and unimplemented as handlers" {
    try std.testing.expect(exclusive_choice_ready);
    try std.testing.expect(!ready);
    try std.testing.expect(!event_contract.handlers_implemented);
    try std.testing.expect(!evidence.readiness.identityReady());
    try std.testing.expect(!evidence.readiness.dependency_closure);
}

test "1601EQ checking one over-remittance mark unchecks the other two" {
    const from_issue_cert = applyCheckRefund(true, .{
        .refund = true,
        .issue_cert = true,
        .carried_over = false,
    });
    try std.testing.expect(from_issue_cert.refund);
    try std.testing.expect(!from_issue_cert.issue_cert);
    try std.testing.expect(!from_issue_cert.carried_over);

    const from_refund = applyCheckIssueCert(true, .{
        .refund = true,
        .issue_cert = true,
        .carried_over = true,
    });
    try std.testing.expect(!from_refund.refund);
    try std.testing.expect(from_refund.issue_cert);
    try std.testing.expect(!from_refund.carried_over);

    const from_both = applyCheckCarriedOver(true, .{
        .refund = true,
        .issue_cert = true,
        .carried_over = true,
    });
    try std.testing.expect(!from_both.refund);
    try std.testing.expect(!from_both.issue_cert);
    try std.testing.expect(from_both.carried_over);
}

test "1601EQ unchecking an over-remittance mark does not check another" {
    const marks = applyCheckRefund(true, .{
        .refund = false,
        .issue_cert = false,
        .carried_over = false,
    });
    try std.testing.expectEqual(OverRemittanceMarks.none, marks);
}

test "1601EQ disabled over-remittance choices clear every mark" {
    const marks = applyCheckRefund(false, .{
        .refund = true,
        .issue_cert = true,
        .carried_over = true,
    });
    try std.testing.expectEqual(OverRemittanceMarks.none, marks);
    try std.testing.expectEqual(
        OverRemittanceMarks.none,
        applyCheckIssueCert(false, .{ .issue_cert = true }),
    );
    try std.testing.expectEqual(
        OverRemittanceMarks.none,
        applyCheckCarriedOver(false, .{ .carried_over = true }),
    );
}
