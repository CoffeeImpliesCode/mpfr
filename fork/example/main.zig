// SPDX-License-Identifier: LGPL-3.0-or-later
//
// Fork-authored. `FORK-LICENSE.md` records the owner's authorization of that
// grant and why it matches MPFR's own primary upstream terms.

//! A runnable, deterministic demonstration of the MPFR facade.
//!
//! `zig build smoke` runs this and prints the tables below. MPFR's results are
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
//!
//! It reaches every public method of the facade with a real value rather than
//! naming it, because `zig build check` compiles this program for six targets
//! without running any of them, and a Zig function body is only analysed when
//! something reaches it. Every block below prints an answer the library
//! computed; none of them prints that a method exists.
//!
//! ## The provider, in the runtime-loading configuration
//!
//! In the linked configuration the libraries are already available and nothing
//! below changes. In the runtime-loading configuration nothing is linked, so
//! this program names its provider explicitly - `--provider <path>` on the
//! command line, or the `MPFR_PROVIDER` environment variable - and stops with
//! an explanation if it was told neither. It never falls back to a bundled or
//! system copy.

const std = @import("std");
const Io = std.Io;
const mpfr = @import("mpfr");

/// The environment variable consulted when `--provider` was not given.
const provider_variable = "MPFR_PROVIDER";

/// A runtime-loading build has no provider until one is named.
const ConfigurationError = error{NoProviderConfigured};

pub fn main(init: std.process.Init) !void {
    // In a runtime-loading build nothing below can run until a provider is
    // loaded, and that load is the one explicit step the contract asks for. In
    // a linked build this whole branch disappears at comptime.
    if (comptime mpfr.runtime_loaded) {
        const provider = try providerRequest(init);
        try mpfr.load(.{ .path = provider });
    }

    var buffer: [4096]u8 = undefined;
    var stdout_writer = Io.File.stdout().writer(init.io, &buffer);
    const out = &stdout_writer.interface;
    defer out.flush() catch {};

    try out.print("mpfr reports version {s}, tuning case {s}, patches [{s}], reached {s}\n", .{
        mpfr.version(),
        mpfr.tuningCase(),
        mpfr.patches(),
        if (mpfr.runtime_loaded) "through the platform loader" else "through the link line",
    });

    try precisionBounds(out);
    try directedRounding(out);
    try oneDecimalDigit(out);
    try arbitraryPrecision(out);
    try specialValues(out);
    try assignmentAndComparison(out);
    try conversionOut(out);
    try textInTextOut(out);
    try libraryState(out);

    // Release the cached constants and pools before exiting, which is what
    // upstream recommends (doc/mpfr.texi:1182-1226).
    mpfr.cleanupMemory();
}

/// The precision range is a real boundary: `mpfr_init2` accepts a value between
/// `MPFR_PREC_MIN` and `MPFR_PREC_MAX` and refuses anything else with a live
/// `MPFR_ASSERTN` (src/init2.c:50-53), and `isValidPrecision` is the ordinary
/// test to run first on a precision that came from outside this program.
/// Nothing here instantiates `max_precision`: on LP64 that is about 2^63 bits,
/// which would ask GMP for an allocation it cannot make
/// (doc/mpfr.texi:807-812).
fn precisionBounds(out: *std.Io.Writer) !void {
    try out.writeAll("\nprecision bounds\n");
    const cases = [_]struct { label: []const u8, bits: mpfr.Precision }{
        .{ .label = "below the minimum", .bits = 0 },
        .{ .label = "the minimum", .bits = mpfr.min_precision },
        .{ .label = "a double's width", .bits = 53 },
        .{ .label = "the maximum", .bits = mpfr.max_precision },
    };
    for (cases) |row| {
        try out.print("  {s:20} {d} bits: accepted={s}\n", .{
            row.label,
            row.bits,
            if (mpfr.isValidPrecision(row.bits)) "yes" else "no",
        });
    }

    // The smallest accepted precision really is usable: `mpfr_init2` stores NaN
    // there (doc/mpfr.texi:1347-1361), and NaN is not a finite number.
    var x = mpfr.Float.init(mpfr.min_precision);
    defer x.deinit();
    try out.print("  one bit holds           NaN={any} finite={any}\n", .{ x.isNan(), x.isNumber() });
}

