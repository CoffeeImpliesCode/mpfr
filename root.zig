// SPDX-License-Identifier: LGPL-3.0-or-later
//
// Fork-authored. `FORK-LICENSE.md` records the owner's authorization of that
// grant and why it matches MPFR's own primary upstream terms.
//
//! Zig facade over the GNU MPFR 4.2.2 public C API.
//!
//! This module is the `mpfr` module published by this package. It is a thin,
//! owned wrapper: it adds Zig types and explicit ownership, and nothing else.
//! No MPFR algorithm is reimplemented here, and the complete translated C API
//! stays reachable through `pub const c = @import("c")`.
//!
//! Supported surface
//! -----------------
//! `Float` and `Digits` own MPFR-allocated memory and release it themselves;
//! `Ternary`, `RoundingMode`, `Flags` and `Prefix` carry results and no
//! resources; the module-level functions reach the library's own state.
//! `c` is a supported route, not a private one: it keeps upstream's names,
//! types and semantics, including the `__gmpfr_` prefixes and the `intmax_t`
//! entry points, and a caller that uses it keeps upstream's obligations for
//! raw pointers, flags and ownership.
//!
//! What this module does not do
//! ----------------------------
//! It chooses no rounding direction on the caller's behalf: every general
//! operation takes its direction as an argument, and the library default is
//! reachable only through `defaultRoundingMode`. It allocates nothing through
//! a Zig allocator and takes no allocator argument; the memory it hands back
//! belongs to GMP's configured allocator. Printing, the `printf`-family
//! formatting and `mpfr_out_str`, which takes a `FILE *`, are upstream's and
//! are reached through `c`.
//!
//! The shortest sequence that uses it:
//!
//! ```zig
//! const std = @import("std");
//! const mpfr = @import("mpfr");
//!
//! pub fn main() !void {
//!     var x = mpfr.Float.init(200);
//!     defer x.deinit();
//!     try x.parseWhole("2.5", 10, .nearest_even);
//!     var digits = try x.toDigits(10, 20, .nearest_even);
//!     defer digits.deinit();
//!     std.debug.print("{s}\n", .{digits.digits()});
//! }
//! ```
//!
//! State the library owns
//! ----------------------
//! Three channels carry state that no `Float` owns, and they are independent
//! of one another. A call reports its rounding through the `Ternary` it
//! returns, may raise bits through `Flags`, and consults the library default
//! rounding direction only where upstream takes no explicit mode. No `Float`
//! method consults that default, and no method synthesises a flag upstream
//! does not set: `roundToPrecision` is the documented case, because
//! `mpfr_prec_round` reports its rounding through its return value alone.
//!
//! Those channels are process-wide C globals in this package's own build: the
//! configuration macros `zig/config_gen.zig` derives do not include
//! `MPFR_USE_THREAD_SAFE`, so `MPFR_THREAD_ATTR` expands to nothing
//! (src/mpfr-thread.h:33-43) and the flags, the exponent limits, the default
//! precision and the default rounding direction are shared by every thread in
//! the process (src/mpfr-impl.h:255-260, 323-325). `-Dsystem=mpfr` links an
//! installed library instead, and `c.mpfr_buildopt_tls_p()` reports at run
//! time whether that library keeps them per thread (src/buildopt.c). Threads
//! that write these channels need external synchronisation; `Float` and
//! `Digits` carry no state shared between them.
//!
//! Why some methods read `__mpfr_struct` fields directly
//! ---------------------------------------------------
//! Much of the MPFR API that a user thinks of as functions is in fact
//! preprocessor macros over the public struct representation:
//!
//!   src/mpfr.h:893-896  mpfr_nan_p / mpfr_inf_p / mpfr_zero_p / mpfr_regular_p
//!   src/mpfr.h:901-904  mpfr_sgn, which also raises the range-error flag on NaN
//!   src/mpfr.h:906-907  mpfr_get_prec / mpfr_get_exp
//!   src/mpfr.h:913-916  mpfr_round / mpfr_trunc / mpfr_ceil / mpfr_floor
//!   src/mpfr.h:918-919  mpfr_cmp_ui / mpfr_cmp_si
//!   src/mpfr.h:921-933  mpfr_set / mpfr_abs / mpfr_copysign / mpfr_setsign
//!                       / mpfr_signbit / mpfr_cmp / mpfr_mul_2exp / mpfr_div_2exp
//!   src/mpfr.h:964-1021 the GCC-optimised mpfr_cmp_ui, mpfr_cmp_si, mpfr_set_ui,
//!                       mpfr_set_si, mpfr_mul_ui, mpfr_div_ui, mpfr_mul_si and
//!                       mpfr_div_si
//!
//! Several of those bodies are GCC statement expressions or `__builtin_constant_p`
//! tests (src/mpfr.h:921-925, 964-1021) and have no faithful Zig translation.
//! This facade therefore calls the underlying real entry points (`mpfr_set4`,
//! `mpfr_cmp3`, `mpfr_set_ui_2exp`, `mpfr_set_si_2exp`, `mpfr_cmp_ui_2exp`,
//! `mpfr_cmp_si_2exp`, `mpfr_mul_2ui`, `mpfr_div_2ui`, `mpfr_rint`, the real
//! `mpfr_number_p`, ...) and, for the four predicates that have no non-macro
//! equivalent, mirrors the macro bodies exactly against the fields that
//! src/mpfr.h:230-236 documents as the public representation. Every such method
//! cites the upstream line it mirrors.
//!
//! Ownership
//! ---------
//! `mpfr_init2` allocates the significand through GMP's configured allocator and
//! `mpfr_clear` releases it; `mpfr_get_str` allocates its buffer the same way and
//! `mpfr_free_str` releases it (doc/mpfr.texi:1201-1210, 1927-1954). Zig
//! allocators are therefore never involved: `Float` carries no allocator and
//! `Float.deinit` calls `mpfr_clear`, while `Digits.deinit` calls
//! `mpfr_free_str`. A Zig leak checker does not observe either allocation, so
//! the owning handle is the whole contract: exactly one `deinit` per successful
//! construction, on one of the copies, never on two. MPFR's internal caches and
//! pools are released by `freeCaches` and `cleanupMemory`.
//!
//! ## Two configurations: linked and runtime-loaded
//!
//! This module is built in one of two shapes, and `runtime_loaded` says which
//! at comptime.
//!
//! *Linked* is the default. The libraries are linked, `c` is the translated
//! header, and every call below is a direct call with no table and no check.
//!
//! *Runtime-loaded* is opt-in (`-Druntime=true`). Neither library is linked;
//! `c` is a dispatch generated from the same translation step's output, and
//! every entry point `fork/mpfr_all.h` declares is resolved through the
//! platform loader when the caller calls
//!
//! ```zig
//! try mpfr.load(.{ .path = "/usr/lib/libmpfr.so.6" });
//! ```
//!
//! before using anything else. A call into a module that has not loaded stops
//! the program with a message naming the function, in every optimization mode.
//! That is a programming error rather than a recoverable condition: the table
//! does not exist yet, and there is no partial state to fall back on. The load
//! itself reports a missing file, a provider that does not export what the
//! header declares, a provider whose limb width or configuration disagrees
//! with the header, a request that cannot be honoured because a different
//! provider already won, or a reentrant call, as errors rather than as a
//! different library being loaded instead.
//!
//! The provider is reached, never guessed. `.path` names a file and `.system`
//! names a library for the platform loader; neither falls back to the other,
//! there is no unload and no reset, and the handle and a copy of the request
//! live to the end of the process.
//!
//! What a provider must be is stated in `runtime/library.zig`, next to the
//! checks that are and are not made about it.
//!
//! ## The external ABI boundary
//!
//! `c` is the whole public surface of **two** libraries, because
//! `src/mpfr.h:52` includes `<gmp.h>`: MPFR's own entry points, the
//! `intmax_t` family under MPFR's `__gmpfr_` spellings
//! (`src/mpfr.h:1162-1179`), GMP's entry points, and GMP's three exported
//! objects `__gmp_bits_per_limb`, `__gmp_errno` and `__gmp_version`
//! (`vendor/gmp/gmp-h.in:489-497`). `mpz_t` values are part of MPFR's own API -
//! `mpfr_set_z`, `mpfr_get_z` and `mpfr_mul_z` take them
//! (`src/mpfr.h:487-488, 527, 544`) - so a caller that only ever touches this
//! facade still needs the GMP closure the provider was built against.
//!
//! The facts a provider and this build must agree about, each with its source:
//!
//!   * **Limbs.** `mp_limb_t` is `GMP_LIMB_BITS` bits wide
//!     (`vendor/gmp/gmp-h.in:44-47`), and every limb-count argument and every
//!     significand layout depends on it.
//!   * **Scalar widths.** `__GMP_MP_SIZE_T_INT` is defined only for CRAY
//!     targets (`vendor/gmp/gmp-h.in:169-178`), so on every platform this
//!     package targets `_MPFR_PREC_FORMAT` is 3 and `_MPFR_EXP_FORMAT` follows
//!     it (`src/mpfr.h:133-143`). `mpfr_prec_t` and `mpfr_exp_t` are therefore
//!     `long`, and `mpfr_uprec_t` and `mpfr_uexp_t` are `unsigned long`
//!     (`src/mpfr.h:159-212`); `mpfr_sign_t` is `int` everywhere
//!     (`src/mpfr.h:180`). That width is a separate axis from the limb width
//!     above and does not follow from it: a 32-bit-`long` target such as
//!     wasm32-wasi still takes its `GMP_LIMB_BITS` from GMP's own
//!     configuration. `mpfr_rnd_t` values are fixed at
//!     `0=RNDN, 1=RNDZ, 2=RNDU, 3=RNDD, 4=RNDA` (`src/mpfr.h:98-109`).
//!     `mpfr_flags_t` is an `unsigned int` bit set (`src/mpfr.h:73-87`), and
//!     this module crosses that boundary through the `MPFR_FLAGS_*` constants
//!     rather than through a width assumption.
//!   * **Struct layout.** `__mpfr_struct` is
//!     `{ mpfr_prec_t _mpfr_prec; mpfr_sign_t _mpfr_sign; mpfr_exp_t _mpfr_exp;
//!     mp_limb_t *_mpfr_d; }` (`src/mpfr.h:231-236`), and `mpfr_t` is one of
//!     those. Four predicate and sign methods below mirror macros against those
//!     fields, so the layout is part of this facade's own contract.
//!   * **Configuration.** `MPFR_WANT_FLOAT128`, `MPFR_WANT_DECIMAL_FLOATS`,
//!     `MPFR_USE_MINI_GMP` and `MPFR_USE_THREAD_SAFE` are all off, which is why
//!     the float128 and decimal entry points are absent
//!     (`src/mpfr.h:470-486, 530-533`), why the module comment above says the
//!     shared state is process-wide, and why `c.mpfr_buildopt_tls_p()` is
//!     expected to answer 0 for a library this build produced.
//!     `MPFR_USE_INTMAX_T` is on (`fork/mpfr_all.h:51`), on both C command
//!     lines, so the `__gmpfr_` entry points are declared *and* defined.
//!   * **Allocator ownership.** Every allocation MPFR makes goes through GMP's
//!     configured allocator: `mpfr_init2` through `mpfr_clear`
//!     (doc/mpfr.texi:1201-1210) and `mpfr_get_str` through `mpfr_free_str`
//!     (doc/mpfr.texi:1927-1954). `Float.deinit` and `Digits.deinit` below call
//!     exactly those two release entry points, so an allocation and its release
//!     always cross the same table, the same `libmpfr` and the same `libgmp`.
//!     No Zig allocator is involved on either side, and no allocator in the
//!     executable can be substituted.

