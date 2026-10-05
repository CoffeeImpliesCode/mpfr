//! NaN, infinity, zero, and the flags raised by division by zero.
//!
//! Provenance of the expected values: upstream's own test suite states each of
//! them in tests/tdiv.c, and the ternary rule comes from doc/mpfr.texi:1002-1014
//! (an infinite result is exact unless it came from overflow, and a NaN result
//! is always exact).
//!
//!  * `1 / +0` is `+inf`, ternary 0, flags exactly `MPFR_FLAGS_DIVBY0`
//!    (tests/tdiv.c:848-852).
//!  * `1 / -0` is `-inf`, ternary 0, flags exactly `MPFR_FLAGS_DIVBY0`
//!    (tests/tdiv.c:853-858).
//!  * `-1 / +0` is `-inf` and `-1 / -0` is `+inf`, both with the same ternary
//!    value and the same single flag (tests/tdiv.c:859-870).
//!  * `+inf / +0` is `+inf`, ternary 0, and raises no flag at all
//!    (tests/tdiv.c:871-877), because the input is already infinite.
//!  * `+inf / +inf` is NaN, ternary 0, flags exactly `MPFR_FLAGS_NAN`
//!    (tests/tdiv.c:845-846).

const std = @import("std");
const mpfr = @import("mpfr");
const support = @import("support.zig");

test "a NaN classifies as NaN and nothing else" {
    try support.requireProvider();
    var x = mpfr.Float.init(64);
    defer x.deinit();
    x.setNan();

    try std.testing.expect(x.isNan());
    try std.testing.expect(!x.isInf());
    try std.testing.expect(!x.isZero());
    try std.testing.expect(!x.isRegular());
    try std.testing.expect(!x.isNumber());
    try std.testing.expect(!x.isSignNegative());
    try std.testing.expect(std.math.isNan(x.toF64(.nearest_even)));
}

test "an infinity classifies as an infinity with the requested sign" {
    try support.requireProvider();
    var positive = mpfr.Float.init(64);
    defer positive.deinit();
    positive.setInf(true);

    try std.testing.expect(positive.isInf());
    try std.testing.expect(!positive.isNan());
    try std.testing.expect(!positive.isZero());
    try std.testing.expect(!positive.isRegular());
    try std.testing.expect(!positive.isNumber());
    try std.testing.expect(!positive.isSignNegative());
    try std.testing.expectEqual(@as(i32, 1), positive.sign());
    try std.testing.expect(std.math.isInf(positive.toF64(.nearest_even)));

    var negative = mpfr.Float.init(64);
    defer negative.deinit();
    negative.setInf(false);

    try std.testing.expect(negative.isInf());
    try std.testing.expect(negative.isSignNegative());
    try std.testing.expectEqual(@as(i32, -1), negative.sign());
    try std.testing.expectEqual(-std.math.inf(f64), negative.toF64(.nearest_even));
}

test "a zero is signed, and its sign function reports zero" {
    try support.requireProvider();
    var positive = mpfr.Float.init(64);
    defer positive.deinit();
    positive.setZero(true);

    try std.testing.expect(positive.isZero());
    try std.testing.expect(!positive.isNan());
    try std.testing.expect(!positive.isInf());
    try std.testing.expect(!positive.isRegular());
    try std.testing.expect(positive.isNumber());
    try std.testing.expect(!positive.isSignNegative());
    try std.testing.expectEqual(@as(i32, 0), positive.sign());

    var negative = mpfr.Float.init(64);
    defer negative.deinit();
    negative.setZero(false);

    try std.testing.expect(negative.isZero());
    try std.testing.expect(negative.isSignNegative());
    try std.testing.expectEqual(@as(i32, 0), negative.sign());
    // A negative zero compares equal to a positive zero.
    try std.testing.expectEqual(mpfr.Order.eq, negative.compare(&positive));
    try std.testing.expect(negative.isEqual(&positive));
}

test "sign on a NaN reports zero and raises the range-error flag" {
    try support.requireProvider();
    // The `mpfr_sgn` macro (src/mpfr.h:901-904) evaluates
    // `mpfr_set_erangeflag()` for a NaN, so the side effect is part of the
    // contract this facade mirrors.
    var x = mpfr.Float.init(64);
    defer x.deinit();
    x.setNan();

    mpfr.clearAllFlags();
    try std.testing.expectEqual(@as(i32, 0), x.sign());
    try std.testing.expectEqual(mpfr.Flags{ .erange = true }, mpfr.flags());

    // A zero is not a NaN, so it reports zero without raising anything.
    var zero = mpfr.Float.init(64);
    defer zero.deinit();
    zero.setZero(false);

    mpfr.clearAllFlags();
    try std.testing.expectEqual(@as(i32, 0), zero.sign());
    try std.testing.expectEqual(mpfr.Flags.none, mpfr.flags());
}

test "any comparison involving a NaN is unordered and compares equal" {
    try support.requireProvider();
    // doc/mpfr.texi:2304-2320: mpfr_cmp yields 0 when either operand is NaN,
    // which is the same sentinel mpfr_cmp uses for equality.
    var nan_value = mpfr.Float.init(64);
    defer nan_value.deinit();
    nan_value.setNan();

    var one = mpfr.Float.init(64);
    defer one.deinit();
    _ = one.setUnsigned(1, .nearest_even);

    try std.testing.expect(nan_value.isUnordered(&one));
    try std.testing.expect(one.isUnordered(&nan_value));
    try std.testing.expect(!nan_value.isEqual(&one));
    try std.testing.expectEqual(mpfr.Order.eq, nan_value.compare(&one));
    try std.testing.expectEqual(mpfr.Order.eq, one.compare(&nan_value));
}

