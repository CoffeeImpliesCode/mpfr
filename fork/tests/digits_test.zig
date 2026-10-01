//! Text rendering and text parsing, including MPFR's own worked example for
//! one-digit decimal rounding.
//!
//! Provenance of the expected values:
//!
//!  * The 95-at-one-digit answer is quoted from the manual.
//!    doc/mpfr.texi:936-943: "Note: In particular for a 1-digit precision (in
//!    radix 2 or other radices, as in conversions to a string of digits), one
//!    considers the significands associated with the exponent of the number to
//!    be rounded. For instance, to round the number 95 in radix 10 with a
//!    1-digit precision, one considers its truncated 1-digit integer significand
//!    9 and the following integer 10 (since these are consecutive integers,
//!    exactly one of them is even). 10 is the even significand, so that 95 will
//!    be rounded to 100, not to 90."
//!  * The -3.1416 example at doc/mpfr.texi:1909-1911 fixes the output shape: a
//!    digit string with an implicit radix point before the first digit, plus a
//!    separate exponent.
//!  * The remaining expectations are the exact rational conversions of exact
//!    decimal fractions, derived by exact arithmetic.

const std = @import("std");
const mpfr = @import("mpfr");
const support = @import("support.zig");

/// Length of the base-2 literal used by the inexact-parse test below, without
/// its sentinel.
const binary_literal_length: usize = "0.0101010101".len;

test "95 at one decimal digit follows the manual's stated tie rule" {
    var x = mpfr.Float.init(64);
    defer x.deinit();
    _ = x.setUnsigned(95, .nearest_even);
    try std.testing.expectEqual(95.0, x.toF64(.nearest_even));

    const cases = [_]struct {
        mode: mpfr.RoundingMode,
        want_digits: [:0]const u8,
        want_exponent: mpfr.Exponent,
    }{
        // 95 is exactly halfway between 90 and 100, and 100 is the even
        // significand, so round-to-nearest goes up.
        .{ .mode = .nearest_even, .want_digits = "1", .want_exponent = 3 },
        .{ .mode = .toward_positive, .want_digits = "1", .want_exponent = 3 },
        .{ .mode = .away_from_zero, .want_digits = "1", .want_exponent = 3 },
        // The directed modes have no tie rule of their own, so they truncate.
        .{ .mode = .toward_zero, .want_digits = "9", .want_exponent = 2 },
        .{ .mode = .toward_negative, .want_digits = "9", .want_exponent = 2 },
    };
    for (cases) |case| {
        mpfr.clearAllFlags();
        try support.expectDigits(&x, 10, 1, case.want_digits, case.want_exponent, case.mode);
        // The rendering is inexact in every mode here, because 95 needs two
        // digits (doc/mpfr.texi:1942).
        try support.expectFlags(.{ .inexact = true });
    }
}

test "95 at two decimal digits is exact and raises no flag" {
    var x = mpfr.Float.init(64);
    defer x.deinit();
    _ = x.setUnsigned(95, .nearest_even);

    for ([_]mpfr.RoundingMode{ .nearest_even, .toward_zero, .toward_positive, .toward_negative, .away_from_zero }) |mode| {
        mpfr.clearAllFlags();
        try support.expectDigits(&x, 10, 2, "95", 2, mode);
        try support.expectFlags(mpfr.Flags.none);
    }
}

test "a negative value carries its sign in the digits" {
    // doc/mpfr.texi:1909-1911: the sign is part of the digit string and the
    // exponent is unchanged.
    var x = mpfr.Float.init(64);
    defer x.deinit();
    _ = x.setSigned(-95, .nearest_even);

    mpfr.clearAllFlags();
    try support.expectDigits(&x, 10, 2, "-95", 2, .nearest_even);
    try support.expectFlags(mpfr.Flags.none);
}

test "a small exact value keeps the implicit-radix-point shape" {
    // 0.5 is 0.1 * 10^0, so the digit string is "5" with exponent 0.
    var half = mpfr.Float.init(64);
    defer half.deinit();
    _ = half.setF64(0.5, .nearest_even);

    mpfr.clearAllFlags();
    try support.expectDigits(&half, 10, 1, "5", 0, .nearest_even);
    try support.expectFlags(mpfr.Flags.none);
    try support.expectDigits(&half, 10, 3, "500", 0, .nearest_even);
    try support.expectFlags(mpfr.Flags.none);
}

test "an exact power of two renders with the exponent carrying the scale" {
    // 2^10 is 0.1024 * 10^3.
    var x = mpfr.Float.init(64);
    defer x.deinit();
    _ = x.setPowerOfTwo(10, .nearest_even);

    mpfr.clearAllFlags();
    try support.expectDigits(&x, 10, 4, "1024", 4, .nearest_even);
    try support.expectFlags(mpfr.Flags.none);
}