const std = @import("std");

/// The complete translated GNU MPFR 4.2.2 public C API, plus GMP's public API
/// that `<gmp.h>` contributes.
///
/// This is the raw escape hatch. Everything here follows upstream naming and
/// semantics, including the `__gmpfr_` prefixes that MPFR's own macros impose
/// on the `intmax_t` entry points (src/mpfr.h:1162-1169): `c.__gmpfr_set_sj`,
/// for instance, is upstream's `mpfr_set_sj`.
///
/// In a runtime-loading build this module is a generated dispatch rather than
/// the translation step's own output. It publishes the same namespace: every
/// type and constant is re-exported from the translated header rather than
/// restated, so `mpfr_t`, `mpfr_prec_t`, the limb pointer inside
/// `__mpfr_struct` and every `MPFR_*` constant are the same nominal
/// declarations in either configuration and nothing here needs a cast. What
/// differs is how a name reaches the library: directly in the linked
/// configuration, and through a table that `load` fills in the runtime-loaded
/// one, where a call before that fill stops the program with a message naming
/// the function. `runtime_loaded` says which configuration this build is.
pub const c = @import("c");

/// The loader core, which is where a linked build's two public types come from.
///
/// It is referenced only by the linked configuration. In a runtime-loading
/// build the generated dispatch carries the same two declarations and this
/// import is not even registered on the facade's module, so the name is never
/// resolved and never compiled. Either way there is exactly one `LoadSource`
/// and one `LoadError` in a build, which is what keeps them one type for a
/// consumer that names them.
const rt = @import("rt");

/// Whether this module was configured to resolve its native symbols at run
/// time.
///
/// False for the ordinary build, where the libraries are linked and `c` is the
/// translated header itself. True when the build generated a dispatch that
/// resolves the same symbols through the platform loader, in which case `load`
/// is the call that makes them usable. It is a comptime constant, so a
/// consumer can write two different code paths and have only the one it chose
/// analysed.
pub const runtime_loaded: bool = if (@hasDecl(c, "rt_runtime_loaded")) c.rt_runtime_loaded else false;

/// Which native library `load` should open.
///
/// `.path` is an explicit file path and `.system` is an explicit name for the
/// platform loader. There is no path-to-system fallback and no implicit
/// fallback of any kind; a request that cannot be honoured is an error, not a
/// different library.
pub const LoadSource = if (runtime_loaded) c.LoadSource else rt.LoadSource;

/// Every way `load` can decline.
///
/// Declared here, in the module a consumer imports, rather than only inside
/// the loader: the caller names the failure it is handling.
pub const LoadError = if (runtime_loaded) c.LoadError else rt.LoadError;

/// Load the native library this module dispatches to.
///
/// In a runtime-loading build this is the whole contract: call it once, then
/// use this module as if it were linked. Calling it again with the same request
/// succeeds and changes nothing; calling it with a different request after a
/// success is `ProviderMismatch`, and the provider already in use stays in use.
/// A failed attempt publishes nothing and can be retried explicitly, by
/// calling this again: there is no automatic retry, and no implicit second
/// source.
///
/// The provider must be a shared `libmpfr` that depends on a shared `libgmp`,
/// because GMP's entry points and objects are part of this module's own
/// surface and are resolved through the provider's dependency closure. See the
/// module comment on the external ABI boundary, and `runtime/library.zig`.
///
/// Safe to call from any thread. A thread that arrives while an attempt for the
/// same request is in flight waits for that attempt and gets its result,
/// whatever it was. A call from the thread that is running the attempt is
/// `ReentrantLoad` rather than a deadlock.
///
/// In a linked build there is no provider, no table and nothing to resolve, so
/// this stops the program with a message saying so instead of quietly
/// succeeding. `runtime_loaded` is false there, so a consumer that supports
/// both configurations can tell the two apart at comptime instead of meeting
/// this at run time.
pub fn load(source: LoadSource) LoadError!void {
    // Both configurations are written out rather than one guarded behind the
    // other's `noreturn`, so the branch a build does not take is never
    // analysed: a linked build's `c` has no `load`, and a runtime-loading build
    // has no `rt` import, and neither name is resolved in the configuration
    // that lacks it.
    if (comptime runtime_loaded) {
        return c.load(source);
    } else {
        std.debug.panic(
            "mpfr: load was called on a linked build; this module is not " ++
                "runtime-loaded, so there is no library to load. Build with " ++
                "runtime loading configured, or do not call load.",
            .{},
        );
    }
}

/// The request that succeeded, or null when nothing has loaded yet.
///
/// The answer is the loader's own retained copy and stays valid for the life of
/// the process. Null in a linked build, which has no request.
pub fn loadedSource() ?LoadSource {
    // The runtime branch keeps `c.loadedSource` inside the branch it belongs
    // to, for the reason `load` states.
    if (comptime runtime_loaded) return c.loadedSource();
    return null;
}

const mpfr = c;

/// Significand precision in bits. Upstream type `mpfr_prec_t`.
pub const Precision = mpfr.mpfr_prec_t;

/// Binary exponent. Upstream type `mpfr_exp_t`.
pub const Exponent = mpfr.mpfr_exp_t;

/// A sign comparison, matching the sign part of `mpfr_cmp3`'s result.
pub const Order = std.math.Order;

/// Smallest precision MPFR accepts. Upstream `MPFR_PREC_MIN` (src/mpfr.h:176).
pub const min_precision: Precision = 1;

