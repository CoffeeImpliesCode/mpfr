//! Arithmetic and conversion methods of the facade.
//!
//! Every exact case below uses operands that are exactly representable in
//! binary, so MPFR must report a ternary value of zero and raise no flag. That
//! is the check that the facade is not silently rounding exact work. The inexact
//! cases use 1/3 and 3/5, whose binary expansions 0.010101...b and
//! 0.1001100110011...b never terminate, and assert the documented contract: a
//! non-zero ternary value and the inexact flag (doc/mpfr.texi:1002-1014,
//! 1150-1153).
//!
//! Scaling by a power of two is always exact, which is what
//! `mpfr_mul_2ui` and `mpfr_div_2ui` guarantee and what the
//! `mpfr_mul_2exp` and `mpfr_div_2exp` macros expand to (src/mpfr.h:932-933).

const std = @import("std");
const mpfr = @import("mpfr");
const support = @import("support.zig");

test "exact operands in the four basic operations" {
    try support.requireProvider();
    {
        var accumulator = try support.exactDecimal("1.5", 200);
        defer accumulator.deinit();
        var operand = try support.exactDecimal("2.25", 200);
        defer operand.deinit();

        mpfr.clearAllFlags();
        try std.testing.expectEqual(mpfr.Ternary.exact, accumulator.add(&operand, .nearest_even));
        try std.testing.expectEqual(3.75, accumulator.toF64(.nearest_even));
        try support.expectFlags(mpfr.Flags.none);
    }
    {
        var accumulator = try support.exactDecimal("3.75", 200);
        defer accumulator.deinit();
        var operand = try support.exactDecimal("1.5", 200);
        defer operand.deinit();

        mpfr.clearAllFlags();
        try std.testing.expectEqual(mpfr.Ternary.exact, accumulator.sub(&operand, .nearest_even));
        try std.testing.expectEqual(2.25, accumulator.toF64(.nearest_even));
        try support.expectFlags(mpfr.Flags.none);
    }
    {
        var accumulator = try support.exactDecimal("1.5", 200);
        defer accumulator.deinit();
        var operand = try support.exactDecimal("2.5", 200);
        defer operand.deinit();

        mpfr.clearAllFlags();
        try std.testing.expectEqual(mpfr.Ternary.exact, accumulator.mul(&operand, .nearest_even));
        try std.testing.expectEqual(3.75, accumulator.toF64(.nearest_even));
        try support.expectFlags(mpfr.Flags.none);
    }
    {
        var accumulator = try support.exactDecimal("3.75", 200);
        defer accumulator.deinit();
        var operand = try support.exactDecimal("1.5", 200);
        defer operand.deinit();

        mpfr.clearAllFlags();
        try std.testing.expectEqual(mpfr.Ternary.exact, accumulator.div(&operand, .nearest_even));
        try std.testing.expectEqual(2.5, accumulator.toF64(.nearest_even));
        try support.expectFlags(mpfr.Flags.none);
    }
}

test "in-place aliasing is allowed, as mpfr_mul(x, x, x, rnd) is" {
    try support.requireProvider();
    // doc/mpfr.texi:876-882: MPFR allows the same variable for input and output.
    var x = try support.exactDecimal("1.5", 200);
    defer x.deinit();

    mpfr.clearAllFlags();
    try std.testing.expectEqual(mpfr.Ternary.exact, x.mul(&x, .nearest_even));
    try std.testing.expectEqual(2.25, x.toF64(.nearest_even));

    try std.testing.expectEqual(mpfr.Ternary.exact, x.sqrt(.nearest_even));
    try std.testing.expectEqual(1.5, x.toF64(.nearest_even));
}

test "an inexact quotient reports a non-zero ternary value and the inexact flag" {
    try support.requireProvider();
    // 1.5 / 2.5 is 3/5, whose binary expansion 0.1001100110011...b does not
    // terminate, so the result is inexact at every finite precision.
    var quotient = try support.exactDecimal("1.5", 200);
    defer quotient.deinit();
    var divisor = try support.exactDecimal("2.5", 200);
    defer divisor.deinit();

    mpfr.clearAllFlags();
    const inexact = quotient.div(&divisor, .nearest_even);

    try std.testing.expect(inexact != .exact);
    try std.testing.expectEqual(mpfr.Flags{ .inexact = true }, mpfr.flags());
    // 3/5 is not near a binary64 tie, so the 200-bit value and the nearest
    // double agree once converted.
    try std.testing.expectEqual(0.6, quotient.toF64(.nearest_even));
}

