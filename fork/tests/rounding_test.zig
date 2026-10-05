//! Directed-rounding behaviour of the MPFR facade.
//!
//! Provenance of the expected values:
//!
//!  * The 2.5-at-two-bits answer is quoted from the manual itself.
//!    doc/mpfr.texi:929-933: "the number 2.5, which is represented by (10.1) in
//!    binary, is rounded to the one with an even significand; in radix 2, this
//!    means that the least significant bit is 0. For example, the number 2.5,
//!    which is represented by (10.1) in binary, is rounded to (10.0) = 2 with a
//!    precision of two bits, and not to (11.0) = 3."
//!  * 3.5 at two bits is the mirror case. Its lower neighbour 3 has an odd
//!    significand, so the same rule at doc/mpfr.texi:928-932 rounds up to 4.
//!  * 0.75 and -0.75 at one bit exercise the sign symmetry that
//!    doc/mpfr.texi:945-962 defines for MPFR_RNDZ and MPFR_RNDA on absolute
//!    values.
//!  * 1/3 at two bits is not a tie: 0.25 and 0.375 straddle 0.33333... and
//!    0.375 is the nearer of the two.
//!  * 1/7 at 24 bits has the exact rational neighbours 2396745 * 2^-24 and
//!    2396745 * 2^-24 + 2^-26, derived from the repeating binary expansion
//!    0.001001001...b. The unit of that significand is 2^-26, not 2^-24, because
//!    1/7 lies in [2^-3, 2^-2). Exact 1/7 is 1/(7 * 2^26) above the lower
//!    neighbour, which is 4/7 of that unit; 4/7 is more than half, so the upper
//!    neighbour is the nearer one and round-to-nearest goes up. The lower
//!    neighbour is exactly 2396745 * 2^-24 = 0.142857134342193603515625, whose
//!    correctly rounded 20-digit form ends in ...52 rather than ...51, and the
//!    upper neighbour is exactly 9586981 * 2^-26 = 0.14285714924335479736328125,
//!    whose 20-digit form ends in ...36 whether it is reached by
//!    round-to-nearest or by rounding up.
//!  * The ternary expectations follow doc/mpfr.texi:1002-1014: a positive
//!    ternary value means the stored value is greater than the exact result, a
//!    negative one means smaller, and zero means it is exact.
//!  * The exception word is part of each answer, and the two rounding entry
//!    points report an inexact rounding differently. `mpfr_prec_round` returns
//!    the ternary value that `mpfr_round_raw` computed and never writes
//!    `__gmpfr_flags` (src/round_prec.c:99-122), and the generic rounder it
//!    calls has no flag store at all (src/round_raw_generic.c:60-273), so the
//!    word is still empty after a precision change that did round. `mpfr_rint`
//!    returns through `MPFR_RET`, which raises the inexact flag for a nonzero
//!    result (src/rint.c:286-302, src/mpfr-impl.h:1183-1184), so the same
//!    rounding through an integer rounding does raise it. `mpfr_get_d` raises
//!    nothing whatsoever (src/get_d.c:34-132), so the value assertions below
//!    can follow the flag assertions without disturbing them. The last test in
//!    this file states both sides of the first pair.

const std = @import("std");
const mpfr = @import("mpfr");
const support = @import("support.zig");

const Rounding = struct {
    mode: mpfr.RoundingMode,
    want: f64,
    want_inexact: mpfr.Ternary,
};

test "2.5 at two bits: the manual's own ties-to-even example" {
    try support.requireProvider();
    const cases = [_]Rounding{
        .{ .mode = .nearest_even, .want = 2.0, .want_inexact = .below },
        .{ .mode = .toward_zero, .want = 2.0, .want_inexact = .below },
        .{ .mode = .toward_negative, .want = 2.0, .want_inexact = .below },
        .{ .mode = .toward_positive, .want = 3.0, .want_inexact = .above },
        .{ .mode = .away_from_zero, .want = 3.0, .want_inexact = .above },
    };
    for (cases) |case| {
        var x = try support.exactDecimal("2.5", 200);
        defer x.deinit();

        mpfr.clearAllFlags();
        const inexact = x.roundToPrecision(2, case.mode);

        try std.testing.expectEqual(case.want_inexact, inexact);
        // src/round_prec.c:99-122: this entry point reports the rounding in
        // the return value above and writes no flag, so the word cleared
        // before the call is still empty.
        try support.expectFlags(mpfr.Flags.none);
        try std.testing.expectEqual(case.want, x.toF64(.nearest_even));
    }
}