/// Largest precision MPFR accepts.
///
/// Computed from upstream's `MPFR_PREC_MAX` (src/mpfr.h:177),
/// `((mpfr_prec_t)(((mpfr_uprec_t) -1) >> 1) - 256)`, instead of read from a
/// macro, because this facade does not rely on macro translation.
pub const max_precision: Precision = blk: {
    const unsigned_max: mpfr.mpfr_uprec_t = @bitCast(@as(std.meta.Int(.signed, @bitSizeOf(mpfr.mpfr_uprec_t)), -1));
    break :blk @as(Precision, @intCast(unsigned_max >> 1)) - 256;
};

/// Whether `precision` lies inside the range MPFR accepts for a significand.
///
/// `Float.init`, `Float.resetPrecision` and `Float.roundToPrecision` all
/// require that range and cannot check it for you, so a precision that comes
/// from outside your own code passes through this first.
pub fn isValidPrecision(precision: Precision) bool {
    return precision >= min_precision and precision <= max_precision;
}

/// MPFR rounding directions.
///
/// The numeric values are upstream's `mpfr_rnd_t` enumerators
/// (src/mpfr.h:101-109) and must not be reordered: src/mpfr.h:98-99 records
/// that src/texceptions.c assumes `0=RNDN, 1=RNDZ, 2=RNDU, 3=RNDD, 4=RNDA`.
///
/// `nearest_away` is `MPFR_RNDNA`, which upstream marks "DON'T USE"
/// (src/mpfr.h:89). Only `mpfr_rint` accepts it, so it exists here solely to
/// serve `Float.roundToNearestAway`; see src/round_raw_generic.c:51-52.
pub const RoundingMode = enum(c_int) {
    /// `MPFR_RNDN`: round to nearest, ties to even significand.
    nearest_even = mpfr.MPFR_RNDN,
    /// `MPFR_RNDZ`: round toward zero.
    toward_zero = mpfr.MPFR_RNDZ,
    /// `MPFR_RNDU`: round toward positive infinity.
    toward_positive = mpfr.MPFR_RNDU,
    /// `MPFR_RNDD`: round toward negative infinity.
    toward_negative = mpfr.MPFR_RNDD,
    /// `MPFR_RNDA`: round away from zero.
    away_from_zero = mpfr.MPFR_RNDA,
    /// `MPFR_RNDF`: faithful rounding, between the RNDD and RNDU results.
    ///
    /// The ternary value and the inexact flag are unspecified in this mode
    /// (doc/mpfr.texi:975-980) and results are not reproducible.
    faithful = mpfr.MPFR_RNDF,
    /// `MPFR_RNDNA`: round to nearest, ties away from zero. Only valid for
    /// `Float.roundToNearestAway`; no other operation accepts it.
    nearest_away = mpfr.MPFR_RNDNA,
};

/// MPFR's ternary value, the `int` that nearly every MPFR operation returns.
///
/// doc/mpfr.texi:984-1014: zero means the stored value is the exact result, a
/// positive value means the stored value is greater than the exact result, and
/// a negative value means it is smaller. An infinite result counts as inexact
/// only when it came from overflow, and a NaN result is always exact.
pub const Ternary = enum {
    /// The stored value is the exact mathematical result; upstream returned 0.
    exact,
    /// The stored value is greater than the exact result; upstream returned > 0.
    above,
    /// The stored value is smaller than the exact result; upstream returned < 0.
    below,

    /// Convert the raw `int` that MPFR returns.
    pub fn fromRaw(value: c_int) Ternary {
        return if (value > 0) .above else if (value < 0) .below else .exact;
    }

    /// A raw `int` MPFR could return for this outcome, chosen so that its
    /// negation stays representable (doc/mpfr.texi:1013-1014).
    pub fn toRaw(self: Ternary) c_int {
        return switch (self) {
            .exact => 0,
            .above => 1,
            .below => -1,
        };
    }
};

/// The MPFR exception flags currently in effect.
///
/// They are the calling thread's only when the linked library was built
/// thread-safe; in this package's own build they are one process-wide word, as
/// the module comment on global state records. Reading and raising them is
/// separate from the ternary value a call returns: a call may return
/// `.exact` and still raise a flag, and an operation upstream does not flag
/// raises nothing here.
///
/// The field order is `MPFR_FLAGS_UNDERFLOW` through `MPFR_FLAGS_DIVBY0`, the
/// bit set `mpfr_flags_t` (src/mpfr.h:73-87) exposes through
/// `mpfr_flags_test`, `mpfr_flags_set` and `mpfr_flags_clear`.
///
/// The backing integer is `u6` because those six macros (src/mpfr.h:76-81) are
/// the only flags upstream defines, one bit each, in exactly this order. A
/// packed struct's backing integer must have the same bit width as its fields,
/// so `u32`, which is what the C `unsigned int` happens to be on every
/// required target, would not compile here. That costs nothing at the
/// boundary: `toRaw` and `fromRaw` go through the `MPFR_FLAGS_*` constants
/// rather than a bit cast, so no assumption about the width of the C type
/// survives into the translated API.
pub const Flags = packed struct(u6) {
    /// `MPFR_FLAGS_UNDERFLOW`: the rounded result fell below the exponent range.
    underflow: bool = false,
    /// `MPFR_FLAGS_OVERFLOW`: the rounded result rose above the exponent range.
    overflow: bool = false,
    /// `MPFR_FLAGS_NAN`: a NaN was produced, including a propagated NaN.
    nan: bool = false,
    /// `MPFR_FLAGS_INEXACT`: the result had to be rounded.
    inexact: bool = false,
    /// `MPFR_FLAGS_ERANGE`: a non-MPFR result was invalid, for example a
    /// comparison against NaN or an out-of-range integer conversion.
    erange: bool = false,
    /// `MPFR_FLAGS_DIVBY0`: a finite division produced an exact infinity.
    divide_by_zero: bool = false,

    /// All flags cleared.
    pub const none: Flags = .{};

    /// Every flag upstream can raise.
    pub const all: Flags = .{
        .underflow = true,
        .overflow = true,
        .nan = true,
        .inexact = true,
        .erange = true,
        .divide_by_zero = true,
    };

    /// Read the exception flags currently in effect. See the type comment for
    /// whether that is the calling thread's or the process's.
    pub fn read() Flags {
        return .{
            .underflow = c.mpfr_underflow_p() != 0,
            .overflow = c.mpfr_overflow_p() != 0,
            .nan = c.mpfr_nanflag_p() != 0,
            .inexact = c.mpfr_inexflag_p() != 0,
            .erange = c.mpfr_erangeflag_p() != 0,
            .divide_by_zero = c.mpfr_divby0_p() != 0,
        };
    }

    /// The `mpfr_flags_t` bit mask this value represents.
    pub fn toRaw(self: Flags) mpfr.mpfr_flags_t {
        var mask: mpfr.mpfr_flags_t = 0;
        if (self.underflow) mask |= mpfr.MPFR_FLAGS_UNDERFLOW;
        if (self.overflow) mask |= mpfr.MPFR_FLAGS_OVERFLOW;
        if (self.nan) mask |= mpfr.MPFR_FLAGS_NAN;
        if (self.inexact) mask |= mpfr.MPFR_FLAGS_INEXACT;
        if (self.erange) mask |= mpfr.MPFR_FLAGS_ERANGE;
        if (self.divide_by_zero) mask |= mpfr.MPFR_FLAGS_DIVBY0;
        return mask;
    }

    /// The inverse of `toRaw`.
    pub fn fromRaw(mask: mpfr.mpfr_flags_t) Flags {
        return .{
            .underflow = mask & mpfr.MPFR_FLAGS_UNDERFLOW != 0,
            .overflow = mask & mpfr.MPFR_FLAGS_OVERFLOW != 0,
            .nan = mask & mpfr.MPFR_FLAGS_NAN != 0,
            .inexact = mask & mpfr.MPFR_FLAGS_INEXACT != 0,
            .erange = mask & mpfr.MPFR_FLAGS_ERANGE != 0,
            .divide_by_zero = mask & mpfr.MPFR_FLAGS_DIVBY0 != 0,
        };
    }

    /// Raise the flags that are set in `self` and leave the others alone.
    pub fn raise(self: Flags) void {
        c.mpfr_flags_set(self.toRaw());
    }

    /// Lower the flags that are set in `self` and leave the others alone.
    pub fn lower(self: Flags) void {
        c.mpfr_flags_clear(self.toRaw());
    }
};

