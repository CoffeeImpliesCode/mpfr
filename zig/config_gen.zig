//! Derivation of MPFR's compile-time configuration from a resolved Zig target.
//!
//! GNU MPFR 4.2.2 obtains every one of these facts by compiling and running a
//! probe program from `configure` (or by calling the autotest in
//! `acinclude.m4`), and autotools then hands the result to the compiler as
//! `-D` arguments. That is exactly what this module does, from the target
//! instead of from a program run on the build host, so one source tree yields a
//! correct library for every supported target and nothing is copied off the
//! machine that happened to run `zig build`.
//!
//! The `DEFS` line of a real autotools build confirms the mechanism and the
//! spelling: in an unpacked MPFR 4.2.1 tree configured for x86_64 GNU/Linux
//! with GCC, `src/Makefile` line 425 reads
//! `-DHAVE_STDARG=1 -DHAVE_STDINT_H=1 -DHAVE_WCHAR_H=1 -DHAVE_VA_COPY=1
//! -DHAVE_LONG_LONG=1 -DHAVE_ALLOCA=1 -DHAVE_ATTRIBUTE_MODE=1
//! -DHAVE_LITTLE_ENDIAN=1 -DHAVE_DOUBLE_IEEE_LITTLE_ENDIAN=1`, among others.
//! Autoconf puts that line on the compile line even though MPFR has no
//! `AC_CONFIG_HEADERS` (`configure.ac:91-93`), so `-D` is upstream's own
//! delivery mechanism and not a shortcut. The macros that line carries and
//! this tree's `src/` never reads are deliberately absent from the table
//! below, as are the ones left off on purpose; each omission names the
//! `src/` line that makes it safe.
//!
//! Three rules shape the table:
//!
//!   1. Only macros that are *true* for the target are defined. Several are
//!      tested with `#ifdef` rather than `#if` (`HAVE_ALLOCA`,
//!      `HAVE_ATTRIBUTE_MODE`, `HAVE_STDARG`), so a false macro would silently
//!      change behaviour rather than fail.
//!   2. Every entry cites the `configure.ac` or `acinclude.m4` test it
//!      reproduces, and the place in `src/` that reads it. A macro nobody in
//!      `src/` reads is not a build input and is not here.
//!   3. A macro whose value is not carried by `std.Target` is left undefined
//!      rather than guessed. MPFR has a generic code path behind almost every
//!      such macro, so leaving it off is a portable answer, not a missing one.
//!
//! The macros that select *declarations* in the public header
//! (`MPFR_WANT_FLOAT128`, `MPFR_WANT_DECIMAL_FLOATS`, `MPFR_USE_MINI_GMP`,
//! `MPFR_USE_INTMAX_T`) are the ones where a wrong answer is a link error
//! rather than a slow path, so each is either set from the target or left off
//! on the compile line *and* the translation line together; see the comment
//! on `macroDefinitions` in `build.zig`.

const std = @import("std");

/// Everything that varies between targets.
pub const Params = struct {
    /// The target stores the most significant byte of a word first. This is
    /// what `AC_C_BIGENDIAN` measures and what `src/fpif.c` requires.
    big_endian: bool,
    /// The target's C `double` is IEEE 754 binary64 and its bit-fields are
    /// allocated in address order, so a `union { struct {...} s; double d; }`
    /// is a bit-level view of the `double`. MPFR relies on exactly that
    /// assumption and states it at `src/mpfr-impl.h:906-909`.
    ieee_binary64_double: bool,
};

/// One configuration macro, ready to become a `-D` argument.
pub const Macro = struct {
    /// The macro name, spelled as `configure` spells it.
    name: []const u8,
    /// The replacement text. `configure` emits `1` for every macro below,
    /// because all of them are tested with `#ifdef` or against zero.
    value: []const u8,
};

