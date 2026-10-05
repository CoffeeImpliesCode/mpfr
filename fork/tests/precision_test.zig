//! Precision behaviour: exactness, arbitrary width, and the difference between
//! `mpfr_set_prec` and `mpfr_prec_round`.
//!
//! Provenance of the expected values:
//!
//!  * `mpfr_set_prec` losing the value is stated in doc/mpfr.texi:1499-1515:
//!    "Set the precision of x to be exactly prec bits, and set its value to NaN.
//!    The previous value stored in x is lost."
//!  * `mpfr_prec_round` keeping the value, zero-filling when the precision grows
//!    and returning a ternary value, is stated in doc/mpfr.texi:3325-3333.
//!  * 1/3 is `0.010101...b` and 1/7 is `0.001001...b`, so both are inexact at
//!    every finite precision of at least two bits. One bit is not enough for
//!    either fixture, because the divisor 3 is not representable in a single
//!    bit and MPFR resolves that tie away from zero (src/round_raw_generic.c:
//!    46-49); that boundary has its own test below.
//!  * The 20-decimal-digit renderings of 1/7 below are the correctly rounded
//!    20-digit forms of the binary values that 1/7 rounds to at each
//!    precision, derived by exact rational arithmetic.
//!  * The exception word is not part of the answer to a precision change.
//!    `mpfr_prec_round` returns the ternary value that `mpfr_round_raw` computed
//!    and never writes `__gmpfr_flags` (src/round_prec.c:99-122), and the
//!    generic rounder it calls has no flag store (src/round_raw_generic.c:
//!    60-273). `mpfr_get_str` does the opposite and raises the inexact flag
//!    whenever its own rendering is inexact (doc/mpfr.texi:1942,
//!    src/get_str.c:2902), and `mpfr_get_d` raises nothing at all
//!    (src/get_d.c:34-132), so a word read after a rendering says nothing
//!    about a precision change that follows it. rounding_test.zig states both
//!    sides of the first pair together.

const std = @import("std");
const mpfr = @import("mpfr");
const support = @import("support.zig");

test "1/3 is inexact at every precision that represents 3 exactly" {
    try support.requireProvider();
    for ([_]mpfr.Precision{ 2, 3, 8, 24, 53, 64, 113, 200, 512 }) |precision| {
        // `div` writes the quotient back into the value it is called on, so
        // the numerator below is the value that ends up holding 1/3.
        var numerator = mpfr.Float.init(precision);
        defer numerator.deinit();
        _ = numerator.setUnsigned(1, .nearest_even);

        var denominator = mpfr.Float.init(precision);
        defer denominator.deinit();
        try std.testing.expectEqual(mpfr.Ternary.exact, denominator.setUnsigned(3, .nearest_even));

        mpfr.clearAllFlags();
        const ternary = numerator.div(&denominator, .nearest_even);

        try std.testing.expect(ternary != .exact);
        try support.expectFlags(.{ .inexact = true });
        try std.testing.expectEqual(precision, numerator.precision());
        try std.testing.expect(numerator.isRegular());
        try std.testing.expectEqual(@as(i32, 1), numerator.sign());
        // Every one of these precisions is wide enough for the quotient to
        // stay strictly inside (0, 1), because 1/3 itself is.
        try std.testing.expectEqual(mpfr.Order.gt, numerator.compareUnsigned(0));
        try std.testing.expectEqual(mpfr.Order.lt, numerator.compareUnsigned(1));
    }
}

test "one bit cannot hold 3, so the one-bit quotient is exact" {
    try support.requireProvider();
    // The one-bit values around 3 are 2 = 0.1b * 2^2 and 4 = 0.1b * 2^3, so 3
    // sits exactly halfway between them. src/round_raw_generic.c:46-49 says a
    // one-bit precision resolves such a tie away from zero rather than to an
    // even significand, which makes the divisor 4, and 1/4 is then exact.
    var numerator = mpfr.Float.init(1);
    defer numerator.deinit();
    _ = numerator.setUnsigned(1, .nearest_even);

    var denominator = mpfr.Float.init(1);
    defer denominator.deinit();

    mpfr.clearAllFlags();
    const ternary = denominator.setUnsigned(3, .nearest_even);
    try std.testing.expectEqual(mpfr.Ternary.above, ternary);
    try std.testing.expectEqual(4.0, denominator.toF64(.nearest_even));
    try support.expectFlags(.{ .inexact = true });

    mpfr.clearAllFlags();
    try std.testing.expectEqual(mpfr.Ternary.exact, numerator.div(&denominator, .nearest_even));
    try support.expectFlags(mpfr.Flags.none);
    try std.testing.expectEqual(0.25, numerator.toF64(.nearest_even));
}

