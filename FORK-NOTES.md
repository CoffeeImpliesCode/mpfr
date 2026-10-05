# Fork notes: issues met while preparing this fork

Every entry below is something actually met while reading, importing and
designing against the pinned sources. Nothing here is a compiler or gate
result: this fork was prepared without running any build, test, lint or
formatter, and the verification status of each entry says so.

Format: symptom and source evidence, cause, chosen fix or constraint, affected
platform/ABI/version, reusable rule, verification status.

---

## 1. Most of the MPFR API a caller uses is a preprocessor macro, not a function

**Evidence.** `src/mpfr.h:893-896` defines `mpfr_nan_p`, `mpfr_inf_p`,
`mpfr_zero_p` and `mpfr_regular_p` as comparisons on the struct's `_mpfr_exp`
field. `src/mpfr.h:901-904` defines `mpfr_sgn` the same way and calls
`mpfr_set_erangeflag()` for a NaN. `src/mpfr.h:906-907` define `mpfr_get_prec`
and `mpfr_get_exp`. `src/mpfr.h:913-916` define `mpfr_round`, `mpfr_trunc`,
`mpfr_ceil` and `mpfr_floor`. `src/mpfr.h:918-919` and `921-933` define
`mpfr_cmp_ui`, `mpfr_cmp_si`, `mpfr_set`, `mpfr_abs`, `mpfr_copysign`,
`mpfr_setsign`, `mpfr_signbit`, `mpfr_cmp`, `mpfr_mul_2exp` and `mpfr_div_2exp`.
Worse, `src/mpfr.h:964-1021` redefine `mpfr_cmp_ui`, `mpfr_cmp_si`, `mpfr_set_ui`,
`mpfr_set_si`, `mpfr_mul_ui`, `mpfr_div_ui`, `mpfr_mul_si` and `mpfr_div_si`
with GCC statement expressions and `__builtin_constant_p` tests, and
`src/mpfr.h:921-925` makes `mpfr_set` a statement expression too.

**Cause.** MPFR predates widespread use of `static inline` in its public header,
so the hot macros are written as preprocessor macros over the public struct.

**Constraint taken.** The facade never calls a macro spelling. It calls the
underlying real entry points — `mpfr_set4`, `mpfr_cmp3`, `mpfr_set_ui_2exp`,
`mpfr_set_si_2exp`, `mpfr_cmp_ui_2exp`, `mpfr_cmp_si_2exp`, `mpfr_mul_2ui`,
`mpfr_div_2ui`, `mpfr_rint`, the real `mpfr_number_p` and `mpfr_integer_p` — and
for the four predicates with no non-macro equivalent it mirrors the macro bodies
against the fields that `src/mpfr.h:230-236` documents as the public
representation. Every such method cites the upstream line it mirrors.

**Affected.** All targets. Any MPFR version that moves or renames those macros.

**Reusable rule.** When translating a mature C library to another language, diff
the header's `#define` list before writing any binding. A library whose "API" is
mostly macros will not survive a naive translation, and the macros that matter
most are the ones with no faithful equivalent in the target language.

**Verification status.** Not run. The choice is a source-level reading of
`src/mpfr.h`, not a gate result.

---

## 2. The `intmax_t` entry points are declared only if `intmax_t` is already visible

**Evidence.** `src/mpfr.h:1136-1154` guards the `mpfr_set_sj`, `mpfr_set_uj`,
`mpfr_get_sj`, `mpfr_get_uj`, `mpfr_pow_sj` and `mpfr_pow_uj` declarations on
`INTMAX_C`/`UINTMAX_C` being visible, on `MPFR_USE_INTMAX_T` being defined, or on
one of `_STDINT_H`, `_STDINT_H_`, `_STDINT`, `_SYS_STDINT_H_` — the last four
being glibc, macOS, MSVC and FreeBSD specific probes. `src/mpfr.h:194-208` notes
that `mpfr.h` never includes `<stdint.h>` itself.

**Cause.** Those probes were written to guess whether the including program had
already pulled in `<stdint.h>`, and they do not answer the same question on every
libc.

**Constraint taken.** The same decision has to be forced on *both* sides, and
forcing it on one side only is the worse half of the fix.

*Translation.* `fork/mpfr_all.h` includes `<stdint.h>` first and then defines
`MPFR_USE_INTMAX_T 1` before including `<mpfr.h>`, so the set of declared
functions is the same everywhere. `x86_64-windows-gnu` is where this matters
most: MinGW-w64 headers do not reliably define `_STDINT`, and it is also the only
target in the matrix with a 32-bit `long`.

*Compilation.* The library only defines `__gmpfr_set_sj` and its siblings in the
units that reach `src/mpfr-intmax.h`, and it reaches it only when
`MPFR_NEED_INTMAX_H` is defined; `src/mpfr-intmax.h:60-68` then includes
`<stdint.h>` and defines `MPFR_USE_INTMAX_T` only under `HAVE_INTTYPES_H` or
`HAVE_STDINT_H`, which normally come from a `configure`-generated `config.h`.
With neither defined, `src/mpfr.h:1151-1154` falls back to the guard probes,
which no POSIX libc satisfies from the `<stdio.h>`, `<stdlib.h>` and
`<limits.h>` that `src/mpfr-impl.h:44-56` includes. So `build.zig` passes
`-DHAVE_STDINT_H=1` on every libmpfr compile line: that is the single
configure-time fact the block tests, and it is the only use of
`HAVE_STDINT_H` in the tree. ISO C99 requires `<stdint.h>` of every target in
the matrix, all of which are hosted implementations.

**Why pinning the translation alone is worse than pinning nothing.** The
translated declarations are what a Zig caller compiles against, and nothing in
`root.zig` references those entry points, so the mismatch would not fail the
suite. It would surface later, as an undefined symbol in a dependent that does
use `c.__gmpfr_set_sj`, against a library built without them. That is the
header/ABI identity hazard `AGENTS.md` section 3 describes, reached from the
other direction.