/// A base-`base` significand produced by `Float.toDigits`, with its exponent.
///
/// `buffer` is allocated by MPFR through GMP's configured allocator, so it is
/// no `std.mem.Allocator`'s to free and a Zig leak checker does not see it. One
/// successful `toDigits` produces one buffer and owes exactly one `deinit`.
/// Zig has no move semantics, so a `Digits` copied by value aliases that same
/// buffer: `deinit` must then be called on one copy only, and a second call,
/// through the copy or through the original, is a double `mpfr_free_str`.
/// `deinit` poisons only the variable it is called on, which bounds a repeat
/// through that variable and protects no alias.
///
/// `Digits` holds no allocator, no borrowed state and no pointer to a `Float`;
/// the value it renders is not kept alive by it.
pub const Digits = struct {
    /// Significant digits, with an implicit radix point immediately to the left
    /// of the first digit, exactly as `mpfr_get_str` produces them
    /// (doc/mpfr.texi:1909-1911). A leading `-` is part of the digits.
    ///
    /// The bytes are writable in place, because upstream allows it as long as
    /// the string's length is unchanged when it is freed
    /// (doc/mpfr.texi:1950-1953) and `mpfr_free_str` frees
    /// `strlen(str) + 1` bytes (doc/mpfr.texi:1945-1948). Editing the digits
    /// or the sign is therefore safe; shortening the string, dropping the
    /// sentinel or writing past it is not, and neither is changing a byte to
    /// anything that ends the string earlier.
    buffer: [:0]u8,
    /// Position of that radix point, so the value is `0.<buffer> * base^exponent`.
    exponent: Exponent,

    /// The significant digits, without the sentinel.
    ///
    /// The slice borrows `buffer`; it stays valid until `deinit` and is not
    /// invalidated by writes to `buffer`, which change the bytes it reads.
    pub fn digits(self: *const Digits) [:0]const u8 {
        return self.buffer;
    }

    /// Release the buffer with `mpfr_free_str`, exactly once.
    ///
    /// The value is unusable afterwards, and a second `deinit` on the same
    /// variable is a double free; `deinit` poisons that variable, so reading it
    /// or calling `deinit` again through it is a use of `undefined` rather than
    /// a diagnosable error. Nothing else is released: MPFR's caches and the
    /// GMP allocator itself are untouched.
    pub fn deinit(self: *Digits) void {
        c.mpfr_free_str(self.buffer.ptr);
        self.* = undefined;
    }
};

/// Failure of a text-to-value or value-to-text conversion.
/// Shared vocabulary: parsing reports `InvalidNumber`, rendering `InvalidBase`.
/// GMP allocation failure is not a recoverable conversion error.
pub const ConversionError = error{
    /// The text is not a complete number. Two upstream entry points report the
    /// same condition and `Float` maps both here:
    ///
    ///  * `mpfr_set_str` fails on an empty string (src/set_str.c:29-30) and on
    ///    any character left over after the parsed number (src/set_str.c:32),
    ///    so `parseWhole("1.0625xyz", ...)` fails even though `1.0625` parsed.
    ///  * `mpfr_strtofr` reports the same thing by leaving the end pointer at
    ///    the start of the input, which is `consumed == 0`
    ///    (doc/mpfr.texi:1622-1627), so `parsePrefix("nonsense", ...)` fails.
    /// The two entry points leave `self` in different states, so read this
    /// beside the method that raised it. `parsePrefix` consumed nothing, and
    /// `mpfr_strtofr` stores a positive zero before it starts, so `self` holds
    /// that zero (src/strtofr.c:953-954). `parseWhole` may already have stored
    /// the prefix it did parse, because `mpfr_set_str` returns -1 only after
    /// `mpfr_strtofr` has run (src/set_str.c:31-32).
    InvalidNumber,
    /// The base was outside the two ranges `mpfr_get_str` accepts, `2..62` and
    /// `-36..-2`, so it did nothing and returned a null pointer before it
    /// allocated anything (doc/mpfr.texi:1888-1889; src/get_str.c:2611-2613).
    /// `isValidBase` is that test; base `0` is not one of the accepted values.
    InvalidBase,
};

/// `__MPFR_EXP_MAX` from src/mpfr.h:225, the largest `mpfr_exp_t`.
const exp_max: Exponent = blk: {
    const unsigned_max: mpfr.mpfr_uexp_t = @bitCast(@as(std.meta.Int(.signed, @bitSizeOf(mpfr.mpfr_uexp_t)), -1));
    break :blk @intCast(unsigned_max >> 1);
};

/// `__MPFR_EXP_NAN` from src/mpfr.h:226.
const exp_nan: Exponent = 1 - exp_max;
/// `__MPFR_EXP_ZERO` from src/mpfr.h:227.
const exp_zero: Exponent = 0 - exp_max;
/// `__MPFR_EXP_INF` from src/mpfr.h:228.
const exp_inf: Exponent = 2 - exp_max;

