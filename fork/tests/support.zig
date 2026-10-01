//! Shared helpers for the MPFR behaviour tests.
//!
//! Every expected value used by the tests is an independent known answer. The
//! provenance of each one is stated where it appears, and falls into exactly
//! three groups:
//!
//!  1. Values stated in the GNU MPFR manual, quoted in the test that uses them.
//!     `doc/mpfr.texi:929-943` gives both the ties-to-even binary example for
//!     2.5 at two bits and the base-10 1-digit example for 95; `tests/tdiv.c`
//!     and `tests/texpm1.c` give the overflow, underflow and divide-by-zero
//!     flag sets and ternary signs that upstream's own test suite asserts.
//!  2. Values derived by exact rational arithmetic from the mathematical
//!     definition of correctly rounded conversion: a rational `x` is rounded to
//!     `p` significant digits in base `b` by locating the exponent `E` with
//!     `b^(E-1) <= |x| < b^E`, forming the exact rational `|x| * b^(p-E)`, and
//!     then rounding that rational to an integer. Every fixture in this package
//!     was produced that way, so none of them is a round trip through MPFR's
//!     own code.
//!  3. Structural facts read from upstream sources, cited by file and line.
//!
//! One consequence of group 2 is worth stating once, because several tests
//! depend on it: MPFR's one-bit precision resolves an exact tie away from zero
//! rather than to an even significand (src/round_raw_generic.c:46-49), and the
//! integer 3 is not representable in one bit at all. The rational fixtures
//! below therefore require at least two bits of precision, which is what their
//! callers use.

const std = @import("std");
const mpfr = @import("mpfr");

/// Assert that `value` renders as `want_digits` with radix exponent `want_exponent`.
///
/// `count` is passed straight through to `mpfr_get_str`, so `0` asks MPFR for
/// its own digit count for the current precision.
pub fn expectDigits(
    value: *const mpfr.Float,
    base: c_int,
    count: usize,
    want_digits: [:0]const u8,
    want_exponent: mpfr.Exponent,
    mode: mpfr.RoundingMode,
) !void {
    var rendered = try value.toDigits(base, count, mode);
    defer rendered.deinit();
    try std.testing.expectEqualStrings(want_digits, rendered.digits());
    try std.testing.expectEqual(want_exponent, rendered.exponent);
}

/// Assert the whole exception-flag word, not just one bit.
///
/// Upstream's tests compare `__gmpfr_flags` for equality (tests/tdiv.c:898, 919,
/// 928, 955), which is the strictest available statement, so this helper does
/// the same.
pub fn expectFlags(want: mpfr.Flags) !void {
    try std.testing.expectEqual(want, mpfr.flags());
}

/// A `Float` holding an exact rational written as decimal text, at a generous
/// precision, so that a later `roundToPrecision` is the only rounding step.
pub fn exactDecimal(text: [:0]const u8, precision: mpfr.Precision) !mpfr.Float {
    return exactLiteral(text, 10, precision);
}

/// A `Float` holding an exact rational written in base 2, at a generous
/// precision, so that a later `roundToPrecision` is the only rounding step.
pub fn exactBinary(text: [:0]const u8, precision: mpfr.Precision) !mpfr.Float {
    return exactLiteral(text, 2, precision);
}

/// Parse `text` in `base` and insist that it was the whole of the text and that
/// nothing was rounded away.
///
/// `mpfr_set_str` cannot answer either question, because its return value is a
/// success code rather than a ternary value (doc/mpfr.texi:1594-1609), and
/// fabricating an exactness claim from it would make every expectation compared
/// against the fixture meaningless. `mpfr_strtofr` is the entry point that
/// reports both the number of bytes consumed and a real ternary value
/// (doc/mpfr.texi:1610-1627), so this helper uses that one and refuses a
/// literal that is truncated, leaves text over, or needs more than `precision`
/// bits.
fn exactLiteral(
    text: [:0]const u8,
    base: c_int,
    precision: mpfr.Precision,
) !mpfr.Float {
    var result = mpfr.Float.init(precision);
    errdefer result.deinit();

    const parsed = try result.parsePrefix(text, base, .nearest_even);
    if (parsed.consumed != text.len) return error.FixtureIsNotComplete;
    if (parsed.ternary != .exact) return error.FixtureIsNotExact;
    return result;
}

/// The rational 1/3 rounded to `precision` bits in round-to-nearest.
///
/// 1/3 is `0.010101...b`, so this is inexact at every finite precision, which
/// `quotient` insists on. `precision` must be at least 2, because the divisor 3
/// itself is not representable in a single bit; the one-bit case is stated and
/// tested in precision_test.zig. The expected results this value is compared
/// against were derived independently by exact rational arithmetic.
pub fn third(precision: mpfr.Precision) !mpfr.Float {
    return quotient(1, 3, precision);
}

/// The rational 1/7 rounded to `precision` bits in round-to-nearest.
///
/// 1/7 is `0.001001...b`, so this is inexact at every finite precision. As with
/// `third`, `precision` must be at least 2.
pub fn seventh(precision: mpfr.Precision) !mpfr.Float {
    return quotient(1, 7, precision);
}

/// The rational `numerator/denominator` rounded to `precision` bits.
///
/// The division is the mutating operation the facade exposes: it writes its
/// result back into its left operand and reports the rounding through its
/// return value, so the quotient is the value that was divided into, not a
/// separate freshly initialised variable. Both operands must be exact at
/// `precision`, which the callers below guarantee by asking for at least two
/// bits, and the quotient must then be inexact, because a quotient of two exact
/// binary values with a non-terminating expansion is the only way for this
/// helper to hand back what it claims.
fn quotient(numerator: c_ulong, denominator: c_ulong, precision: mpfr.Precision) !mpfr.Float {
    var value = mpfr.Float.init(precision);
    errdefer value.deinit();
    _ = value.setUnsigned(numerator, .nearest_even);

    var divisor = mpfr.Float.init(precision);
    defer divisor.deinit();
    const divisor_ternary = divisor.setUnsigned(denominator, .nearest_even);
    if (divisor_ternary != .exact) return error.FixtureOperandIsNotExact;

    const ternary = value.div(&divisor, .nearest_even);
    if (ternary == .exact) return error.FixtureIsNotInexact;
    return value;
}
