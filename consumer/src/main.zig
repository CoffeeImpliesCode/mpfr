//! A downstream user of the MPFR fork, reached only through
//! `b.dependency("mpfr", ...)`.
//!
//! Every line printed is a known answer, and every one of them is checked
//! against the expectation before it is printed, so a behaviour change shows up
//! as a non-zero exit rather than as silently different text. The expectations
//! come from:
//!
//!  * doc/mpfr.texi:929-933 for 2.5 at two bits, and doc/mpfr.texi:936-943 for
//!    95 at one decimal digit.
//!  * tests/tdiv.c:848-854 for 1 / +0.
//!  * exact rational arithmetic for the decimal renderings. `2^100` is exact
//!    at 200 bits; `sqrt(2)` and `1/3` at 100 bits are rounded far below the
//!    twentieth decimal digit, so their renderings are the exact values'; and
//!    the rendering labelled 1/7 is the correctly rounded 24-bit form of the
//!    thirty-digit base-2 literal, which is 153391689/2^30 and needs 28
//!    significant bits, so it is not the exact literal.
//!
//!  * `src/mpfr.h:1162-1179` for the `__gmpfr_`-prefixed `intmax_t` entry
//!    points, which are reached here through the raw module.

const std = @import("std");
const Io = std.Io;
const mpfr = @import("mpfr");