test "3.5 at two bits: ties-to-even rounds up when the lower neighbour is odd" {
    try support.requireProvider();
    const cases = [_]Rounding{
        .{ .mode = .nearest_even, .want = 4.0, .want_inexact = .above },
        .{ .mode = .toward_zero, .want = 3.0, .want_inexact = .below },
        .{ .mode = .toward_negative, .want = 3.0, .want_inexact = .below },
        .{ .mode = .toward_positive, .want = 4.0, .want_inexact = .above },
        .{ .mode = .away_from_zero, .want = 4.0, .want_inexact = .above },
    };
    for (cases) |case| {
        var x = try support.exactDecimal("3.5", 200);
        defer x.deinit();

        mpfr.clearAllFlags();
        const inexact = x.roundToPrecision(2, case.mode);

        try std.testing.expectEqual(case.want_inexact, inexact);
        // src/round_prec.c:99-122: the return value is the whole report, and
        // the word cleared before the call is still empty.
        try support.expectFlags(mpfr.Flags.none);
        try std.testing.expectEqual(case.want, x.toF64(.nearest_even));
    }
}

test "0.75 at one bit: directed rounding is symmetric in the sign" {
    try support.requireProvider();
    const cases = [_]Rounding{
        .{ .mode = .nearest_even, .want = 1.0, .want_inexact = .above },
        .{ .mode = .toward_zero, .want = 0.5, .want_inexact = .below },
        .{ .mode = .toward_negative, .want = 0.5, .want_inexact = .below },
        .{ .mode = .toward_positive, .want = 1.0, .want_inexact = .above },
        .{ .mode = .away_from_zero, .want = 1.0, .want_inexact = .above },
    };
    for (cases) |case| {
        var x = try support.exactDecimal("0.75", 200);
        defer x.deinit();

        mpfr.clearAllFlags();
        const inexact = x.roundToPrecision(1, case.mode);

        try std.testing.expectEqual(case.want_inexact, inexact);
        // src/round_prec.c:99-122: the return value is the whole report, and
        // the word cleared before the call is still empty.
        try support.expectFlags(mpfr.Flags.none);
        try std.testing.expectEqual(case.want, x.toF64(.nearest_even));
    }
}

test "-0.75 at one bit: the same neighbours seen from below zero" {
    try support.requireProvider();
    const cases = [_]Rounding{
        .{ .mode = .nearest_even, .want = -1.0, .want_inexact = .below },
        .{ .mode = .toward_zero, .want = -0.5, .want_inexact = .above },
        .{ .mode = .toward_negative, .want = -1.0, .want_inexact = .below },
        .{ .mode = .toward_positive, .want = -0.5, .want_inexact = .above },
        .{ .mode = .away_from_zero, .want = -1.0, .want_inexact = .below },
    };
    for (cases) |case| {
        var x = try support.exactDecimal("-0.75", 200);
        defer x.deinit();

        mpfr.clearAllFlags();
        const inexact = x.roundToPrecision(1, case.mode);

        try std.testing.expectEqual(case.want_inexact, inexact);
        // src/round_prec.c:99-122: the return value is the whole report, and
        // the word cleared before the call is still empty.
        try support.expectFlags(mpfr.Flags.none);
        try std.testing.expectEqual(case.want, x.toF64(.nearest_even));
    }
}

test "1/3 at two bits is not a tie: 0.375 is the nearer neighbour" {
    try support.requireProvider();
    const cases = [_]Rounding{
        .{ .mode = .nearest_even, .want = 0.375, .want_inexact = .above },
        .{ .mode = .toward_zero, .want = 0.25, .want_inexact = .below },
        .{ .mode = .toward_negative, .want = 0.25, .want_inexact = .below },
        .{ .mode = .toward_positive, .want = 0.375, .want_inexact = .above },
        .{ .mode = .away_from_zero, .want = 0.375, .want_inexact = .above },
    };
    for (cases) |case| {
        var x = try support.third(200);
        defer x.deinit();

        mpfr.clearAllFlags();
        const inexact = x.roundToPrecision(2, case.mode);

        try std.testing.expectEqual(case.want_inexact, inexact);
        // src/round_prec.c:99-122: the return value is the whole report, and
        // the word cleared before the call is still empty.
        try support.expectFlags(mpfr.Flags.none);
        try std.testing.expectEqual(case.want, x.toF64(.nearest_even));
    }
}