**Related.** The same block renames the symbols: `src/mpfr.h:1162-1169` map
`mpfr_set_sj` to `__gmpfr_set_sj` and so on with object-like macros, so the
translated Zig names carry the `__gmpfr_` prefix. The facade therefore does not
use them, and `root.zig` documents the rename on `pub const c`.

**FILE surface correction.** The private aggregate now includes `<stdio.h>`
before MPFR/GMP headers (`src/mpfr.h:1195-1215`). Runtime generation routes
every `mpfr_`/`__gmp` extern and keeps the target-libc externs direct; the public
headers' actual-symbol inventory confirms both prefixes cover every provider
symbol. No library export is optional and no native header changed.

**Bounded driver observation — 2026-10-04.** The real stdio/variadic probe
passed 16/16 `x86_64-linux-gnu` cells: linked/loaded × static/dynamic delivery
× Debug/ReleaseSafe/ReleaseFast/ReleaseSmall. Real libc `FILE *` streams and
stdout each received exactly `4.20e+01\n` (nine bytes) from raw
`__gmpfr_fprintf`, with a `c_int` precision argument and an `mpfr_srcptr`.
Passing `null` to that tested entry point terminated by native signal, not a
typed checked error. A separate Debug linked-static `mpfr_out_str` probe
subsequently compiled (26/26 steps) and emitted exactly
`4.200000000000000000000000000000000000000e1` to stdout, exit 0.
The same entry point with a null stream compiled but exited 134 in native
`out_str.c:68` (`fputc`), with no stdout normalization. These two observations
are separate from the 16-cell `__gmpfr_fprintf` proof, not all-mode
`mpfr_out_str` coverage.
All loaded cells used one existing Debug-dynamic `libmpfr.so.6.2.2` provider
with sibling `libgmp.so.10` and `$ORIGIN` RUNPATH, not a fresh provider per mode
or an independent external-ABI certification. Exact commands, per-row exits,
signals and provider closure:
`/home/tmp2/gertullj/scratch/foundation-libs/mpfr-stdio-proof/out/20261004T224515Z-69013/report.json`.

**Reusable rule.** A binding must make the target's feature-macro state explicit
rather than inheriting whatever the host toolchain happened to define.

**Original intmax preparation status.** Not run at that stage; the later stdio
observation above is a separate, bounded result.

---

## 3. Two build inputs are generated by autotools and do not exist in the tree

**Evidence.** `configure.ac:894` lists `src/mparam.h:src/mparam_h.in` in
`AC_CONFIG_FILES`, and `src/Makefile.am` lists `BUILT_SOURCES = get_patches.c
mparam.h` with `nodist_libmpfr_la_SOURCES = $(BUILT_SOURCES)`. Neither generated
file is in the Git tree, and `tools/get_patches.sh` is a shell script.

**Cause.** MPFR's release tarballs are built by autotools; the Git tree
deliberately does not carry generated files.

**Constraint taken.** `build.zig` produces both as deterministic build steps: a
verbatim copy of `src/mparam_h.in` to `mparam.h`, and a Zig reproduction of
`tools/get_patches.sh` to `get_patches.c`. No shell, no autotools.

**Where they are compiled from.** Not from `src/`. `nodist_libmpfr_la_SOURCES =
$(BUILT_SOURCES)` is upstream saying these units are built outside the source
tree, so `build.zig` resolves them against the `addWriteFiles` directory that
emits them. Joining them onto the `src/` list instead would name files that do
not exist, and would hide the mistake for as long as no compiler looked: both
names end in `.c` and both directories are on the include path, so the failure
mode is "nothing here" rather than "cannot open".

**Worth recording.** `src/mparam_h.in` contains **zero** `@` characters, so the
`AC_CONFIG_FILES` entry substitutes nothing and a copy is byte-identical to what
configure would write. That is a fact about 4.2.2's template, not a general
property, so `UPSTREAM.md` lists it as a rebase checkpoint.

**Reusable rule.** Before porting a build, diff what the build generates against
what the generator actually substitutes. A generated header can be a rename in
disguise.

**Verification status.** Not run.

---

## 4. The generated `mparam.h` includes architecture thresholds by bare name

**Evidence.** `src/mparam_h.in:26-85` does `#include "generic/coverage/mparam.h"`,
`#include "x86_64/core2/mparam.h"`, `#include "amd/mparam.h"` and so on, chosen by
`__x86_64__`, `__tune_core2__`, `__amd64__`, `__PPC64__`, `__sparc_v9__`,
`__mips__`, `__arm__` and friends.

**Cause.** The generated file lands in the build directory, not in `src/`, so its
quoted includes cannot resolve against its own directory.

**Constraint taken.** The C module gets `-I src` in addition to the generated
directory. Omitting it compiles only on targets whose thresholds happen to be in
the `default` case, that is, only where `MPFR_TUNE_CASE` is `"default"`.

**Related, same mechanism.** `src/mpfr-impl.h:1425` does `#include "mparam.h"`,
so the generated directory itself must be on the include path too.

**Affected.** Every target, but it fails silently-ish: the build still links, with
generic thresholds.

**Reusable rule.** A generated header that includes sibling files by bare name
forces its source directory onto the include path, not just the generated one.

**Verification status.** Not run.

---

## 5. A C library's installed headers reach a dependent module automatically in Zig 0.16

**Evidence.** `std/Build/Step/Compile.zig:520-556` documents that
`installHeader` marks a header as travelling with the artifact, and
`std/Build/Module.zig` turns a linked artifact's include tree into
`-I <emitted tree>` via `Module.IncludeDir.other_step`.

**Use here.** GMP's generated `gmp.h` is what `src/mpfr.h:52` includes, and it is
not in this repository. Marking it on the GMP artifact means
`module.linkLibrary(gmp_artifact)` is enough to make the whole of libmpfr compile,
and `mpfr_lib.installHeader(b.path("src/mpfr.h"), "mpfr.h")` is enough to make
`dep.module("mpfr")` usable downstream with no further configuration.

**Consumer recipe correction.** Importing `dep.module("mpfr")` already carries
the linked MPFR/GMP closure. `README.zig.md` no longer links the artifact again:
runtime imports must stay unlinked, and system MPFR exports no bundled artifact.
Only a separate C source in a bundled, linked build should link the artifact
for its installed header tree. `SOURCE-CONFIRMED`; execution pending.

