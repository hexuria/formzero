//! HTA money text rules for 1601EQ: the `round` field normaliser and the
//! `formatCurrency` display formatter.
//!
//! Provenance (value-free):
//! - Offline eBIRForms 7.9.6
//! - `js/string-util.js`, a resolved dependency loading at script position 5
//! - `isAmountWithinAllowedPrecision` line 268, `round` line 286,
//!   `formatCurrency` line 321, `NumWithComma` line 358
//! - `numbersonly` lines 120 and 148, called as `numbersonly(this, event)`
//!   at ten 1601EQ keypress bindings
//! - `setInputTextControl_NumberFormatter` HTA lines 2883-2886, called six
//!   times as `(id, 15, 2)`
//!
//! Both functions strip `$` and `,` before doing anything else, then round
//! the magnitude half away from zero at the centavo and regroup the integer
//! part in threes. They differ in their limits and in what they do when a
//! value exceeds them, and neither difference is incidental.
//!
//! `round` is the onblur normaliser for Part II tax base and rate fields.
//! It rejects an integer part longer than twelve characters and **replaces
//! the field with `0.00`** rather than truncating, so an over-long entry is
//! silently destroyed rather than clamped. `formatCurrency` is the display
//! path and instead truncates at fifteen.
//!
//! The twelve-character budget is measured after stripping, and a leading
//! minus counts against it, so a negative value is limited to eleven digits
//! where a positive one gets twelve.
//!
//! `round(field, dec)` never reads `dec`. Every call site passes `2` and the
//! body hardcodes two decimals, so the argument is inert.
//!
//! Text that survives the precision gate but is not a number becomes `0.00`
//! by way of the HTA's `isNaN` branch; the empty string is not NaN in
//! JavaScript and takes the same path to zero.
//!
//! Rounding here is exact-decimal half away from zero. The HTA reaches the
//! same result through a double and `Math.floor(x * 100 + 0.50000000001)`,
//! which diverges by one centavo when the exact value lands on a half
//! centavo at a large enough magnitude. That divergence is characterised in
//! `atc_rows`; `calculation_reconciled` stays false.
//! `numbersonly` is declared twice in the same file. The later declaration
//! wins, and the two differ: the earlier one rejects `.` outright and moves
//! focus to another field, while the later one accepts it. Every 1601EQ
//! binding passes `(this, event)`, which matches the earlier signature
//! `(myfield, e, dec)` rather than the surviving `(e, decimal)`. The
//! mismatch is harmless only because the body reads `window.event` before
//! looking at either argument, so under an IE engine the arguments are never
//! consulted. That also means the filter is keyed to the host, not to what
//! the call site passes.
//!
//! A third formatter reaches the same fields.
//! `setInputTextControl_NumberFormatter(id, limit, deci)` sets the control's
//! `size` and rewrites its value as `parseFloat(value).toFixed(deci)`. Every
//! 1601EQ call passes `(id, 15, 2)`, so it fixes two decimals like the other
//! two — but `toFixed` inserts no group separators, where `round` and
//! `formatCurrency` both do. A tax base written by the row renderer is
//! therefore ungrouped, and the same field becomes grouped the moment it is
//! blurred. Its `limit` of 15 sets a display width and is unrelated to the
//! twelve-character precision gate.
//!
//! The surviving filter admits digits, `.`, and the control keys the HTA
//! lists by code. It admits no sign character, so a negative amount cannot
//! be typed into a Part II field at all. It also has no guard against a
//! second `.`, so `1.2.3` is typeable; `round` then finds it unparseable and
//! writes `0.00`.

const std = @import("std");
const calculations = @import("calculations.zig");
const evidence = @import("evidence.zig");

const Money = calculations.Money;

/// `isAmountWithinAllowedPrecision` rejects beyond this many characters.
pub const round_max_integer_digits: usize = 12;
/// `formatCurrency` truncates beyond this many instead of rejecting.
pub const format_currency_max_integer_digits: usize = 15;
/// `round`'s second parameter is never read.
pub const round_honours_dec_argument = false;
/// Characters both functions strip before measuring or parsing.
pub const stripped_characters = "$,";

/// Longest string `formatInto` can produce: sign, fifteen digits, four
/// group separators, the point and two decimals.
pub const max_formatted_length: usize = 1 + 15 + 4 + 1 + 2;

fn isStripped(character: u8) bool {
    return std.mem.indexOfScalar(u8, stripped_characters, character) != null;
}

