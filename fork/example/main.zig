//! A runnable, deterministic demonstration of the MPFR facade.
//!
//! `zig build smoke` runs this and prints the table below. MPFR's results are
//! correctly rounded, so each line is a fixed consequence of the library and
//! the same table appears in Debug and ReleaseSafe and on every target; a
//! change in it is a change in behaviour.
//!
//! This program prints values rather than checking them. The source of each
//! value is cited beside its block: doc/mpfr.texi for the rounding rules and the
//! 95-at-one-digit example, and upstream's own test suite for the special-value
//! divisions. The independently derived expectations live in fork/tests, which
//! checks its renderings, and in the consumer package, which checks every line
//! it prints.

const std = @import("std");
const Io = std.Io;
const mpfr = @import("mpfr");

pub fn main(init: std.process.Init) !void {
    var buffer: [4096]u8 = undefined;
    var stdout_writer = Io.File.stdout().writer(init.io, &buffer);
    const out = &stdout_writer.interface;
    defer out.flush() catch {};

    try out.print("mpfr version {s}, tuning case {s}, patches [{s}]\n", .{
        mpfr.version(),
        mpfr.tuningCase(),
        mpfr.patches(),
    });
    try out.print("precision limits: {d}..{d} bits\n", .{
        mpfr.min_precision,
        mpfr.max_precision,
    });

    try directedRounding(out);
    try oneDecimalDigit(out);
    try arbitraryPrecision(out);
    try specialValues(out);

    // Release the per-thread constant caches and pools before exiting, which is
    // what upstream recommends (doc/mpfr.texi:1182-1226).
    mpfr.cleanupMemory();
}

fn directedRounding(out: *std.Io.Writer) !void {
    try out.writeAll("\n2.5 rounded to two bits, by direction\n");
    try out.writeAll("  mode              value  ternary  flags\n");
    for ([_]struct { name: []const u8, mode: mpfr.RoundingMode }{
        .{ .name = "nearest_even", .mode = .nearest_even },
        .{ .name = "toward_zero", .mode = .toward_zero },
        .{ .name = "toward_positive", .mode = .toward_positive },
        .{ .name = "toward_negative", .mode = .toward_negative },
        .{ .name = "away_from_zero", .mode = .away_from_zero },
    }) |row| {
        var x = mpfr.Float.init(200);
        defer x.deinit();
        try x.parseWhole("2.5", 10, .nearest_even);

        mpfr.clearAllFlags();
        const inexact = x.roundToPrecision(2, row.mode);
        try out.print("  {s:16} {d:6}  {s:7}  {s}\n", .{
            row.name,
            @as(i64, @intFromFloat(x.toF64(.nearest_even))),
            @tagName(inexact),
            if (mpfr.flags() == mpfr.Flags.none) "none" else "some",
        });
    }
    // doc/mpfr.texi:929-933: ties to even gives 2, not 3. The ternary column,
    // not the flag column, is where the rounding is reported: mpfr_prec_round
    // returns it and writes no flag (src/round_prec.c:99-122), so every row
    // here leaves the exception word empty.
}

fn oneDecimalDigit(out: *std.Io.Writer) !void {
    try out.writeAll("\n95 rendered with one decimal digit\n");
    var x = mpfr.Float.init(64);
    defer x.deinit();
    _ = x.setUnsigned(95, .nearest_even);

    for ([_]struct { name: []const u8, mode: mpfr.RoundingMode }{
        .{ .name = "nearest_even", .mode = .nearest_even },
        .{ .name = "toward_zero", .mode = .toward_zero },
        .{ .name = "toward_positive", .mode = .toward_positive },
        .{ .name = "toward_negative", .mode = .toward_negative },
        .{ .name = "away_from_zero", .mode = .away_from_zero },
    }) |row| {
        mpfr.clearAllFlags();
        var digits = try x.toDigits(10, 1, row.mode);
        defer digits.deinit();
        try out.print("  {s:16} {s:>4} * 10^{d}  inexact={s}\n", .{
            row.name,
            digits.digits(),
            digits.exponent,
            if (mpfr.flags().inexact) "yes" else "no",
        });
    }
    // doc/mpfr.texi:936-943: 95 at one digit goes to 100 under round-to-nearest,
    // because the candidate integer significand 10 is even.
}