**Reusable rule.** In Zig 0.16, ship a C dependency's generated headers by marking
them on the artifact, not by telling consumers where to look.

**Verification status.** Not run.

---

## 6. `b.addModule` is keyed by name, so a target matrix must not publish per-target modules

**Evidence.** `std.Build.addModule` registers into a name-keyed map; calling it
once per cross target means the last call wins, and a dependent's
`dep.module("mpfr")` would resolve to the matrix's last target rather than the
one the consumer asked for.

**Constraint taken.** `build.zig` publishes exactly one `mpfr` module, for the
target from `b.standardTargetOptions`, and the `matrix` step builds private
modules with `b.createModule` for each of the six required targets.

**Reusable rule.** One published module per package; loop with private modules for
any target matrix.

**Verification status.** Not run.

---

## 7. The exponent range is process-wide per thread, not per value

**Evidence.** `doc/mpfr.texi:3733-3755`: `mpfr_set_emin` and `mpfr_set_emax` set a
range for the calling thread, and using a value outside the current range as an
input is explicitly undefined. `src/mpfr-impl.h:1748-1749` shows the defaults
coming from the thread-local globals.

**Constraint taken.** `root.zig` exposes the range through
`minimumExponentInUse`, `setMinimumExponent`, `maximumExponentInUse` and
`setMaximumExponent`, the setters returning `false` when the request is out of
range rather than silently clamping. The range tests save and restore both
endpoints so one test cannot leak a range into the next, following
`tests/tests.c:684-705`, which does the same and aborts on failure.

**Reusable rule.** A test that mutates global numeric state must restore it with a
`defer`, and should follow the upstream suite's own pattern for doing so.

**Verification status.** Not run.

---

## 8. `zig build` matrix coverage needs a separate step from `check`

**Constraint taken.** `check` compiles the test binary and the example for the
standard target without running either, so it can be used for a target whose
binaries cannot execute here. `matrix` repeats that for the six required targets.
`check` and `matrix` never execute a target binary, so a green matrix is a
compile result and nothing more.

**Verification status.** Not run.

---

## 9. Design constraint carried in from the driver: system mode must use the real system headers

**Constraint.** With `-Dsystem=mpfr`, `src/` is deliberately not added to the
translation's include path, so `<mpfr.h>` resolves to the installed header and the
translated declarations describe the library that is actually linked. Translating
the bundled 4.2.2 header while linking an older installed library would produce a
silent ABI mismatch. No fork-only shim symbol is expected from an installed MPFR
and none is used.

**How it is made checkable.** `fork/tests/lifetime_test.zig` compares the
translated `c.MPFR_VERSION_STRING` against the linked `mpfr_get_version()`, so a
header and library that disagree fail the suite. That is a header-versus-library
identity check, not a release pin: which release is pinned belongs to the
provenance job in `.github/workflows/verify.yml`, and `zig build smoke` prints
it.

**Verification status.** Not run. No mismatch has been observed; this is a design
constraint, not a found bug.

---

## 10. `refAllDecls` does not prove a facade was instantiated

**Constraint taken.** Zig analyses a function body only when that body is
reached, and `std.testing.refAllDecls` merely names a declaration. So
`fork/tests/all_tests.zig` does not rely on it: `fork/tests/surface.zig` is part
of the same test compilation and *calls* every public facade method and every
module-level function on real values, with a real assertion beside each call.
`zig build check` compiles that file, so a missing rename, a changed signature or
a method nothing exercises is a compile error rather than a silent pass. The
file header says so explicitly, so a later reader does not mistake the
`refAllDecls` call for the guarantee.

**Verification status.** Not run.

---

## 11. Packaging requirement: Zig build output must not reach a downstream commit

**Requirement.** `.zig-cache/` and `zig-out/` are created at the repository root
by any normal `zig build`, so they must be ignored by Git and must be absent from
the package path allowlist, or an ordinary user build would show up as a change
to a downstream source commit.

**How it is met.** Entries are appended to upstream's `.gitignore` under marked
comments. Upstream's 37 existing lines are kept byte-for-byte; nothing is
removed, and MPFR's list is an autotools artefact list that a Zig build never
produces, so it stays as the upstream convention it is. A root-level ignore file
is the only one Git reads there, and a local exclude would not travel with the
repository, so appending is the mechanism. `zig-out` is confirmed as the install
directory by `lib/std/Build.zig:733`; no separate `zig-pkg` entry is added, since
the toolchain shipped here does not document one.

Two further blocks were appended later, for the same reason and with the same
marking: `/result`, which `nix build` leaves as a symlink at the repository root,
and `/.devenv*` and `/.direnv*`, which the development environment creates beside
it. None of the five is in `.paths` either. The carried file is 19 lines longer
than upstream's 37, and `UPSTREAM-BASELINE.sha256` records its digest as well as
upstream's.

**Separately**, `build.zig.zon`'s `.paths` is an explicit allowlist that names
only the build files, `fork/`, `consumer/` and upstream's own files. Neither
directory appears there, so a user build cannot change the package hash even
before the ignores apply.

**Verification status.** The requirement holds, and it is checked rather than
assumed: `UPSTREAM-BASELINE.sha256` records `.gitignore` as the one divergence
from the pinned commit, with both digests, and `check-upstream-baseline.sh` fails
if the carried file stops being exactly those 1371 bytes. Both `.zig-cache/` and
`zig-out/` exist in this tree because builds have been run in it; neither is
tracked, and neither is in `build.zig.zon`'s `.paths`.

---

## 12. `mpfr_fits_*_p` decides after rounding, not by integrality

**Symptom, found while checking the facade's own tests.** A test in
`fork/tests/arithmetic_test.zig` asserted that 3.75 "fits neither integer
domain", because it has a fractional part. That expectation is false.