/// `isAmountWithinAllowedPrecision`: measures the text before any decimal
/// point, after stripping, including a leading sign.
pub fn withinAllowedPrecision(text: []const u8) bool {
    var integer_length: usize = 0;
    for (text) |character| {
        if (isStripped(character)) continue;
        if (character == '.') {
            // A leading point leaves `indexOf` at zero, so HTA measures the
            // whole string instead of the part before it.
            if (integer_length == 0) continue;
            break;
        }
        integer_length += 1;
    }
    return integer_length <= round_max_integer_digits;
}

pub const RoundOutcome = struct {
    /// False when the precision gate rejected the text and HTA wrote `0.00`.
    accepted: bool,
    value: Money,
};

/// Exact-decimal parse of already-stripped text. Null when the text is not a
/// number, which HTA funnels to zero through `isNaN`.
fn parseCentavos(text: []const u8) ?i64 {
    var negative = false;
    var index: usize = 0;
    var digits: usize = 0;
    var whole: i128 = 0;
    var fraction: [3]u8 = .{ 0, 0, 0 };
    var fraction_seen: usize = 0;
    var seen_point = false;

    if (index < text.len and (text[index] == '-' or text[index] == '+')) {
        negative = text[index] == '-';
        index += 1;
    }
    while (index < text.len) : (index += 1) {
        const character = text[index];
        if (character == '.') {
            if (seen_point) return null;
            seen_point = true;
            continue;
        }
        if (character < '0' or character > '9') return null;
        const digit: u8 = character - '0';
        digits += 1;
        if (seen_point) {
            if (fraction_seen < fraction.len) fraction[fraction_seen] = digit;
            fraction_seen += 1;
        } else {
            whole = whole * 10 + digit;
            if (whole > std.math.maxInt(i64)) return null;
        }
    }
    // The empty string is not NaN in JavaScript; it becomes zero.
    if (digits == 0) return if (seen_point or text.len == 0) 0 else null;

    var centavos: i128 = whole * 100 + @as(i128, fraction[0]) * 10 + fraction[1];
    // Half away from zero: the third decimal decides, and anything past it
    // can only push further from the boundary.
    if (fraction_seen > 2 and fraction[2] >= 5) centavos += 1;
    if (centavos > std.math.maxInt(i64)) return null;
    return @intCast(if (negative) -centavos else centavos);
}

fn stripInto(buffer: []u8, text: []const u8) []const u8 {
    var length: usize = 0;
    for (text) |character| {
        if (isStripped(character)) continue;
        if (length == buffer.len) break;
        buffer[length] = character;
        length += 1;
    }
    return buffer[0..length];
}

/// `round(field, 2)`: normalise a field in place. A value past the precision
/// limit is replaced with zero rather than truncated.
pub fn roundField(text: []const u8) RoundOutcome {
    if (!withinAllowedPrecision(text)) {
        return .{ .accepted = false, .value = Money.zero };
    }
    var buffer: [64]u8 = undefined;
    const stripped = stripInto(&buffer, text);
    const centavos = parseCentavos(stripped) orelse 0;
    return .{ .accepted = true, .value = Money.fromCentavos(centavos) };
}

/// `formatCurrency`: two decimals, integer part grouped in threes, sign
/// ahead of everything.
pub fn formatInto(buffer: []u8, value: Money) []const u8 {
    std.debug.assert(buffer.len >= max_formatted_length);
    const negative = value.centavos < 0;
    const magnitude: u64 = @intCast(if (negative) -@as(i128, value.centavos) else value.centavos);
    const cents: u64 = magnitude % 100;
    const whole: u64 = magnitude / 100;

    var digits: [20]u8 = undefined;
    var digit_count: usize = 0;
    var remaining = whole;
    while (true) {
        digits[digit_count] = @intCast('0' + (remaining % 10));
        digit_count += 1;
        remaining /= 10;
        if (remaining == 0) break;
    }

    var length: usize = 0;
    if (negative) {
        buffer[length] = '-';
        length += 1;
    }
    var index = digit_count;
    while (index > 0) {
        index -= 1;
        buffer[length] = digits[index];
        length += 1;
        if (index > 0 and index % 3 == 0) {
            buffer[length] = ',';
            length += 1;
        }
    }
    buffer[length] = '.';
    length += 1;
    buffer[length] = @intCast('0' + (cents / 10));
    length += 1;
    buffer[length] = @intCast('0' + (cents % 10));
    length += 1;
    return buffer[0..length];
}

fn formatted(value: Money) []const u8 {
    const Static = struct {
        var buffer: [max_formatted_length]u8 = undefined;
    };
    return formatInto(&Static.buffer, value);
}

/// Key codes `numbersonly` admits before it inspects the character, in the
/// order the HTA lists them: unset, null, backspace, tab, enter, escape.
pub const accepted_control_key_codes = [_]u16{ 0, 8, 9, 13, 27 };