test "scaling by a power of two is exact in both directions" {
    try support.requireProvider();
    var x = try support.exactDecimal("1.5", 200);
    defer x.deinit();

    mpfr.clearAllFlags();
    try std.testing.expectEqual(mpfr.Ternary.exact, x.scaleByPowerOfTwo(3, .nearest_even));
    try std.testing.expectEqual(12.0, x.toF64(.nearest_even));
    try support.expectFlags(mpfr.Flags.none);

    mpfr.clearAllFlags();
    try std.testing.expectEqual(mpfr.Ternary.exact, x.divideByPowerOfTwo(2, .nearest_even));
    try std.testing.expectEqual(3.0, x.toF64(.nearest_even));
    try support.expectFlags(mpfr.Flags.none);

    // Scaling 1/3 by a power of two is exact too, because only the exponent
    // moves.
    var third = try support.third(200);
    defer third.deinit();
    mpfr.clearAllFlags();
    try std.testing.expectEqual(mpfr.Ternary.exact, third.scaleByPowerOfTwo(10, .nearest_even));
    try support.expectFlags(mpfr.Flags.none);
    // Only the exponent moved, so the value is still the 200-bit 1/3 scaled by
    // 2^10, whose nearest double is the nearest one to 1024/3.
    try std.testing.expectEqual(@as(f64, 1024.0 / 3.0), third.toF64(.nearest_even));
}

test "set, setAbs and negateFrom copy a value exactly" {
    try support.requireProvider();
    var source = try support.exactDecimal("3.75", 200);
    defer source.deinit();

    var copy = mpfr.Float.init(53);
    defer copy.deinit();
    mpfr.clearAllFlags();
    try std.testing.expectEqual(mpfr.Ternary.exact, copy.set(&source, .nearest_even));
    try std.testing.expectEqual(3.75, copy.toF64(.nearest_even));
    try std.testing.expect(copy.isEqual(&source));
    try support.expectFlags(mpfr.Flags.none);

    var magnitude = mpfr.Float.init(53);
    defer magnitude.deinit();
    mpfr.clearAllFlags();
    try std.testing.expectEqual(mpfr.Ternary.exact, magnitude.setAbs(&source, .nearest_even));
    try std.testing.expectEqual(3.75, magnitude.toF64(.nearest_even));
    try support.expectFlags(mpfr.Flags.none);

    var negative = mpfr.Float.init(53);
    defer negative.deinit();
    mpfr.clearAllFlags();
    try std.testing.expectEqual(mpfr.Ternary.exact, negative.negateFrom(&source, .nearest_even));
    try std.testing.expectEqual(-3.75, negative.toF64(.nearest_even));
    try support.expectFlags(mpfr.Flags.none);

    // setAbs of a negative value drops the sign.
    mpfr.clearAllFlags();
    try std.testing.expectEqual(mpfr.Ternary.exact, magnitude.setAbs(&negative, .nearest_even));
    try std.testing.expectEqual(3.75, magnitude.toF64(.nearest_even));
    try std.testing.expect(!magnitude.isSignNegative());
}

test "mulF64 uses the double exactly, without a detour through the significand" {
    try support.requireProvider();
    // This is mpfr_mul_d, which multiplies by the exact value of the double.
    var x = try support.exactDecimal("1.5", 200);
    defer x.deinit();

    mpfr.clearAllFlags();
    try std.testing.expectEqual(mpfr.Ternary.exact, x.mulF64(0.5, .nearest_even));
    try std.testing.expectEqual(0.75, x.toF64(.nearest_even));
    try support.expectFlags(mpfr.Flags.none);

    // A double that needs all 53 bits is exact too.
    mpfr.clearAllFlags();
    try std.testing.expectEqual(mpfr.Ternary.exact, x.mulF64(0.1, .nearest_even));
    try support.expectFlags(mpfr.Flags.none);

    // Multiplying 1/3 by 0.1 is inexact, because 1/3 never terminates.
    var third = try support.third(200);
    defer third.deinit();
    mpfr.clearAllFlags();
    const inexact = third.mulF64(0.1, .nearest_even);
    try std.testing.expect(inexact != .exact);
    try std.testing.expectEqual(mpfr.Flags{ .inexact = true }, mpfr.flags());
    // The double 0.1 is exactly 3602879701896397 * 2^-55, and the 200-bit 1/3
    // is within 2^-201 of 1/3, so the product is within 2^-201 of 1/30 and its
    // nearest double is the nearest one to 1/30.
    try std.testing.expectEqual(@as(f64, 1.0 / 30.0), third.toF64(.nearest_even));
}