pub fn main(init: std.process.Init) !void {
    var buffer: [2048]u8 = undefined;
    var stdout_writer = Io.File.stdout().writer(init.io, &buffer);
    const out = &stdout_writer.interface;
    defer out.flush() catch {};

    // The version is printed, not asserted: which release is pinned is the
    // provenance job's business, and a release pin here would only re-state it.
    try out.print("mpfr {s}, reached through dep.module(\"mpfr\")\n", .{mpfr.version()});

    // 2.5 at two bits: the manual's own example, 10.1b rounding to 10.0b = 2.
    {
        var x = try parse("2.5", 200);
        defer x.deinit();

        try expect(mpfr.Ternary.below == x.roundToPrecision(2, .nearest_even));
        try expectEqualF64(2.0, x.toF64(.nearest_even));

        var y = try parse("2.5", 200);
        defer y.deinit();
        try expect(mpfr.Ternary.above == y.roundToPrecision(2, .toward_positive));
        try expectEqualF64(3.0, y.toF64(.nearest_even));

        try out.print("2.5 at 2 bits: nearest_even={d} below, toward_positive={d} above\n", .{
            @as(i64, @intFromFloat(x.toF64(.nearest_even))),
            @as(i64, @intFromFloat(y.toF64(.nearest_even))),
        });
    }

    // 95 at one decimal digit: the manual says round-to-nearest gives 100,
    // because the candidate integer significand 10 is the even one.
    {
        var x = mpfr.Float.init(64);
        defer x.deinit();
        _ = x.setUnsigned(95, .nearest_even);

        mpfr.clearAllFlags();
        var up = try x.toDigits(10, 1, .nearest_even);
        defer up.deinit();
        try expectEqualStrings("1", up.digits());
        try expect(up.exponent == 3);
        try expect(mpfr.flags().inexact);

        mpfr.clearAllFlags();
        var down = try x.toDigits(10, 1, .toward_negative);
        defer down.deinit();
        try expectEqualStrings("9", down.digits());
        try expect(down.exponent == 2);

        try out.print("95 at 1 decimal digit: nearest_even={s}e{d}, toward_negative={s}e{d}\n", .{
            up.digits(),
            up.exponent,
            down.digits(),
            down.exponent,
        });
    }

    // Arbitrary precision: 1/7, 1/3, sqrt(2) and 2^100 at working precisions
    // wide enough that the renderings below are stable.
    {
        // The thirty-digit base-2 literal is 153391689/2^30 exactly and needs
        // 28 significant bits, so this parse rounds at 24 bits. The rendering
        // below belongs to the rounded value 153391696/2^30: the literal's own
        // twenty digits are 14285714272409677505, and 1/7 itself renders as
        // 14285714285714285714.
        var seventh = mpfr.Float.init(24);
        defer seventh.deinit();
        try seventh.parseWhole("0.001001001001001001001001001001", 2, .nearest_even);
        mpfr.clearAllFlags();
        var digits = try seventh.toDigits(10, 20, .nearest_even);
        defer digits.deinit();
        try expectEqualStrings("14285714924335479736", digits.digits());
        try expect(digits.exponent == 0);

        var third = try divide(1, 3, 100);
        defer third.deinit();
        mpfr.clearAllFlags();
        var third_digits = try third.toDigits(10, 20, .nearest_even);
        defer third_digits.deinit();
        try expectEqualStrings("33333333333333333333", third_digits.digits());
        try expect(third_digits.exponent == 0);

        var root = mpfr.Float.init(100);
        defer root.deinit();
        _ = root.setUnsigned(2, .nearest_even);
        mpfr.clearAllFlags();
        const root_inexact = root.sqrt(.nearest_even);
        try expect(root_inexact != .exact);
        var root_digits = try root.toDigits(10, 20, .nearest_even);
        defer root_digits.deinit();
        try expectEqualStrings("14142135623730950488", root_digits.digits());
        try expect(root_digits.exponent == 1);

        var power = mpfr.Float.init(200);
        defer power.deinit();
        _ = power.setPowerOfTwo(100, .nearest_even);
        mpfr.clearAllFlags();
        var power_digits = try power.toDigits(10, 31, .nearest_even);
        defer power_digits.deinit();
        try expectEqualStrings("1267650600228229401496703205376", power_digits.digits());
        try expect(power_digits.exponent == 31);

        try out.print("1/7 at 24 bits: {s} (exponent {d})\n", .{ digits.digits(), digits.exponent });
        try out.print("1/3 at 100 bits: {s} (exponent {d})\n", .{ third_digits.digits(), third_digits.exponent });
        try out.print("sqrt(2) at 100 bits: {s} (exponent {d})\n", .{ root_digits.digits(), root_digits.exponent });
        try out.print("2^100: {s} (exponent {d})\n", .{ power_digits.digits(), power_digits.exponent });
    }

    // 1 / +0 is a positive infinity, exact, with only the divide-by-zero flag.
    {
        var numerator = mpfr.Float.init(64);
        defer numerator.deinit();
        _ = numerator.setUnsigned(1, .nearest_even);

        var zero = mpfr.Float.init(64);
        defer zero.deinit();
        zero.setZero(true);

        mpfr.clearAllFlags();
        const inexact = numerator.div(&zero, .toward_zero);
        try expect(inexact == .exact);
        try expect(numerator.isInf());
        try expect(!numerator.isSignNegative());
        try expect(mpfr.flags().divide_by_zero);
        try expect(!mpfr.flags().inexact);

        try out.print("1 / +0: +infinity, ternary exact, divide_by_zero={any}\n", .{
            mpfr.flags().divide_by_zero,
        });
    }

    // The raw C API is reachable through the same module. The write is asserted
    // because it changes the value, not because any constant has a particular
    // number: the escape hatch and the facade must agree on one value.
    {
        var x = mpfr.Float.init(64);
        defer x.deinit();
        try expectEqual(@as(c_int, 0), mpfr.c.mpfr_set_ui_2exp(x.raw(), 1, 5, mpfr.c.MPFR_RNDN));
        try expectEqualF64(32.0, x.toF64(.nearest_even));
        // And the facade writes the same value the other way round.
        try expect(x.setPowerOfTwo(5, .nearest_even) == .exact);
        try expectEqualF64(32.0, x.toF64(.nearest_even));
        try out.print("raw C API reachable: 2^5 written through mpfr.c and through the facade both read {d}\n", .{
            @as(i64, @intFromFloat(x.toF64(.nearest_even))),
        });
    }

    // The `intmax_t` entry points are why this package pins MPFR_USE_INTMAX_T on
    // the compile line as well as on the translation: they are reached here
    // through the `__gmpfr_` names MPFR's own macros impose
    // (src/mpfr.h:1162-1179), so a library compiled without them fails here at
    // link time in a real dependent rather than in a declaration nothing
    // references. A `-Dsystem=mpfr` consumer should drop this block, because
    // there the installed header decides which of those declarations exist.
    {
        var x = mpfr.Float.init(64);
        defer x.deinit();

        // 1234567890123 needs 41 bits, so 64 holds it exactly and so does its
        // `f64` conversion.
        try expectEqual(@as(c_int, 0), mpfr.c.__gmpfr_set_sj(x.raw(), -1234567890123, mpfr.c.MPFR_RNDN));
        try expectEqualF64(-1234567890123.0, x.toF64(.nearest_even));
        // Typed from the call's own return type: `intmax_t` is a C typedef, so
        // naming it here would be a guess about what `translate-c` called it.
        const signed_value = mpfr.c.__gmpfr_mpfr_get_sj(x.rawConst(), mpfr.c.MPFR_RNDN);
        try expectEqual(@as(@TypeOf(signed_value), -1234567890123), signed_value);

        // The unsigned counterpart reads back its own value, not the previous
        // one, so the two entry points are not aliases of each other.
        try expectEqual(@as(c_int, 0), mpfr.c.__gmpfr_set_uj(x.raw(), 1234567890123, mpfr.c.MPFR_RNDN));
        try expectEqualF64(1234567890123.0, x.toF64(.nearest_even));
        const unsigned_value = mpfr.c.__gmpfr_mpfr_get_uj(x.rawConst(), mpfr.c.MPFR_RNDN);
        try expectEqual(@as(@TypeOf(unsigned_value), 1234567890123), unsigned_value);

        try out.print("intmax_t entry points reachable: -1234567890123 in and out, 1234567890123 in and out\n", .{});
    }

    try out.print("all consumer expectations met\n", .{});
    mpfr.cleanupMemory();
}

