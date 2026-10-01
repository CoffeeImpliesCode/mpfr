//! Exponent-range behaviour: overflow and underflow, and the flags and ternary
//! values that go with them.
//!
//! Provenance of the expected values: upstream's own test suite states each of
//! them, and this file reproduces those cases through the facade.
//!
//!  * Overflow with round-to-nearest yields a positive infinity, and
//!    tests/tdiv.c:920-930 asserts the flag word is exactly
//!    `MPFR_FLAGS_OVERFLOW | MPFR_FLAGS_INEXACT`.
//!  * tests/texpm1.c:99-121 gives the ternary sign on both sides: round-to-
//!    nearest and round-toward-positive overflow to an infinity with a
//!    positive ternary value, while round-toward-negative overflows to a finite
//!    value with a negative ternary value.
//!  * Underflow with round-toward-zero yields a zero, and tests/tdiv.c:931-970
//!    asserts the flag word is exactly
//!    `MPFR_FLAGS_UNDERFLOW | MPFR_FLAGS_INEXACT`.
//!  * `mpfr_set_emin` and `mpfr_set_emax` report out-of-range requests and leave
//!    the range untouched, per doc/mpfr.texi:3733-3755.

const std = @import("std");
const mpfr = @import("mpfr");

test "the documented exponent bounds accept the values this test uses" {
    // A precondition check, so a platform that narrows the range fails loudly
    // here rather than mysteriously inside the overflow cases. The four bounds
    // are the limits the library itself reports (src/mpfr.h:3733-3755), and
    // each of them must contain the +/-1 the cases below narrow the range to.
    try std.testing.expect(mpfr.minimumExponent() <= -1);
    try std.testing.expect(mpfr.maximumNegativeExponent() >= -1);
    try std.testing.expect(mpfr.minimumPositiveExponent() <= 1);
    try std.testing.expect(mpfr.maximumExponent() >= 1);
}

test "an out-of-range exponent request is rejected and changes nothing" {
    // doc/mpfr.texi:3733-3738: a non-zero return means the exponent was not
    // accepted and the range was not changed.
    const previous = mpfr.maximumExponentInUse();
    try std.testing.expect(!mpfr.setMaximumExponent(mpfr.maximumExponent() + 1));
    try std.testing.expectEqual(previous, mpfr.maximumExponentInUse());

    const previous_min = mpfr.minimumExponentInUse();
    try std.testing.expect(!mpfr.setMinimumExponent(mpfr.minimumExponent() - 1));
    try std.testing.expectEqual(previous_min, mpfr.minimumExponentInUse());
}

test "round-to-nearest overflow yields a positive infinity, inexact" {
    // tests/tdiv.c:920-930 with emax = 1: 1 / 0.5 = 2 is out of range.
    const previous_emin = mpfr.minimumExponentInUse();
    const previous_emax = mpfr.maximumExponentInUse();
    defer restoreRange(previous_emin, previous_emax);
    try std.testing.expect(mpfr.setMaximumExponent(1));

    var numerator = mpfr.Float.init(53);
    defer numerator.deinit();
    _ = numerator.setUnsigned(1, .toward_zero);

    var denominator = mpfr.Float.init(53);
    defer denominator.deinit();
    _ = denominator.setUnsigned(1, .toward_zero);
    _ = denominator.divideByPowerOfTwo(1, .toward_zero);

    mpfr.clearAllFlags();
    const inexact = numerator.div(&denominator, .nearest_even);

    try std.testing.expect(numerator.isInf());
    try std.testing.expect(!numerator.isSignNegative());
    // tests/texpm1.c:108-112: an infinity from an overflow counts as inexact,
    // and the stored value is greater than the exact result.
    try std.testing.expect(inexact == .above);
    try std.testing.expectEqual(
        mpfr.Flags{ .overflow = true, .inexact = true },
        mpfr.flags(),
    );
}