**Cause.** The name reads as a question about integrality. `doc/mpfr.texi:
1964-1969` says the question is "would `op` fit in the respective C data type
... **when rounded to an integer in the direction `rnd`**", and `src/fits_s.h:
42-48` spells the same rule out as `MINIMUM <= round(f, prec(long), rnd) <=
MAXIMUM`. The manual's own example is a fractional one: with `MPFR_RNDU` on
`-0.5` every one of these functions is non-zero.

**Fix.** The assertion is derived from the rule rather than from the name:
3.75 rounds to 3 toward zero, so it fits both `long` and `unsigned long`; and
the manual's `-0.5` case is now the boundary case of the suite, because it is
the one upstream picked. `src/fits_u.h:39-43` explains why the unsigned family
still says no for `-0.5` rounded toward negative infinity.

**Affected.** Every target. Any binding that exposes `mpfr_fits_*_p` under a
name that suggests integrality.

**Reusable rule.** When a C predicate's name and its documentation disagree,
read the implementation before writing an expectation for it, and prefer the
documentation's own worked example as the fixture. A name like `fits` or `is`
is the place a wrong oracle hides longest.

**Verification status.** Not run. The rule is a source-level reading of
`doc/mpfr.texi` and `src/fits_s.h` / `src/fits_u.h`; no test has been executed.

---

## 13. A packed struct's backing integer must have exactly the fields' bit width

**Symptom.** `Flags` was declared `packed struct(Flags)`, naming itself as its
own backing type.

**Cause.** The obvious choice was `u32`, because `src/mpfr.h:73` types
`mpfr_flags_t` as `unsigned int`, which is 32 bits on every required target.
That does not compile. The 0.16 language reference states that a packed
struct's backing integer, when given explicitly, must have the same bit width
as the total of its fields, and shows the failure
`backing integer bit width does not match total bit width of fields`
(`doc/langref.html:4431-4434`). Six `bool` fields are six bits.

**Constraint taken.** The backing is `u6`. Nothing is lost by it being narrower
than the C type: `Flags.toRaw` and `Flags.fromRaw` go through the
`MPFR_FLAGS_*` constants (`src/mpfr.h:76-81`) rather than a bit cast, so no
assumption about the width of `unsigned int` survives into the translated API.

**Reusable rule.** Map a C flag word onto the exact set of bits the library
defines, and convert through the named constants. Reaching for the C width and
then "padding it out" is both a compile error and a chance to bake a layout
assumption into a public type.

**Verification status.** Not run. The rule is read out of the pinned language
reference; no compile has happened here.
## 14. A success code is not a rounding direction

**Evidence.** `Float.parseWhole` was declared `ConversionError!Ternary` and
answered `.exact` on every success. Its doc comment said so: "On success the
ternary value is exact, because the text named a value and nothing was rounded
away." `mpfr_set_str` returns `0` or `-1` (`doc/mpfr.texi:1603-1607`,
`src/set_str.c:24-33`). It has no ternary channel at all.

**Cause.** The wrapper answered a question the caller asked of the wrong
function. `mpfr_set_str` is a success/failure conversion; `mpfr_strtofr` is the
one that reports a ternary, and it reports it because it rounds.

**The claim was false, not merely unsupported.** The text does not have to name
a value the precision can hold. `0.001001001001001001001001001001` in base 2 is
the sum of `2^-3k` for `k` in 1..10, which is exactly `153391689/2^30`, and
`153391689` needs 28 significant bits. Parsing that literal into a 24-bit
`Float` succeeds and rounds, so an `.exact` answer asserted a property of the
fixture that never held.

**Fix.** `parseWhole` returns `ConversionError!void`. A caller that needs
exactness asks `parsePrefix` and reads the ternary MPFR actually returned, with
full consumption checked separately. The consumer and the example now do that,
and the tests that wanted a provably exact fixture use the same shape.

**Promise withdrawn.** `ConversionError.OutOfMemory` promised recovery that
GMP cannot provide: allocators must not return null and the default aborts
(`vendor/gmp/doc/gmp.texi:7487-7490`; `vendor/gmp/memory.c:53-58`).
`ConversionError` now names only `InvalidNumber` and `InvalidBase`; an
unexpected valid-base null result panics. `defaultRoundingMode` also panics
ordinarily for an unknown getter value without changing its return type.
The raw-setter corruption repro is refuted by `src/set_rnd.c:30-31`; the
unknown-getter and valid-base-null panic paths remain `SOURCE-CONFIRMED`
obligations, not manufactured failure observations.

**Bounded driver observations — 2026-10-04.** On `x86_64-linux-gnu`, native
rounding controls (valid modes `0..5`, invalid setter `99` rejected) and
digits controls (`42` in base 10; base 1 returns `InvalidBase`) built and ran
with exit 0 in Debug, ReleaseSafe, ReleaseFast and ReleaseSmall. The exhaustive
two-tag conversion taxonomy built and ran with exit 0 in Debug. Receipts:
`/home/tmp2/gertullj/scratch/foundation-libs/numerical-contract-probes/receipts/mpfr-valid-domain-controls/after/`,
then `mpfr-rounding-native/<mode>/receipt.json`,
`mpfr-digits-boundary/<mode>/receipt.json` and
`mpfr-conversion-taxonomy/Debug/receipt.json`. Each records the exact
`zig build -j8 --summary all -Dtarget=x86_64-linux-gnu -Doptimize=<mode>`
argv, probe selector, external caches/prefix, environment and executed binary.
These controls did not exercise either impossible-return panic or allocator
failure; the raw FILE/runtime closure gates are separate.

**Related.** `parseWhole` leaves `self` unspecified on failure, because
`mpfr_set_str` returns `-1` only after `mpfr_strtofr` has already run
(`src/set_str.c:31-32`); `parsePrefix` leaves a positive zero
(`src/strtofr.c:953-954`) when it consumed nothing. Those are different
post-conditions and `ConversionError.InvalidNumber` now documents both.

**Reusable rule.** Before giving a wrapper a richer result than the C function
returns, check that the function has a channel for it. When it does not, the
wrapper either drops the result or reaches for a different entry point; it must
not synthesize the answer, because a synthesized answer is indistinguishable from
a real one at every call site.

**Verification status.** Not run. MPFR has never seen this compiler: the build
panics on a missing `vendor/gmp` before any of this is compiled.

## 15. Every configure fact MPFR needs, derived from the target

**Evidence.** `libmpfr` reached its C compile and failed with 19 diagnostics in
three families, none of them a defect in the sources: `src/fpif.c:25-27`
`#error`s unless exactly one of `HAVE_BIG_ENDIAN` and `HAVE_LITTLE_ENDIAN` is
defined; `src/inits.c:26`, `src/inits2.c:27` and `src/clears.c:27` select
`<varargs.h>` when `HAVE_STDARG` is off, which costs six diagnostics each as
`va_alist`, `va_dcl`, `va_start` and `va_end` go missing and the K&R
definitions stop matching the prototypes in `src/mpfr.h`; and
`src/vasprintf.c:73-75` includes `<wchar.h>` only under `HAVE_WCHAR_H`, which
`WINT_MAX` at `:419` and `wint_t` at `:422` need. Six plus one plus one is
eighteen plus one plus one.

