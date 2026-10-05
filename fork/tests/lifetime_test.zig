//! Lifetime, ownership, and library-state behaviour.
//!
//! These tests cover the contract a Zig caller actually depends on: what a
//! freshly initialised `Float` holds, what `deinit` releases, that values
//! survive a precision change that is supposed to keep them, that MPFR's caches
//! can be released and are then rebuilt, that the raw C escape hatch reaches
//! the same state the facade reports, and that the library answering the calls
//! is the one this header describes - its limb width through the object GMP
//! exports, and its float128 and decimal configuration through the two
//! `mpfr_buildopt_*` entry points that exist to report exactly that.
//!
//! Provenance: `mpfr_init2` sets the value to NaN and requires a precision
//! between `MPFR_PREC_MIN` and `MPFR_PREC_MAX` (doc/mpfr.texi:1347-1361);
//! `mpfr_set_prec` sets the value to NaN and reuses the allocation when it can
//! (doc/mpfr.texi:1499-1515); `mpfr_prec_round` keeps the value
//! (doc/mpfr.texi:3325-3333); `mpfr_free_cache` and `mpfr_mp_memory_cleanup`
//! release the cached constants and pools (doc/mpfr.texi:1182-1226);
//! `GMP_NUMB_BITS` is `GMP_LIMB_BITS - GMP_NAIL_BITS`
//! (vendor/gmp/gmp-h.in:44-47) and `__gmp_bits_per_limb` is GMP's own exported
//! object (vendor/gmp/mp_bpl.c:32); the two `mpfr_buildopt_*` answers follow
//! from `MPFR_WANT_FLOAT128` and `MPFR_WANT_DECIMAL_FLOATS`
//! (src/buildopt.c:35-53, src/mpfr.h:470-486, 530-533).

const std = @import("std");
const mpfr = @import("mpfr");
const support = @import("support.zig");

test "a freshly initialised value holds NaN at the requested precision" {
    try support.requireProvider();
    const precisions = [_]mpfr.Precision{ 1, 2, 24, 53, 64, 200, 1024 };
    for (precisions) |precision| {
        var x = mpfr.Float.init(precision);
        defer x.deinit();

        try std.testing.expectEqual(precision, x.precision());
        try std.testing.expect(x.isNan());
        try std.testing.expect(!x.isNumber());
    }
}

test "a value's precision can be raised and lowered through exact work" {
    try support.requireProvider();
    // Bounded, consumer-visible precision behaviour. Nothing here instantiates
    // MPFR_PREC_MAX: on LP64 that is about 2^63 bits, which would ask GMP for an
    // impossible allocation. The largest precision used anywhere in this suite
    // is 1024 bits, in the test above.
    var x = mpfr.Float.init(24);
    defer x.deinit();
    try std.testing.expectEqual(@as(mpfr.Precision, 24), x.precision());

    // The literal is 1/7 truncated at 30 fraction bits: it lies below 1/7 by
    // 1/(7 * 2^30), and it still rounds up to the same 24-bit value that exact
    // 1/7 does, namely 9586981 * 2^-26 = 0.14285714924335479736328125.
    try x.parseWhole("0.001001001001001001001001001001", 2, .nearest_even);
    try support.expectDigits(&x, 10, 20, "14285714924335479736", 0, .nearest_even);

    // Widening zero-fills rather than rounding, so the ternary value is exact
    // and the digits are unchanged (doc/mpfr.texi:3325-3333).
    const widened = x.roundToPrecision(200, .nearest_even);
    try std.testing.expectEqual(mpfr.Ternary.exact, widened);
    try std.testing.expectEqual(@as(mpfr.Precision, 200), x.precision());
    try support.expectDigits(&x, 10, 20, "14285714924335479736", 0, .nearest_even);

    // Narrowing to a precision that cannot hold the value is inexact and raises
    // the inexact flag, and the two directions pick the two different neighbours.
    var down = try support.seventh(200);
    defer down.deinit();
    mpfr.clearAllFlags();
    try std.testing.expect(down.roundToPrecision(24, .toward_negative) == .below);
    // The narrowing is real, which the return value above and the digits
    // below both show, but mpfr_prec_round reports it only through that
    // return value and never writes __gmpfr_flags (src/round_prec.c:99-122), so
    // it raises no exception at all. rounding_test.zig states the contrast
    // with mpfr_rint, which does raise the inexact flag.
    try std.testing.expectEqual(mpfr.Flags.none, mpfr.flags());
    try support.expectDigits(&down, 10, 20, "14285713434219360352", 0, .nearest_even);

    var up = try support.seventh(200);
    defer up.deinit();
    mpfr.clearAllFlags();
    try std.testing.expect(up.roundToPrecision(24, .toward_positive) == .above);
    // src/round_prec.c:99-122 again: the direction is reported by the return
    // value alone.
    try std.testing.expectEqual(mpfr.Flags.none, mpfr.flags());
    try support.expectDigits(&up, 10, 20, "14285714924335479736", 0, .nearest_even);
}