/// Characters the surviving `numbersonly` admits.
pub const accepted_characters = "0123456789.";

/// The earlier declaration rejects `.`; the later one accepts it and wins.
pub const numbersonly_declaration_count: usize = 2;

/// True when a keypress survives the filter. `key_code` null models the
/// HTA's `key == null` branch, which passes.
pub fn keypressAccepted(key_code: ?u16) bool {
    const code = key_code orelse return true;
    for (accepted_control_key_codes) |accepted| {
        if (code == accepted) return true;
    }
    if (code > 0x7F) return false;
    const character: u8 = @intCast(code);
    return std.mem.indexOfScalar(u8, accepted_characters, character) != null;
}

/// `setInputTextControl_NumberFormatter` decimal count, from every call.
pub const number_formatter_decimals: usize = 2;
/// Its `limit`, which sets the control's display width only.
pub const number_formatter_size: usize = 15;
/// `toFixed` emits no group separators, unlike `round` and `formatCurrency`.
pub const number_formatter_groups_digits = false;

/// Value the row renderer writes: two decimals, no separators, sign kept.
pub fn numberFormatterInto(buffer: []u8, value: Money) []const u8 {
    const grouped = formatInto(buffer, value);
    var length: usize = 0;
    for (grouped) |character| {
        if (character == ',') continue;
        buffer[length] = character;
        length += 1;
    }
    return buffer[0..length];
}

test "1601EQ round and formatCurrency carry different limits" {
    try std.testing.expectEqual(@as(usize, 12), round_max_integer_digits);
    try std.testing.expectEqual(@as(usize, 15), format_currency_max_integer_digits);
    try std.testing.expect(!round_honours_dec_argument);
    try std.testing.expect(!evidence.readiness.calculation_reconciled);
}

test "1601EQ the precision gate measures stripped text and counts the sign" {
    try std.testing.expect(withinAllowedPrecision("999999999999"));
    try std.testing.expect(!withinAllowedPrecision("9999999999999"));
    // A leading minus spends one of the twelve, so negatives lose a digit.
    try std.testing.expect(withinAllowedPrecision("-99999999999"));
    try std.testing.expect(!withinAllowedPrecision("-999999999999"));
    // Only the part before the point is measured.
    try std.testing.expect(withinAllowedPrecision("999999999999.99"));
    try std.testing.expect(!withinAllowedPrecision("9999999999999.99"));
    // Stripping happens first, so separators do not count.
    try std.testing.expect(withinAllowedPrecision("$999,999,999,999.99"));
}

test "1601EQ an over-long entry is destroyed rather than truncated" {
    const rejected = roundField("9999999999999.99");
    try std.testing.expect(!rejected.accepted);
    try std.testing.expectEqual(@as(i64, 0), rejected.value.centavos);
    try std.testing.expectEqualStrings("0.00", formatted(rejected.value));

    const kept = roundField("999999999999.99");
    try std.testing.expect(kept.accepted);
    try std.testing.expectEqual(@as(i64, 99_999_999_999_999), kept.value.centavos);
}

test "1601EQ round strips separators and keeps two decimals" {
    try std.testing.expectEqual(@as(i64, 123_450), roundField("$1,234.50").value.centavos);
    try std.testing.expectEqual(@as(i64, 50), roundField(".50").value.centavos);
    try std.testing.expectEqual(@as(i64, -50), roundField("-.50").value.centavos);
    try std.testing.expectEqual(@as(i64, 100), roundField("1.").value.centavos);
    try std.testing.expectEqual(@as(i64, 0), roundField("0").value.centavos);
}

test "1601EQ text that is not a number becomes zero, as does the empty field" {
    const letters = roundField("abc");
    // It clears the precision gate on length, then the isNaN branch zeroes it.
    try std.testing.expect(letters.accepted);
    try std.testing.expectEqual(@as(i64, 0), letters.value.centavos);

    const empty = roundField("");
    try std.testing.expect(empty.accepted);
    try std.testing.expectEqual(@as(i64, 0), empty.value.centavos);
}

test "1601EQ round takes the third decimal half away from zero" {
    try std.testing.expectEqual(@as(i64, 1), roundField("0.005").value.centavos);
    try std.testing.expectEqual(@as(i64, 0), roundField("0.004").value.centavos);
    try std.testing.expectEqual(@as(i64, -1), roundField("-0.005").value.centavos);
    try std.testing.expectEqual(@as(i64, 124), roundField("1.2351").value.centavos);
    try std.testing.expectEqual(@as(i64, 123), roundField("1.2349").value.centavos);
}