**Cause.** `configure` answers these by probing the build machine. A cross build
must answer them from the target instead, or it inherits the host's answers,
which is the failure mode AGENTS §5 names.

**Fix.** `zig/config_gen.zig` derives thirteen macros from `target.result`, each
with the `acinclude.m4` feature test it reproduces in a comment beside it.
`build.zig` builds the list once and passes it to both
`translate.defineCMacroRaw` and the library's `addCMacro`, so the translated
declarations and the compiled library cannot disagree about whether an entry
point exists.

**What is deliberately left undefined, and why.** The same file groups the
omissions under their reasons rather than listing names:

* No lock method, so no thread-local flags. `MPFR_NEED_THREAD_LOCK` is only
  defined under `MPFR_WANT_SHARED_CACHE`, which `configure.ac:216-225` defaults
  off, so the caches become plain globals. That is upstream's own documented
  `--disable-thread-safe` build, and `src/buildopt.c:28-30` reports 0 truthfully.
  `wasm32-wasi` has neither `<threads.h>` nor `<pthread.h>`, so this is the one
  answer that holds for all six matrix targets.
* Formats `std.Target` does not carry, each with a generic path behind it:
  `HAVE_LDOUBLE_*` falls to the format-agnostic code at `src/get_ld.c:180` and
  `src/set_ld.c:233`; `HAVE_LOCALE_H` and the two `struct lconv` members fall to
  the locale-independent decimal point at `src/mpfr-impl.h:1675`.
* Language features not offered on every target, gated symmetrically on the
  public header and the implementation: `MPFR_WANT_FLOAT128` and
  `MPFR_WANT_DECIMAL_FLOATS` are off, so both sides agree and none of the five
  decimal `#error`s at `src/mpfr-impl.h:866-886` can fire.
* A GMP internal, and a substitute GMP: `WANT_GMP_INTERNALS` and
  `MPFR_HAVE_GMP_IMPL` need `gmp-impl.h`, which a released GMP does not ship,
  and `configure.ac:818-826` says outright they must not be used by default.
  `MPFR_USE_MINI_GMP` is forbidden by the shared fork contract.
* Recomputed by MPFR itself or read by nobody: `HAVE_CONFIG_H`, `HAVE_ALLOCA_H`,
  `MPFR_LONG_WITHIN_LIMB`, `MPFR_INTMAX_WITHIN_LIMB`, `WORDS_BIGENDIAN`.

**Rule.** Deriving a configure fact from the target is not a shortcut around the
feature test; it is the feature test. The two obligations that come with it are
to cite which test each macro reproduces, and to define each macro on both the
compile line and the translation line, because a macro on only one of them
leaves declarations describing entry points the linked library never exported.

**Verification status.** The nineteen diagnostics are gone; the C library
compiles and links, and the behaviour suite runs. The values themselves are
`SOURCE-CONFIRMED` from `acinclude.m4` and the cited lines, not yet exercised by
a green native run.

## 16. A vendored provider is a licence surface, not just a build input

**Symptom.** `NOTICE.md` named the vendored GMP as a dependency and recorded that
it "retains its GNU GMP licence terms and four `COPYING*` files", and nothing
else. Four files were named; none of them was identified, and none of them was
distinguished from the other three. A reader could not tell which file carried
which term, could not check that a file had not been swapped, and could not tell
which of them travelled with an installed output.

**Evidence.** GMP is dual licensed and its own snapshot says so:
`vendor/gmp/build.zig.zon` declares `LGPL-3.0-or-later OR GPL-2.0-or-later`.
The four files are four different documents, read from the tree:

| File | Term | Bytes | SHA-256 |
| --- | --- | --- | --- |
| `vendor/gmp/COPYING` | GPLv3 | 35147 | `8ceb4b9ee5adedde47b31e975c1d90c73ad27b6b165a1dcd80c7c545eb65b903` |
| `vendor/gmp/COPYING.LESSERv3` | LGPLv3 additional permissions | 7639 | `a853c2ffec17057872340eee242ae4d96cbf2b520ae27d903e1b2fef1a5f9d1c` |
| `vendor/gmp/COPYINGv2` | GPLv2 | 18092 | `8177f97513213526df2cf6184d8ff986c675afb514d4e68a404010521b880643` |
| `vendor/gmp/COPYINGv3` | GPLv3 | 35150 | `e6037104443f9a7829b2aa7c5370d0789a7bda3ca65a0b904cdc0c2e285d9195` |

**The finding that makes the digests worth keeping.** GMP's GPLv3 text and
MPFR's are *different bytes*. `vendor/gmp/COPYING` is 35147 bytes with digest
`8ceb4b9e…`; this tree's `COPYING` is 35149 bytes with digest `3972dc97…`. The
wording differs in its FSF contact URL, `<http://fsf.org/>` against
`<https://fsf.org/>`. The same is true of the LGPL texts, 7639 against 7652
bytes. Two files carrying the same licence name are not interchangeable, and
"GPL-3" is not enough to decide whether a file was replaced.

**Fix.** `NOTICE.md` now names each file, its term, its size and its digest, and
states that both projects' pairs are preserved separately. `package.nix` and
`build.zig` install the four files into `$out/share/licenses/gmp/`, and
`NOTICE.md` records why: the GMP artefact now ships inside this output, so its
terms travel with it.

