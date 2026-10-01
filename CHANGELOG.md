# Changelog: fork-only divergences from GNU MPFR 4.2.2

Upstream's own release history is in `NEWS` and `ChangeLog`; those files are
unmodified. This file records only what this fork changes relative to upstream tag
`4.2.2` (commit `eaa57b856d814af32f97d5e5eb129fb986235323`).

Numbering is fork-local. Nothing here is numbered after an upstream release.

## 1. Zig 0.16 build and package

- Added `build.zig` and `build.zig.zon`. The package publishes the module `mpfr`,
  the artifact `mpfr`, and the translated C module `c`.
- libmpfr is compiled from `src/` by Zig. `configure`, `autoreconf`, `make` and
  CMake are never invoked, nothing is downloaded at build time, and no installed
  MPFR is used by default.
- The C source list is read from `libmpfr_la_SOURCES` and `BUILT_SOURCES` in
  `src/Makefile.am` at configure time, so it cannot silently drift from upstream.
  A missing assignment is a hard error rather than a shorter library. The two
  lists are taken from different places, as upstream takes them: units named by
  `libmpfr_la_SOURCES` live in `src/`, and units named by `BUILT_SOURCES` are
  compiled out of the generated directory, because upstream builds them there
  too (`nodist_libmpfr_la_SOURCES = $(BUILT_SOURCES)`).
- Two inputs that autotools generates are now deterministic build steps, both
  emitted into one generated directory: `mparam.h`, copied verbatim from
  `src/mparam_h.in`, and `get_patches.c`, produced by a Zig reproduction of
  `tools/get_patches.sh`.
- Every libmpfr unit is compiled with `HAVE_STDINT_H` defined, which is the
  configure fact `src/mpfr-intmax.h:60-68` tests and turns into `<stdint.h>`
  plus `MPFR_USE_INTMAX_T`. The library therefore really exports the
  `intmax_t` entry points that `fork/mpfr_all.h` declares to the translation.
- `vendor/gmp` is resolved against the package's own build root rather than the
  working directory of whatever invoked the build, so a dependent that runs
  `zig build` from its own directory does not report a present snapshot as
  missing.
- System-library modes exist for both MPFR and GMP through
  `b.systemIntegrationOption`. In MPFR's system mode the in-tree `src/` is
  deliberately kept off the translation's include path, and so is the vendored
  GMP include tree, so the installed header is what gets translated and it is
  the installed library that is linked.

## 2. Zig facade

API notes for a consumer:

- `Prefix`, returned by `Float.parsePrefix`, names its outcome field
  `ternary`, not `inexact`, so it reads the way upstream calls the same thing.
  The rename was made before any release; there is no alias.
- `Flags` gives each of its six bool fields a `= false` default, so
  `Flags.none = .{}` and partial literals such as `.{ .inexact = true }` are
  valid. Its packed backing integer is an explicit `u6`, the six bits
  `MPFR_FLAGS_UNDERFLOW` through `MPFR_FLAGS_DIVBY0` occupy; `Flags.toRaw`
  widens to upstream's `mpfr_flags_t` through the `MPFR_FLAGS_*` constants
  rather than exposing a wider backing.
- `Float.toDigits` passes a `digits` count of 0 straight through to
  `mpfr_get_str`, so MPFR performs its own digit-count choice, base
  normalisation and validation.
- `Float.parseWhole` requires the whole string to be a valid number and
  returns `error.InvalidNumber` for any trailing character, leaving `self`
  unspecified; `parsePrefix` is the way to read a leading number.

- Added `root.zig` as the `mpfr` module root. It is a thin owned wrapper:
  `Float` over one upstream `mpfr_t`, `Digits` over `mpfr_get_str`'s
  GMP-allocated buffer, `RoundingMode`, `Ternary`, `Flags`, `Precision`,
  `Exponent` and a set of library-state helpers. No MPFR algorithm is
  reimplemented.
- `pub const c = @import("c")` exposes the complete translated public C API as
  the raw escape hatch, including the `__gmpfr_`-prefixed names that MPFR's own
  macros impose on the `intmax_t` entry points.

## 3. Tests, example, consumer

- Added `fork/tests/`, a behaviour suite covering directed rounding, precision,
  arithmetic, NaN and infinity, text rendering and parsing, overflow and
  underflow, and lifetime and ownership. Every expected value is an independent
  known answer with its provenance stated in the test.
- Added `fork/example/main.zig`, a deterministic demonstration reachable through
  `zig build smoke` and `zig build run`.
- `fork/tests/surface.zig` calls every public facade method and every
  module-level function on real values, with a real assertion beside each call.
  `zig build check` compiles it, which is what makes `check` analyse the whole
  public surface rather than just build an unreferenced C archive.
  `std.testing.refAllDecls` alone would not do that, because it names a
  declaration without instantiating its body.
- Added `consumer/`, a separate package that depends on `..` and exercises the
  published module through `b.dependency("mpfr", ...).module("mpfr")`. It has
  `zig build run`. It calls the `__gmpfr_`-prefixed `intmax_t` entry points
  directly and reads the value back through the facade, which is what makes the
  `MPFR_USE_INTMAX_T` compile-line pin observable: with those symbols missing
  from the library, that link is what fails.
- Added `zig build check`, which compiles the facade and the example without
  running either, and `zig build matrix`, which repeats that for the six
  required targets.

## 4. Documentation

- Added `UPSTREAM.md`, `NOTICE.md`, `FORK-NOTES.md`, `README.zig.md` and this
  file. Upstream's `README` is untouched.
