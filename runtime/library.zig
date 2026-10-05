// SPDX-License-Identifier: LGPL-3.0-or-later
//
// Fork-authored. `FORK-LICENSE.md` records the owner's authorization of that
// grant and why it matches MPFR's own primary upstream terms.
//
//! MPFR's side of the runtime loader: the names its synchronization binding
//! has, and what it requires of a provider beyond resolving its symbols.
//!
//! Everything else about the runtime route is generic. `runtime/loader.zig` is
//! the state machine and the platform layer; `runtime/generate.zig` builds the
//! dispatch from whatever the translation step actually produced;
//! `runtime/graph.zig` wires them together. This file is what makes them MPFR's,
//! and it is the file another SDK replaces.
//!
//! ## What a provider must be
//!
//! Everything `fork/mpfr_all.h` declares, which is the public surface of two
//! libraries and not one:
//!
//!  * every MPFR entry point `src/mpfr.h` and `src/mpf2mpfr.h` declare, including
//!    the `intmax_t` family that `fork/mpfr_all.h` pins on
//!    (`MPFR_USE_INTMAX_T=1`), whose exported names are MPFR's own
//!    `__gmpfr_`-prefixed spellings (src/mpfr.h:1162-1179);
//!  * every GMP entry point and every GMP exported object `gmp.h` declares,
//!    because `src/mpfr.h:52` includes `<gmp.h>`. `mpz`, `mpq` and `mpf` are part
//!    of MPFR's own API - `mpfr_set_z`, `mpfr_get_z`, `mpfr_mul_z` and the rest
//!    take `mpz_srcptr`/`mpz_ptr` (src/mpfr.h:487-488, 527, 544) - and so are the
//!    three exported objects `__gmp_bits_per_limb`, `__gmp_errno` and
//!    `__gmp_version` (`vendor/gmp/gmp-h.in:489-497`).
//!
//! Those GMP symbols are reached **through** MPFR, not from the provider's own
//! export table, and that is a requirement on the provider rather than an
//! implementation detail of this loader. `dlsym`/`GetProcAddress` searches the
//! object it was given and that object's dependency closure, so a `libmpfr`
//! whose `DT_NEEDED` lists `libgmp` answers every GMP name. A provider that
//! absorbed GMP instead of depending on it - a single merged object, or a
//! `libmpfr` built against a static GMP - exports no `__gmpz_*` symbol and this
//! load is refused with `MissingSymbol` rather than half-used. That arrangement
//! is exactly what `configure.ac:635-662` forbids for a shared libmpfr on a
//! `*-mingw*` host, and what this fork's own `-Dlinkage` forwarding produces
//! everywhere else: one linkage selection drives both libraries, so a shared
//! libmpfr always has a shared libgmp behind it.
//!
//! The one thing a provider must *not* be asked for is a bundled fallback. In
//! this configuration nothing links libmpfr or libgmp, so a module that reaches
//! an MPFR symbol before `load` stops the program with a message naming the
//! function rather than quietly resolving it out of an archive this build
//! happens to have produced.
//!
//! ## The ABI boundary, stated exactly
//!
//! Resolving the symbols and translating the header is the boundary. What a
//! provider must additionally agree with is the following, and each item names
//! where the requirement comes from rather than asserting compatibility:
//!
//!  * **Limbs.** `__gmp_bits_per_limb` is GMP's exported `GMP_LIMB_BITS`
//!    (`vendor/gmp/mp_bpl.c:32`). It must equal `GMP_NUMB_BITS` from the
//!    translated header (`vendor/gmp/gmp-h.in:44-47`), which is the limb width
//!    *this* build's `gmp.h` was generated for. Every limb-count argument,
//!    every `mp_size_t` and every `__gmpfr_struct`'s meaning depends on it: a
//!    64-bit-limb provider against a 32-bit-limb header would misread
//!    `_mpfr_d` and the significand's limb count. This is the one check in
//!    `validate` that is a genuine ABI fact rather than a smoke signal, and it
//!    is also what makes the "same actual GMP closure" requirement checkable:
//!    the GMP that answered is the GMP the header describes.
//!
//!  * **Scalar widths.** `__GMP_MP_SIZE_T_INT` is defined only for CRAY
//!    targets (`vendor/gmp/gmp-h.in:169-178`), so on every platform this
//!    package targets `_MPFR_PREC_FORMAT` is 3 and `_MPFR_EXP_FORMAT` follows
//!    it (`src/mpfr.h:133-143`). `mpfr_prec_t` and `mpfr_exp_t` are
//!    therefore `long`, and `mpfr_uprec_t` and `mpfr_uexp_t` are
//!    `unsigned long` (`src/mpfr.h:159-212`). `mpfr_sign_t` is `int` in every
//!    case (`src/mpfr.h:180`), and `mpfr_rnd_t` is an `int`-sized enumeration
//!    whose values are fixed at
//!    `0=RNDN, 1=RNDZ, 2=RNDU, 3=RNDD, 4=RNDA` (`src/mpfr.h:98-109`).
//!
//!    That width follows the target's `long` and not the limb width above; the
//!    two are independent, which is why the limb check above is stated on its
//!    own and this paragraph claims nothing about it.
//!
//!  * **Struct layout.** `__mpfr_struct` is exactly
//!    `{ mpfr_prec_t _mpfr_prec; mpfr_sign_t _mpfr_sign; mpfr_exp_t _mpfr_exp;
//!    mp_limb_t *_mpfr_d; }` (`src/mpfr.h:231-236`), and `mpfr_t` is one of
//!    those (`src/mpfr.h`). This facade mirrors four macros against those fields
//!    rather than calling the entry points behind them (`src/mpfr.h:893-896`,
//!    901-904, 906-907, 930), so the layout is part of its contract and not
//!    only of the raw route's.
//!
//!  * **Configuration.** `MPFR_WANT_FLOAT128` and `MPFR_WANT_DECIMAL_FLOATS`
//!    are not defined on either C command line, which is why
//!    `mpfr_set_float128`, `mpfr_get_float128`, `mpfr_set_decimal64`,
//!    `mpfr_set_decimal128`, `mpfr_get_decimal64` and `mpfr_get_decimal128` are
//!    absent from the translated header (`src/mpfr.h:470-486, 530-533`). A
//!    provider that answers `1` to `mpfr_buildopt_float128_p()` or
//!    `mpfr_buildopt_decimal_p()` was compiled with entry points this header
//!    does not describe, so its configuration is not the one the declarations
//!    were derived from and the load is refused.
//!
//!    `MPFR_USE_MINI_GMP` is likewise undefined, so the `mpf`- and `mpq`-taking
//!    entry points are declared (`src/mpfr.h:494-514`) and mini-gmp is not a
//!    candidate provider for any configuration of this package.
//!
//!  * **Allocator ownership.** MPFR allocates every significand and every
//!    rendered string through GMP's configured allocator - `mpfr_init2` through
//!    `mpfr_clear` (doc/mpfr.texi:1201-1210) and `mpfr_get_str` through
//!    `mpfr_free_str` (doc/mpfr.texi:1927-1954) - and `Float.deinit` and
//!    `Digits.deinit` in `root.zig` call exactly those two release entry points.
//!    In a runtime-loading build "the same allocator" means the one inside the
//!    loaded provider: the allocation went through the `__gmpfr_malloc` the
//!    provider resolved and it comes back through the same table, so no Zig
//!    allocator and no allocator in the executable is involved on either side.
//!    A value built before a load and released after a *different* load would
//!    not be, which is one more reason the loader refuses a second provider
//!    rather than closing the first.
//!
//!  * **Thread-local state.** This build does not define `MPFR_USE_THREAD_SAFE`,
//!    so the exception word, the exponent range, the default precision and the
//!    default rounding direction are one process-wide set of globals
//!    (`src/mpfr-impl.h:255-260, 323-325`). That is a behavioural difference
//!    from a thread-safe provider, not an ABI one - `__mpfr_struct`'s layout is
//!    unchanged - so it is documented rather than enforced, and
//!    `mpfr_buildopt_tls_p()` is deliberately not part of `validate`.
//!
//! Nothing here proves a provider is compatible, and this file does not pretend
//! to add such a proof. `validate` runs three checks and says what they are: the
//! limb width is compared against the header's, the float128 and decimal
//! configuration answers are compared against the header's silence, and two
//! string-returning entry points are asked to answer at all. A version string
//! alone proves that an entry point ran; it is not an ABI verdict, and the
//! limb-width comparison is there because that one is.