**Rule.** A vendored dependency has two independent surfaces: its build
interface and its licence surface. Recording only the build interface leaves
the licence obligation unverifiable. Name every file, its term and its digest,
and treat two same-named licences from two projects as two documents until a
digest says they are one.

**Verification status.** `SOURCE-CONFIRMED`: every size and digest above was read
from the files. The installation into `$out` is `PENDING-VERIFICATION`; no Nix
build has run.

## 17. A dependency's allocator is not established by its version string

**Symptom.** It is easy to write "MPFR 4.2.2 with GMP 6.3.0" and leave it there,
which reads like a compatibility statement. It is not one, and the difference
matters the moment anybody substitutes a GMP.

**Evidence.** MPFR does not call an allocator; it asks GMP for one on every
operation. `src/mpfr-gmp.c:313`, `:324` and `:335` each call
`mp_get_memory_functions` and then call through the returned pointer. GMP's
memory functions are process-wide state of the GMP *image* — `memory.c` and
`mp_set_fns.c` in the snapshot — not of a header. `src/free_cache.c:77-80`
records the consequence directly: MPFR's caches and pools are allocated with
GMP's current allocator, so an application has to free them before calling
`mp_set_memory_functions`.

**Fix.** `NOTICE.md` and `README.md` state the binding narrowly: this package
allocates through the allocator of the GMP image named in `UPSTREAM.md`, built
from `vendor/gmp`. Neither records a claim for another GMP build, another GMP
version, another allocator or another GMP ABI, and both say why a version string
cannot establish one. The same records name the duplication hazard, because a
consumer of `<mpfr.h>` links GMP too — `src/mpfr.h:52` includes `<gmp.h>` and
`mpfr_t` carries `mp_limb_t` — so a process must reach exactly one GMP state.

**Rule.** For a dependency reached through a hook the dependent calls on every
operation, record the *image* the pair is bound to, never a version. Then state
plainly which questions the record does not answer, so nobody later reads the
silence as a compatibility claim.

**Verification status.** `SOURCE-CONFIRMED` from the cited lines. That the two
variants behave as documented is `PENDING-VERIFICATION`.

## 18. A shared library on MinGW needs an export list nothing here can generate

**Symptom.** The shared route is delivered for five systems and the cross matrix
compiles six targets, so nothing about a Windows DLL stands out until a consumer
tries to link one and finds symbols missing. There is no diagnostic at build
time, because the build did not do anything wrong: it produced a DLL, and the
DLL exports what the linker chose to export.

**Evidence.** Three facts, each read from this tree:

- **MPFR's own source text carries no export annotation.** A count of
  `dllexport` across `src/*.c` and `src/*.h` is zero, and the four `__declspec`
  uses there are `noreturn` (`src/mpfr-impl.h:167`), `thread`
  (`src/mpfr-thread.h:36`) and `deprecated` (`src/mpfr.h:356`, with a comment at
  `:363`).
- **Its export decoration is inherited from GMP, and it does become an export
  annotation on the shared route.** `src/mpfr.h:321-331` maps `__MPFR_DECLSPEC` to
  `__GMP_DECLSPEC_EXPORT` when `__MPFR_WITHIN_MPFR` and `__GMP_LIBGMP_DLL` are
  both set, and `vendor/gmp/gmp-h.in:104` defines
  `__GMP_DECLSPEC_EXPORT` as `__declspec(__dllexport__)`, with `:123` defining
  `__GMP_DECLSPEC` in terms of it. `__GMP_LIBGMP_DLL` is itself derived from the
  selected linkage: `vendor/gmp/gmp-h.in:62` defines it as `@LIBGMP_DLL@`, and
  that substitution is answered at `vendor/gmp/zig/config_gen.zig:446-450`
  rather than at `:442`, which is the `_LONG_LONG_LIMB` case. So on
  `x86_64-windows-gnu -Dlinkage=dynamic` MPFR's declarations are annotated, and
  it would be wrong to say the shared route exports nothing.
- **What is not established from source is whether that annotation is
  sufficient for every symbol.** Upstream does not rely on it: it generates a
  `.def` from `nm` over the objects (`vendor/gmp/ltmain.sh:4643-4665`, whose
  `case` covers `*cygwin* | *mingw* | *cegcc*`), and Zig 0.16's build API exposes
  no way to run that. Whether a MinGW DLL built with the annotation exports
  everything is therefore an observation, not a deduction.
- **Upstream produces that list explicitly.** `vendor/gmp/ltmain.sh:4643-4665`
  runs the symbol listing through `sed` into an export list and, for
  `*cygwin* | *mingw* | *cegcc*`, writes a `.def`. Zig 0.16's build API exposes no
  way to run `nm` and consume its output during the build.

**Why nothing was invented to fill the gap.** A hand-written `.def` that omits
one symbol is worse than no `.def` at all: the library builds, the package
installs, and the failure surfaces in a consumer's link with a name nobody
connects back to this decision. A partial export list is also exactly the kind
of thing that looks correct in review.

**Fix.** None, deliberately. The position is recorded instead, in `NOTICE.md`
("The Windows export surface is unresolved"), in `README.md` section 2, in
`CHANGELOG.md` section 10 and in the `flake.nix` systems comment beside the
`x86_64-windows` attribute. Each says the same three things: the shared route on
that target is unobserved, the static route is unaffected because there is no
export list to produce, and the fix if a gate observes a missing export is a
generated `.def` from the build graph rather than a hand-maintained one.

**Rule.** When a platform's correctness depends on a tool the build system cannot
run, do not approximate the tool's output. Name the gap, say which targets and
which routes it affects, and say what a later fix must be *generated* from. An
unresolved item with a named boundary is information; an approximated artefact is
a lie that costs someone a day.

**Verification status.** `SOURCE-CONFIRMED` from the three citations above.
`x86_64-windows-gnu -Dlinkage=dynamic` is `PENDING-VERIFICATION` and is the most
likely failure in this delivery.