/// An arbitrary-precision floating-point value with an explicit precision.
///
/// `init` is the only construction that establishes a valid value. A struct
/// literal is reachable in Zig, so a `Float` the caller did not get from `init`
/// holds storage upstream never initialised and is not a value MPFR can
/// operate on. `Float.init(bits)` yields NaN at `bits` bits, and every method
/// leaves that one value valid until `deinit`.
///
/// A `Float` owns exactly one upstream `mpfr_t`, whose significand is allocated
/// by GMP's allocator. `deinit` releases it with `mpfr_clear`; MPFR keeps the
/// same allocated space for the whole life of the variable
/// (doc/mpfr.texi:870-874). No Zig allocator is involved, so a Zig leak checker
/// does not observe that allocation.
///
/// Zig has no move semantics, so a `Float` copied by value aliases the same
/// limbs and the same allocation: `deinit` must then be called on exactly one
/// copy, and calling it through two copies is a double `mpfr_clear`. Pass
/// `*Float` and `*const Float` rather than duplicating the value. A pointer
/// from `raw` or `rawConst` addresses the `Float` it was taken from, so a copy
/// made afterwards does not move it and a copy returned in place of the
/// original leaves it naming storage the caller no longer owns.
pub const Float = struct {
    /// The upstream `mpfr_t` this wrapper owns. It is a reachable field because
    /// Zig has no private fields, so the facade's invariants are a documented
    /// obligation rather than an enforced one. Reading `_mpfr_prec`,
    /// `_mpfr_sign` and `_mpfr_exp` is what the classification methods do;
    /// writing them directly is not supported and no method re-derives a value
    /// upstream defines. Giving a second `Float` this field makes the two
    /// values share one significand, with one `deinit` between them.
    inner: mpfr.mpfr_t,

    /// Allocate a value of `bits` significand bits, initialised to NaN.
    ///
    /// `bits` must lie between `min_precision` and `max_precision`; outside
    /// that range the behaviour is undefined (doc/mpfr.texi:1359-1360), and
    /// `mpfr_init2` checks it with `MPFR_ASSERTN (MPFR_PREC_COND (p))`
    /// (src/init2.c:50-53). That check is not compiled out here:
    /// `MPFR_WANT_ASSERT` is left at its default 0 (src/mpfr-impl.h:488-497),
    /// which keeps `MPFR_ASSERTN` a live test. An out-of-range `bits` therefore
    /// aborts the process in Debug, ReleaseSafe, ReleaseFast and ReleaseSmall
    /// alike, rather than being diagnosed in one mode and ignored in another,
    /// so `isValidPrecision` is the ordinary test to run first on a precision
    /// that came from outside your own code. Upstream also notes that MPFR
    /// raises the precision internally for correct rounding, so a precision
    /// near the maximum asks GMP for an allocation it cannot make
    /// (doc/mpfr.texi:807-812).
    ///
    /// `mpfr_init2` sets the value to NaN. Prefer this over `mpfr_init` for the
    /// reason upstream does: the default precision can be changed by other
    /// libraries that do not restore it (doc/mpfr.texi:1408-1409).
    ///
    /// The call cannot fail, so the returned value owes exactly one `deinit`
    /// and the `defer` belongs directly after it.
    pub fn init(bits: Precision) Float {
        var result: Float = undefined;
        c.mpfr_init2(&result.inner, bits);
        return result;
    }

    /// Release the significand with `mpfr_clear`, exactly once.
    ///
    /// The value is unusable afterwards, and a second `deinit` reached through
    /// any copy is a double free. This one does not poison `self`, so a repeat
    /// through the same variable hands freed limbs back to `mpfr_clear` with no
    /// diagnostic in any optimize mode. Nothing else is released: MPFR's
    /// caches and the GMP allocator are untouched.
    pub fn deinit(self: *Float) void {
        c.mpfr_clear(&self.inner);
    }

    /// The raw upstream destination pointer, for the escape hatch.
    ///
    /// The pointer is `&self.inner`, so it addresses this `Float`'s own
    /// storage rather than the significand: it is valid from this call until
    /// `deinit`, it is not moved by an operation on any other value, and it
    /// says nothing about another `Float` that copied this one. It is not a
    /// second owner, and it must not be passed to `mpfr_clear`,
    /// `mpfr_free_cache` or anything else that ends the variable's life,
    /// because `deinit` still owes that one `mpfr_clear`.
    pub fn raw(self: *Float) mpfr.mpfr_ptr {
        return &self.inner;
    }

    /// The raw upstream const pointer, for the escape hatch.
    ///
    /// The same borrow as `raw`, read-only: it is valid until `deinit` and it
    /// names this `Float`'s own storage. MPFR requires an `mpfr_srcptr` for
    /// every read-only entry point, so this is what reaches `c` methods that
    /// take one.
    pub fn rawConst(self: *const Float) mpfr.mpfr_srcptr {
        return &self.inner;
    }

    // ---- precision ----------------------------------------------------

    /// The current significand width in bits.
    ///
    /// Mirrors the `mpfr_get_prec` macro (src/mpfr.h:906), which reads
    /// `_mpfr_prec` directly.
    pub fn precision(self: *const Float) Precision {
        return self.inner[0]._mpfr_prec;
    }

    /// Reset the significand width to `bits` bits and set the value to NaN.
    ///
    /// This is `mpfr_set_prec`, whose documented contract is that the previous
    /// value is lost (doc/mpfr.texi:1499-1515). Use `roundToPrecision` to keep
    /// the value. The allocated space is reused when it is already large enough.
    ///
    /// `bits` must lie between `min_precision` and `max_precision`
    /// (doc/mpfr.texi:1507-1508), the same bound `init` requires; `init` states
    /// what an out-of-range precision does. Upstream also forbids this call on a
    /// value built with `MPFR_DECL_INIT` or `mpfr_custom_init_set`
    /// (doc/mpfr.texi:1512-1514), neither of which this facade constructs.
    pub fn resetPrecision(self: *Float, bits: Precision) void {
        c.mpfr_set_prec(&self.inner, bits);
    }

    /// Round the value to `bits` bits, keeping its value.
    ///
    /// This is `mpfr_prec_round` (doc/mpfr.texi:3325-3333): the significand is
    /// rounded in the direction `mode` and the precision becomes `bits`.
    /// Growing the precision zero-fills instead of rounding, so the ternary
    /// value is then exact. `bits` must lie between `min_precision` and
    /// `max_precision` (doc/mpfr.texi:3327-3328), the bound `init` states in
    /// full.
    ///
    /// The returned `Ternary` is the whole report of that rounding. This entry
    /// point does not raise the inexact flag: `mpfr_prec_round` returns the
    /// value `mpfr_round_raw` computed and never writes `__gmpfr_flags`
    /// (src/round_prec.c:99-122), and the generic rounder it calls has no flag
    /// store at all (src/round_raw_generic.c:60-273). A caller that must know
    /// whether the precision change rounded reads this return value, not
    /// `Flags.read`. The one path that does reach a flag is a carry out of the
    /// exponent range, which calls `mpfr_overflow` (src/round_prec.c:107-108).
    ///
    /// The integer roundings `roundToNearestEven`, `roundToNearestAway`,
    /// `truncate`, `ceil` and `floor` go through `mpfr_rint` and behave
    /// differently: it returns through `MPFR_RET`, which raises the inexact
    /// flag for a nonzero result (src/rint.c:286-302, src/mpfr-impl.h:1183-1184).
    pub fn roundToPrecision(self: *Float, bits: Precision, mode: RoundingMode) Ternary {
        return Ternary.fromRaw(c.mpfr_prec_round(&self.inner, bits, rnd(mode)));
    }

    // ---- assignment ----------------------------------------------------

    /// `self = other`, rounded in `mode`. Using `self` as `other` is allowed.
    ///
    /// This is the `mpfr_set` macro (src/mpfr.h:921-925) reduced to
    /// `mpfr_set4(self, other, mode, sign(other))`.
    pub fn set(self: *Float, other: *const Float, mode: RoundingMode) Ternary {
        return Ternary.fromRaw(c.mpfr_set4(&self.inner, other.rawConst(), rnd(mode), signBitOf(other)));
    }

    /// `self = |other|`, rounded in `mode`. This is `mpfr_abs` (src/mpfr.h:927).
    pub fn setAbs(self: *Float, other: *const Float, mode: RoundingMode) Ternary {
        return Ternary.fromRaw(c.mpfr_set4(&self.inner, other.rawConst(), rnd(mode), 1));
    }

    /// `self = -other`, rounded in `mode`.
    pub fn negateFrom(self: *Float, other: *const Float, mode: RoundingMode) Ternary {
        return Ternary.fromRaw(c.mpfr_neg(&self.inner, other.rawConst(), rnd(mode)));
    }

    /// `self = value`, rounded in `mode`. Exact for any `f64` once
    /// `precision >= 53`; otherwise it is the correctly rounded conversion.
    pub fn setF64(self: *Float, value: f64, mode: RoundingMode) Ternary {
        return Ternary.fromRaw(c.mpfr_set_d(&self.inner, value, rnd(mode)));
    }

    /// `self = value * 2^0`, rounded in `mode`.
    ///
    /// The domain is upstream's `unsigned long`, which is 32 bits on the
    /// x86_64-windows-gnu target of the cross matrix. Zig does not narrow the
    /// argument for you, so passing a value that does not fit is a caller error.
    /// Use the raw `c` module, or a `Float` fed by `setF64`, when 64-bit-exact
    /// integer construction is needed on an LLP64 target.
    pub fn setUnsigned(self: *Float, value: c_ulong, mode: RoundingMode) Ternary {
        return Ternary.fromRaw(c.mpfr_set_ui_2exp(&self.inner, value, 0, rnd(mode)));
    }

    /// `self = value * 2^0`, rounded in `mode`. See `setUnsigned` on width.
    pub fn setSigned(self: *Float, value: c_long, mode: RoundingMode) Ternary {
        return Ternary.fromRaw(c.mpfr_set_si_2exp(&self.inner, value, 0, rnd(mode)));
    }

    /// `self = 1 * 2^exponent`, rounded in `mode`.
    pub fn setPowerOfTwo(self: *Float, exponent: Exponent, mode: RoundingMode) Ternary {
        return Ternary.fromRaw(c.mpfr_set_ui_2exp(&self.inner, 1, exponent, rnd(mode)));
    }

    /// Parse the whole of `text` in `base` and round in `mode`.
    ///
    /// `base` is 0 to auto-detect or 2..62, as `mpfr_strtofr` requires;
    /// anything else is undefined behaviour upstream
    /// (doc/mpfr.texi:1614-1617). `text` must be sentinel-terminated, because
    /// MPFR reads the C string in place; no copy is made.
    ///
    /// On success `self` holds the value of the text, correctly rounded in
    /// `mode`, and nothing is returned because nothing else is known. This is
    /// `mpfr_set_str`, whose return value is 0 or -1 and is deliberately not a
    /// ternary value (doc/mpfr.texi:1603-1607; src/set_str.c:24-33): a text
    /// that this precision cannot hold exactly parses successfully and is
    /// silently rounded, so there is no rounding signal to report here. Use
    /// `parsePrefix` when the ternary value of the conversion matters, which
    /// is also the only way to tell an infinity that came from the text from
    /// one that came from an overflow (doc/mpfr.texi:1609-1611).
    ///
    /// The whole string must be a valid number: any trailing character,
    /// trailing whitespace included, makes this return `error.InvalidNumber`
    /// instead of parsing a prefix. Use `parsePrefix` to read a leading number
    /// out of a longer string.
    ///
    /// Upstream accepts string shapes that are not numbers. `@NaN@` and
    /// `@Inf@`, with an optional sign, are special values in every base from 2
    /// to 62, and `nan`, `inf` and `infinity` are special values in the bases
    /// up to 16, with the sign read first and the case ignored
    /// (src/strtofr.c:249-303; upstream's own tests, tests/tset_str.c:284-346).
    /// A NaN alone additionally accepts a parenthesised run of letters, digits
    /// and underscores as part of the string, so `"@NaN@(garbage)"` parses whole
    /// in every base from 2 to 62 (tests/tset_str.c:284-291). An infinity gets
    /// no such leniency (src/strtofr.c:296-303), which is why upstream keeps
    /// its `"@Inf@garbage"` cases commented out (tests/tset_str.c:293-314).
    ///
    /// On failure `self` must not be read: an empty string returns before
    /// anything is written (src/set_str.c:29-30), and otherwise `mpfr_strtofr`
    /// has already stored either the prefix it parsed or a positive zero
    /// (src/strtofr.c:953-954).
    pub fn parseWhole(
        self: *Float,
        text: [:0]const u8,
        base: c_int,
        mode: RoundingMode,
    ) ConversionError!void {
        if (c.mpfr_set_str(&self.inner, text.ptr, base, rnd(mode)) != 0) return error.InvalidNumber;
    }

    /// Parse the longest numeric prefix of `text` in `base` and round in
    /// `mode`.
    ///
    /// Returns how many bytes were consumed together with the ternary value of
    /// the conversion, which is how a caller learns whether this precision
    /// held the parsed value exactly. This is `mpfr_strtofr`, the entry point
    /// that does report a real ternary value (doc/mpfr.texi:1614-1624), so it
    /// is the only way to tell an infinity that came from the text from one
    /// that came from an overflow (doc/mpfr.texi:1609-1611).
    ///
    /// A special value ends the number at the end of its token: `"@INF@*2"`
    /// consumes the five bytes of the token and leaves `"*2"` (upstream's own
    /// test, tests/tstrtofr.c:178-184). Requiring `consumed == text.len` is
    /// therefore not the same test as `parseWhole` accepting the whole string,
    /// which is the one shape where a NaN swallows a parenthesised payload.
    ///
    /// Failure means no byte was consumed, and then `self` holds a positive
    /// zero, because `mpfr_strtofr` stores one before it starts parsing
    /// (src/strtofr.c:953-954, 981-982).
    pub fn parsePrefix(
        self: *Float,
        text: [:0]const u8,
        base: c_int,
        mode: RoundingMode,
    ) ConversionError!Prefix {
        var end: [*c]u8 = undefined;
        const status = c.mpfr_strtofr(&self.inner, text.ptr, &end, base, rnd(mode));
        const consumed = @intFromPtr(end) - @intFromPtr(text.ptr);
        if (consumed == 0) return error.InvalidNumber;
        return .{ .consumed = consumed, .ternary = Ternary.fromRaw(status) };
    }

    // ---- special values ------------------------------------------------

    /// Set `self` to a NaN.
    pub fn setNan(self: *Float) void {
        c.mpfr_set_nan(&self.inner);
    }

    /// Set `self` to an infinity with the given sign.
    pub fn setInf(self: *Float, positive: bool) void {
        c.mpfr_set_inf(&self.inner, if (positive) 1 else -1);
    }

    /// Set `self` to a zero with the given sign.
    pub fn setZero(self: *Float, positive: bool) void {
        c.mpfr_set_zero(&self.inner, if (positive) 1 else -1);
    }

    // ---- arithmetic ----------------------------------------------------

    /// `self += other`, rounded in `mode`. Using `self` as `other` is allowed.
    pub fn add(self: *Float, other: *const Float, mode: RoundingMode) Ternary {
        return Ternary.fromRaw(c.mpfr_add(&self.inner, &self.inner, other.rawConst(), rnd(mode)));
    }

    /// `self -= other`, rounded in `mode`. Using `self` as `other` is allowed.
    pub fn sub(self: *Float, other: *const Float, mode: RoundingMode) Ternary {
        return Ternary.fromRaw(c.mpfr_sub(&self.inner, &self.inner, other.rawConst(), rnd(mode)));
    }

    /// `self *= other`, rounded in `mode`. Using `self` as `other` is allowed.
    pub fn mul(self: *Float, other: *const Float, mode: RoundingMode) Ternary {
        return Ternary.fromRaw(c.mpfr_mul(&self.inner, &self.inner, other.rawConst(), rnd(mode)));
    }

    /// `self /= other`, rounded in `mode`. Using `self` as `other` is allowed.
    ///
    /// Dividing a non-zero value by zero yields a signed infinity, raises
    /// `divide_by_zero` and returns `.exact`, because that infinity is exact
    /// rather than the result of an overflow (doc/mpfr.texi:1010-1012, 1141).
    /// Zero divided by zero yields NaN and also returns `.exact`.
    pub fn div(self: *Float, other: *const Float, mode: RoundingMode) Ternary {
        return Ternary.fromRaw(c.mpfr_div(&self.inner, &self.inner, other.rawConst(), rnd(mode)));
    }

    /// `self *= value`, rounded in `mode`. The `f64` is used exactly, with no
    /// detour through the significand; this is `mpfr_mul_d`.
    pub fn mulF64(self: *Float, value: f64, mode: RoundingMode) Ternary {
        return Ternary.fromRaw(c.mpfr_mul_d(&self.inner, &self.inner, value, rnd(mode)));
    }

    /// `self = sqrt(self)`, rounded in `mode`. Negative input yields NaN.
    pub fn sqrt(self: *Float, mode: RoundingMode) Ternary {
        return Ternary.fromRaw(c.mpfr_sqrt(&self.inner, &self.inner, rnd(mode)));
    }

    /// `self *= 2^power`, rounded in `mode`.
    ///
    /// This is the `mpfr_mul_2exp` macro (src/mpfr.h:932) expanded to
    /// `mpfr_mul_2ui`.
    pub fn scaleByPowerOfTwo(self: *Float, power: c_ulong, mode: RoundingMode) Ternary {
        return Ternary.fromRaw(c.mpfr_mul_2ui(&self.inner, &self.inner, power, rnd(mode)));
    }

    /// `self /= 2^power`, rounded in `mode`.
    ///
    /// This is the `mpfr_div_2exp` macro (src/mpfr.h:933) expanded to
    /// `mpfr_div_2ui`.
    pub fn divideByPowerOfTwo(self: *Float, power: c_ulong, mode: RoundingMode) Ternary {
        return Ternary.fromRaw(c.mpfr_div_2ui(&self.inner, &self.inner, power, rnd(mode)));
    }

    /// Round `self` to an integer, ties away from zero, and return the ternary
    /// value.
    ///
    /// This is the `mpfr_round` macro (src/mpfr.h:913) expanded to
    /// `mpfr_rint(self, self, MPFR_RNDNA)`. It is the only supported way to
    /// reach `RoundingMode.nearest_away`.
    pub fn roundToNearestAway(self: *Float) Ternary {
        return Ternary.fromRaw(c.mpfr_rint(&self.inner, &self.inner, rnd(RoundingMode.nearest_away)));
    }

    /// Round `self` to an integer, ties to even, and return the ternary value.
    ///
    /// This is the `MPFR_RNDN` counterpart of `roundToNearestAway`, and it is
    /// the call that shows the two nearest modes apart. MPFR has no
    /// `mpfr_roundeven` macro, so this goes straight to `mpfr_rint`.
    pub fn roundToNearestEven(self: *Float) Ternary {
        return Ternary.fromRaw(c.mpfr_rint(&self.inner, &self.inner, rnd(RoundingMode.nearest_even)));
    }

    /// Round `self` to an integer, truncating toward zero, and return the
    /// ternary value. This is `mpfr_trunc` (src/mpfr.h:914).
    pub fn truncate(self: *Float) Ternary {
        return Ternary.fromRaw(c.mpfr_rint(&self.inner, &self.inner, rnd(RoundingMode.toward_zero)));
    }

    /// Round `self` up toward positive infinity. This is `mpfr_ceil` (src/mpfr.h:915).
    pub fn ceil(self: *Float) Ternary {
        return Ternary.fromRaw(c.mpfr_rint(&self.inner, &self.inner, rnd(RoundingMode.toward_positive)));
    }

    /// Round `self` down toward negative infinity. This is `mpfr_floor` (src/mpfr.h:916).
    pub fn floor(self: *Float) Ternary {
        return Ternary.fromRaw(c.mpfr_rint(&self.inner, &self.inner, rnd(RoundingMode.toward_negative)));
    }

    // ---- comparison ----------------------------------------------------

    /// Compare `self` with `other` the way the `mpfr_cmp` macro does.
    ///
    /// This is src/mpfr.h:931, `mpfr_cmp3(self, other, 1)`. An unordered
    /// comparison, which includes every comparison involving NaN, yields `.eq`;
    /// test `isUnordered` first when that matters.
    pub fn compare(self: *const Float, other: *const Float) Order {
        return orderOf(c.mpfr_cmp3(self.rawConst(), other.rawConst(), 1));
    }

    /// Compare `|self|` with `|other|`, which is upstream's real
    /// `mpfr_cmpabs` (src/cmpabs.c:27-28). A NaN operand makes it yield zero
    /// and raise the range-error flag (src/cmpabs.c:36-39), so a caller that
    /// cares should test `isUnordered` first.
    pub fn compareAbs(self: *const Float, other: *const Float) Order {
        return orderOf(c.mpfr_cmpabs(self.rawConst(), other.rawConst()));
    }

    /// Compare `self` with `value`, the way the `mpfr_cmp_ui` macro does
    /// (src/mpfr.h:918 and 964-967) expanded to `mpfr_cmp_ui_2exp(..., 0)`.
    pub fn compareUnsigned(self: *const Float, value: c_ulong) Order {
        return orderOf(c.mpfr_cmp_ui_2exp(self.rawConst(), value, 0));
    }

    /// Compare `self` with `value`, the way the `mpfr_cmp_si` macro does
    /// (src/mpfr.h:919 and 970-973) expanded to `mpfr_cmp_si_2exp(..., 0)`.
    pub fn compareSigned(self: *const Float, value: c_long) Order {
        return orderOf(c.mpfr_cmp_si_2exp(self.rawConst(), value, 0));
    }

    /// Whether `self` and `other` are unordered, which holds exactly when at
    /// least one of them is NaN.
    pub fn isUnordered(self: *const Float, other: *const Float) bool {
        return c.mpfr_unordered_p(self.rawConst(), other.rawConst()) != 0;
    }

    /// Whether `self` and `other` are exactly equal. This is `mpfr_equal_p`,
    /// which is false when either operand is NaN.
    pub fn isEqual(self: *const Float, other: *const Float) bool {
        return c.mpfr_equal_p(self.rawConst(), other.rawConst()) != 0;
    }

    // ---- classification ------------------------------------------------

    /// Whether `self` is a NaN. Mirrors the `mpfr_nan_p` macro (src/mpfr.h:893).
    pub fn isNan(self: *const Float) bool {
        return self.inner[0]._mpfr_exp == exp_nan;
    }

    /// Whether `self` is an infinity. Mirrors the `mpfr_inf_p` macro (src/mpfr.h:894).
    pub fn isInf(self: *const Float) bool {
        return self.inner[0]._mpfr_exp == exp_inf;
    }

    /// Whether `self` is a zero. Mirrors the `mpfr_zero_p` macro (src/mpfr.h:895).
    pub fn isZero(self: *const Float) bool {
        return self.inner[0]._mpfr_exp == exp_zero;
    }

    /// Whether `self` is a finite non-zero value. Mirrors the `mpfr_regular_p`
    /// macro (src/mpfr.h:896).
    pub fn isRegular(self: *const Float) bool {
        return self.inner[0]._mpfr_exp > exp_inf;
    }

    /// Whether `self` is finite, that is neither NaN nor an infinity. This is
    /// upstream's real `mpfr_number_p` function, not a macro.
    pub fn isNumber(self: *const Float) bool {
        return c.mpfr_number_p(self.rawConst()) != 0;
    }

    /// Whether `self` has no fractional part. This is upstream's real
    /// `mpfr_integer_p` function.
    pub fn isInteger(self: *const Float) bool {
        return c.mpfr_integer_p(self.rawConst()) != 0;
    }

    /// Whether the sign bit of `self` is set. Mirrors the `mpfr_signbit` macro
    /// (src/mpfr.h:930), which is `_mpfr_sign < 0`.
    pub fn isSignNegative(self: *const Float) bool {
        return self.inner[0]._mpfr_sign < 0;
    }

    /// The sign of `self`: -1, 0 or +1, with 0 for both zero and NaN.
    ///
    /// Mirrors the `mpfr_sgn` macro (src/mpfr.h:901-904) including its side
    /// effect, because that macro evaluates `mpfr_set_erangeflag()` for a NaN.
    pub fn sign(self: *const Float) i32 {
        const exponent = self.inner[0]._mpfr_exp;
        if (exponent < exp_inf) {
            if (exponent == exp_nan) c.mpfr_set_erangeflag();
            return 0;
        }
        return self.inner[0]._mpfr_sign;
    }

    // ---- conversion out ------------------------------------------------

    /// The nearest `f64` to `self` in the direction `mode`.
    ///
    /// The conversion is exact when the value fits a `f64`, and it rounds
    /// silently when it does not: `mpfr_get_d` is the whole of that entry point
    /// and never writes `__gmpfr_flags` (src/get_d.c:34-132), so neither an
    /// inexact conversion nor an overflow to an infinity is reported in the
    /// exception word. The returned value is the only result. Contrast
    /// `toSigned` and `toUnsigned`, which do raise `erange` and `inexact`
    /// (doc/mpfr.texi:1760-1772).
    pub fn toF64(self: *const Float, mode: RoundingMode) f64 {
        return c.mpfr_get_d(self.rawConst(), rnd(mode));
    }

    /// The nearest `long` to `self` in the direction `mode`, saturating outside
    /// the type's range and raising `erange`.
    pub fn toSigned(self: *const Float, mode: RoundingMode) c_long {
        return c.mpfr_get_si(self.rawConst(), rnd(mode));
    }

    /// The nearest `unsigned long` to `self` in the direction `mode`,
    /// saturating outside the type's range and raising `erange`.
    pub fn toUnsigned(self: *const Float, mode: RoundingMode) c_ulong {
        return c.mpfr_get_ui(self.rawConst(), rnd(mode));
    }

    /// Whether `self` fits in a `long` once rounded to an integer in `mode`.
    ///
    /// The question is asked *after* rounding, not before: upstream returns
    /// non-zero when `round(self, mode)` is representable
    /// (doc/mpfr.texi:1964-1969; src/fits_s.h:42-48 spells out the same rule).
    /// So a value with a fractional part can fit, and the manual's own example
    /// is fractional: with `MPFR_RNDU` on -0.5 this is non-zero. The call
    /// raises no flag: any conversion it performs is internal.
    pub fn fitsSigned(self: *const Float, mode: RoundingMode) bool {
        return c.mpfr_fits_slong_p(self.rawConst(), rnd(mode)) != 0;
    }

    /// Whether `self` fits in an `unsigned long` once rounded to an integer in
    /// `mode`. See `fitsSigned` for the after-rounding rule; the signed family
    /// and this one differ for negative operands (src/fits_u.h:39-43).
    pub fn fitsUnsigned(self: *const Float, mode: RoundingMode) bool {
        return c.mpfr_fits_ulong_p(self.rawConst(), rnd(mode)) != 0;
    }

    /// Render `self` as `digits` significant digits in `base`, or as many digits
    /// as the current precision needs when `digits` is zero.
    ///
    /// `base` must be in `2..62` or `-36..-2`, the two ranges `mpfr_get_str`
    /// accepts; base `0` is not one of them. Any other value returns
    /// `error.InvalidBase`, and `isValidBase` is that test. The digit alphabet
    /// follows the range: `2..36` gives digits and lower-case letters,
    /// `-36..-2` digits and upper-case letters, and `37..62` digits, upper-case
    /// then lower-case letters in that order, so above base 10 the successor of
    /// the digit `9` depends on the base (doc/mpfr.texi:1888-1898).
    ///
    /// The value is rounded in the direction `mode` and the inexact flag is set
    /// exactly when the rendering is inexact, because `mpfr_get_str` has no
    /// return channel of its own (doc/mpfr.texi:1942). A NaN input renders as
    /// `@NaN@` and also raises the NaN flag, and an infinity renders as
    /// `@Inf@` or `-@Inf@` (doc/mpfr.texi:1900-1902); `flags()` shows either.
    ///
    /// On success the result owns MPFR-allocated memory and owes exactly one
    /// `Digits.deinit`. On `error.InvalidBase` nothing was allocated.
    /// GMP allocators must not return null (vendor/gmp/doc/gmp.texi:7487-7490);
    /// the default allocator aborts on allocation failure. An unexpected null
    /// result for a valid base panics in every optimization mode.
    pub fn toDigits(self: *const Float, base: c_int, digits: usize, mode: RoundingMode) ConversionError!Digits {
        // A `digits` of 0 is passed through unchanged, so MPFR chooses the
        // count itself (doc/mpfr.texi:1923-1925) and performs its own base
        // normalisation and validation. Substituting a count here would skip
        // that and would accept a base MPFR rejects for the count but not for
        // the digits.
        var exponent: Exponent = 0;
        const buffer = c.mpfr_get_str(null, &exponent, base, digits, self.rawConst(), rnd(mode));
        if (cIsNull(buffer)) {
            if (!isValidBase(base)) return error.InvalidBase;
            @panic("mpfr: mpfr_get_str returned null for a valid base");
        }
        // `mpfr_get_str` returns a NUL-terminated block, so the buffer is the
        // span up to that terminator; a bare `@ptrCast` cannot infer a length.
        return .{ .buffer = std.mem.span(buffer), .exponent = exponent };
    }
};