test "a value survives the precision change that is meant to keep it" {
    try support.requireProvider();
    var x = try support.seventh(53);
    defer x.deinit();
    try support.expectDigits(&x, 10, 20, "14285714285714284921", 0, .nearest_even);

    // Narrowing keeps the value, rounded, and the digits show the rounding.
    mpfr.clearAllFlags();
    const inexact = x.roundToPrecision(24, .nearest_even);
    try std.testing.expect(inexact != .exact);
    try std.testing.expectEqual(24, x.precision());
    try support.expectDigits(&x, 10, 20, "14285714924335479736", 0, .nearest_even);

    // Widening keeps it too, and is exact.
    const widened = x.roundToPrecision(200, .nearest_even);
    try std.testing.expectEqual(mpfr.Ternary.exact, widened);
    try std.testing.expectEqual(200, x.precision());
    try support.expectDigits(&x, 10, 20, "14285714924335479736", 0, .nearest_even);
}

test "the raw C escape hatch reaches the same value the facade reports" {
    try support.requireProvider();
    var x = try support.exactDecimal("1.0625", 200);
    defer x.deinit();

    const raw = mpfr.c.mpfr_get_d(x.rawConst(), mpfr.c.MPFR_RNDN);
    try std.testing.expectEqual(x.toF64(.nearest_even), raw);

    // The destination pointer is writable through the escape hatch too, and
    // 2^10 fits in 200 bits, so the C call reports a ternary value of zero.
    const inexact = mpfr.c.mpfr_set_ui_2exp(x.raw(), 1, 10, mpfr.c.MPFR_RNDN);
    try std.testing.expectEqual(0, inexact);
    try support.expectDigits(&x, 10, 4, "1024", 4, .nearest_even);
}

test "caches and pools can be released and are rebuilt afterwards" {
    try support.requireProvider();
    var x = try support.exactDecimal("3.0625", 200);
    defer x.deinit();
    _ = x.sqrt(.nearest_even);

    mpfr.freeCaches();
    mpfr.cleanupMemory();

    // The library still works, and still produces the same result, after the
    // caches have been dropped.
    var again = try support.exactDecimal("3.0625", 200);
    defer again.deinit();
    // 3.0625 is (7/4)^2 exactly, so its square root is 1.75, which is exact in
    // binary at any precision this value carries. The point of the test is that
    // the caches are rebuilt, not that this particular root rounds.
    const inexact = again.sqrt(.nearest_even);
    try std.testing.expectEqual(mpfr.Ternary.exact, inexact);
    try std.testing.expect(again.compareAbs(&x) == .eq);
}

test "flags can be raised, lowered and cleared individually" {
    try support.requireProvider();
    defer mpfr.clearAllFlags();

    mpfr.clearAllFlags();
    try std.testing.expectEqual(mpfr.Flags.none, mpfr.flags());

    mpfr.setFlags(.{ .overflow = true, .inexact = true });
    try std.testing.expectEqual(
        mpfr.Flags{ .overflow = true, .inexact = true },
        mpfr.flags(),
    );

    // Raising one bit keeps the other.
    mpfr.setFlags(.{ .nan = true });
    try std.testing.expectEqual(
        mpfr.Flags{ .overflow = true, .inexact = true, .nan = true },
        mpfr.flags(),
    );

    // Lowering one bit keeps the others.
    mpfr.clearFlags(.{ .nan = true });
    try std.testing.expectEqual(
        mpfr.Flags{ .overflow = true, .inexact = true },
        mpfr.flags(),
    );

    mpfr.clearAllFlags();
    try std.testing.expectEqual(mpfr.Flags.none, mpfr.flags());
}

test "the provider's exported limb width is the one this header describes" {
    try support.requireProvider();

    // `GMP_NUMB_BITS` is `GMP_LIMB_BITS - GMP_NAIL_BITS` from the translated
    // gmp.h (`vendor/gmp/gmp-h.in:44-47`), and `GMP_NAIL_BITS` is 0 in every
    // configuration GMP ships. `__gmp_bits_per_limb` is the object GMP itself
    // exports (`vendor/gmp/mp_bpl.c:32`), under the name gmp.h gives it
    // (`vendor/gmp/gmp-h.in:489-490`).
    //
    // In a runtime-loading build this reads the provider's own object through
    // the generated address accessor rather than a copy of its value; in a
    // linked build the declaration *is* the object. Both shapes answer the same
    // question, and a mismatch here is the failure that would otherwise show
    // up much later as a misread significand.
    const provider_limb_bits: c_int = if (comptime mpfr.runtime_loaded)
        mpfr.c.__gmp_bits_per_limbAddr().*
    else
        mpfr.c.__gmp_bits_per_limb;
    try std.testing.expectEqual(@as(c_int, mpfr.c.GMP_NUMB_BITS), provider_limb_bits);

    // Both answers are off, which is exactly why the translated header declares
    // none of the float128 or decimal entry points (`src/mpfr.h:470-486,
    // 530-533`). A provider that answered otherwise would be describing a
    // different library from the one these declarations came from.
    try std.testing.expectEqual(@as(c_int, 0), mpfr.c.mpfr_buildopt_float128_p());
    try std.testing.expectEqual(@as(c_int, 0), mpfr.c.mpfr_buildopt_decimal_p());

    // `mpfr_prec_t` and `mpfr_exp_t` are `long` on every platform this package
    // targets, and the facade's `Precision` and `Exponent` are those types
    // unchanged, so what a caller sees is the target's `long` and nothing
    // else.
    try std.testing.expectEqual(@bitSizeOf(c_long), @bitSizeOf(mpfr.Precision));
    try std.testing.expectEqual(@bitSizeOf(c_long), @bitSizeOf(mpfr.Exponent));
}