## 19. A lock file can be a shipped package path and an excluded build input at once

**Condition.** A package that advertises `flake.nix` through `build.zig.zon`'s
`.paths`, in a tree that also carries a `package.nix` whose `cleanSourceWith`
filter drops lock files. Both statements describe one tree and both are true.

**Evidence.** `build.zig.zon:91-104` names `flake.lock` and states the reason for
both halves of that decision: the lock exists and the workspace integration
owner writes it, while `devenv.lock` is absent from this tree, and naming an
absent path in `.paths` is a resolution failure. `package.nix:23-37` filters
both names out of the derivation source, and its comment says why: lock files
are inputs to the flake frontend rather than to the derivation. That holds for
this tree — `installPhase` (`package.nix:54-68`) runs `zig build install` and
reads no lock file at all.

**What the two axes are actually asking.** "Does a package fetched by hash
evaluate its flake reproducibly?" is answered by shipping the lock, because the
fetched copy is what the flake frontend reads and nothing else carries the pin.
"Does a re-lock invalidate an unchanged library build?" is answered by
excluding it, because the lock is not an input to the compile and a change to it
should not dirty the build hash. Reading either presence or absence as a defect
in the other place costs a redundant re-resolve or a spurious rebuild.

**Rule.** When a lock is missing from a shipped package, name it only if it
exists. Never create a lock to make a `.paths` entry resolvable, and never remove
an advertised Nix entry point to keep a lock out; both replace a described
state with an invented one. The provenance record has to move with the decision:
a lock is fork-owned, so it takes a `fork-owned-file:` line and no manifest
digest, and the fork-owned carried-path count changes with it. Here that is 72 to
73 (`UPSTREAM-BASELINE.sha256:112` and `:235`), while every upstream digest, the
2810 carried paths and the single `.gitignore` divergence are untouched, because
none of them describes a file this fork writes.

**Targets bound.** Any Zig package that advertises a Nix entry point through
`.paths`, and any Nix derivation whose source filter excludes lock files. The
two rules are independent of each other and of the Zig build graph: no
compiler, target or optimize mode is involved.

**Verification status.** `SOURCE-CONFIRMED` from the four citations above.
`./check-upstream-baseline.sh` has not been re-run since the classification
changed and no build of any kind was run here, so the coverage arithmetic and
the package resolution are `PENDING-VERIFICATION` on the driver's gates.

## 20. A type pun in a vendored dependency is a source fact, not a predicted failure

**Condition.** A review reads an upstream incompatible function-pointer
conversion and the build graph that compiles it, and concludes that a consumer
will trap. Every step of that chain is individually true: the conversion is
undefined behaviour in C, the build emits no `-fsanitize-c` of its own, and the
call really is indirect. The conclusion still is not established, and a chain of
true premises is not a premise about behaviour.

**Symptom.** The finding was that GMP's `printf` table cannot satisfy clang's
C function-type instrumentation, so an mpfr consumer reaching GMP's `printf`
family aborts at the first indirect call, `DOPRNT_FORMAT (last_fmt, last_ap)`
at `printf/doprnt.c:612`, in every optimize mode but `Debug`. A disposable
reproducer was prepared and the predicted failure stated in advance. Observed
on Zig 0.16.0, `x86_64-linux-gnu`, linked route, static linkage: `Debug` exit 0
(bg759) and `ReleaseSafe` exit 0 (bg765), both printing
`gmp-printf-family-reached` and reporting `3 of 3 checks matched`.
`WITHDRAWN` for the form "every release-safe MPFR `printf` consumer traps", and
kept here together with the refutation.

**Cause.** Not established, and deliberately not guessed. Neither graph sets
`Module.sanitize_c`, which is null unless a module says otherwise and emits no
`-fsanitize-c` flag when it is (`lib/std/Build/Module.zig:246`, `:558-562`), so
the two packages differ only in an explicit `-fno-sanitize=function`; what that
flag switches off in the supplier's graph, this run shows does not fire in this
one. The supplier's receipt for its own graph is `gmp/FORK-NOTES.md` section 36
and this run does not re-litigate it. Naming the toolchain default, the flag, or
the source as the cause would each be a separate claim with no run behind it.

**Fix.** None, on purpose. `vendor/gmp/build.zig` is unchanged. Adding the flag
to match the supplier would switch off a check in a graph where nothing was
observed to fail, which buys nothing established and costs real coverage, and
whether to pay that is the driver's call rather than a worker's. The part of
the finding that survives is recorded as a source fact in `CHANGELOG.md` section
13: the conversion at `printf/printffuns.c:76` is undefined behaviour upstream
and is carried byte-for-byte here, and this fork does not change it.

**Rule.** Keep "this code is undefined behaviour" and "this build fails because
of it" as two separate statements. The first is `SOURCE-CONFIRMED`, survives any
gate, and outlives the toolchain that would have exposed it. The second needs a
run, and when a run refutes a prediction, the prediction is withdrawn with its
refutation rather than quietly dropped or quietly kept. When a finding is
partly right, keep the confirmed half, bound the refuted half by exactly what
the run covered, and list what it did not cover - the bound is what stops the
next reader from re-generalising the sentence that was refuted.

**Targets bound.** The run covers one toolchain (Zig 0.16.0 as pinned), one host
target (`x86_64-linux-gnu`), the linked route, static linkage, and one entry
point (`__gmp_printf`, i.e. `__gmp_fprintf_funs`) reached with a format string
carrying no conversion. The loaded route, the shared linkage, the other four
`doprnt_funs_t` tables, any conversion specifier, and every cross target are
outside it. A later gate that exercises one of those may re-open the question,
and then the right instrument is that gate, not this record.

**Verification status.** `OBSERVED` for bg759 and bg765, both exit 0.
`SOURCE-CONFIRMED` for the five conversions and for the `sanitize_c` default.
The reproducer is disposable scratch under
`contract-physics-lua/api-repros/mpfr/`; it pins no version, no default and no
forwarding, so it is not proposed as a permanent test here.

## 21. A file:line citation into a vendored snapshot expires when its owner edits it

**Condition.** A record that cites a line inside another package's build file,
which that package's own fork keeps editing.