/// What `Float.parsePrefix` consumed and what it produced.
pub const Prefix = struct {
    /// Bytes of the input that formed a valid number.
    consumed: usize,
    /// The ternary value of the conversion, named after upstream's own term.
    ternary: Ternary,
};

/// Whether `base` is one `mpfr_get_str` accepts: `2..62`, or `-36..-2` for
/// upper-case digits (doc/mpfr.texi:1888-1898, src/get_str.c:2611-2613).
/// Base `0` is not among them.
pub fn isValidBase(base: c_int) bool {
    return (base >= 2 and base <= 62) or (base >= -36 and base <= -2);
}

/// Translate a rounding mode into the C representation.
///
/// Zig 0.16's `translate-c` represents a C enum as its underlying integer type
/// (the `enum_FOO` example in the 0.16 language reference), so this is a
/// checked narrowing cast rather than an `@enumFromInt`.
inline fn rnd(rounding: RoundingMode) mpfr.mpfr_rnd_t {
    return @intCast(@intFromEnum(rounding));
}

fn orderOf(value: c_int) Order {
    return if (value > 0) .gt else if (value < 0) .lt else .eq;
}

fn signBitOf(value: *const Float) c_int {
    return value.inner[0]._mpfr_sign;
}

/// Whether a translated C pointer is the null pointer.
///
/// Zig 0.16's `translate-c` gives `T *` an optional single-pointer type only
/// when the child is a function prototype or was demoted to opaque
/// (lib/compiler/translate-c/Translator.zig:1215-1237); every other pointer
/// becomes the non-optional `[*c]T`. `mpfr_get_str` returns `char *`, so the
/// translated return type is `[*c]u8`, which cannot be unwrapped with `orelse`
/// and cannot be compared with `null`. Comparing the address is the same test,
/// and it is what `src/get_str.c:2489` compares against when it rejects a base
/// or a digit count.
fn cIsNull(ptr: [*c]u8) bool {
    return @intFromPtr(ptr) == 0;
}