test "1601EQ formatCurrency groups the integer part in threes" {
    try std.testing.expectEqualStrings("0.00", formatted(Money.zero));
    try std.testing.expectEqualStrings("1.00", formatted(Money.fromCentavos(100)));
    try std.testing.expectEqualStrings("1,234.50", formatted(Money.fromCentavos(123_450)));
    try std.testing.expectEqualStrings("1,000,000.00", formatted(Money.fromCentavos(100_000_000)));
    try std.testing.expectEqualStrings(
        "999,999,999,999.99",
        formatted(Money.fromCentavos(99_999_999_999_999)),
    );
}

test "1601EQ formatCurrency puts the sign ahead of the grouped digits" {
    try std.testing.expectEqualStrings("-1,234,567.89", formatted(Money.fromCentavos(-123_456_789)));
    try std.testing.expectEqualStrings("-0.01", formatted(Money.fromCentavos(-1)));
    try std.testing.expectEqualStrings("-1,000.00", formatted(Money.fromCentavos(-100_000)));
}

test "1601EQ a rounded field survives a round trip through the formatter" {
    const samples = [_][]const u8{ "0", "1.00", "1,234.50", "$99,999.99", "-1,000.00", ".05" };
    for (samples) |sample| {
        const outcome = roundField(sample);
        try std.testing.expect(outcome.accepted);
        const text = formatted(outcome.value);
        // Reparsing the formatted text yields the same centavos.
        try std.testing.expectEqual(outcome.value.centavos, roundField(text).value.centavos);
    }
}

test "1601EQ the surviving numbersonly filter admits digits and the point" {
    try std.testing.expectEqual(@as(usize, 2), numbersonly_declaration_count);
    for ("0123456789.") |character| {
        try std.testing.expect(keypressAccepted(character));
    }
}

test "1601EQ no sign character can be typed into a Part II field" {
    try std.testing.expect(!keypressAccepted('-'));
    try std.testing.expect(!keypressAccepted('+'));
    // So a negative tax base is unreachable by typing, whatever round accepts.
    try std.testing.expectEqual(@as(i64, -50), roundField("-.50").value.centavos);
}

test "1601EQ the listed control keys pass and other characters do not" {
    try std.testing.expect(keypressAccepted(null));
    for (accepted_control_key_codes) |code| {
        try std.testing.expect(keypressAccepted(code));
    }
    try std.testing.expect(!keypressAccepted('a'));
    try std.testing.expect(!keypressAccepted('$'));
    try std.testing.expect(!keypressAccepted(','));
    try std.testing.expect(!keypressAccepted(' '));
}

test "1601EQ a second point is typeable and round then zeroes the field" {
    // The filter has no guard against repeating the separator.
    try std.testing.expect(keypressAccepted('.'));
    const outcome = roundField("1.2.3");
    // It clears the precision gate, then fails to parse and becomes zero.
    try std.testing.expect(outcome.accepted);
    try std.testing.expectEqual(@as(i64, 0), outcome.value.centavos);
}

test "1601EQ the row renderer writes two decimals without separators" {
    try std.testing.expectEqual(@as(usize, 2), number_formatter_decimals);
    try std.testing.expectEqual(@as(usize, 15), number_formatter_size);
    try std.testing.expect(!number_formatter_groups_digits);

    const Static = struct {
        var buffer: [max_formatted_length]u8 = undefined;
    };
    try std.testing.expectEqualStrings(
        "1234567.89",
        numberFormatterInto(&Static.buffer, Money.fromCentavos(123_456_789)),
    );
    try std.testing.expectEqualStrings(
        "0.00",
        numberFormatterInto(&Static.buffer, Money.zero),
    );
    try std.testing.expectEqualStrings(
        "-1000.00",
        numberFormatterInto(&Static.buffer, Money.fromCentavos(-100_000)),
    );
}

test "1601EQ the same amount is grouped by blur and ungrouped by render" {
    const Static = struct {
        var rendered: [max_formatted_length]u8 = undefined;
        var blurred: [max_formatted_length]u8 = undefined;
    };
    const amount = Money.fromCentavos(123_456_789);
    const on_render = numberFormatterInto(&Static.rendered, amount);
    const on_blur = formatInto(&Static.blurred, amount);
    try std.testing.expect(!std.mem.eql(u8, on_render, on_blur));
    try std.testing.expect(std.mem.indexOfScalar(u8, on_render, ',') == null);
    try std.testing.expect(std.mem.indexOfScalar(u8, on_blur, ',') != null);
    // Both still parse back to the same value.
    try std.testing.expectEqual(amount.centavos, roundField(on_render).value.centavos);
    try std.testing.expectEqual(amount.centavos, roundField(on_blur).value.centavos);
}