test "a power of two is exact and integral at every precision" {
    try support.requireProvider();
    // 2^100 needs a single significand bit, so it is exact everywhere, and its
    // exact decimal expansion 1267650600228229401496703205376 has 31 digits.
    for ([_]mpfr.Precision{ 1, 2, 53, 64, 200, 1000 }) |precision| {
        var x = mpfr.Float.init(precision);
        defer x.deinit();

        mpfr.clearAllFlags();
        const inexact = x.setPowerOfTwo(100, .nearest_even);

        try std.testing.expectEqual(mpfr.Ternary.exact, inexact);
        try support.expectFlags(mpfr.Flags.none);
        try std.testing.expectEqual(precision, x.precision());
        try std.testing.expect(x.isRegular());
        try std.testing.expect(x.isInteger());
        try std.testing.expectEqual(@as(i32, 1), x.sign());
        try support.expectDigits(&x, 10, 31, "1267650600228229401496703205376", 31, .nearest_even);
    }
}

test "resetPrecision discards the value, exactly as mpfr_set_prec does" {
    try support.requireProvider();
    // doc/mpfr.texi:1499-1515.
    var x = try support.seventh(200);
    defer x.deinit();
    try std.testing.expectEqual(200, x.precision());
    try std.testing.expect(x.isRegular());

    x.resetPrecision(24);

    try std.testing.expectEqual(24, x.precision());
    try std.testing.expect(x.isNan());
    try std.testing.expect(!x.isNumber());
}

test "roundToPrecision keeps the value and zero-fills when widening" {
    try support.requireProvider();
    // doc/mpfr.texi:3325-3333: the precision grows without rounding, so the
    // ternary value is exact and the rendered digits are unchanged.
    var x = try support.seventh(24);
    defer x.deinit();
    try support.expectDigits(&x, 10, 20, "14285714924335479736", 0, .nearest_even);

    // The word is cleared after that first rendering rather than before it,
    // because the rendering raises the inexact flag whenever its own rounding
    // is inexact (doc/mpfr.texi:1942, src/get_str.c:2902), and a 20-digit
    // rendering of a 24-bit 1/7 is inexact. A word read further down would
    // still carry that bit and would say nothing about the widening.
    mpfr.clearAllFlags();
    const inexact = x.roundToPrecision(64, .nearest_even);

    try std.testing.expectEqual(mpfr.Ternary.exact, inexact);
    // src/round_prec.c:99-122: this entry point writes no flag, so the word is
    // still empty and the ternary value above is the whole report of the
    // change.
    try support.expectFlags(mpfr.Flags.none);
    try std.testing.expectEqual(64, x.precision());
    try std.testing.expect(x.isRegular());
    try support.expectDigits(&x, 10, 20, "14285714924335479736", 0, .nearest_even);
}

test "1/7 gains accuracy as the precision grows" {
    try support.requireProvider();
    const cases = [_]struct {
        precision: mpfr.Precision,
        want_digits: [:0]const u8,
    }{
        .{ .precision = 8, .want_digits = "14257812500000000000" },
        .{ .precision = 16, .want_digits = "14285659790039062500" },
        .{ .precision = 24, .want_digits = "14285714924335479736" },
        .{ .precision = 53, .want_digits = "14285714285714284921" },
        .{ .precision = 200, .want_digits = "14285714285714285714" },
    };
    for (cases) |case| {
        var x = try support.seventh(case.precision);
        defer x.deinit();
        try std.testing.expectEqual(case.precision, x.precision());
        mpfr.clearAllFlags();
        try support.expectDigits(&x, 10, 20, case.want_digits, 0, .nearest_even);
    }
}

