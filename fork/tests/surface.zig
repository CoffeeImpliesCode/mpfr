//! Compile-only exercise of the whole public facade surface.
//!
//! This file exists because `zig build check` must analyse every public facade
//! method, not merely build a C archive that nothing references. Zig analyses a
//! function body only when that body is reached, and `std.testing.refAllDecls`
//! merely names a declaration: it does not instantiate anything. So every
//! public method is *called* here on real values, in a file that `check`
//! compiles. Assertions appear where the result of a call is worth stating in
//! its own right; where another file in this package already carries the
//! behavioural fixture, this file only has to reach the body.
//!
//! Every expectation here is derived independently of the code under test, and
//! every operation that has to be compared against a rounding mode is given a
//! freshly built operand, because the mutating methods leave their result in
//! the value they were called on.
//!
//! The behavioural fixtures themselves live in the other files of this package.
//! See `support.zig` for their provenance.

const std = @import("std");
const mpfr = @import("mpfr");
const support = @import("support.zig");

/// 1.75 held exactly at 200 bits.
///
/// None of the five integer roundings leaves a non-integer alone, so each of
/// them needs its own copy rather than the result of the previous one.
fn oneAndThreeQuarters() !mpfr.Float {
    return support.exactDecimal("1.75", 200);
}

test "every public Float method is reached with a real value" {
    var x = try support.exactDecimal("1.5", 200);
    defer x.deinit();
    var y = try support.exactDecimal("2.5", 200);
    defer y.deinit();
    var negative = try support.exactDecimal("-3.75", 200);
    defer negative.deinit();
    // A positive 3.75 for the negation below. Negating the negative value
    // instead would land back on the 3.75 that setAbs already stored, and the
    // assertion after it would then pass whether or not the call did anything.
    var positive = try support.exactDecimal("3.75", 200);
    defer positive.deinit();
    var not_a_number = mpfr.Float.init(64);
    defer not_a_number.deinit();
    not_a_number.setNan();
    var infinity = mpfr.Float.init(64);
    defer infinity.deinit();
    infinity.setInf(true);
    var zero = mpfr.Float.init(64);
    defer zero.deinit();
    zero.setZero(true);
    var scratch = mpfr.Float.init(200);
    defer scratch.deinit();

    // Precision.
    try std.testing.expectEqual(@as(mpfr.Precision, 200), x.precision());
    scratch.resetPrecision(64);
    try std.testing.expectEqual(@as(mpfr.Precision, 64), scratch.precision());
    try std.testing.expect(scratch.isNan());

    // Assignment and classification.
    _ = scratch.set(&x, .nearest_even);
    try std.testing.expectEqual(1.5, scratch.toF64(.nearest_even));
    _ = scratch.setAbs(&negative, .nearest_even);
    try std.testing.expectEqual(3.75, scratch.toF64(.nearest_even));
    // src/neg.c:24-28: mpfr_neg stores -op in rop, so this gives -3.75.
    _ = scratch.negateFrom(&positive, .nearest_even);
    try std.testing.expectEqual(-3.75, scratch.toF64(.nearest_even));
    _ = scratch.setF64(0.5, .nearest_even);
    try std.testing.expectEqual(0.5, scratch.toF64(.nearest_even));
    _ = scratch.setUnsigned(7, .nearest_even);
    try std.testing.expectEqual(7.0, scratch.toF64(.nearest_even));
    _ = scratch.setSigned(-7, .nearest_even);
    try std.testing.expectEqual(-7.0, scratch.toF64(.nearest_even));
    _ = scratch.setPowerOfTwo(-4, .nearest_even);
    try std.testing.expectEqual(0.0625, scratch.toF64(.nearest_even));
    try scratch.parseWhole("6.25", 10, .nearest_even);
    try std.testing.expectEqual(6.25, scratch.toF64(.nearest_even));
    const prefix = try scratch.parsePrefix("0.5z", 10, .nearest_even);
    try std.testing.expectEqual(@as(usize, 3), prefix.consumed);
    try std.testing.expectEqual(mpfr.Ternary.exact, prefix.ternary);

    // Arithmetic.
    _ = x.add(&y, .nearest_even);
    try std.testing.expectEqual(4.0, x.toF64(.nearest_even));
    _ = x.sub(&y, .nearest_even);
    try std.testing.expectEqual(1.5, x.toF64(.nearest_even));
    _ = x.mul(&y, .nearest_even);
    try std.testing.expectEqual(3.75, x.toF64(.nearest_even));
    _ = x.div(&y, .nearest_even);
    try std.testing.expectEqual(1.5, x.toF64(.nearest_even));
    _ = x.mulF64(4.0, .nearest_even);
    try std.testing.expectEqual(6.0, x.toF64(.nearest_even));
    _ = x.scaleByPowerOfTwo(1, .nearest_even);
    try std.testing.expectEqual(12.0, x.toF64(.nearest_even));
    _ = x.divideByPowerOfTwo(2, .nearest_even);
    try std.testing.expectEqual(3.0, x.toF64(.nearest_even));
    _ = x.sqrt(.nearest_even);
    // sqrt(3) = 1.7320508075688772935..., which lies strictly between 1.7
    // and 1.8.
    try std.testing.expect(x.toF64(.nearest_even) > 1.7);
    try std.testing.expect(x.toF64(.nearest_even) < 1.8);

    // Four significant bits of sqrt(3). The neighbours are 1.625 = 1.101b and
    // 1.75 = 1.110b; 1.75 is 0.018 away and 1.625 is 0.107 away, so this is
    // not a tie and the upper neighbour wins.
    _ = x.roundToPrecision(4, .nearest_even);
    try std.testing.expectEqual(1.75, x.toF64(.nearest_even));

    // 1.75 is not an integer, and the five integer roundings do not agree:
    // nearest-to-even, nearest-away and toward positive infinity all send it up
    // to 2, because 1.75 is nearer 2 than 1, while toward zero and toward
    // negative infinity send it down to 1. Each one starts from its own 1.75.
    {
        var v = try oneAndThreeQuarters();
        defer v.deinit();
        try std.testing.expectEqual(mpfr.Ternary.above, v.roundToNearestEven());
        try std.testing.expectEqual(2.0, v.toF64(.nearest_even));
    }
    {
        var v = try oneAndThreeQuarters();
        defer v.deinit();
        try std.testing.expectEqual(mpfr.Ternary.above, v.roundToNearestAway());
        try std.testing.expectEqual(2.0, v.toF64(.nearest_even));
    }
    {
        var v = try oneAndThreeQuarters();
        defer v.deinit();
        try std.testing.expectEqual(mpfr.Ternary.below, v.truncate());
        try std.testing.expectEqual(1.0, v.toF64(.nearest_even));
    }
    {
        var v = try oneAndThreeQuarters();
        defer v.deinit();
        try std.testing.expectEqual(mpfr.Ternary.above, v.ceil());
        try std.testing.expectEqual(2.0, v.toF64(.nearest_even));
    }
    {
        var v = try oneAndThreeQuarters();
        defer v.deinit();
        try std.testing.expectEqual(mpfr.Ternary.below, v.floor());
        try std.testing.expectEqual(1.0, v.toF64(.nearest_even));
    }

    // Comparison. `x` is 1.75, `y` is 2.5 and `negative` is still -3.75.
    try std.testing.expectEqual(mpfr.Order.lt, x.compare(&y));
    // The signed and the magnitude comparison answer different questions here,
    // which is what mpfr_cmpabs is for: 1.75 is above -3.75, while |1.75| is
    // below |-3.75| = 3.75.
    try std.testing.expectEqual(mpfr.Order.gt, x.compare(&negative));
    try std.testing.expectEqual(mpfr.Order.lt, x.compareAbs(&negative));
    try std.testing.expectEqual(mpfr.Order.lt, x.compareUnsigned(1000));
    try std.testing.expectEqual(mpfr.Order.gt, x.compareSigned(-1000));
    // `mpfr_unordered_p` returns non-zero when either operand is a NaN
    // (doc/mpfr.texi:2292-2294), so the comparison is unordered in either
    // direction and no ordering answer is defined for it.
    try std.testing.expect(x.isUnordered(&not_a_number));
    try std.testing.expect(not_a_number.isUnordered(&x));
    // Equality is not reflexivity: mpfr_equal_p is false against a NaN, and
    // true against a value parsed independently from text.
    try std.testing.expect(!x.isEqual(&not_a_number));
    var same = try support.exactDecimal("1.75", 200);
    defer same.deinit();
    try std.testing.expect(x.isEqual(&same));
    try std.testing.expect(!x.isEqual(&y));

    // Classification.
    try std.testing.expect(not_a_number.isNan());
    try std.testing.expect(infinity.isInf());
    try std.testing.expect(zero.isZero());
    try std.testing.expect(x.isRegular());
    try std.testing.expect(x.isNumber());
    // 1.75 has a fractional part, -3.75 has one, and 2 has none.
    try std.testing.expect(!x.isInteger());
    try std.testing.expect(!negative.isInteger());
    var whole = mpfr.Float.init(200);
    defer whole.deinit();
    _ = whole.setUnsigned(2, .nearest_even);
    try std.testing.expect(whole.isInteger());
    try std.testing.expect(negative.isSignNegative());
    try std.testing.expectEqual(@as(i32, -1), negative.sign());
    try std.testing.expectEqual(@as(i32, 0), not_a_number.sign());

    // Conversion out. The value is pinned here so the assertions do not depend
    // on the sequence above. 3.75 is not an integer, so the integer
    // conversions round it: 3 toward zero and 4 toward positive infinity, and
    // its ten-digit rendering is 0.3750000000 * 10^1.
    _ = x.setAbs(&negative, .nearest_even);
    try std.testing.expectEqual(3.75, x.toF64(.nearest_even));
    try std.testing.expectEqual(@as(c_long, 3), x.toSigned(.toward_zero));
    try std.testing.expectEqual(@as(c_long, 4), x.toSigned(.toward_positive));
    try std.testing.expectEqual(@as(c_ulong, 3), x.toUnsigned(.toward_zero));
    // Whether a value "fits" an integer type is decided after rounding to an
    // integer, not before (doc/mpfr.texi:1964-1969; src/fits_s.h:42-48 is the
    // same rule spelled out for the signed family), so 3.75 fits both domains
    // here even though it has a fractional part.
    try std.testing.expect(x.fitsSigned(.toward_zero));
    try std.testing.expect(x.fitsUnsigned(.toward_zero));
    // A negative value is outside the unsigned domain whatever the direction,
    // while 2^100 is a valid integer that no long can hold. Both are real range
    // boundaries rather than a statement about a constant.
    try std.testing.expect(negative.fitsSigned(.toward_zero));
    try std.testing.expect(!negative.fitsUnsigned(.toward_zero));
    _ = scratch.setPowerOfTwo(100, .nearest_even);
    try std.testing.expect(!scratch.fitsSigned(.toward_zero));
    try std.testing.expect(!scratch.fitsUnsigned(.toward_zero));

    // Rendering, with the owning deinit.
    mpfr.clearAllFlags();
    var rendered = try x.toDigits(10, 10, .nearest_even);
    defer rendered.deinit();
    try std.testing.expectEqualStrings("3750000000", rendered.digits());
    try std.testing.expectEqual(@as(mpfr.Exponent, 1), rendered.exponent);
    try support.expectFlags(mpfr.Flags.none);

    // The raw escape hatch, in both directions.
    _ = mpfr.c.mpfr_set_ui_2exp(x.raw(), 1, 3, mpfr.c.MPFR_RNDN);
    try std.testing.expectEqual(8.0, x.toF64(.nearest_even));
    try std.testing.expectEqual(8.0, mpfr.c.mpfr_get_d(x.rawConst(), mpfr.c.MPFR_RNDN));
}