test "1/7 at 24 bits: the exact neighbours and their decimal renderings" {
    try support.requireProvider();
    // 1/7 is 0.001001001001...b. Truncating that at 24 bits gives
    // 2396745 * 2^-24, and the next 24-bit value is 2396745 * 2^-24 + 2^-26.
    // The unit of that significand is 2^-26, not 2^-24, because 1/7 lies in
    // [2^-3, 2^-2). Exact 1/7 is 1/(7 * 2^26) above the lower neighbour, which
    // is 4/7 of that unit; 4/7 is more than half, so the upper neighbour is the
    // nearer one and round-to-nearest goes up.
    const below: f64 = 2396745.0 / 16777216.0;
    const above: f64 = 2396745.0 / 16777216.0 + 1.0 / 67108864.0;
    try std.testing.expect(below < 1.0 / 7.0);
    try std.testing.expect(above > 1.0 / 7.0);
    try std.testing.expect(above - below == 1.0 / 67108864.0);

    const cases = [_]struct {
        mode: mpfr.RoundingMode,
        want: f64,
        want_inexact: mpfr.Ternary,
        want_digits: [:0]const u8,
    }{
        .{ .mode = .nearest_even, .want = above, .want_inexact = .above, .want_digits = "14285714924335479736" },
        .{ .mode = .toward_zero, .want = below, .want_inexact = .below, .want_digits = "14285713434219360352" },
        .{ .mode = .toward_negative, .want = below, .want_inexact = .below, .want_digits = "14285713434219360352" },
        .{ .mode = .toward_positive, .want = above, .want_inexact = .above, .want_digits = "14285714924335479736" },
        .{ .mode = .away_from_zero, .want = above, .want_inexact = .above, .want_digits = "14285714924335479736" },
    };
    for (cases) |case| {
        var x = try support.seventh(200);
        defer x.deinit();

        mpfr.clearAllFlags();
        const inexact = x.roundToPrecision(24, case.mode);

        try std.testing.expectEqual(case.want_inexact, inexact);
        // src/round_prec.c:99-122: the return value is the whole report, and
        // the word cleared before the call is still empty.
        try support.expectFlags(mpfr.Flags.none);
        try std.testing.expectEqual(case.want, x.toF64(.nearest_even));

        mpfr.clearAllFlags();
        try support.expectDigits(&x, 10, 20, case.want_digits, 0, .nearest_even);
    }
}

test "an explicit rounding mode wins over the process-wide default" {
    try support.requireProvider();
    // Every Float operation passes its direction explicitly, so MPFR's
    // process-wide default (src/mpfr.h:409-410) has no effect on any of them.
    const previous = mpfr.defaultRoundingMode();
    defer mpfr.setDefaultRoundingMode(previous);

    for ([_]mpfr.RoundingMode{ .away_from_zero, .toward_positive, .toward_negative }) |default_mode| {
        mpfr.setDefaultRoundingMode(default_mode);
        {
            var x = try support.exactDecimal("2.5", 200);
            defer x.deinit();
            // Still the manual's answer, not the default mode's answer.
            try std.testing.expectEqual(mpfr.Ternary.below, x.roundToPrecision(2, .nearest_even));
            try std.testing.expectEqual(2.0, x.toF64(.nearest_even));
        }
        {
            var x = try support.exactDecimal("2.5", 200);
            defer x.deinit();
            // The default is accepted where it is the only input the
            // operation has, and then it does decide the answer.
            const inexact = x.roundToPrecision(2, default_mode);
            const want: f64 = switch (default_mode) {
                .toward_positive, .away_from_zero => 3.0,
                else => 2.0,
            };
            const want_inexact: mpfr.Ternary = if (want == 3.0) .above else .below;
            try std.testing.expectEqual(want_inexact, inexact);
            try std.testing.expectEqual(want, x.toF64(.nearest_even));
        }
    }
}