test "a NaN renders as @NaN@ and an infinity as @Inf@" {
    // doc/mpfr.texi:1900-1902.
    var nan_value = mpfr.Float.init(64);
    defer nan_value.deinit();
    nan_value.setNan();

    mpfr.clearAllFlags();
    try support.expectDigits(&nan_value, 10, 1, "@NaN@", 0, .nearest_even);
    try std.testing.expect(mpfr.flags().nan);

    var positive = mpfr.Float.init(64);
    defer positive.deinit();
    positive.setInf(true);
    try support.expectDigits(&positive, 10, 1, "@Inf@", 0, .nearest_even);

    var negative = mpfr.Float.init(64);
    defer negative.deinit();
    negative.setInf(false);
    try support.expectDigits(&negative, 10, 1, "-@Inf@", 0, .nearest_even);
}

test "an invalid base is rejected instead of silently rendering nothing" {
    // doc/mpfr.texi:1888-1889: outside 2..62 and -2..-36 the function does
    // nothing and immediately returns a null pointer.
    try std.testing.expect(!mpfr.isValidBase(1));
    try std.testing.expect(!mpfr.isValidBase(63));
    try std.testing.expect(!mpfr.isValidBase(0));
    try std.testing.expect(!mpfr.isValidBase(-1));
    try std.testing.expect(mpfr.isValidBase(2));
    try std.testing.expect(mpfr.isValidBase(10));
    try std.testing.expect(mpfr.isValidBase(62));
    try std.testing.expect(mpfr.isValidBase(-36));

    var x = mpfr.Float.init(64);
    defer x.deinit();
    _ = x.setUnsigned(95, .nearest_even);

    try std.testing.expectError(error.InvalidBase, x.toDigits(1, 1, .nearest_even));
    try std.testing.expectError(error.InvalidBase, x.toDigits(63, 1, .nearest_even));
}

test "parseWhole accepts only a complete number" {
    // doc/mpfr.texi:1594-1609: mpfr_set_str returns 0 only when the entire
    // string up to the final null character is a valid number. Its return
    // value is a success code rather than a ternary value, so it says nothing
    // about how much precision the text needed; parsePrefix below is the entry
    // point that answers that.
    var x = mpfr.Float.init(200);
    defer x.deinit();

    try x.parseWhole("1.0625", 10, .nearest_even);
    try std.testing.expectEqual(1.0625, x.toF64(.nearest_even));

    try std.testing.expectError(error.InvalidNumber, x.parseWhole("1.0625xyz", 10, .nearest_even));
    try std.testing.expectError(error.InvalidNumber, x.parseWhole("", 10, .nearest_even));
    try std.testing.expectError(error.InvalidNumber, x.parseWhole("  ", 10, .nearest_even));
    try std.testing.expectError(error.InvalidNumber, x.parseWhole("0x1p4", 10, .nearest_even));
}

test "the NaN spelling takes a dummy suffix that the infinity spelling does not" {
    // src/strtofr.c:254-282 accepts "@nan@" case-insensitively and then skips an
    // optional parenthesised run of letters, digits and underscores, while the
    // "@inf@" branch at src/strtofr.c:284-301 has no such branch. mpfr_set_str
    // therefore sees the whole string in the NaN case and only a prefix in the
    // infinity case, which is the difference between success and
    // error.InvalidNumber.
    var x = mpfr.Float.init(64);
    defer x.deinit();

    try x.parseWhole("@NaN@(garbage1)", 10, .nearest_even);
    try std.testing.expect(x.isNan());

    try std.testing.expectError(error.InvalidNumber, x.parseWhole("@Inf@garbage", 10, .nearest_even));

    // The bare spellings are whole strings in both branches, and the sign is
    // read before either of them.
    try x.parseWhole("@INF@", 10, .nearest_even);
    try std.testing.expect(x.isInf());
    try std.testing.expect(!x.isSignNegative());

    try x.parseWhole("-@inf@", 10, .nearest_even);
    try std.testing.expect(x.isInf());
    try std.testing.expect(x.isSignNegative());
}

test "parsePrefix reports how much it consumed" {
    // doc/mpfr.texi:1610-1627: mpfr_strtofr points the end pointer just past
    // the valid data and returns the usual ternary value.
    var x = mpfr.Float.init(200);
    defer x.deinit();

    const whole = try x.parsePrefix("1.0625", 10, .nearest_even);
    try std.testing.expectEqual(@as(usize, 6), whole.consumed);
    try std.testing.expectEqual(mpfr.Ternary.exact, whole.ternary);

    const partial = try x.parsePrefix("1.0625xyz", 10, .nearest_even);
    try std.testing.expectEqual(@as(usize, 6), partial.consumed);
    try std.testing.expectEqual(mpfr.Ternary.exact, partial.ternary);

    try std.testing.expectError(error.InvalidNumber, x.parsePrefix("nonsense", 10, .nearest_even));
}