test "dividing a non-zero value by zero yields a signed infinity, exactly" {
    try support.requireProvider();
    // tests/tdiv.c:848-870.
    const cases = [_]struct {
        numerator: c_long,
        denominator_negative: bool,
        want_negative: bool,
    }{
        .{ .numerator = 1, .denominator_negative = false, .want_negative = false },
        .{ .numerator = 1, .denominator_negative = true, .want_negative = true },
        .{ .numerator = -1, .denominator_negative = false, .want_negative = true },
        .{ .numerator = -1, .denominator_negative = true, .want_negative = false },
    };
    for (cases) |case| {
        var numerator = mpfr.Float.init(64);
        defer numerator.deinit();
        _ = numerator.setSigned(case.numerator, .nearest_even);

        var denominator = mpfr.Float.init(64);
        defer denominator.deinit();
        denominator.setZero(!case.denominator_negative);

        mpfr.clearAllFlags();
        const inexact = numerator.div(&denominator, .toward_zero);

        // An exact infinite result, so the ternary value is zero
        // (doc/mpfr.texi:1010-1012) and only the divide-by-zero flag is raised
        // (doc/mpfr.texi:1141-1142).
        try std.testing.expectEqual(mpfr.Ternary.exact, inexact);
        try std.testing.expect(numerator.isInf());
        try std.testing.expectEqual(case.want_negative, numerator.isSignNegative());
        try std.testing.expectEqual(mpfr.Flags{ .divide_by_zero = true }, mpfr.flags());
    }
}

test "dividing an infinity by zero is exact and raises no flag" {
    try support.requireProvider();
    // tests/tdiv.c:871-877: the divide-by-zero flag needs finite inputs.
    var numerator = mpfr.Float.init(64);
    defer numerator.deinit();
    numerator.setInf(true);

    var denominator = mpfr.Float.init(64);
    defer denominator.deinit();
    denominator.setZero(true);

    mpfr.clearAllFlags();
    const inexact = numerator.div(&denominator, .toward_zero);

    try std.testing.expectEqual(mpfr.Ternary.exact, inexact);
    try std.testing.expect(numerator.isInf());
    try std.testing.expect(!numerator.isSignNegative());
    try std.testing.expectEqual(mpfr.Flags.none, mpfr.flags());
}

test "dividing an infinity by an infinity yields an exact NaN" {
    try support.requireProvider();
    // tests/tdiv.c:845-846.
    var numerator = mpfr.Float.init(64);
    defer numerator.deinit();
    numerator.setInf(true);

    var denominator = mpfr.Float.init(64);
    defer denominator.deinit();
    denominator.setInf(true);

    mpfr.clearAllFlags();
    const inexact = numerator.div(&denominator, .toward_zero);

    // A NaN result always reports a ternary value of zero
    // (doc/mpfr.texi:1011-1012).
    try std.testing.expectEqual(mpfr.Ternary.exact, inexact);
    try std.testing.expect(numerator.isNan());
    try std.testing.expectEqual(mpfr.Flags{ .nan = true }, mpfr.flags());
}

test "dividing zero by zero yields an exact NaN" {
    try support.requireProvider();
    // doc/mpfr.texi:1011-1012 for the ternary value and 1145-1147 for the NaN
    // flag, which upstream raises whenever a NaN is produced.
    var numerator = mpfr.Float.init(64);
    defer numerator.deinit();
    numerator.setZero(true);

    var denominator = mpfr.Float.init(64);
    defer denominator.deinit();
    denominator.setZero(true);

    mpfr.clearAllFlags();
    const inexact = numerator.div(&denominator, .toward_zero);

    try std.testing.expectEqual(mpfr.Ternary.exact, inexact);
    try std.testing.expect(numerator.isNan());
    try std.testing.expect(mpfr.flags().nan);
}

test "a NaN propagates through addition and raises the NaN flag" {
    try support.requireProvider();
    // doc/mpfr.texi:1163-1165: unlike ISO C99, MPFR raises the NaN flag even
    // when a NaN is merely propagated.
    var nan_value = mpfr.Float.init(64);
    defer nan_value.deinit();
    nan_value.setNan();

    var one = mpfr.Float.init(64);
    defer one.deinit();
    _ = one.setUnsigned(1, .nearest_even);

    mpfr.clearAllFlags();
    const inexact = one.add(&nan_value, .nearest_even);

    try std.testing.expectEqual(mpfr.Ternary.exact, inexact);
    try std.testing.expect(one.isNan());
    try std.testing.expect(mpfr.flags().nan);
}

test "an integer conversion of a NaN raises the range-error flag" {
    try support.requireProvider();
    // doc/mpfr.texi:1155-1158: a range error is reported when a function that
    // does not return an MPFR number has an invalid result.
    var x = mpfr.Float.init(64);
    defer x.deinit();
    x.setNan();

    mpfr.clearAllFlags();
    _ = x.toUnsigned(.toward_zero);

    try std.testing.expect(mpfr.flags().erange);
    try std.testing.expect(!mpfr.flags().inexact);
}