// ---- library state ---------------------------------------------------

/// The MPFR version string of the linked library, e.g. `"4.2.2"`.
/// This is `mpfr_get_version`, a real function (src/mpfr.h:389).
///
/// The slice borrows storage the library owns for the life of the process and
/// is never freed; it is not a `Digits` and no allocator applies.
pub fn version() [:0]const u8 {
    return std.mem.span(c.mpfr_get_version());
}

/// The patches applied to the linked library, as recorded in the `PATCHES`
/// file the library was built from (src/Makefile.am:108-111). The `PATCHES`
/// file in this repository is empty at 4.2.2, so a library built from it
/// reports `""`; in `-Dsystem=mpfr` mode the string is whatever the installed
/// library recorded, which is why no caller may assume it is empty. As with
/// `version`, the slice borrows library storage and is never freed.
pub fn patches() [:0]const u8 {
    return std.mem.span(c.mpfr_get_patches());
}

/// The name of the threshold-tuning case this MPFR build selected, taken from
/// `MPFR_TUNE_CASE` in the generated `src/mparam.h` (src/mparam_h.in:26-85).
/// As with `version`, the slice borrows library storage and is never freed.
pub fn tuningCase() [:0]const u8 {
    return std.mem.span(c.mpfr_buildopt_tune_case());
}