test "1/3 at 200 bits renders 60 decimal digits" {
    try support.requireProvider();
    // 1/3 is 2/3 scaled by two, that is 0.101010...b in significand form, so
    // its 200-bit significand ends on a zero bit with a one behind it. That
    // remainder is more than half the last bit, so round-to-nearest moves the
    // value up and it sits above 1/3 by less than 2^-201. Its 60-digit
    // renderings are therefore 60 threes for nearest and toward negative
    // infinity, and the same string with the last digit incremented toward
    // positive infinity.
    var x = try support.third(200);
    defer x.deinit();

    const sixty_threes = "333333333333333333333333333333333333333333333333333333333333";
    const fifty_nine_threes_and_four = "333333333333333333333333333333333333333333333333333333333334";

    mpfr.clearAllFlags();
    try support.expectDigits(&x, 10, 60, sixty_threes, 0, .nearest_even);
    try support.expectDigits(&x, 10, 60, sixty_threes, 0, .toward_negative);
    try support.expectDigits(&x, 10, 60, fifty_nine_threes_and_four, 0, .toward_positive);
}

test "a double is exact once the precision reaches 53 bits" {
    try support.requireProvider();
    // Every finite f64 is representable in 53 significand bits, so 0.1 is exact
    // at 53 and at 200 bits, and inexact at 4 bits.
    var wide = mpfr.Float.init(200);
    defer wide.deinit();
    mpfr.clearAllFlags();
    try std.testing.expectEqual(mpfr.Ternary.exact, wide.setF64(0.1, .nearest_even));
    try support.expectFlags(mpfr.Flags.none);

    var narrow = mpfr.Float.init(4);
    defer narrow.deinit();
    mpfr.clearAllFlags();
    try std.testing.expect(narrow.setF64(0.1, .nearest_even) != .exact);
    try std.testing.expect(mpfr.flags().inexact);
}

test "6.75 at two bits is not a tie, so the nearer neighbour 6 wins" {
    try support.requireProvider();
    // 6.75 is 110.11b. At two bits the neighbours are 110b = 6 and 1000b = 8.
    // 6.75 sits 0.75 above 6 and 1.25 below 8, so this is not a tie and
    // round-to-nearest goes down. The directed modes still split.
    var x = try support.exactDecimal("6.75", 200);
    defer x.deinit();

    mpfr.clearAllFlags();
    const inexact = x.roundToPrecision(2, .nearest_even);

    try std.testing.expectEqual(mpfr.Ternary.below, inexact);
    // src/round_prec.c:99-122: the rounding is reported by the return value
    // above and raises no flag, so the word cleared before the call is still
    // empty. The f64 conversion below raises nothing either, because
    // mpfr_get_d writes no flag (src/get_d.c:34-132).
    try support.expectFlags(mpfr.Flags.none);
    try std.testing.expectEqual(6.0, x.toF64(.nearest_even));

    var up = try support.exactDecimal("6.75", 200);
    defer up.deinit();
    try std.testing.expectEqual(mpfr.Ternary.above, up.roundToPrecision(2, .toward_positive));
    try std.testing.expectEqual(8.0, up.toF64(.nearest_even));

    var down = try support.exactDecimal("6.75", 200);
    defer down.deinit();
    try std.testing.expectEqual(mpfr.Ternary.below, down.roundToPrecision(2, .toward_negative));
    try std.testing.expectEqual(6.0, down.toF64(.nearest_even));
}

test "6.75 at three bits is not a tie, so 7 wins" {
    try support.requireProvider();
    // At three bits the neighbours are 110b = 6 and 111b = 7, and 7 is nearer.
    var x = try support.exactDecimal("6.75", 200);
    defer x.deinit();

    mpfr.clearAllFlags();
    const inexact = x.roundToPrecision(3, .nearest_even);

    try std.testing.expectEqual(mpfr.Ternary.above, inexact);
    try std.testing.expectEqual(7.0, x.toF64(.nearest_even));

    var down = try support.exactDecimal("6.75", 200);
    defer down.deinit();
    try std.testing.expectEqual(mpfr.Ternary.below, down.roundToPrecision(3, .toward_negative));
    try std.testing.expectEqual(6.0, down.toF64(.nearest_even));
}