const rt = @import("rt");

/// The synchronization this loader calls, bound by exact name.
///
/// The names below are `runtime/sync.h` compiled with
/// `RT_SYNC_PREFIX=mpfr_rt`, which is what `runtime/graph.zig` passes. Two
/// spellings of that prefix have to agree: this file names the symbols and
/// graph.zig defines the macro. A build where they disagree does not link, and
/// that is the whole error report: there is no runtime path that could hide it.
///
/// The core in `runtime/loader.zig` never names a symbol of its own, which is
/// what lets this SDK and another one hold their own loader state in one
/// process without sharing any of it.
pub const Sync = struct {
    extern fn mpfr_rt_lock() void;
    extern fn mpfr_rt_unlock() void;
    extern fn mpfr_rt_wait() void;
    extern fn mpfr_rt_broadcast() void;
    // `unsigned long long`. Declared as u64, which is the same type in every
    // ABI this SDK targets: 64-bit on x86_64, aarch64, riscv64 and wasm32.
    extern fn mpfr_rt_thread_self() u64;

    pub fn lock() void {
        mpfr_rt_lock();
    }
    pub fn unlock() void {
        mpfr_rt_unlock();
    }
    pub fn wait() void {
        mpfr_rt_wait();
    }
    pub fn broadcast() void {
        mpfr_rt_broadcast();
    }
    pub fn threadSelf() u64 {
        return mpfr_rt_thread_self();
    }
};