- Added a fork-owned CI workflow under `.github/workflows/`. It targets this
  repository's own Actions runner; no upstream CI configuration is copied,
  because upstream has none that this fork could inherit. The provenance job
  compares every upstream-tracked path byte-for-byte against the pinned commit,
  so it does not also grep `src/mpfr.h` or `src/version.c` for the version
  string: a text match would only restate that gate in a form an upstream
  reformat could break.

## 5. One additive change to an upstream file

- `.gitignore` gains `/.zig-cache/` and `/zig-out/` under a marked comment, so an
  ordinary user build cannot contaminate a downstream source commit. Upstream's
  37 existing entries are kept byte-for-byte and nothing is removed. This is the
  only upstream file the fork touches. See `FORK-NOTES.md` entry 11.

  Separately, `build.zig.zon`'s `.paths` allowlist names only the build files,
  `fork/`, `consumer/` and upstream's own files, so neither directory is part of
  the package even before the ignores apply.

## 6. `parseWhole` returned a rounding direction it never had

- `Float.parseWhole` returned `ConversionError!Ternary` and answered `.exact` on
  every success, with a doc comment claiming that "the text named a value and
  nothing was rounded away". `mpfr_set_str` returns 0 or -1
  (`doc/mpfr.texi:1603-1607`, `src/set_str.c:24-33`); it has no ternary channel.
  The claim was false, and a literal this precision cannot hold parses
  successfully and is silently rounded. It now returns
  `ConversionError!void`, and a caller that needs to know whether the text was
  represented exactly asks `parsePrefix` and reads the ternary MPFR really
  returned.
- `ConversionError.InvalidNumber` documents each entry point separately: what
  `mpfr_set_str` refuses and what it leaves behind, against `mpfr_strtofr`'s
  end pointer.
- The consumer and the example now check exactness from that real ternary, and
  the consumer's fraction helper computes in the value it returns instead of
  returning an initialised result it never wrote to.
- Several provenance comments were wrong and are corrected: the 24-bit rendering
  of 1/7 is the correctly rounded 24-bit form of `153391689/2^30`, not the
  literal's own expansion, and the base-2 literal `0.001001...` (ten groups of
  `001`) is `153391689/2^30`, which needs 28 significant bits and is therefore
  inexact at 24.
- `Float.init`, `Float.resetPrecision` and `Float.roundToPrecision` took a
  parameter named `precision`, which Zig forbids inside a struct that also
  declares `Float.precision()`. `Float.parsePrefix` and `Float.toDigits` held
  locals named `raw` for the same reason. All five are renamed; no public name
  and no signature type changed.

No build has been run against these edits: MPFR has never seen this compiler,
because `vendor/gmp` does not exist yet.

## Not changed

- No file under `src/`, `doc/`, `tests/`, `tools/`, `tune/`, `m4/`, `other/` or
  `examples/` is modified. The only upstream file touched is `.gitignore`, and
  only additively; see section 5.
- `COPYING`, `COPYING.LESSER`, `README`, `INSTALL`, `NEWS`, `ChangeLog`, `TODO`,
  `BUGS`, `AUTHORS`, `VERSION` and `PATCHES` are byte-identical to upstream.
- `MPFR_USE_MINI_GMP` is never defined. mini-gmp is explicitly rejected by the
  shared fork contract and is not a substitute for GMP.

## 7. The vendored GMP snapshot, and three build-script defects

`mpfr/vendor/gmp` is now populated with this workspace's verified GMP package,
copied on 2026-10-01 after that package's own gates had been observed.
`diff -rq --exclude=.zig-cache --exclude=zig-out --exclude=.git gmp
mpfr/vendor/gmp` reports no difference. `UPSTREAM.md` records the archive
identity, the digest, the four `COPYING*` files the snapshot carries and that
command. There is still no `../gmp` path, no archive URL and no installed host
GMP in the default route.

Three build-script defects stood between that snapshot and a compiling
libmpfr, and all three are Zig 0.16 shape errors rather than design changes:

* `getPatchesSource` concatenated the runtime `PATCHES` content with `++`,
  which is comptime-only. It now formats, and escapes the C braces in the
  emitted unit as `{{` and `}}` so they are not read as format placeholders.
* `assignmentWords` built its Automake key with `++` for the same reason. It
  formats now.
* Its panic message had the same concatenation. It formats now.

`std.mem.trimRight` does not exist in 0.16; the backslash-continuation check
uses `std.mem.trimEnd`.

## 8. Five of six cross targets compile; wasm32-wasi inherits GMP's boundary

Observed with Zig 0.16.0: `zig build check matrix` compiles the library, the
facade, the behaviour suite and the example for `x86_64-linux-gnu`,
`aarch64-linux-gnu`, `aarch64-macos-none`, `x86_64-windows-gnu` and
`riscv64-linux-gnu`. `wasm32-wasi` fails for exactly the reason GMP's own cross
gate does: the vendored `vendor/gmp/invalid.c:80` raises `SIGFPE` and wasi-libc
has no signal support, so `signal.h` refuses to be included.

That boundary belongs to the provider, not to this package, and nothing here
invents a substitute for `raise`. The target stays in the matrix, the attempt
stays visible, and CI marks that one target `continue-on-error`. `-Dsystem=gmp`
is the documented way to build against an installed GMP, and it is always
explicit.

`zig build run` in `consumer/` passes, including the `__gmpfr_`-prefixed
`intmax_t` entry points, which is what makes the `MPFR_USE_INTMAX_T` pin
observable through a real dependent package rather than a declaration nothing
references.