test "rounding to nearest, ties away from zero, differs from ties to even" {
    try support.requireProvider();
    // src/mpfr.h:913: `mpfr_round(a,b)` is `mpfr_rint(a, b, MPFR_RNDNA)`, the
    // only supported way to reach MPFR_RNDNA. Each value is held exactly at
    // 200 bits, so the tie is real rather than a rounding artefact.
    const cases = [_]struct {
        text: [:0]const u8,
        want_even: f64,
        want_away: f64,
        even_inexact: mpfr.Ternary,
        away_inexact: mpfr.Ternary,
    }{
        // 2.5: the lower neighbour 2 has an even significand, so the two
        // nearest modes disagree.
        .{ .text = "2.5", .want_even = 2.0, .want_away = 3.0, .even_inexact = .below, .away_inexact = .above },
        // 3.5: the lower neighbour 3 has an odd significand, so they agree.
        .{ .text = "3.5", .want_even = 4.0, .want_away = 4.0, .even_inexact = .above, .away_inexact = .above },
        // 4.5: the lower neighbour 4 is even again, so they disagree.
        .{ .text = "4.5", .want_even = 4.0, .want_away = 5.0, .even_inexact = .below, .away_inexact = .above },
        // -2.5: the sign of the stored value decides the ternary value.
        .{ .text = "-2.5", .want_even = -2.0, .want_away = -3.0, .even_inexact = .above, .away_inexact = .below },
    };
    for (cases) |case| {
        {
            var x = try support.exactDecimal(case.text, 200);
            defer x.deinit();
            mpfr.clearAllFlags();
            const inexact = x.roundToNearestEven();
            try std.testing.expectEqual(case.even_inexact, inexact);
            try std.testing.expectEqual(case.want_even, x.toF64(.nearest_even));
        }
        {
            var x = try support.exactDecimal(case.text, 200);
            defer x.deinit();
            mpfr.clearAllFlags();
            const inexact = x.roundToNearestAway();
            try std.testing.expectEqual(case.away_inexact, inexact);
            try std.testing.expectEqual(case.want_away, x.toF64(.nearest_even));
        }
    }
}

test "truncate, ceil and floor agree with the directed modes" {
    try support.requireProvider();
    // Each rounding gets its own copy of the value. Rounding in place would
    // leave the next call with an integer, which is already its own nearest
    // integer, so it would report an exact ternary value rather than the
    // direction it is being tested for. A negative value flips which of ceil
    // and floor moves away from zero.
    const cases = [_]struct {
        text: [:0]const u8,
        mode: enum { truncate, ceil, floor },
        want: f64,
        want_ternary: mpfr.Ternary,
    }{
        .{ .text = "2.5", .mode = .truncate, .want = 2.0, .want_ternary = .below },
        .{ .text = "2.5", .mode = .ceil, .want = 3.0, .want_ternary = .above },
        .{ .text = "2.5", .mode = .floor, .want = 2.0, .want_ternary = .below },
        .{ .text = "-2.5", .mode = .truncate, .want = -2.0, .want_ternary = .above },
        .{ .text = "-2.5", .mode = .ceil, .want = -2.0, .want_ternary = .above },
        .{ .text = "-2.5", .mode = .floor, .want = -3.0, .want_ternary = .below },
    };
    for (cases) |case| {
        var v = try support.exactDecimal(case.text, 200);
        defer v.deinit();

        mpfr.clearAllFlags();
        const ternary = switch (case.mode) {
            .truncate => v.truncate(),
            .ceil => v.ceil(),
            .floor => v.floor(),
        };

        try std.testing.expectEqual(case.want_ternary, ternary);
        try std.testing.expectEqual(case.want, v.toF64(.nearest_even));
        try support.expectFlags(.{ .inexact = true });
    }
}