test "every module-level facade function is reached" {
    // These three are informational: the pinned release, and the agreement
    // between the translated header and the linked library it came from, are
    // the provenance job's business rather than this suite's. Calling them
    // here is what makes `check` analyse their bodies.
    _ = mpfr.version();
    _ = mpfr.tuningCase();
    _ = mpfr.patches();

    // The process-wide defaults are moved here and put back, because
    // rounding_test.zig states what an explicit direction does to a result
    // while a different default is in force. What that default reads back is
    // a setting of the library, not a result of any computation, so this file
    // only has to reach the accessors.
    const previous_precision = mpfr.defaultPrecision();
    const previous_mode = mpfr.defaultRoundingMode();
    defer {
        mpfr.setDefaultPrecision(previous_precision);
        mpfr.setDefaultRoundingMode(previous_mode);
    }
    mpfr.setDefaultPrecision(80);
    mpfr.setDefaultRoundingMode(.toward_negative);

    const previous_emin = mpfr.minimumExponentInUse();
    const previous_emax = mpfr.maximumExponentInUse();
    defer {
        _ = mpfr.setMinimumExponent(previous_emin);
        _ = mpfr.setMaximumExponent(previous_emax);
    }
    _ = mpfr.minimumExponent();
    _ = mpfr.maximumNegativeExponent();
    _ = mpfr.minimumPositiveExponent();
    _ = mpfr.maximumExponent();

    // With the largest allowed exponent at 64, 2^100 no longer fits.
    // src/set_ui_2exp.c:78 ends the assignment in mpfr_check_range, whose
    // overflow branch (src/exceptions.c:405-429) stores a positive infinity,
    // returns a positive ternary value, and raises the overflow and inexact
    // flags. The range checks themselves are in range_test.zig.
    try std.testing.expect(mpfr.setMaximumExponent(64));
    var beyond_range = mpfr.Float.init(200);
    defer beyond_range.deinit();

    mpfr.clearAllFlags();
    const overflow_ternary = beyond_range.setPowerOfTwo(100, .nearest_even);
    try std.testing.expectEqual(mpfr.Ternary.above, overflow_ternary);
    try std.testing.expect(beyond_range.isInf());
    try std.testing.expect(!beyond_range.isSignNegative());
    try support.expectFlags(.{ .overflow = true, .inexact = true });
    defer mpfr.clearAllFlags();

    mpfr.clearAllFlags();
    mpfr.setFlags(.{ .inexact = true });
    try std.testing.expect(mpfr.flags().inexact);
    mpfr.clearFlags(.{ .inexact = true });
    try std.testing.expectEqual(mpfr.Flags.none, mpfr.flags());
    // lifetime_test.zig states the bit-level behaviour of raising and lowering
    // individual bits, so this block only has to reach these bodies.
    mpfr.setFlags(mpfr.Flags.all);
    mpfr.clearAllFlags();

    // The ternary mapping, checked against a real operation rather than a
    // hand-written table. 2.5 is 10.1b, so at two bits its neighbours are
    // 2 = 10.0b and 3 = 11.0b, and it lies exactly between them. Each
    // direction gets its own parse, because rounding once would leave the next
    // call with 2, which two bits represent exactly.
    var x = mpfr.Float.init(200);
    defer x.deinit();
    try x.parseWhole("2.5", 10, .nearest_even);
    try std.testing.expectEqual(mpfr.Ternary.below, x.roundToPrecision(2, .nearest_even));
    try std.testing.expectEqual(2.0, x.toF64(.nearest_even));

    var up = mpfr.Float.init(200);
    defer up.deinit();
    try up.parseWhole("2.5", 10, .nearest_even);
    try std.testing.expectEqual(mpfr.Ternary.above, up.roundToPrecision(2, .toward_positive));
    try std.testing.expectEqual(3.0, up.toF64(.nearest_even));

    // The ternary mapping is read out of the value MPFR itself returned, not
    // out of a hand-written table: a result above the exact one comes back
    // positive and a result below it comes back negative
    // (doc/mpfr.texi:1002-1014).
    var raw_value = try support.exactDecimal("2.5", 200);
    defer raw_value.deinit();
    const raw_below = mpfr.c.mpfr_prec_round(raw_value.raw(), 2, mpfr.c.MPFR_RNDN);
    try std.testing.expect(raw_below < 0);
    try std.testing.expectEqual(mpfr.Ternary.below, mpfr.Ternary.fromRaw(raw_below));

    // A second 2.5, because the first call left 2 in that one and two bits
    // hold 2 exactly, so rounding it again would report zero.
    var raw_other = try support.exactDecimal("2.5", 200);
    defer raw_other.deinit();
    const raw_above = mpfr.c.mpfr_prec_round(raw_other.raw(), 2, mpfr.c.MPFR_RNDU);
    try std.testing.expect(raw_above > 0);
    try std.testing.expectEqual(mpfr.Ternary.above, mpfr.Ternary.fromRaw(raw_above));
    // `toRaw` is the other direction of the same convention. Restating the
    // sign of a hand-written enumerator would only repeat its definition, so
    // the calls here exist to reach the body.
    _ = mpfr.Ternary.below.toRaw();
    _ = mpfr.Ternary.above.toRaw();
    _ = mpfr.Ternary.exact.toRaw();

    mpfr.freeCaches();
    mpfr.cleanupMemory();
}