test "round-toward-positive overflow is also inexact and above" {
    // tests/texpm1.c:113-121.
    const previous_emin = mpfr.minimumExponentInUse();
    const previous_emax = mpfr.maximumExponentInUse();
    defer restoreRange(previous_emin, previous_emax);
    try std.testing.expect(mpfr.setMaximumExponent(1));

    var numerator = mpfr.Float.init(53);
    defer numerator.deinit();
    _ = numerator.setUnsigned(1, .toward_zero);

    var denominator = mpfr.Float.init(53);
    defer denominator.deinit();
    _ = denominator.setUnsigned(1, .toward_zero);
    _ = denominator.divideByPowerOfTwo(1, .toward_zero);

    mpfr.clearAllFlags();
    const inexact = numerator.div(&denominator, .toward_positive);

    try std.testing.expect(numerator.isInf());
    try std.testing.expect(inexact == .above);
    try std.testing.expectEqual(
        mpfr.Flags{ .overflow = true, .inexact = true },
        mpfr.flags(),
    );
}

test "round-toward-negative overflow saturates to a finite value below the exact result" {
    // tests/texpm1.c:114-121 asserts `!MPFR_IS_INF (x) && MPFR_IS_POS (x)` and
    // `inex < 0` for this case.
    const previous_emin = mpfr.minimumExponentInUse();
    const previous_emax = mpfr.maximumExponentInUse();
    defer restoreRange(previous_emin, previous_emax);
    try std.testing.expect(mpfr.setMaximumExponent(1));

    var numerator = mpfr.Float.init(53);
    defer numerator.deinit();
    _ = numerator.setUnsigned(1, .toward_zero);

    var denominator = mpfr.Float.init(53);
    defer denominator.deinit();
    _ = denominator.setUnsigned(1, .toward_zero);
    _ = denominator.divideByPowerOfTwo(1, .toward_zero);

    mpfr.clearAllFlags();
    const inexact = numerator.div(&denominator, .toward_negative);

    try std.testing.expect(!numerator.isInf());
    try std.testing.expect(!numerator.isSignNegative());
    try std.testing.expect(inexact == .below);
    // The saturated result is below the exact 2 but still above 1, because the
    // largest value with emax = 1 is (1 - 2^-53) * 2.
    try std.testing.expectEqual(mpfr.Order.gt, numerator.compareUnsigned(1));
    try std.testing.expectEqual(mpfr.Order.lt, numerator.compareUnsigned(2));
    try std.testing.expectEqual(
        mpfr.Flags{ .overflow = true, .inexact = true },
        mpfr.flags(),
    );
}

test "underflow with round-toward-zero yields a zero, inexact" {
    // tests/tdiv.c:931-970 with emin = -1: 2^-2 / 2 is 2^-3, far below the
    // smallest normal value, so the result truncates to zero.
    const previous_emin = mpfr.minimumExponentInUse();
    const previous_emax = mpfr.maximumExponentInUse();
    defer restoreRange(previous_emin, previous_emax);
    try std.testing.expect(mpfr.setMinimumExponent(-1));

    var numerator = mpfr.Float.init(53);
    defer numerator.deinit();
    _ = numerator.setPowerOfTwo(-2, .toward_zero);

    var denominator = mpfr.Float.init(53);
    defer denominator.deinit();
    _ = denominator.setUnsigned(2, .toward_zero);

    mpfr.clearAllFlags();
    const inexact = numerator.div(&denominator, .toward_zero);

    try std.testing.expect(numerator.isZero());
    try std.testing.expect(!numerator.isSignNegative());
    try std.testing.expect(inexact == .below);
    try std.testing.expectEqual(
        mpfr.Flags{ .underflow = true, .inexact = true },
        mpfr.flags(),
    );
}

/// Put back the exponent bounds a test narrowed.
///
/// Both bounds came from the library itself, so neither request can be out of
/// range. A failure means the library changed its own bounds mid-test, which is
/// not something this suite can recover from, so it stops the run outright
/// rather than leaving the range narrowed for the next test.
fn restoreRange(emin: mpfr.Exponent, emax: mpfr.Exponent) void {
    if (!mpfr.setMinimumExponent(emin)) @panic("restoring emin failed");
    if (!mpfr.setMaximumExponent(emax)) @panic("restoring emax failed");
}