/// Derive the MPFR configuration for `target`.
///
/// `target` is the resolved target, never the build host: `wireUp` passes
/// `ResolvedTarget.result`, so one `-Dtarget=` selects the whole table.
pub fn paramsFor(target: std.Target) Params {
    return .{
        .big_endian = target.cpu.arch.endian() == .big,
        .ieee_binary64_double = hasIeeeBinary64Double(target.cpu.arch),
    };
}

/// Number of entries `macros` returns.
pub const macro_count = 13;

/// The configuration macros for `p`, in a fixed order.
///
/// The two endianness pairs are the only target-selected names: `configure`
/// defines exactly one member of each pair, and `src/fpif.c:25-27` refuses to
/// compile unless exactly one of the integer pair is defined.
pub fn macros(p: Params) [macro_count]Macro {
    return .{
        // ---- Headers the C standard requires, so true on every target ----

        // `acinclude.m4:120-123`:
        //   AC_CHECK_HEADER([stdarg.h], [AC_DEFINE([HAVE_STDARG], 1)], ...)
        // Read at `src/inits.c:26`, `src/inits2.c:27`, `src/clears.c:27`, where
        // it selects `#include <stdarg.h>` over the K&R `#include <varargs.h>`,
        // and at `src/printf.c:28` and `src/vasprintf.c:58`, where it selects
        // the whole `mpfr_printf` family. ISO C89 7.8 and later require
        // `<stdarg.h>`, and `build.zig` compiles with `-std=gnu11`.
        .{ .name = "HAVE_STDARG", .value = "1" },

        // `acinclude.m4` (the plain `AC_CHECK_HEADERS` group) for
        // `<stdint.h>`; ISO C99 7.18 requires it. Read at
        // `src/mpfr-intmax.h:65`, where it includes `<stdint.h>` and defines
        // `MPFR_USE_INTMAX_T`; that is what makes every libmpfr unit compile
        // the `intmax_t` entry points (`__gmpfr_set_sj` and friends) that
        // `src/mpfr.h:1162-1179` declares.
        .{ .name = "HAVE_STDINT_H", .value = "1" },

        // The same `AC_CHECK_HEADERS` group for `<inttypes.h>`; ISO C99 7.8
        // requires it. Read at `src/mpfr-intmax.h:60`, which includes it and
        // also defines `MPFR_USE_INTMAX_T`. Defining it keeps the two branches
        // of `mpfr-intmax.h:60-68` in the state `configure` observed.
        .{ .name = "HAVE_INTTYPES_H", .value = "1" },

        // The same `AC_CHECK_HEADERS` group for `<wchar.h>`, which ISO C95
        // 7.24 requires. Read at `src/vasprintf.c:73-75`, and *needed* there:
        // `src/vasprintf.c:419-423` picks between `int` and `wint_t` from
        // `WINT_MAX`, and both that macro and the type come only from
        // `<wchar.h>`. ChangeLog:30419-30421 records the same reasoning when
        // the include was made conditional.
        .{ .name = "HAVE_WCHAR_H", .value = "1" },

        // ---- C types and builtins the selected C dialect guarantees ----

        // `acinclude.m4:190-191`:
        //   AC_CHECK_TYPE([long long int], AC_DEFINE(HAVE_LONG_LONG, 1), ...)
        // ISO C99 6.2.5 requires `long long int`, and `-std=gnu11` is at
        // least C11. Read at `src/mpfr-gmp.h:210` (the `DItype` fallback),
        // `src/vasprintf.c:341,452,2263` (the `ll` length modifier) and
        // `src/mpfr-intmax.h:79`.
        .{ .name = "HAVE_LONG_LONG", .value = "1" },

        // `acinclude.m4:138-154`: the first of three link tests, which defines
        // `HAVE_VA_COPY` when `va_copy(ap1, ap2)` links, else falls back to
        // `__va_copy` and then to `memcpy`. ISO C99 7.15 requires `va_copy`.
        // Read at `src/vasprintf.c:62-71`, where taking the fallback would
        // copy a `va_list` whose real representation is not a plain object.
        .{ .name = "HAVE_VA_COPY", .value = "1" },

        // `acinclude.m4:133` (`AC_FUNC_ALLOCA`); ChangeLog:25438-25441 names it
        // as the test MPFR relies on for these two macros. Read at
        // `src/mpfr-gmp.h:293-299`, where it sets `MPFR_ALLOCA_MAX 16384`
        // instead of 0 and thereby turns on the `alloca` branch of `TMP_ALLOC`
        // for every temporary allocation up to that size. Zig's C frontend is
        // clang, so `src/mpfr-gmp.h:311-314` maps `alloca` to
        // `__builtin_alloca` and the `#elif defined (HAVE_ALLOCA_H)` branch
        // below it is unreachable; that is why `HAVE_ALLOCA_H` is not set,
        // and also why `<alloca.h>` is not required on macOS or Windows.
        .{ .name = "HAVE_ALLOCA", .value = "1" },

        // `acinclude.m4:1596-1599` (`GMP_C_ATTRIBUTE_MODE`): a compile test
        // for `__attribute__ ((mode (XX)))`. Read at `src/mpfr-gmp.h:200-205`,
        // where the `QI`/`SI`/`DI` typedefs that `mpfr-longlong.h` needs
        // become width-exact instead of falling back to `unsigned char`,
        // `long` and `long long int` (`src/mpfr-gmp.h:206-216`). clang
        // implements the attribute on every target.
        .{ .name = "HAVE_ATTRIBUTE_MODE", .value = "1" },

        // `acinclude.m4:224-226`: a compile test for the `_Noreturn` function
        // specifier. Read at `src/mpfr-impl.h:154-157`. ISO C11 6.7.4
        // specifies it and `-std=gnu11` selects C11, so `MPFR_NORETURN` is
        // `_Noreturn` rather than nothing.
        .{ .name = "MPFR_HAVE_NORETURN", .value = "1" },

        // `acinclude.m4:238-241`: a compile test for `__builtin_unreachable`.
        // Read at `src/mpfr-impl.h:543-546` (`MPFR_ASSUME`) and
        // `src/mpfr-impl.h:559-563` (`MPFR_RET_NEVER_GO_HERE`). GCC has
        // provided it since 4.5 and clang has always had it.
        .{ .name = "MPFR_HAVE_BUILTIN_UNREACHABLE", .value = "1" },

        // `acinclude.m4:838-843`: a compile test for `_Static_assert`, which
        // is what `src/mpfr-sassert.h:38-45` keys on; without it the header
        // falls back to `MPFR_ASSERTN`, and with `MPFR_WANT_ASSERT` at its
        // default 0 (`src/mpfr-impl.h:488-489`) that expands to nothing, so
        // every `MPFR_STAT_STATIC_ASSERT` in the tree silently disappears.
        // Those assertions are the ABI self-checks, for example
        // `src/init2.c:32-48` (limb width, exponent limits) and
        // `src/fpif.c:617-618` (`CHAR_BIT`). ISO C11 6.7.10 requires
        // `_Static_assert` and `-std=gnu11` selects C11.
        .{ .name = "MPFR_USE_STATIC_ASSERT", .value = "1" },

        // ---- Endianness ----

        // `configure.ac:535-540`:
        //   AC_C_BIGENDIAN([AC_DEFINE(HAVE_BIG_ENDIAN)],
        //                  [AC_DEFINE(HAVE_LITTLE_ENDIAN)], [true], [true])
        // The third argument is the universal-build action, which defines
        // neither, because without `AC_CONFIG_HEADERS` (commented out at
        // `configure.ac:91-93`) configure cannot answer per slice. A Zig target
        // is never an autotools universal binary, so exactly one is always
        // defined. `src/fpif.c:25-27` `#error`s without one, and
        // `src/fpif.c:110-166` then selects the byte-swapping helpers for the
        // `mpfr_fpif_*` interchange format. `std.Target.Cpu.Arch.endian` is
        // the same fact, keyed on the architecture rather than measured by
        // running a program.
        .{
            .name = if (p.big_endian) "HAVE_BIG_ENDIAN" else "HAVE_LITTLE_ENDIAN",
            .value = "1",
        },

        // `acinclude.m4:519-533`, which dispatches on the result of
        // `MPFR_C_REALFP_FORMAT(double,)` (`acinclude.m4:1158-1471`): that test
        // stores `-123456789.0` in a struct and reads the bytes back, so it
        // measures the `double` format *and* its byte order. Its `unknown`
        // answer defines neither macro. Read at `src/mpfr-gmp.h:710-740`,
        // where it defines `union mpfr_ieee_double_extract` and
        // `_MPFR_IEEE_FLOATS 1`, and at `src/ieee_floats.h:56-68`, which holds
        // the exact `+Inf`/`-Inf` byte patterns. `_MPFR_IEEE_FLOATS` is read
        // by `src/set_d.c`, `src/scale2.c`, `src/uceil_exp2.c`,
        // `src/uceil_log2.c`, `src/ufloor_log2.c` and the decimal converters;
        // every one of them has a portable `#else` branch, so this macro buys
        // speed and bit-exact special values, never correctness, and it never
        // changes a declaration in `src/mpfr.h`.
        .{
            .name = if (p.big_endian)
                "HAVE_DOUBLE_IEEE_BIG_ENDIAN"
            else
                "HAVE_DOUBLE_IEEE_LITTLE_ENDIAN",
            .value = "1",
        },
    };
}