/// The exception flags currently in effect. Whether they are the calling
/// thread's or the whole process's is the library's build, as the module
/// comment on the state the library owns records.
pub fn flags() Flags {
    return Flags.read();
}

/// Raise the flags set in `value` and leave the others alone.
pub fn setFlags(value: Flags) void {
    value.raise();
}

/// Lower the flags set in `value` and leave the others alone.
pub fn clearFlags(value: Flags) void {
    value.lower();
}

/// Clear every exception flag.
pub fn clearAllFlags() void {
    c.mpfr_clear_flags();
}

/// The default precision `mpfr_init` uses, 53 bits out of the box
/// (doc/mpfr.texi:1466). It changes only values not yet initialised, and no
/// `Float` method reads it.
pub fn defaultPrecision() Precision {
    return c.mpfr_get_default_prec();
}

/// Set the default precision `mpfr_init` uses. `precision` must lie between
/// `min_precision` and `max_precision` (doc/mpfr.texi:1456-1459); it changes
/// only values not yet initialised.
///
/// Prefer `Float.init`, which takes an explicit precision, because other
/// libraries can move this and need not restore it
/// (doc/mpfr.texi:1408-1409).
pub fn setDefaultPrecision(precision: Precision) void {
    c.mpfr_set_default_prec(precision);
}

/// The default rounding direction; `nearest_even` out of the box
/// (doc/mpfr.texi:3318). No `Float` method reads it.
/// Panics in every optimization mode if the library returns an unknown value.
pub fn defaultRoundingMode() RoundingMode {
    const value = c.mpfr_get_default_rounding_mode();
    return std.enums.fromInt(RoundingMode, value) orelse
        std.debug.panic("mpfr: invalid default rounding mode {d}", .{value});
}

/// Set the default rounding direction.
///
/// MPFR consults this only where a rounding direction is not passed explicitly.
/// Every operation on `Float` takes its direction as an argument, so changing
/// this never changes the result of a `Float` call. It is shared with other
/// threads under the same rule as the flags.
pub fn setDefaultRoundingMode(rounding: RoundingMode) void {
    c.mpfr_set_default_rounding_mode(rnd(rounding));
}

/// The smallest exponent `mpfr_set_emin` accepts, and the largest exponent
/// `mpfr_set_emax` accepts.
pub fn minimumExponent() Exponent {
    return c.mpfr_get_emin_min();
}

/// The largest exponent `mpfr_set_emin` accepts, and the smallest exponent
/// `mpfr_set_emax` accepts.
pub fn maximumNegativeExponent() Exponent {
    return c.mpfr_get_emin_max();
}

/// The smallest exponent `mpfr_set_emax` accepts.
pub fn minimumPositiveExponent() Exponent {
    return c.mpfr_get_emax_min();
}

/// The largest exponent `mpfr_set_emax` accepts.
pub fn maximumExponent() Exponent {
    return c.mpfr_get_emax_max();
}

/// The smallest allowed exponent currently in effect.
pub fn minimumExponentInUse() Exponent {
    return c.mpfr_get_emin();
}

/// Set the smallest allowed exponent. Returns `false` and leaves the range
/// untouched when `exponent` is out of range
/// (doc/mpfr.texi:3733-3755).
///
/// Neither setter checks that the smallest exponent stays at or below the
/// largest: with the range inverted, producing any output value is undefined
/// behaviour (doc/mpfr.texi:3751-3754), and the two calls can be interleaved
/// with other threads writing the same shared state.
pub fn setMinimumExponent(exponent: Exponent) bool {
    return c.mpfr_set_emin(exponent) == 0;
}

/// The largest allowed exponent currently in effect.
pub fn maximumExponentInUse() Exponent {
    return c.mpfr_get_emax();
}

/// Set the largest allowed exponent. Returns `false` and leaves the range
/// untouched when `exponent` is out of range, and see `setMinimumExponent` for
/// the inverted-range obligation.
pub fn setMaximumExponent(exponent: Exponent) bool {
    return c.mpfr_set_emax(exponent) == 0;
}

/// Release MPFR's cached constants for the calling thread, as that thread
/// reaches them; the caches are shared state in a build without thread-local
/// storage, so the module comment on the state the library owns applies here
/// too.
///
/// Upstream recommends this before a thread exits, and in every thread that
/// used MPFR before the GMP allocator is replaced (doc/mpfr.texi:1182-1226).
/// MPFR rebuilds what it needs afterwards, so no `Float` and no `Digits` has
/// to be released first.
pub fn freeCaches() void {
    c.mpfr_free_cache();
}

/// Release MPFR's memory in a way that stays correct if the GMP allocator is
/// later replaced. Prefer this over `freeCaches` for that purpose
/// (doc/mpfr.texi:1207-1226).
pub fn cleanupMemory() void {
    _ = c.mpfr_mp_memory_cleanup();
}