test "integer comparison and conversion follow the C long domain" {
    try support.requireProvider();
    var x = try support.exactDecimal("3.75", 200);
    defer x.deinit();

    try std.testing.expectEqual(mpfr.Order.gt, x.compareSigned(3));
    try std.testing.expectEqual(mpfr.Order.gt, x.compareUnsigned(3));
    try std.testing.expectEqual(mpfr.Order.lt, x.compareSigned(4));
    try std.testing.expectEqual(mpfr.Order.gt, x.compareSigned(-4));

    // Whether a value "fits" an integer type is decided after rounding to an
    // integer, not before (doc/mpfr.texi:1964-1969; src/fits_s.h:42-48 spells
    // the same rule out as "MINIMUM <= round(f, prec(long), rnd) <= MAXIMUM"),
    // so 3.75 has a fractional part and still fits both domains: it rounds to
    // 3, and 3 is in range for each of them. It raises no flag, because the
    // conversion happened inside the query.
    mpfr.clearAllFlags();
    try std.testing.expect(x.fitsSigned(.toward_zero));
    try std.testing.expect(x.fitsUnsigned(.toward_zero));
    try support.expectFlags(mpfr.Flags.none);

    try std.testing.expectEqual(@as(c_long, 3), x.toSigned(.toward_zero));
    try std.testing.expectEqual(@as(c_long, 4), x.toSigned(.toward_positive));
    try std.testing.expectEqual(@as(c_ulong, 3), x.toUnsigned(.toward_zero));

    var whole = try support.exactDecimal("4", 200);
    defer whole.deinit();
    try std.testing.expect(whole.fitsSigned(.toward_zero));
    try std.testing.expect(whole.fitsUnsigned(.toward_zero));

    // The manual's own boundary case: with MPFR_RNDU on -0.5 every fits_
    // function is non-zero (doc/mpfr.texi:1968-1969), because rounding toward
    // positive infinity sends -0.5 to 0, which every one of those types holds.
    // Rounding toward negative infinity instead sends it to -1, which no
    // unsigned type holds while every signed one does (src/fits_u.h:39-43).
    var minus_half = try support.exactDecimal("-0.5", 200);
    defer minus_half.deinit();
    try std.testing.expect(minus_half.fitsSigned(.toward_positive));
    try std.testing.expect(minus_half.fitsUnsigned(.toward_positive));
    try std.testing.expect(minus_half.fitsSigned(.toward_negative));
    try std.testing.expect(!minus_half.fitsUnsigned(.toward_negative));

    var negative = try support.exactDecimal("-4", 200);
    defer negative.deinit();
    try std.testing.expect(negative.fitsSigned(.toward_zero));
    // A negative value is outside the unsigned domain.
    try std.testing.expect(!negative.fitsUnsigned(.toward_zero));
    try std.testing.expectEqual(@as(c_long, -4), negative.toSigned(.toward_zero));
}

test "sqrt is exact for a perfect square and inexact otherwise" {
    try support.requireProvider();
    {
        var x = try support.exactDecimal("2.25", 200);
        defer x.deinit();
        mpfr.clearAllFlags();
        try std.testing.expectEqual(mpfr.Ternary.exact, x.sqrt(.nearest_even));
        try std.testing.expectEqual(1.5, x.toF64(.nearest_even));
        try support.expectFlags(mpfr.Flags.none);
    }
    {
        var x = try support.exactDecimal("2", 200);
        defer x.deinit();
        mpfr.clearAllFlags();
        const inexact = x.sqrt(.nearest_even);
        try std.testing.expect(inexact != .exact);
        try std.testing.expectEqual(mpfr.Flags{ .inexact = true }, mpfr.flags());
        // sqrt(2) is 1.41421356237... and is not near a binary64 tie.
        try std.testing.expectEqual(1.4142135623730951, x.toF64(.nearest_even));
    }
}