/// True when the architecture's C `double` is IEEE 754 binary64 and its
/// bit-fields are laid out in address order.
///
/// `std.Target` carries the byte order (`Arch.endian`, which the caller has
/// already read for the integer endianness) but has no field for the floating
/// point format, because LLVM selects that from the ABI rather than from the
/// architecture tag. The mapping is therefore spelled out, and an architecture
/// that is not listed panics instead of silently answering "not IEEE": a wrong
/// answer here would make `union mpfr_ieee_double_extract` a wrong view of a
/// `double`, which no later test would catch.
///
/// Listed are the architectures for which the C frontend offers IEEE 754
/// binary64 `double`; every architecture with a hosted C library in the
/// shared fork contract's cross matrix is present.
fn hasIeeeBinary64Double(arch: std.Target.Cpu.Arch) bool {
    return switch (arch) {
        .x86_64,
        .aarch64,
        .aarch64_be,
        .powerpc64,
        .powerpc64le,
        .riscv64,
        .riscv64be,
        .s390x,
        .mips64,
        .mips64el,
        .loongarch64,
        .sparc64,
        .wasm64,
        .x86,
        .arm,
        .armeb,
        .thumb,
        .thumbeb,
        .riscv32,
        .riscv32be,
        .powerpc,
        .powerpcle,
        .mips,
        .mipsel,
        .sparc,
        .loongarch32,
        .wasm32,
        => true,

        else => @panic(
            "mpfr: the C double format of this architecture is not recorded; " ++
                "add it to hasIeeeBinary64Double in zig/config_gen.zig",
        ),
    };
}