**Symptom.** Four pointers into `vendor/gmp` had drifted inside one table: a
library-linkage pointer fifty lines off and describing an option as hard-coded
after it had become declared, a header-installation pointer a hundred lines off,
a `config_gen.zig` pointer naming the neighbouring macro case, and a
field/assignment pair eight lines off. Every one of them still reads as
plausible, because nothing in the record lets a reader tell `:442` from `:450`
without opening the file. Beside them sat a factual error of the same vintage:
two records stated that no `gmp.pc` is installed, which is false - the snapshot
installs one at `vendor/gmp/build.zig:386-396` and this package installs another
at `build.zig:1146-1159`.

**Cause.** The cited file is not this package's to hold still. `vendor/gmp` is
a snapshot under active fork work, and its Zig build graph gains and loses lines
as that work lands. A pointer into it is an assertion about a file that changes
without notice, so it decays silently and never fails anything.

**Fix.** Re-read every pointer in the affected records against the file it names
and correct it; correct the factual claim by giving the reason the build graph
itself gives (`build.zig:1095-1097`), not the reason that was assumed. Nothing
in the build graph changed.

**Rule.** Treat "this line number looks right" as no evidence at all; only
reading the named line is. When a record is touched, re-derive its pointers into
files it does not own rather than assuming they held. And when a record gives a
reason for a decision, check the reason as well as the decision - a right answer
reached by a false premise advertises a checkable falsehood, and a reader who
checks it stops trusting the answer too.

**Targets bound.** Any record that cites another package's build file by line.
Here it was four pointers and one claim in two files; no compiler, target or
optimize mode is involved, and no build graph, source or native byte moved.

**Verification status.** `SOURCE-CONFIRMED` for each pointer and for the
`gmp.pc` install, by reading this tree. No build or `pkg-config` invocation was
run, so the installed prefix's actual contents are `PENDING-VERIFICATION` on the
driver's canonical and fetched gates.

## 22. A task body runs where the caller stood, not where the SDK is

**Condition.** A canonical devenv whose task bodies use relative paths, or an
install prefix that defaults inside the checkout, entered with
`devenv shell --from path:<sdk>` from a project directory that is not the SDK.

**Symptom.** `OBSERVED` in `nix-acceptance-20261004T175328Z`:
`devenv tasks run sdk:consumer` failed with
`/nix/store/fsl53025k6jhr0hdanxkgsfbh4hy8fvj-sdk-consumer: line 3: cd:
consumer: No such file or directory`
(`nix-acceptance-evidence/20261004T175328Z/mpfr-devenv-consumer.log:20`). The
generated wrapper is named after the task and carries the caller's working
directory, and `mpfr-devenv-info.log:19` shows that directory is
`…/sdks/mpfr/project`, with `DEVENV_DOTFILE` at `:17` beside it. That directory
holds no `build.zig`, no `consumer/` and no `UPSTREAM-BASELINE.sha256`. The
same shape would have hit every other body in this file; the consumer is only
the one the run reached.

**Cause.** Two assumptions, both false, and they are the reason the SDK's Nix
half was the only green part of this run. First: that a task runs in the SDK.
`devenv tasks run` and `devenv shell -- <script>` both execute in the working
directory of whoever invoked them, so every relative path in a body resolved
against a scratch project. Second, and worse because it is silent: that
`$DEVENV_ROOT` is the SDK. It is the same scratch project. Reaching for it
would have produced a different failure with the same shape — the environment
did name a directory, just the wrong one.

**Fix.** Take the root from the file that needs it. `./.` in an expression is
relative to the file that writes it, and `builtins.toString` renders the path
the evaluation already holds, so `pkgs.lib.escapeShellArg (builtins.toString
./.)` is this SDK and not the caller's directory. `${./.}` is the trap next
door: as an interpolation it copies this whole SDK — 2810 baseline records and
the vendored GMP snapshot — into the store on every evaluation, and a task that
had to write beside what it built could not, because the store is read-only.

The second half is the same rule one level down: `zig build`'s default install
prefix is `zig-out` in the source tree, so a bare `zig build` in a task is a
write into the checkout, on a network mount, by a file that has no authority to
authorise it. The installing bodies now pass `--prefix` beneath
`$ZIG_LOCAL_CACHE_DIR`, and the consumer keeps its own `--cache-dir` under the
same root because it is a second build root. `devenv tasks run` does not run
`enterShell`, which the run's own log shows (`devenv:enterShell` appears in the
shell gate and not in the task gate), so the task bodies resolve that variable
themselves, in the same order the shell does. A host that named none of the
three gets a stopped task, never a directory this file invented — `/tmp` is not
an approved mount here.

**Rule.** In a canonical task body, the working directory is an input the caller
controls and the install prefix is a filesystem the caller has not necessarily
approved: name both from something the SDK owns. `./.` in the owning file beats
every environment variable here, including `$DEVENV_ROOT`, and
`builtins.toString ./.` beats `${./.}`. Where a command installs or generates
a delivered artefact, it takes `--prefix` under a caller-chosen root rather
than the tool's in-tree default. Neither is a rule about devenv specifically;
it is a rule about any wrapper that hands a body to someone else's shell.

**Targets bound.** Any canonical devenv task or script body. Here: ten task
bodies in one file, no names changed, no build graph, source or native byte
moved, and the vendored GMP snapshot untouched. No compiler, target or optimize
mode is involved.

**Verification status.** The failure and the two log lines are `OBSERVED` as
quoted; the repair is `SOURCE-CONFIRMED` by reading `devenv.nix`. Nothing was
evaluated, built or run here, so the corrected bodies are
`PENDING-VERIFICATION` on the driver's next canonical devenv gate for this SDK.

**CI prefix correction.** The existing workflow now puts native installs under
`$RUNNER_TEMP/mpfr-native-prefix` and runtime providers under
`$RUNNER_TEMP/mpfr-runtime-prefix`, with every paired header, licence,
pkg-config and provider reference redirected. Non-installing steps are unchanged.
`SOURCE-CONFIRMED`; CI execution remains `PENDING-VERIFICATION`.