test "a parse that needs more bits than the destination reports itself inexact" {
    // 0.0101010101b is 2^-2 + 2^-4 + 2^-6 + 2^-8 + 2^-10 = 341/1024, a finite
    // binary fraction that needs ten fraction bits. At a four-bit precision the
    // significand reaches from 2^-1 down to 2^-4, so the kept part is
    // 2^-2 + 2^-4 and one unit is 2^-5. Truncating gives 5/16 = 0.3125 and
    // rounding up gives 11/32 = 0.34375, which is where the destination has to
    // land; a parse into a destination wide enough to hold the literal exactly
    // would be exact, so the width is what this test varies.
    const cases = [_]struct {
        mode: mpfr.RoundingMode,
        want: f64,
        want_ternary: mpfr.Ternary,
        want_digits: [:0]const u8,
    }{
        .{ .mode = .toward_negative, .want = 0.3125, .want_ternary = .below, .want_digits = "31250000000000000000" },
        .{ .mode = .toward_positive, .want = 0.34375, .want_ternary = .above, .want_digits = "34375000000000000000" },
    };
    for (cases) |case| {
        var narrow = mpfr.Float.init(4);
        defer narrow.deinit();

        mpfr.clearAllFlags();
        const parsed = try narrow.parsePrefix("0.0101010101", 2, case.mode);

        try std.testing.expectEqual(binary_literal_length, parsed.consumed);
        try std.testing.expectEqual(case.want_ternary, parsed.ternary);
        try std.testing.expect(mpfr.flags().inexact);
        try std.testing.expectEqual(case.want, narrow.toF64(.nearest_even));
        mpfr.clearAllFlags();
        try support.expectDigits(&narrow, 10, 20, case.want_digits, 0, .nearest_even);
    }

    // The same literal in a destination that can hold it is exact, which is
    // what makes the narrow destination above the interesting case.
    var wide = mpfr.Float.init(20);
    defer wide.deinit();
    mpfr.clearAllFlags();
    const exact = try wide.parsePrefix("0.0101010101", 2, .nearest_even);
    try std.testing.expectEqual(mpfr.Ternary.exact, exact.ternary);
    try support.expectFlags(mpfr.Flags.none);
    try std.testing.expectEqual(0.3330078125, wide.toF64(.nearest_even));
}

test "base 0 auto-detects only the binary and hexadecimal prefixes" {
    // doc/mpfr.texi:1646-1650: base 0 means `0b`/`0B` selects base 2,
    // `0x`/`0X` selects base 16, and anything else is base 10. There is no
    // `0o` prefix, so "0o17" is not an octal literal here.
    var x = mpfr.Float.init(200);
    defer x.deinit();

    try x.parseWhole("0x10", 0, .nearest_even);
    try std.testing.expectEqual(16.0, x.toF64(.nearest_even));

    try x.parseWhole("0b101", 0, .nearest_even);
    try std.testing.expectEqual(5.0, x.toF64(.nearest_even));

    try x.parseWhole("17", 0, .nearest_even);
    try std.testing.expectEqual(17.0, x.toF64(.nearest_even));

    // "0o17" is not octal, so a whole-string parse rejects it.
    try std.testing.expectError(error.InvalidNumber, x.parseWhole("0o17", 0, .nearest_even));
}

test "a bare radix prefix stops the number after the leading zero" {
    // doc/mpfr.texi:1652-1655: if "0b", "0B", "0x" or "0X" is not followed by
    // a digit of that base, the subject sequence stops at the "0", so 0 is
    // read.
    var x = mpfr.Float.init(200);
    defer x.deinit();

    const parsed = try x.parsePrefix("0x", 0, .nearest_even);
    try std.testing.expectEqual(@as(usize, 1), parsed.consumed);
    try std.testing.expectEqual(mpfr.Ternary.exact, parsed.ternary);
    try std.testing.expect(x.isZero());
}

test "a base-2 literal parses exactly and renders exactly" {
    // 0.101b is 5/8, which is exact in three bits, so the parse reports an
    // exact ternary value and raises no flag (doc/mpfr.texi:1610-1627).
    var x = try support.exactBinary("0.101", 3);
    defer x.deinit();

    try std.testing.expectEqual(@as(mpfr.Precision, 3), x.precision());
    try std.testing.expectEqual(0.625, x.toF64(.nearest_even));
    // The word is cleared before the assertion below, which compares all six
    // bits at once: the parse above is exact, so it leaves the word exactly as
    // the preceding test left it, and this test must not depend on that.
    mpfr.clearAllFlags();
    try support.expectFlags(mpfr.Flags.none);

    mpfr.clearAllFlags();
    try support.expectDigits(&x, 10, 20, "62500000000000000000", 0, .nearest_even);
    try support.expectFlags(mpfr.Flags.none);

    // The same value in base 2 is its own significand, with exponent 0.
    mpfr.clearAllFlags();
    try support.expectDigits(&x, 2, 3, "101", 0, .nearest_even);
    try support.expectFlags(mpfr.Flags.none);
}