fn arbitraryPrecision(out: *std.Io.Writer) !void {
    try out.writeAll("\n1/7 as twenty decimal digits, by working precision\n");
    try out.writeAll("  bits  nearest        toward_positive  ternary\n");
    for ([_]mpfr.Precision{ 8, 16, 24, 53, 200 }) |precision| {
        var x = mpfr.Float.init(precision);
        defer x.deinit();

        // The ternary value printed here comes from the division that produced
        // the digits below it, so it is read from that division rather than
        // from a leftover flag or from a second division of the same numbers.
        const inexact = divideOneBy(7, precision, &x);

        var down = try x.toDigits(10, 20, .toward_negative);
        defer down.deinit();
        var up = try x.toDigits(10, 20, .toward_positive);
        defer up.deinit();

        try out.print("  {d:4}  {s}  {s}  {s}\n", .{
            precision,
            down.digits(),
            up.digits(),
            @tagName(inexact),
        });
    }
    // 1/7 is 0.001001001... in binary and its expansion never terminates, so
    // every value in this table is a rounded one. The exact expectations for
    // these renderings are derived in fork/tests and in the consumer package.
}

fn divideOneBy(denominator: c_ulong, precision: mpfr.Precision, out: *mpfr.Float) mpfr.Ternary {
    var numerator = mpfr.Float.init(precision);
    defer numerator.deinit();
    _ = numerator.setUnsigned(1, .nearest_even);

    var divisor = mpfr.Float.init(precision);
    defer divisor.deinit();
    _ = divisor.setUnsigned(denominator, .nearest_even);

    return numerator.div(out, .nearest_even);
}

fn specialValues(out: *std.Io.Writer) !void {
    try out.writeAll("\nspecial values\n");

    var zero = mpfr.Float.init(64);
    defer zero.deinit();
    zero.setZero(true);

    var one = mpfr.Float.init(64);
    defer one.deinit();
    _ = one.setUnsigned(1, .nearest_even);

    var not_a_number = mpfr.Float.init(64);
    defer not_a_number.deinit();
    not_a_number.setNan();

    // tests/tdiv.c:848-854: 1 / +0 is a positive infinity, the ternary value is
    // exact, and the only flag raised is divide-by-zero.
    mpfr.clearAllFlags();
    const inexact = one.div(&zero, .toward_zero);
    try out.print("  1 / +0 -> is_inf={any} sign={d} ternary={s} divide_by_zero={s}\n", .{
        one.isInf(),
        one.sign(),
        @tagName(inexact),
        if (mpfr.flags().divide_by_zero) "yes" else "no",
    });

    // tests/tdiv.c:882-889: an infinite dividend divided by zero is still exact
    // and raises no flag at all, because doc/mpfr.texi:1141-1142 gives the
    // divide-by-zero flag only to an exact infinity from finite inputs.
    var infinity = mpfr.Float.init(64);
    defer infinity.deinit();
    infinity.setInf(true);

    mpfr.clearAllFlags();
    const infinity_inexact = infinity.div(&zero, .toward_zero);
    try out.print("  +inf / +0 -> is_inf={any} ternary={s} flags_raised={s}\n", .{
        infinity.isInf(),
        @tagName(infinity_inexact),
        if (mpfr.flags() == mpfr.Flags.none) "none" else "some",
    });

    mpfr.clearAllFlags();
    _ = zero.div(&zero, .toward_zero);
    try out.print("  0 / +0 -> is_nan={any} nan_flag={s}\n", .{
        zero.isNan(),
        if (mpfr.flags().nan) "yes" else "no",
    });
    // doc/mpfr.texi:1011-1012: a NaN result is always exact.

    mpfr.clearAllFlags();
    try out.print("  sign(NaN) = {d}, erange_flag={s}\n", .{
        not_a_number.sign(),
        if (mpfr.flags().erange) "yes" else "no",
    });
    // src/mpfr.h:901-904: mpfr_sgn raises the range-error flag for a NaN.
}