// ---------------------------------------------------------------------------
// Deliberately undefined
// ---------------------------------------------------------------------------
//
// Every `#error` and every `#if`-on-a-macro site in `src/` that a target has to
// answer, and why the answer here is "not defined". Grouped by the reason,
// because most of them share one.
//
// **No lock method, so no `#error` and no TLS.** `src/mpfr-impl.h:89-91` defines
// `MPFR_NEED_THREAD_LOCK` only under `MPFR_WANT_SHARED_CACHE`, and
// `configure.ac:216-225` defaults that to no. Without it `src/mpfr-thread.h`
// never reaches its `#error "No thread lock / unsupported OS."` (line 155) and
// `MPFR_THREAD_ATTR` stays empty (lines 42-44), so the constant caches become
// plain globals: exactly upstream's documented `--disable-thread-safe` build
// (`configure.ac:206-214`), and `src/buildopt.c:28-30` reports 0 truthfully.
// `MPFR_USE_THREAD_SAFE`, `MPFR_USE_C11_THREAD_SAFE`, `HAVE_PTHREAD`,
// `MPFR_HAVE_C11_LOCK` (acinclude.m4:596-636, 1890-1893),
// `MPFR_HAVE_CONSTRUCTOR_ATTR` (acinclude.m4:1851-1853, consumed only at
// `src/mpfr-thread.h:193` under `MPFR_NEED_DEFERRED_INIT`) and
// `MPFR_WANT_SHARED_CACHE` are therefore all off. This is the one answer that
// holds for all six matrix targets: `wasm32-wasi` has neither `<threads.h>`
// nor `<pthread.h>`.
//
// **A format `std.Target` does not record, with a generic path behind it.**
// `HAVE_LDOUBLE_*` (acinclude.m4:535-573) needs the C `long double` format,
// which Zig's target does not carry; `acinclude.m4:568-569` is the `unknown`
// case and it defines nothing, which lands on the generic code at
// `src/get_ld.c:180` and `src/set_ld.c:233`. That code is format-agnostic (it
// works from `MPFR_LDBL_MANT_DIG` and the `LONGDOUBLE_NAN_ACTION` fallback at
// `src/mpfr-impl.h:786-792`), so `mpfr_set_ld`, `mpfr_get_ld`,
// `mpfr_get_ld_2exp` and `mpfr_cmp_ld` stay defined, and `src/cmp_ld.c:35`
// takes its ordinary branch. `HAVE_LOCALE_H` (acinclude.m4:126),
// `HAVE_STRUCT_LCONV_DECIMAL_POINT` and `HAVE_STRUCT_LCONV_THOUSANDS_SEP`
// (acinclude.m4:128-130) go the same way: `MPFR_LCONV_DPTS` at
// `src/mpfr-impl.h:1643-1651` needs all three at once, the two struct members
// are properties of the C library's `struct lconv` that no target field
// describes, and the result is a locale-independent `.` decimal point
// (`src/mpfr-impl.h:1675`).
//
// **A language feature this build does not offer on every target, gated
// symmetrically on the public header and the implementation.** `src/mpfr.h`
// declares `mpfr_set_float128`/`mpfr_get_float128` under `MPFR_WANT_FLOAT128`
// (lines 477-485) and `mpfr_set/get_decimal64`/`mpfr_set/get_decimal128` under
// `MPFR_WANT_DECIMAL_FLOATS` (lines 470-475 and 530-533), and the defining
// units test the same macros (`src/set_float128.c:26`, `src/get_float128.c:25`,
// `src/set_d64.c:30`, `src/get_d64.c:31`, `src/set_d128.c:30`,
// `src/get_d128.c:49`). Whether the target's C frontend offers `_Float128` or
// `_Decimal64`/`_Decimal128` is not a `std.Target` field, so
// `MPFR_WANT_FLOAT128`, `MPFR_WANT_DECIMAL_FLOATS`, `DECIMAL_BID_FORMAT`,
// `DECIMAL_DPD_FORMAT` and `HAVE_DECIMAL128_IEEE_*` are off. Both sides then
// agree, `mpfr_buildopt_float128_p` and `mpfr_buildopt_decimal_p` report 0
// (`src/buildopt.c:36-53`), and none of the five decimal `#error`s at
// `src/mpfr-impl.h:866-886` can fire. `build.zig` repeats that decision on the
// translation line.
//
// **A GMP internal, and a substitute GMP.** `WANT_GMP_INTERNALS`
// (`configure.ac:179-185`), `MPFR_HAVE_GMP_IMPL` (`configure.ac:699-712`) and
// the three `HAVE___GMPN_*` results (`configure.ac:818-831`) all require
// `gmp-impl.h` and undocumented `mpn` symbols, which a released GMP does not
// ship; `configure.ac:818-826` says outright that they must not be used by
// default. Leaving them off keeps `src/mpfr-gmp.h:92` on the
// gmp-impl-free branch, avoids `src/mpfr-impl.h:121`, and leaves
// `mpfr_buildopt_gmpinternals_p` at 0. `MPFR_USE_MINI_GMP`
// (`configure.ac:156-173`) is forbidden by the shared fork contract and would
// trip `src/mpfr-gmp.h:58` against the real GMP this build links.
//
// **Recomputed by MPFR itself, or read by nobody.** `HAVE_CONFIG_H` is left
// off because no `config.h` is generated; `src/mpfr-impl.h:26-28` would
// `#include` a file that does not exist. `HAVE_ALLOCA_H` is unreachable
// behind the `__GNUC__` branch at `src/mpfr-gmp.h:311-314`.
// `MPFR_LONG_WITHIN_LIMB` (acinclude.m4:1047) is derived from `GMP_NUMB_BITS`
// and `ULONG_MAX` at `src/mpfr-impl.h:113-116`, and
// `MPFR_INTMAX_WITHIN_LIMB` (acinclude.m4:1080) only switches which of two
// equal shifts `src/get_sj.c:84-88` uses, so a `-D` would be a second source of
// truth for an ABI value. `WORDS_BIGENDIAN` appears nowhere in `src/`; it is a
// GMP `config.in` macro (vendor/gmp/config.in:630-640) and the endianness
// answer here is `HAVE_BIG_ENDIAN`/`HAVE_LITTLE_ENDIAN`.
//
// **`configure` options left at their default.** `MPFR_WANT_ASSERT`
// (configure.ac:187-195, default 0 and already defaulted again at
// `src/mpfr-impl.h:488-489`), `MPFR_USE_LOGGING` (configure.ac:197-204),
// `MPFR_USE_WARNINGS` (configure.ac:227-233), `MPFR_TUNE_COVERAGE`
// (configure.ac:252-259), `MPFR_WANT_PROVEN_CODE` (configure.ac:317-325) and
// `MPFR_DEBUG_PREDICTION` (configure.ac:290-302) all default to off, which is
// what keeps the three `#error`s at `src/mpfr-impl.h:1478,2078,2158` and
// `src/jyn_asympt.c:28` unreachable.
//
// **Not a build input.** The rest of a real `DEFS` line
// (`HAVE_STDIO_H`, `HAVE_INTMAX_T`, `HAVE_UINTPTR_T`, `HAVE_SIGACTION`,
// `HAVE_SIGNAL`, `HAVE_SETLOCALE`, `HAVE_GETTIMEOFDAY`, `HAVE_CLOCK_GETTIME`,
// `HAVE_GETRUSAGE`, `HAVE_FPC_CSR`, `HAVE_SYS_FPU_H`,
// `HAVE_DECL_*` from the `AC_CHECK_DECLS` group, `MPFR_HAVE_FESETROUND`,
// `HAVE_SUBNORM_DBL`, `HAVE_SUBNORM_FLT`, `HAVE_SIGNEDZ`, `HAVE_ROUND`,
// `HAVE_TRUNC`, `HAVE_FLOOR`, `HAVE_CEIL`, `HAVE_NEARBYINT`,
// `MPFR_HAVE_INTMAX_MAX`, `PRINTF_L`, `PRINTF_T`, `PRINTF_A`,
// `PRINTF_GROUPFLAG`, `NPRINTF_J`, `NPRINTF_LL`, `NPRINTF_L`, `NPRINTF_HH`,
// `NPRINTF_T`, `NPRINTF_A`, `MPFR_ERRDIVZERO`, `MPFR_NANISNAN`,
// `MPFR_NO_CONSECUTIVE_CHARSET`, `MPFR_MULHIGH_SIZE` and
// `MPFR_TESTS_TIMEOUT`) is read by `tests/` or by `tools/bench`, never by
// `src/`, and none of it guards a `#error` there.