test "binary arithmetic reports the same ternary contract as conversion" {
    try support.requireProvider();
    // The directed-rounding rules apply to arithmetic too, not only to
    // precision reduction. Each direction below starts from a freshly built
    // 1 + 2^-200, which is exact at the 201 bits its helper allocates, so
    // scaling it down to 1 bit is the only rounding step: rounding in one
    // direction would otherwise leave the next direction with an already
    // rounded value to work from.
    {
        var down = try onePlusTwoToTheMinusTwoHundred();
        defer down.deinit();
        mpfr.clearAllFlags();
        try std.testing.expectEqual(mpfr.Ternary.below, down.roundToPrecision(1, .toward_negative));
        // src/round_prec.c:99-122: the return value is the whole report, and
        // the word cleared before the call is still empty.
        try support.expectFlags(mpfr.Flags.none);
        try std.testing.expectEqual(1.0, down.toF64(.nearest_even));
    }
    {
        var up = try onePlusTwoToTheMinusTwoHundred();
        defer up.deinit();
        mpfr.clearAllFlags();
        try std.testing.expectEqual(mpfr.Ternary.above, up.roundToPrecision(1, .toward_positive));
        // src/round_prec.c:99-122: the return value is the whole report, and
        // the word cleared before the call is still empty.
        try support.expectFlags(mpfr.Flags.none);
        try std.testing.expectEqual(2.0, up.toF64(.nearest_even));
    }
    {
        // 1 + 2^-200 is nearer to 1 than to 2, so the nearest-integer rounding
        // goes down, is inexact, and raises the inexact flag: unlike
        // mpfr_prec_round, mpfr_rint returns through MPFR_RET
        // (src/rint.c:286-302, src/mpfr-impl.h:1183-1184).
        var nearest = try onePlusTwoToTheMinusTwoHundred();
        defer nearest.deinit();
        mpfr.clearAllFlags();
        try std.testing.expectEqual(mpfr.Ternary.below, nearest.roundToNearestEven());
        try std.testing.expectEqual(1.0, nearest.toF64(.nearest_even));
        try support.expectFlags(.{ .inexact = true });
    }
}

test "one tie, two entry points, two different exception words" {
    try support.requireProvider();
    // 2.5 at two bits is the manual's own example (doc/mpfr.texi:929-933), and
    // the same rounding is reachable through two entry points that disagree
    // about the exception word. Each operand is exact at 200 bits, so the
    // precision change is the only rounding step in either block.
    {
        var by_precision = try support.exactDecimal("2.5", 200);
        defer by_precision.deinit();

        mpfr.clearAllFlags();
        const ternary = by_precision.roundToPrecision(2, .nearest_even);
        try std.testing.expectEqual(mpfr.Ternary.below, ternary);
        try support.expectFlags(mpfr.Flags.none);
        try std.testing.expectEqual(2.0, by_precision.toF64(.nearest_even));
    }
    {
        var by_integer = try support.exactDecimal("2.5", 200);
        defer by_integer.deinit();

        mpfr.clearAllFlags();
        const ternary = by_integer.roundToNearestEven();
        try std.testing.expectEqual(mpfr.Ternary.below, ternary);
        try support.expectFlags(.{ .inexact = true });
        try std.testing.expectEqual(2.0, by_integer.toF64(.nearest_even));
    }
    // Same value, same direction, same stored result, and the flag word tells
    // the two entry points apart: the tie in 2.5 is reported by
    // mpfr_prec_round through its return value alone (src/round_prec.c:99-122)
    // and by mpfr_rint through MPFR_RET, which stores
    // `__gmpfr_flags |= MPFR_FLAGS_INEXACT` for a nonzero result
    // (src/rint.c:286-302, src/mpfr-impl.h:1183-1184). Neither call is
    // disturbed by the f64 conversion, because mpfr_get_d writes no flag
    // (src/get_d.c:34-132).
}

/// 1 + 2^-200 held exactly at 201 bits.
///
/// The sum needs 201 significant bits, not 200. The last bit of a 200-bit
/// significand for a value in [1, 2) is 2^-199, so 1 + 2^-200 does not fit in
/// one and `mpfr_add` would round it back to 1, leaving nothing for the
/// rounding under test to work from. A 201-bit significand reaches from 2^0
/// down to 2^-200, and both operands are exact at that width.
fn onePlusTwoToTheMinusTwoHundred() !mpfr.Float {
    var sum = mpfr.Float.init(201);
    errdefer sum.deinit();
    _ = sum.setUnsigned(1, .nearest_even);

    var epsilon = mpfr.Float.init(201);
    defer epsilon.deinit();
    _ = epsilon.setPowerOfTwo(-200, .nearest_even);

    mpfr.clearAllFlags();
    try std.testing.expectEqual(mpfr.Ternary.exact, sum.add(&epsilon, .nearest_even));
    try support.expectFlags(mpfr.Flags.none);
    return sum;
}