/// Parse `text` in base 10 and return the value, which the caller then owns.
///
/// `parsePrefix` is used rather than `parseWhole` because exactness is a real
/// property of the fixture that has to be checked, and this is the only entry
/// point that reports it. A literal that this precision cannot hold exactly
/// would invalidate every expectation compared against the returned value, so
/// the helper reports it instead of handing back a value the caller would
/// trust wrongly. Requiring the whole text to be consumed is what makes this
/// a whole-string parse for the decimal literals used here, which is what
/// `mpfr_set_str` requires of them.
fn parse(text: [:0]const u8, precision: mpfr.Precision) !mpfr.Float {
    var x = mpfr.Float.init(precision);
    errdefer x.deinit();
    const parsed = try x.parsePrefix(text, 10, .nearest_even);
    if (parsed.consumed != text.len) return error.TrailingCharacters;
    if (parsed.ternary != .exact) return error.FixtureIsNotExact;
    return x;
}

/// `numerator_value / denominator_value` at `precision` bits, correctly rounded.
///
/// The quotient is computed in the value that is returned, so one owner holds
/// the significand and nothing is copied: `div` rounds its receiver in place.
/// Each operand must survive `setUnsigned` exactly, which a `c_ulong` does not
/// at every precision, and a rounded operand would silently make the quotient
/// the wrong one.
fn divide(numerator_value: c_ulong, denominator_value: c_ulong, precision: mpfr.Precision) !mpfr.Float {
    var quotient = mpfr.Float.init(precision);
    errdefer quotient.deinit();
    if (quotient.setUnsigned(numerator_value, .nearest_even) != .exact)
        return error.OperandIsNotExact;

    var divisor = mpfr.Float.init(precision);
    defer divisor.deinit();
    if (divisor.setUnsigned(denominator_value, .nearest_even) != .exact)
        return error.OperandIsNotExact;

    _ = quotient.div(&divisor, .nearest_even);
    return quotient;
}

fn expect(condition: bool) !void {
    if (!condition) return error.ConsumerExpectationNotMet;
}

fn expectEqualStrings(expected: []const u8, actual: []const u8) !void {
    if (!std.mem.eql(u8, expected, actual)) return error.ConsumerExpectationNotMet;
}

fn expectEqual(expected: anytype, actual: anytype) !void {
    if (expected != actual) return error.ConsumerExpectationNotMet;
}

/// Exact equality of two `f64` values, which is what every expectation in this
/// program asks: each compared value is one that MPFR holds exactly, so there
/// is no tolerance to give.
fn expectEqualF64(expected: f64, actual: f64) !void {
    if (actual != expected) return error.ConsumerExpectationNotMet;
}