fn directedRounding(out: *std.Io.Writer) !void {
    try out.writeAll("\n2.5 rounded to two bits, by direction\n");
    try out.writeAll("  mode              value  ternary  raw  flags\n");
    for ([_]struct { name: []const u8, mode: mpfr.RoundingMode }{
        .{ .name = "nearest_even", .mode = .nearest_even },
        .{ .name = "toward_zero", .mode = .toward_zero },
        .{ .name = "toward_positive", .mode = .toward_positive },
        .{ .name = "toward_negative", .mode = .toward_negative },
        .{ .name = "away_from_zero", .mode = .away_from_zero },
    }) |row| {
        var x = try parseDecimal("2.5", 200);
        defer x.deinit();

        mpfr.clearAllFlags();
        const inexact = x.roundToPrecision(2, row.mode);
        try out.print("  {s:16} {d:6}  {s:7} {d:>3}  {s}\n", .{
            row.name,
            @as(i64, @intFromFloat(x.toF64(.nearest_even))),
            @tagName(inexact),
            inexact.toRaw(),
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

/// Assignment, arithmetic, comparison and classification, on real operands.
///
/// 1.5 and 2.5 are exact at 200 bits, so every result in the first block is an
/// exact mathematical consequence of the operation rather than of a rounding
/// step. The comparison block is the interesting half: the signed and the
/// magnitude comparison answer different questions about the same pair, and one
/// operand there is negative on purpose so the two answers disagree.
fn assignmentAndComparison(out: *std.Io.Writer) !void {
    try out.writeAll("\nassignment, arithmetic and comparison at 200 bits\n");

    var x = try parseDecimal("1.5", 200);
    defer x.deinit();
    var y = try parseDecimal("2.5", 200);
    defer y.deinit();
    var negative = try parseDecimal("-3.75", 200);
    defer negative.deinit();
    var positive = try parseDecimal("3.75", 200);
    defer positive.deinit();
    var scratch = mpfr.Float.init(200);
    defer scratch.deinit();

    _ = scratch.set(&x, .nearest_even);
    try out.print("  1.5                      -> {s}\n", .{(try Rendered.of(&scratch)).get()});
    _ = scratch.setAbs(&negative, .nearest_even);
    try out.print("  abs(-3.75)               -> {s}\n", .{(try Rendered.of(&scratch)).get()});
    // src/neg.c:24-28: mpfr_neg stores -op in rop, so this is -3.75.
    _ = scratch.negateFrom(&positive, .nearest_even);
    try out.print("  -3.75                    -> {s}\n", .{(try Rendered.of(&scratch)).get()});
    _ = scratch.setF64(0.5, .nearest_even);
    try out.print("  0.5                      -> {s}\n", .{(try Rendered.of(&scratch)).get()});
    _ = scratch.setUnsigned(7, .nearest_even);
    try out.print("  7                        -> {s}\n", .{(try Rendered.of(&scratch)).get()});
    _ = scratch.setSigned(-7, .nearest_even);
    try out.print("  -7                       -> {s}\n", .{(try Rendered.of(&scratch)).get()});
    _ = scratch.setPowerOfTwo(-4, .nearest_even);
    try out.print("  2^-4                     -> {s}\n", .{(try Rendered.of(&scratch)).get()});

    _ = x.add(&y, .nearest_even);
    try out.print("  1.5 + 2.5                -> {s}\n", .{(try Rendered.of(&x)).get()});
    _ = x.sub(&y, .nearest_even);
    try out.print("  1.5 - 2.5                -> {s}\n", .{(try Rendered.of(&x)).get()});
    _ = x.mul(&y, .nearest_even);
    try out.print("  1.5 * 2.5                -> {s}\n", .{(try Rendered.of(&x)).get()});
    _ = x.div(&y, .nearest_even);
    try out.print("  1.5 / 2.5                -> {s}\n", .{(try Rendered.of(&x)).get()});
    _ = x.mulF64(4.0, .nearest_even);
    try out.print("  (1.5 / 2.5) * 4.0        -> {s}\n", .{(try Rendered.of(&x)).get()});
    _ = x.scaleByPowerOfTwo(3, .nearest_even);
    try out.print("  that times 2^3           -> {s}\n", .{(try Rendered.of(&x)).get()});
    _ = x.divideByPowerOfTwo(4, .nearest_even);
    try out.print("  that over 2^4            -> {s}\n", .{(try Rendered.of(&x)).get()});

    // `x` is 3 at this point, and 3 is not a square, so this one rounds.
    mpfr.clearAllFlags();
    _ = x.sqrt(.nearest_even);
    try out.print("  sqrt(3)                  -> {s}  inexact={s}\n", .{
        (try Rendered.of(&x)).get(),
        if (mpfr.flags().inexact) "yes" else "no",
    });

    try out.writeAll("  2.5 compared with 2.5 and -3.75\n");
    _ = x.set(&y, .nearest_even);
    try out.print("    against 2.5            {s}\n", .{@tagName(x.compare(&y))});
    try out.print("    against -3.75          {s}\n", .{@tagName(x.compare(&negative))});
    try out.print("    |x| against |-3.75|    {s}\n", .{@tagName(x.compareAbs(&negative))});
    try out.print("    against 1000           {s}\n", .{@tagName(x.compareUnsigned(1000))});
    try out.print("    against -1000          {s}\n", .{@tagName(x.compareSigned(-1000))});
    try out.print("    equal to 2.5           {s}\n", .{if (x.isEqual(&y)) "yes" else "no"});

    var nan_value = mpfr.Float.init(200);
    defer nan_value.deinit();
    nan_value.setNan();
    try out.print("    unordered with NaN     {s}, equal to NaN {s}\n", .{
        if (x.isUnordered(&nan_value)) "yes" else "no",
        if (x.isEqual(&nan_value)) "yes" else "no",
    });
    // mpfr_unordered_p is non-zero for a NaN operand
    // (doc/mpfr.texi:2292-2294) and mpfr_equal_p is false against one.

    var negative_zero = mpfr.Float.init(200);
    defer negative_zero.deinit();
    negative_zero.setZero(false);
    try out.print("    nan/inf/zero/regular/integer of 2.5 = {any}/{any}/{any}/{any}/{any}\n", .{
        x.isNan(),
        x.isInf(),
        x.isZero(),
        x.isRegular(),
        x.isInteger(),
    });
    try out.print("    -0.0 is negative {s}, and its sign() is {d}\n", .{
        if (negative_zero.isSignNegative()) "yes" else "no",
        negative_zero.sign(),
    });
}

/// Conversion out of the value, and the fit predicates that precede it.
///
/// 3.75 is not an integer, so the integer conversions round it: 3 toward zero
/// and 4 toward positive infinity. Whether a value "fits" an integer type is
/// decided after rounding to an integer rather than before
/// (doc/mpfr.texi:1964-1969; src/fits_s.h:42-48), so a fractional value can fit
/// and the first line shows that.
fn conversionOut(out: *std.Io.Writer) !void {
    try out.writeAll("\nconversion out, and the fit predicates\n");

    var x = try parseDecimal("3.75", 200);
    defer x.deinit();

    mpfr.clearAllFlags();
    try out.print("  3.75                     -> {s}\n", .{(try Rendered.of(&x)).get()});
    try out.print("    toward zero             {d}, toward positive {d}\n", .{
        x.toSigned(.toward_zero),
        x.toSigned(.toward_positive),
    });
    try out.print("    toward zero unsigned    {d}, toward positive {d}\n", .{
        x.toUnsigned(.toward_zero),
        x.toUnsigned(.toward_positive),
    });
    try out.print("    fits a long / ulong     {s} / {s}\n", .{
        if (x.fitsSigned(.toward_zero)) "yes" else "no",
        if (x.fitsUnsigned(.toward_zero)) "yes" else "no",
    });
    // mpfr_get_si and mpfr_get_ui raise the range-error flag, unlike mpfr_get_d
    // which raises nothing at all (src/get_d.c:34-132).
    try out.print("    range error raised      {s}\n", .{
        if (mpfr.flags().erange) "yes" else "no",
    });

    var negative = try parseDecimal("-3.75", 200);
    defer negative.deinit();
    try out.print("  -3.75 fits a long / ulong {s} / {s}\n", .{
        if (negative.fitsSigned(.toward_zero)) "yes" else "no",
        if (negative.fitsUnsigned(.toward_zero)) "yes" else "no",
    });

    var huge = mpfr.Float.init(200);
    defer huge.deinit();
    _ = huge.setPowerOfTwo(100, .nearest_even);
    try out.print("  2^100 fits a long / ulong {s} / {s}\n", .{
        if (huge.fitsSigned(.toward_zero)) "yes" else "no",
        if (huge.fitsUnsigned(.toward_zero)) "yes" else "no",
    });
    // 2^100 is an exact integer that no 64-bit long holds.
}

/// The two text entry points, the error each one reports, and the base rule.
///
/// `parseWhole` insists on consuming the whole string and `parsePrefix` reports
/// how much it read (doc/mpfr.texi:1594-1610), which is what tells a literal
/// that was parsed exactly from one that was rounded into the destination. Both
/// are shown on a valid number followed by something else, and on text that is
/// not a number at all.
fn textInTextOut(out: *std.Io.Writer) !void {
    try out.writeAll("\ntext in, text out\n");

    var x = mpfr.Float.init(200);
    defer x.deinit();

    const whole = x.parseWhole("6.25", 10, .nearest_even);
    try out.print("  parseWhole(\"6.25\")       {s} -> {s}\n", .{
        if (whole) |_| "accepted" else |err| @errorName(err),
        (try Rendered.of(&x)).get(),
    });

    const prefix = try x.parsePrefix("0.5z", 10, .nearest_even);
    try out.print("  parsePrefix(\"0.5z\")      {s} consumed {d} {s}\n", .{
        (try Rendered.of(&x)).get(),
        prefix.consumed,
        @tagName(prefix.ternary),
    });

    // Any trailing character makes parseWhole fail, whitespace included, because
    // mpfr_set_str requires the entire string (doc/mpfr.texi:1594-1609).
    const trailing = x.parseWhole("1.0625xyz", 10, .nearest_even);
    try out.print("  parseWhole(\"1.0625xyz\")   {s}\n", .{
        if (trailing) |_| "accepted" else |err| @errorName(err),
    });

    const nonsense = x.parsePrefix("nonsense", 10, .nearest_even);
    try out.print("  parsePrefix(\"nonsense\")  {s}\n", .{
        if (nonsense) |_| "accepted" else |err| @errorName(err),
    });

    // An infinity written as text is not an overflow: the parse reports what it
    // consumed and nothing else (doc/mpfr.texi:1609-1611).
    const infinity = try x.parsePrefix("@Inf@", 10, .nearest_even);
    try out.print("  parsePrefix(\"@Inf@\")     consumed {d}, is_inf={s}\n", .{
        infinity.consumed,
        if (x.isInf()) "yes" else "no",
    });

    // A NaN takes a parenthesised payload and an infinity does not
    // (src/strtofr.c:254-303), so the whole string parses in one case and not in
    // the other.
    try x.parseWhole("@NaN@(payload)", 10, .nearest_even);
    try out.print("  parseWhole(\"@NaN@(payload)\") accepted, is_nan={s}\n", .{
        if (x.isNan()) "yes" else "no",
    });
    const not_an_infinity = x.parseWhole("@Inf@*2", 10, .nearest_even);
    try out.print("  parseWhole(\"@Inf@*2\")    {s}\n", .{
        if (not_an_infinity) |_| "accepted" else |err| @errorName(err),
    });

    // The base is validated rather than clamped: outside 2..62 and -36..-2
    // mpfr_get_str returns a null pointer without allocating anything
    // (src/get_str.c:2611-2613), so nothing has to be released on that path.
    try x.parseWhole("1.5", 10, .nearest_even);
    if (x.toDigits(1, 4, .nearest_even)) |value| {
        var rendered = value;
        defer rendered.deinit();
        try out.print("  toDigits(base 1)          rendered {s}, and base 1 is valid = {s}\n", .{
            rendered.digits(),
            if (mpfr.isValidBase(1)) "yes" else "no",
        });
    } else |err| {
        try out.print("  toDigits(base 1)          {s}, and base 1 is valid = {s}\n", .{
            @errorName(err),
            if (mpfr.isValidBase(1)) "yes" else "no",
        });
    }
}

/// The process-wide state MPFR owns, reached through this module's own
/// accessors, and the cache release upstream recommends before exit
/// (doc/mpfr.texi:1182-1226).
///
/// Every setting below is put back before the block ends, so the state another
/// block sees is the one this build chose. `mpfr_buildopt_tls_p` is not read
/// here on purpose: this package does not define `MPFR_USE_THREAD_SAFE`, so the
/// state below is one process-wide set of globals rather than the calling
/// thread's, which is a property of the library's build rather than a setting.
fn libraryState(out: *std.Io.Writer) !void {
    try out.writeAll("\nlibrary state\n");

    const previous_precision = mpfr.defaultPrecision();
    const previous_mode = mpfr.defaultRoundingMode();
    const previous_emin = mpfr.minimumExponentInUse();
    const previous_emax = mpfr.maximumExponentInUse();
    defer {
        mpfr.setDefaultPrecision(previous_precision);
        mpfr.setDefaultRoundingMode(previous_mode);
        _ = mpfr.setMinimumExponent(previous_emin);
        _ = mpfr.setMaximumExponent(previous_emax);
    }

    mpfr.setDefaultPrecision(80);
    mpfr.setDefaultRoundingMode(.toward_negative);
    try out.print("  default precision set to  {d}, read back {d}\n", .{
        mpfr.defaultPrecision(),
        mpfr.defaultPrecision(),
    });
    try out.print("  default rounding set to   toward_negative, read back {s}\n", .{
        @tagName(mpfr.defaultRoundingMode()),
    });

    try out.print("  exponent range in use     {d} .. {d}\n", .{
        mpfr.minimumExponentInUse(),
        mpfr.maximumExponentInUse(),
    });
    try out.print("  settable range            emin {d}..{d}, emax {d}..{d}\n", .{
        mpfr.minimumExponent(),
        mpfr.maximumNegativeExponent(),
        mpfr.minimumPositiveExponent(),
        mpfr.maximumExponent(),
    });
    // doc/mpfr.texi:3733-3755: an out-of-range request is refused and leaves the
    // range untouched.
    const accepted = mpfr.setMaximumExponent(mpfr.maximumExponent() + 1);
    try out.print("  emax one past the limit   accepted={s}, emax still {d}\n", .{
        if (accepted) "yes" else "no",
        mpfr.maximumExponentInUse(),
    });

    mpfr.clearAllFlags();
    mpfr.setFlags(.{ .inexact = true, .overflow = true });
    try out.print("  flags raised              inexact={any} overflow={any}\n", .{
        mpfr.flags().inexact,
        mpfr.flags().overflow,
    });
    mpfr.clearFlags(.{ .overflow = true });
    try out.print("  overflow lowered          inexact={any} overflow={any}\n", .{
        mpfr.flags().inexact,
        mpfr.flags().overflow,
    });
    mpfr.setFlags(mpfr.Flags.all);
    mpfr.clearAllFlags();
    try out.print("  all raised then cleared   none={s}\n", .{
        if (mpfr.flags() == mpfr.Flags.none) "yes" else "no",
    });

    // The exception word crosses the C boundary as an `unsigned int` bit set
    // (src/mpfr.h:73-87) and `Flags` is the named view of it, so both
    // directions of that mapping are printed here: the six upstream bits and
    // the one word they make.
    const all_flags = mpfr.Flags.all;
    const word = all_flags.toRaw();
    try out.print("  every flag as a bit word  {x}\n", .{word});
    try out.print("  that word names           overflow={any} divide_by_zero={any}\n", .{
        mpfr.Flags.fromRaw(word).overflow,
        mpfr.Flags.fromRaw(word).divide_by_zero,
    });

    // The caches are rebuilt on demand, so releasing them changes nothing a
    // later call can observe except that the memory went back.
    var before = mpfr.Float.init(200);
    defer before.deinit();
    _ = before.sqrt(.nearest_even);
    mpfr.freeCaches();

    var after = try parseDecimal("2.25", 200);
    defer after.deinit();
    const inexact = after.sqrt(.nearest_even);
    try out.print("  sqrt(2.25) after caching  {s}, exact={s}\n", .{
        (try Rendered.of(&after)).get(),
        if (inexact == .exact) "yes" else "no",
    });
}

/// The provider this process should load, named explicitly.
///
/// Both sources are explicit. Nothing looks in a default location, and nothing
/// falls back to a linked copy: a runtime-loading build that was not told which
/// file to load reports that it was not told, rather than loading something else.
fn providerRequest(init: std.process.Init) ConfigurationError![]const u8 {
    const args = init.minimal.args.toSlice(init.arena.allocator()) catch
        return noProvider();
    var index: usize = 1;
    while (index < args.len) : (index += 1) {
        if (std.mem.eql(u8, args[index], "--provider")) {
            if (index + 1 >= args.len) return noProvider();
            return args[index + 1];
        }
    }
    return init.environ_map.get(provider_variable) orelse
        return noProvider();
}

/// Say which variable is missing. An error name on its own would send the next
/// person into the loader instead of to the command line.
fn noProvider() ConfigurationError {
    std.debug.print(
        "mpfr example: this is a runtime-loading build. Pass --provider <path>, " ++
            "or export {s} with a shared libmpfr whose dependency closure " ++
            "contains a shared libgmp. Nothing is loaded by default and no " ++
            "other file is tried.\n",
        .{provider_variable},
    );
    return error.NoProviderConfigured;
}

/// `text` parsed in base 10 at `precision` bits, checked to be exact.
///
/// `parsePrefix` is used because it is the entry point that reports a real
/// ternary value; `parseWhole` answers 0 or -1 and cannot say whether the
/// literal was rounded (doc/mpfr.texi:1594-1610). A literal this precision could
/// not hold exactly would invalidate every expectation printed against the
/// result, so it is refused instead of being silently rounded.
fn parseDecimal(text: [:0]const u8, precision: mpfr.Precision) !mpfr.Float {
    var x = mpfr.Float.init(precision);
    errdefer x.deinit();
    const parsed = try x.parsePrefix(text, 10, .nearest_even);
    if (parsed.consumed != text.len) return error.TrailingCharacters;
    if (parsed.ternary != .exact) return error.FixtureIsNotExact;
    return x;
}

/// One rendered value, copied out of MPFR's own allocation.
///
/// `mpfr_get_str` allocates through GMP's allocator and `mpfr_free_str` frees
/// `strlen(str) + 1` bytes (doc/mpfr.texi:1945-1948), so the bytes a caller
/// prints have to be copied before the release. This is that copy, and it lives
/// in the value rather than in a global, so one render cannot alias another.
const Rendered = struct {
    /// Long enough for every rendering this program prints: the widest is a
    /// twenty-digit 1/7 with its sign, and the longest exponent carries three
    /// digits.
    const capacity = 64;

    buffer: [capacity]u8 = undefined,
    len: usize = 0,

    /// Render `value` with as many digits as its precision needs.
    pub fn of(value: *const mpfr.Float) !Rendered {
        var digits = try value.toDigits(10, 0, .nearest_even);
        defer digits.deinit();
        const borrowed = digits.digits();
        if (borrowed.len > capacity) return error.RenderedTooLong;
        var result: Rendered = .{ .len = borrowed.len };
        @memcpy(result.buffer[0..borrowed.len], borrowed);
        return result;
    }

    /// The digits, without the sentinel `Digits` owns.
    pub fn get(self: *const Rendered) []const u8 {
        return self.buffer[0..self.len];
    }
};

fn divideOneBy(denominator: c_ulong, precision: mpfr.Precision, out: *mpfr.Float) mpfr.Ternary {
    var numerator = mpfr.Float.init(precision);
    defer numerator.deinit();
    _ = numerator.setUnsigned(1, .nearest_even);

    var divisor = mpfr.Float.init(precision);
    defer divisor.deinit();
    _ = divisor.setUnsigned(denominator, .nearest_even);

    return numerator.div(out, .nearest_even);
}
