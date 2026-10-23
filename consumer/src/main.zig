// SPDX-License-Identifier: LGPL-3.0-or-later

//! Consumer example for the MPFR facade and raw C API.
//! Runtime builds require an explicit provider path.

const std = @import("std");
const Io = std.Io;
const mpfr = @import("mpfr");

const provider_variable = "MPFR_PROVIDER";

const ConfigurationError = error{NoProviderConfigured};

pub fn main(init: std.process.Init) !void {
    // Runtime builds load the named provider before any MPFR call.
    if (comptime mpfr.runtime_loaded) {
        const provider = try providerRequest(init);
        try mpfr.load(.{ .path = provider });
    }

    var buffer: [2048]u8 = undefined;
    var stdout_writer = Io.File.stdout().writer(init.io, &buffer);
    const out = &stdout_writer.interface;
    defer out.flush() catch {};

    try out.print("mpfr {s}, reached through dep.module(\"mpfr\") {s}\n", .{
        mpfr.version(),
        if (mpfr.runtime_loaded) "after an explicit load" else "through the link line",
    });
    if (comptime mpfr.runtime_loaded) {
        const loaded = mpfr.loadedSource() orelse
            return error.LoadSucceededWithoutARecordedRequest;
        try out.print("provider loaded from {s}\n", .{loaded.path});
    }

    // Manual example: 2.5 rounds to 2 at two bits (doc/mpfr.texi:929-933).
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

    // Manual example: 95 rounds to 100 at one decimal digit (doc/mpfr.texi:936-943).
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

    {
        // The 30-digit binary input needs 28 bits and rounds at this 24-bit precision.
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

    // Upstream test: 1 / +0 returns positive infinity (tests/tdiv.c:848-854).
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

    // The raw C API and facade write the same value.
    {
        var x = mpfr.Float.init(64);
        defer x.deinit();
        try expectEqual(@as(c_int, 0), mpfr.c.mpfr_set_ui_2exp(x.raw(), 1, 5, mpfr.c.MPFR_RNDN));
        try expectEqualF64(32.0, x.toF64(.nearest_even));
        try expect(x.setPowerOfTwo(5, .nearest_even) == .exact);
        try expectEqualF64(32.0, x.toF64(.nearest_even));
        try out.print("raw C API reachable: 2^5 written through mpfr.c and through the facade both read {d}\n", .{
            @as(i64, @intFromFloat(x.toF64(.nearest_even))),
        });
    }

    // MPFR prefixes its pinned `intmax_t` entry points with `__gmpfr_` (src/mpfr.h:1162-1179).
    // System-header builds may omit this declaration set.
    {
        var x = mpfr.Float.init(64);
        defer x.deinit();

        // This integer and its `f64` conversion are exact.
        try expectEqual(@as(c_int, 0), mpfr.c.__gmpfr_set_sj(x.raw(), -1234567890123, mpfr.c.MPFR_RNDN));
        try expectEqualF64(-1234567890123.0, x.toF64(.nearest_even));
        // Infer `intmax_t` from the translated function's return type.
        const signed_value = mpfr.c.__gmpfr_mpfr_get_sj(x.rawConst(), mpfr.c.MPFR_RNDN);
        try expectEqual(@as(@TypeOf(signed_value), -1234567890123), signed_value);

        try expectEqual(@as(c_int, 0), mpfr.c.__gmpfr_set_uj(x.raw(), 1234567890123, mpfr.c.MPFR_RNDN));
        try expectEqualF64(1234567890123.0, x.toF64(.nearest_even));
        const unsigned_value = mpfr.c.__gmpfr_mpfr_get_uj(x.rawConst(), mpfr.c.MPFR_RNDN);
        try expectEqual(@as(@TypeOf(unsigned_value), 1234567890123), unsigned_value);

        try out.print("intmax_t entry points reachable: -1234567890123 in and out, 1234567890123 in and out\n", .{});
    }

    // MPFR accepts `mpz_t`, so consumers need GMP from the same provider (src/mpfr.h:487-488, 527, 544).
    {
        var integer: mpfr.c.mpz_t = undefined;
        mpfr.c.__gmpz_init(&integer[0]);
        defer mpfr.c.__gmpz_clear(&integer[0]);

        try expectEqual(@as(c_int, 0), mpfr.c.__gmpz_set_str(
            &integer[0],
            "123456789012345678901234567890",
            10,
        ));
        try expect(mpfr.c.__gmpz_sizeinbase(&integer[0], 10) == 30);

        mpfr.c.__gmpz_set_ui(&integer[0], 255);
        try expectEqual(@as(c_ulong, 255), mpfr.c.__gmpz_get_ui(&integer[0]));
        try expectEqual(@as(usize, 8), mpfr.c.__gmpz_sizeinbase(&integer[0], 2));

        var x = mpfr.Float.init(200);
        defer x.deinit();
        try expectEqual(@as(c_int, 0), mpfr.c.mpfr_set_z(x.raw(), &integer[0], mpfr.c.MPFR_RNDN));
        try expectEqualF64(255.0, x.toF64(.nearest_even));

        // GMP owns the integer storage written by `mpfr_get_z`.
        var bigger = mpfr.Float.init(200);
        defer bigger.deinit();
        _ = bigger.setPowerOfTwo(100, .nearest_even);
        try expectEqual(@as(c_int, 0), mpfr.c.mpfr_get_z(&integer[0], bigger.rawConst(), mpfr.c.MPFR_RNDN));
        try expectEqual(@as(usize, 31), mpfr.c.__gmpz_sizeinbase(&integer[0], 10));

        try out.print("GMP integers reachable from the same provider: 255 -> {d}, 2^100 -> 31 digits\n", .{
            @as(i64, @intFromFloat(x.toF64(.nearest_even))),
        });
    }

    try out.print("all consumer expectations met\n", .{});
    mpfr.cleanupMemory();
}

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

fn noProvider() ConfigurationError {
    std.debug.print(
        "mpfr consumer: this is a runtime-loading build. Pass --provider <path>, " ++
            "or export {s} with a shared libmpfr whose dependency closure " ++
            "contains a shared libgmp. Nothing is loaded by default and no " ++
            "other file is tried.\n",
        .{provider_variable},
    );
    return error.NoProviderConfigured;
}

/// Parses the whole base-10 string exactly; the caller owns the returned value.
/// Returns errors for trailing text or inexact input.
fn parse(text: [:0]const u8, precision: mpfr.Precision) !mpfr.Float {
    var x = mpfr.Float.init(precision);
    errdefer x.deinit();
    const parsed = try x.parsePrefix(text, 10, .nearest_even);
    if (parsed.consumed != text.len) return error.TrailingCharacters;
    if (parsed.ternary != .exact) return error.FixtureIsNotExact;
    return x;
}

/// Returns the correctly rounded quotient at `precision` bits.
/// Owns the result; errors if either operand is not exact.
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

fn expectEqualF64(expected: f64, actual: f64) !void {
    if (actual != expected) return error.ConsumerExpectationNotMet;
}
