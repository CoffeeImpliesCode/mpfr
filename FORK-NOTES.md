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

**Reusable rule.** A binding must make the target's feature-macro state explicit
rather than inheriting whatever the host toolchain happened to define.

**Verification status.** Not run.

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

**How it is met.** Two entries are appended to upstream's `.gitignore` under a
marked comment. Upstream's 37 existing entries are kept byte-for-byte; nothing
is removed, and MPFR's list is an autotools artefact list that a Zig build never
produces, so it stays as the upstream convention it is. A root-level ignore file
is the only one Git reads there, and a local exclude would not travel with the
repository, so appending is the mechanism. `zig-out` is confirmed as the install
directory by `lib/std/Build.zig:733`; no separate `zig-pkg` entry is added, since
the toolchain shipped here does not document one.

**Separately**, `build.zig.zon`'s `.paths` is an explicit allowlist that names
only the build files, `fork/`, `consumer/` and upstream's own files. Neither
directory appears there, so a user build cannot change the package hash even
before the ignores apply.

**Verification status.** Not run, and no contamination was observed: no build has
been performed, so `.zig-cache/` and `zig-out/` do not exist in this tree. This is
a packaging requirement, not a found bug.

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