/// The loader's configuration for this SDK, given the dispatch that owns the
/// table.
///
/// `dispatch` is the generated module, passed as a type by the dispatch itself
/// so that this file never has to import it. The direction is one-way on
/// purpose: the descriptor knows what the loader needs, the dispatch knows what
/// the header said, and neither imports the other.
pub fn Config(comptime dispatch: type) type {
    return struct {
        /// Named in the pre-load panic, so the message says which library was
        /// reached for before it was loaded.
        pub const library_name = "mpfr";

        /// The table the generated dispatch declares, and the symbols it needs
        /// to fill it. Both come from the translated header, not from this file:
        /// the MPFR entry points, the `__gmpfr_` intmax spellings and the GMP
        /// entry points and objects that `<gmp.h>` contributes are all in it
        /// because `src/mpfr.h:52` includes `<gmp.h>`.
        pub const table = dispatch.Table;
        pub const symbols = dispatch.symbols;
        pub const optional_symbols = dispatch.optional_symbols;

        /// The project's namespaced synchronization binding.
        pub const sync = Sync;

        pub fn tablePtr() *table {
            return dispatch.tablePtr();
        }

        pub fn ready() *rt.Ready {
            return &dispatch.ready;
        }

        pub fn assign(comptime index: usize, dst: *table, address: *const anyopaque) void {
            dispatch.assign(index, dst, address);
        }

        /// One resolved address into one optional table field, and the empty
        /// case beside it. Both index `optional_symbols`, not `symbols`.
        pub inline fn assignOptional(comptime index: usize, dst: *table, address: *const anyopaque) void {
            dispatch.assignOptional(index, dst, address);
        }

        pub inline fn assignMissing(comptime index: usize, dst: *table) void {
            dispatch.assignMissing(index, dst);
        }

        /// The checks, run after every symbol has resolved and before anything
        /// is published. A non-null answer becomes `ValidationFailed` and the
        /// candidate is closed, so none of these can leave a half-published
        /// table behind.
        ///
        /// They read the table directly rather than through the generated
        /// accessors, because an accessor's readiness check would fire here:
        /// the flag is still `loading` at this point by construction, since the
        /// loader publishes only after this returns null.
        pub fn validate(dst: *const table) ?[]const u8 {
            // The limb width the provider was built with, read out of the
            // object GMP itself exports. `GMP_NUMB_BITS` is
            // `GMP_LIMB_BITS - GMP_NAIL_BITS` from the translated gmp.h
            // (vendor/gmp/gmp-h.in:44-47), and `GMP_NAIL_BITS` is 0 in every
            // configuration this package builds.
            if (dst.__gmp_bits_per_limb.* != dispatch.GMP_NUMB_BITS) {
                return "this provider's GMP reports a different number of bits " ++
                    "per limb than the translated gmp.h describes, so mp_limb_t, " ++
                    "mp_size_t and __mpfr_struct do not mean the same thing on " ++
                    "both sides";
            }

            // The configuration switches this build keeps off, which is why the
            // header declares none of the float128 or decimal entry points
            // (src/mpfr.h:470-486, 530-533).
            if (dst.mpfr_buildopt_float128_p() != 0) {
                return "this provider was built with MPFR_WANT_FLOAT128, so it " ++
                    "declares float128 entry points the translated header does not";
            }
            if (dst.mpfr_buildopt_decimal_p() != 0) {
                return "this provider was built with MPFR_WANT_DECIMAL_FLOATS, " ++
                    "so it declares decimal entry points the translated header " ++
                    "does not";
            }

            // Two entry points asked to answer, which shows they were resolved
            // to something callable. `mpfr_get_version` and
            // `mpfr_buildopt_tune_case` both return `const char *`
            // (src/mpfr.h:389, 397-398) and both are declared
            // `MPFR_RETURNS_NONNULL`, so the first byte is the test: an empty
            // string starts with the terminator. Neither string is inspected
            // beyond that, and neither is taken as evidence about the ABI; the
            // limb-width comparison above is the check that is.
            if (dst.mpfr_get_version()[0] == 0) {
                return "mpfr_get_version() answered with an empty string, so this " ++
                    "provider is not the library this header describes";
            }
            if (dst.mpfr_buildopt_tune_case()[0] == 0) {
                return "mpfr_buildopt_tune_case() answered with an empty string, " ++
                    "which no MPFR_TUNE_CASE can be (src/mparam_h.in:26-85)";
            }

            return null;
        }
    };
}