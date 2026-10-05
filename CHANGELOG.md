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
- The private translation aggregate now includes `<stdio.h>` before MPFR/GMP
  headers, making their public `FILE *` entry points reachable through `c`.
  Runtime generation routes the source-traced `mpfr_` and `__gmp` namespaces,
  leaving target-libc externs directly linked. All translated library exports
  remain required; native headers are unchanged. The bounded real
  `FILE *`/stdout variadic proof passed 16/16 linked/loaded delivery cells
  on `x86_64-linux-gnu`, 2026-10-04 (receipt and same-provider scope:
  `FORK-NOTES.md` entry 2). This does not certify every raw entry point.
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
- `ConversionError` now names only `InvalidNumber` and `InvalidBase`. GMP
  allocation failure cannot be recovered through this set: its allocator must
  not return null and the default aborts (`vendor/gmp/doc/gmp.texi:7487-7490`;
  `vendor/gmp/memory.c:53-58`). Valid-base null results panic ordinarily.
- `defaultRoundingMode` retains its return type and ordinarily panics for an
  unknown getter value in every mode. The raw-setter corruption repro is
  refuted (`src/set_rnd.c:30-31`); the guard enforces a public-policy
  constraint, not an observed corruption fix. The unknown-getter panic was
  never exercised: valid controls do not establish it. `SOURCE-CONFIRMED`.
- The two-tag conversion taxonomy probe is observed to exit 0 in Debug, and the
  bounded native rounding controls pass in all four optimize modes
  (`x86_64-linux-gnu`, 2026-10-04; receipts in FORK-NOTES 14).

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
- Corrected the consumer recipe to import the module without linking the
  artifact again; artifact lookup for bundled C headers is scoped to bundled,
  linked mode, not runtime or system MPFR mode. `PENDING-VERIFICATION`.
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

`mpfr/vendor/gmp` is populated with this workspace's verified GMP package,
copied on 2026-10-01 after that package's own gates had been observed, and it has
been kept in step with the supplier since. The comparison command,
`diff -rq --exclude=.zig-cache --exclude=zig-out --exclude=.git gmp
mpfr/vendor/gmp`, reported no difference at the copy; it does not now, because
the supplier moved on. The comparison as it stands is recorded once, in
`UPSTREAM.md`, which is the only place that states it and which carries the
groups the differences fall into; this file does not restate it, so that a later
supplier update cannot leave two records disagreeing. That comparison is a source
comparison and certifies nothing about either package's behaviour.

What has not changed is the archive identity. `UPSTREAM.md` records the archive
name, its digest, the four `COPYING*` files the snapshot carries and the command
itself, and the snapshot still carries GNU MP 6.3.0 from that one archive
byte-for-byte; what moved is the fork that ships it. `UPSTREAM-BASELINE.sha256`
is the per-file record of that, over all 2156 vendored paths. There is still no
`../gmp` path, no archive URL and no installed host GMP in the default route.

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

## 9. Zig API contract alignment — 2026-10-03

**Condition.** MPFR's rendering base rules differ from its parsing rules.
Digits owns one allocation; rounding result, flags and defaults are separate
channels. The declared GMP provider is present, not an absent placeholder.

**Fix.** State render bases 2..62/-36..-2, constructor precision bounds,
Float/Digits owner-copy-release and borrowed-field contracts, and the three
state channels. Correct provider/provenance status and citations without
inventing byte identity. Integrate GMP's authored corrections and supplier
record. The executable module example uses the real `Digits.digits` method.

**Verification and bound.** Zig 0.16.0, native Linux x86-64: install,
Debug/ReleaseSafe tests, smoke, package consumer and module example pass.
Aggregate compile-only `matrix` fails at GMP's WASI signal configuration
boundary. System providers and foreign runtime are not certified. The
supplier comparison retains its documented build-file blank-line difference;
no native source/header, generated binding or pin changed.

**Superseded by section 10.** This section's observations describe the tree as
of 2026-10-03. The 2026-10-04 migration changed `build.zig`, `build.zig.zon` and
`vendor/gmp/build.zig`, so nothing in this section is a current result for the
package as it now stands. `README.md` section 3 records the same split.

## 10. Standalone SDK contract — 2026-10-04

**Condition.** The package had no canonical README, no standalone Nix
packaging, no installed pkg-config file, no shared-library route and no recorded
licence for the files the fork itself authors. Its GMP provider was present and
named but its dependency metadata, its four licence files and its allocator
binding were not written down anywhere.

### Provenance and documentation

- Added `README.md` as the canonical fork README, in the required order: current
  native-source deviations, current native-build deviations with a pointer to
  this file for dated history, the build/run/test matrix, then consumption. It
  separates what the driver observed **before** this migration from what is
  **PENDING-VERIFICATION** after it, and claims no unrun pass.
- Preserved upstream's `README` byte-for-byte as `README.upstream.md`. SHA-256
  `74e733d2cfa1a6f4e6530326ed460f13ac9e4a5d79bb0f682ab67db2c9dc4d5b`, identical
  to `README` and to the file at tag `4.2.2`. It is not fork-authored text and is
  never described as such.
- Updated `README.zig.md` to point at `README.md` for deviations and matrix, to
  state the linkage and install layout, and to document pkg-config and Nix
  consumption. The facade documentation is unchanged.
- Added `FORK-LICENSE.md`. The owner authorized a per-project licence for
  fork-authored additions matching the primary upstream terms where appropriate,
  and MPFR's primary terms are LGPL-3-or-later, so the grant is
  **`LGPL-3.0-or-later`**. `NOTICE.md`'s earlier "may be copied and modified with
  the repository" described the state before that authorization and is
  superseded. No personal copyright identity is asserted and no fork addition
  is attributed to the Free Software Foundation or to INRIA.

### Licence and dependency records

- `NOTICE.md` now carries the complete vendored GMP inventory: all four
  `COPYING*` files with their terms, byte counts and SHA-256, the snapshot's own
  part-by-part breakdown, and the observation that GMP's GPLv3 text and MPFR's
  are different bytes with different FSF contact URLs, so each project's pair is
  preserved separately.
- Recorded the provider's dependency metadata as read from the tree: package
  name, version `6.3.0`, fingerprint, declared SPDX expression, installed
  headers, the absence of an installed `gmp.pc`, and `__GMP_LIBGMP_DLL`.
- Recorded the allocator binding from source rather than from version text.
  `src/mpfr-gmp.c:313`, `:324` and `:335` each call `mp_get_memory_functions`,
  and `src/free_cache.c:77-80` records that MPFR's caches are allocated with
  GMP's current allocator. The package is therefore bound to the GMP image it
  is built with. **No claim is made for any other GMP build, version, allocator
  or ABI.**
- Recorded that `__GMP_LIBGMP_DLL` is the hinge of the shared route:
  `src/mpfr.h:321-331` exports MPFR's entry points only when it is set and
  `src/mpfr-impl.h:250-252` turns on `MPFR_WIN_THREAD_SAFE_DLL` in the same case.

### Standalone packaging

- Added `package.nix`: one source-only derivation consumed by both `flake.nix`
  and `devenv.nix`. It builds from this repository only — no `../` workspace
  import, no host account, node or store path, and no build-time download. GMP
  comes from the in-tree `vendor/gmp` snapshot. It installs nothing itself: the
  build graph owns every artifact, header, licence file and `.pc`, so there is
  one writer per path.
- Added `flake.nix` with a fixed nixpkgs revision and two package variants,
  `packages.<system>.static` and `.shared`, as separate attributes of one SDK.
  `default` preserves the existing linkage policy, which is static.
- Added `devenv.nix`, `devenv.yaml` and `.envrc`. `devenv` is canonical. Its
  `packages` list carries tools and not the SDK; the packaging route is the lazy
  `outputs.static` and `outputs.shared`, reached with `devenv build`.
- `static` names the installed artefact and is not a promise of a wholly static
  executable. The shared variant's output is only closed together with the
  shared `libgmp` beside it.

### Native delivery this migration added, and one question it could not answer

- `-Dlinkage=static|dynamic` selects the installed artefact; the default stays
  `static`, which is what the recorded evidence was collected against. It is
  forwarded to `vendor/gmp` as a declared option, so GMP's linkage follows MPFR's
  and a shared `libmpfr` records a real dynamic dependency on a shared `libgmp`
  installed beside it.
- Both shared sonames are libtool's arithmetic on upstream's own numbers, not
  typed-in constants. `src/Makefile.am:106` sets `-version-info 8:2:2`, so
  `libmpfr.so.6.2.2` with soname `libmpfr.so.6`.
  `vendor/gmp/Makefile.am:107-109` sets `15:0:5`, so `libgmp.so.10.5.0` with
  soname `libgmp.so.10`.
- `mpfr.pc` is installed to `$out/lib/pkgconfig/mpfr.pc` from upstream's
  `mpfr.pc.in`, with `Libs: -L${libdir} -lmpfr -lgmp` preserved verbatim and
  `Requires:` empty. `Requires: gmp` is not used because this build installs no
  `gmp.pc` for pkg-config to find.
- GMP's four `COPYING*` files are installed to `$out/share/licenses/gmp/`,
  because the GMP artefact now ships inside this output.
- **One question stays open and is recorded as open.** A MinGW DLL's export
  surface. MPFR's own source text carries no `__declspec(dllexport)` — the count
  across `src/*.c` and `src/*.h` is zero — but on the shared route its decoration
  does become an export annotation, because `src/mpfr.h:321-331` adopts
  `__GMP_DECLSPEC_EXPORT` and `vendor/gmp/gmp-h.in:104` defines that as
  `__declspec(__dllexport__)`. Whether that covers every symbol is not settled by
  source: upstream does not rely on it and generates a `.def` from `nm` over the
  objects instead (`vendor/gmp/ltmain.sh:4643-4665`), which Zig 0.16's build API
  cannot run. No `.def` was fabricated, because a partial export list silently
  drops symbols and then fails somewhere else. So
  `x86_64-windows-gnu -Dlinkage=dynamic` is PENDING-VERIFICATION and is the most
  likely failure in this delivery; the static route on that target is unaffected.
  `NOTICE.md` and `FORK-NOTES.md` entry 18 carry the same statement with sources.

**Verification and bound.** Nothing here has been run. No build, test, smoke,
cross-target check, Nix build or devenv shell has observed any part of this
section. `README.md` section 3 lists the pending gates and the commands that
exist for them. `devenv.lock` and `flake.lock` are not written by this change.
No upstream file is modified by it; the only upstream-tracked file this fork has
ever changed remains `.gitignore`, additively.

## 11. Per-file upstream byte baseline — 2026-10-04

**What changed.** Added `UPSTREAM-BASELINE.sha256` and
`check-upstream-baseline.sh`. The record carries a SHA-256 for each of the 2810
upstream paths this package ships: all 654 paths GNU MPFR 4.2.2 tracks at commit
`eaa57b856d814af32f97d5e5eb129fb986235323`, and all 2156 files of the GNU MP 6.3.0
release vendored under `vendor/gmp/`. Its header states the pin, the exact
derivation, the per-area counts and the single divergence; the script verifies
all of it from the repository root and is run by the `licence-and-provenance` CI
job. Both are added to `build.zig.zon`'s `.paths`, so a fetched package carries
the record rather than only the claim. `UPSTREAM.md` gained a section describing
the record and a rebase item for regenerating it.

**Why the existing gate was not enough.** The `git diff` against the pinned
commit is a complete gate for MPFR's own tree, and it still runs. It cannot see
`vendor/gmp` at all: the provider is another package's tree, so "differs from the
MPFR commit" says nothing about whether it still matches GMP 6.3.0, and that is
where the native dependency this package links against actually lives. The
baseline covers both, from the pinned sources rather than from the working tree.

**The divergence.** `.gitignore` is the only upstream-tracked file this fork has
ever changed, and the record carries both digests: upstream's
`e363fac26f837cd1c3357f9b2ce08325c5e8adde9a9dc496bcde61f86be8837f` and the
carried `6e7047860c580040aa6575d305484e5ef132872c1c74722cec31d70337171fe8`.
`UPSTREAM.md` said the file differs "by ten added lines"; it has nineteen
appended lines, 1371 bytes against upstream's 440, and that sentence now says so.

**Test fix.** `fork/tests/special_test.zig` called `support.requireProvider()` in
all six of its tests without importing `support.zig`, so the file did not compile.
It now imports it, exactly as the other seven test files in that directory do.

**Verification and bound.** `./check-upstream-baseline.sh` passes on this tree:
2810 carried upstream paths, 2809 byte-identical, 1 recorded divergence, 72
fork-owned paths accounted for. The derivation was re-run from upstream, not from
the tree: `git fetch --depth 1 origin refs/tags/4.2.2` resolves the tag object,
the commit and the tree recorded above, and `gmp-6.3.0.tar.xz` fetched from
`gmplib.org` and `ftp.gnu.org` on 2026-10-04 gave identical 2094196-byte files
with digest `a3c2b80201b89e68616f4ad30bc66aee4927c3ce50e33929ca819d5c43538898`, and
all 2156 of its files are carried byte-identically. Sixteen mutations were
applied to a scratch copy of this tree, and every one of them failed the gate
while an untouched copy passed:

- a changed native source, a changed upstream test, and a changed upstream
  testdata file;
- a changed vendored GMP native source, header and licence text;
- a changed MPFR licence text;
- a deleted native source and a deleted upstream testdata file;
- an unrecorded new file under `src/` and one under `vendor/gmp/mpn/`;
- an edited recorded divergence, a broken verbatim copy of `README`, a tampered
  per-area count, a dropped manifest line and a drifted pin value.

No build, test, cross-target check, Nix build or devenv shell was run, and no
upstream file was modified: `.gitignore` remains the only upstream-tracked file
this fork changes, additively.

## 12. The canonical Nix lock is a shipped package path — 2026-10-04

**Condition.** This package advertises `flake.nix` and `devenv.nix` in
`build.zig.zon`'s `.paths`, so a package fetched by hash evaluates them. A
fetched package that carried `flake.nix` without `flake.lock` would resolve its
own `nixpkgs` input on first evaluation instead of using the recorded one, so
the same commit would give two different dependency sets depending on how it was
obtained. `flake.lock` is in the tree and the workspace integration owner writes
it. `devenv.lock` is not in the tree, and a `.paths` entry for a path that does
not exist is a package resolution failure rather than a documentation choice, so
it stays unnamed.

**What changed.** `build.zig.zon` names `flake.lock` in `.paths` and records the
reason for both decisions beside the entry. `UPSTREAM-BASELINE.sha256` declares
it `fork-owned-file: flake.lock` and moves the fork-owned carried-path count
from 72 to 73; it carries no manifest digest for it, because a lock file is not
upstream material and the coverage check counts carried paths that are neither
upstream nor declared.

**What did not change.** No native byte. The carried-upstream counts are still
2810 paths, 2809 byte-identical and 1 recorded divergence, which is
`.gitignore`; nothing under `src/`, `doc/`, `tests/`, `tools/`, `tune/`, `m4/`,
`other/`, `examples/` or `vendor/gmp/` was touched, and no file under
`vendor/gmp/` is a fork-owned lock or manifest entry.

**The two axes are separate, and naming one is not a claim about the other.**
`.paths` governs what a fetched Zig package contains. `package.nix:23-37` filters
`flake.lock` and `devenv.lock` out of the Nix derivation's own source. That is
not a contradiction: the flake frontend resolves locked inputs before the
derivation's source is assembled, and `installPhase` (`package.nix:54-68`) reads
no lock. Shipping the lock in the package and excluding it from the build source
answer two different questions and are both correct.

**Verification and bound.** `SOURCE-CONFIRMED` from the four files named above.
`flake.lock` is 593 bytes with SHA-256
`ca3c2564b75f5881752ee00a5218f3263a0d61bb4a1a00bd4fd9b32448214e02`, lock format
7, pinning `nixpkgs` at revision
`c7def046b9a883d46974757852106483d741586f`. `./check-upstream-baseline.sh` has
not been re-run since the classification changed, and no `zig build`, Nix build
or devenv shell was run: both are `PENDING-VERIFICATION` on the driver's gates.
The recorded byte is a build-input identity, not a provenance anchor; the
archive digest in `UPSTREAM.md` is the anchor, and this entry does not restate
it.

## 13. The vendored GMP `printf` type pun: source fact, no repair — 2026-10-04

**The source fact, which stands.** `gmp-impl.h:4540` declares
`doprnt_format_t` as `int (*)(void *, const char *, va_list)`, and all five
`struct doprnt_funs_t` initializers fill the `format` slot by converting a
function pointer to it: `printf/snprntffuns.c:153` from
`gmp_snprintf_format (struct gmp_snprintf_t *, ...)` (`:62`),
`printf/sprintffuns.c:90` from `gmp_sprintf_format (char **, ...)` (`:52`),
`printf/vasprintf.c:104` from `gmp_asprintf_format (struct gmp_asprintf_t *, ...)`
(`:70`), `printf/printffuns.c:76` from libc's own
`vfprintf (FILE *, const char *, va_list)`, and `printf/obprntffuns.c:66` from
glibc's `obstack_vprintf (void *, const char *, va_list)`. Converting between
incompatible function pointer types is undefined behaviour in C whether or not
any tool notices it. All five are upstream, carried byte-for-byte, and this fork
does not touch them.

**The claim that is withdrawn.** A review finding asserted that an mpfr consumer
reaching GMP's `printf` family aborts in a release-safe build, and a
disposable reproducer was prepared for it. `WITHDRAWN`. Zig 0.16.0,
`x86_64-linux-gnu`, linked route, static linkage, one probe program:

- `-Doptimize=ReleaseSafe`, exit 0, `gmp-printf-family-reached` printed and
  `3 of 3 checks matched` reported (run bg765);
- `-Doptimize=Debug`, exit 0, the same output (run bg759).

`__gmp_printf` is the entry point that reaches `__gmp_fprintf_funs`
(`printf/printf.c:45`), the table whose `format` slot is the libc `vfprintf`
conversion, and the call site is the indirect
`DOPRNT_FORMAT (last_fmt, last_ap)` at `printf/doprnt.c:612`. That call
completed. So the claim as stated - that a current release-safe MPFR consumer
traps on this path - is false, and **no `-fno-sanitize=function` exception was
added to `vendor/gmp/build.zig`**. The supplier fork's exception belongs to that
package's graph; importing it here would switch off a check in a graph where
nothing was observed to fail.

**What the run does and does not establish.** It establishes that the linked
`x86_64-linux-gnu` release-safe build of this package executes GMP's `printf`
table correctly, through one table and one entry point, with a format string
carrying no conversion. It establishes nothing about the loaded
(`-Druntime=true`) route, the shared linkage, the other four `doprnt_funs_t`
tables, any conversion specifier, any cross target, or any other toolchain
version. Neither graph sets `Module.sanitize_c`, so no `-fsanitize-c` flag is
emitted from either build file; what that implies for this graph is a
`PENDING-VERIFICATION` question about the toolchain default, not a reason to
edit a build. The supplier's own receipt for its own graph is `gmp/FORK-NOTES.md`
section 36; this run does not re-litigate it, and no cause is attributed here.

The probe is scratch under `contract-physics-lua/api-repros/mpfr/`, not a test
added to this package: it pins no version, no default and no forwarding, so
there is nothing in it that belongs in the repository.

## 14. Four record corrections in `README.md` and `NOTICE.md` — 2026-10-04

Documentation only. No build file, no source file and no native byte changed.

**The stale citations.** All four were `file:line` pointers into `vendor/gmp`,
a snapshot whose Zig files keep moving as the package is maintained, and all
four had drifted:

| Record | Said | Actually |
| --- | --- | --- |
| `NOTICE.md` linkage row | `vendor/gmp/build.zig:191`, `.linkage = .static`, hard-coded | `:81-85` declares `-Dlinkage` and defaults it to `.static`; `:241` applies it. The row also contradicted the paragraph directly below it, which already described a forwarded option |
| `NOTICE.md` headers row | `vendor/gmp/build.zig:238-240` | `:340-342`, the three `installHeader` calls |
| `NOTICE.md` `__GMP_LIBGMP_DLL` row | `config_gen.zig:442`; field at `:61`, set at `:208` | `:446-450` for the substitution and `:450` for the line itself; the field is `:69` and the assignment `:216`. `:442` is the neighbouring `DEFN_LONG_LONG_LIMB` case, and `:208` opens the struct literal rather than setting the field |
| `README.md` linkage paragraph | `vendor/gmp/zig/config_gen.zig:442` | `:446-450` |

**The false claim, which was not a citation.** `NOTICE.md` and `README.md` both
stated that no `gmp.pc` is installed, and gave that absence as the reason
`mpfr.pc` leaves `Requires:` empty. `gmp.pc` *is* installed, twice over: by the
snapshot at `vendor/gmp/build.zig:386-396`, and again by this package at
`build.zig:1146-1159`, each rendered from `vendor/gmp/gmp.pc.in` to
`lib/pkgconfig/gmp.pc`. The conclusion was right and the reason was not: the
real reason is stated in the build graph at `build.zig:1095-1097`, namely that
`gmp.pc` declares no dependency of its own, so `Requires: gmp` would only
restate the `-lgmp` that `mpfr.pc.in:10` already carries. Both records now give
that reason, and the installed-file tables list `gmp.pc` beside `mpfr.pc`.

A record that gives the wrong reason for a right decision is worse than one
that gives no reason: it publishes a fact a consumer can check and find false,
and the reader then distrusts the decision as well.

**Verification and bound.** `SOURCE-CONFIRMED` by reading each named file in
this tree. No build, `pkg-config` invocation or gate was run here, so what an
installed prefix actually contains stays `PENDING-VERIFICATION` on the driver's
canonical and fetched gates.

## 15. Every task names its own working directory and its own install prefix — 2026-10-04

**Condition.** `devenv.nix` was written as though the shell that runs a task
were entered in this repository. The canonical acceptance run enters it from a
scratch project directory instead, which is a supported way to use devenv and
not a mistake by the caller.

**Symptom.** `OBSERVED` in run `nix-acceptance-20261004T175328Z`:
`devenv tasks run sdk:consumer` failed with
`/nix/store/fsl53025k6jhr0hdanxkgsfbh4hy8fvj-sdk-consumer: line 3: cd:
consumer: No such file or directory`
(`nix-acceptance-evidence/20261004T175328Z/mpfr-devenv-consumer.log:20`), and
the same run's `mpfr-devenv-info.log:19` prints `DEVENV_ROOT` as
`…/nix-acceptance-20261004T175328Z/sdks/mpfr/project` — a directory holding no
`build.zig`, no `consumer/` and no `UPSTREAM-BASELINE.sha256`. Nothing else in
this SDK failed there: `mpfr-nix-build.log` in that evidence set shows both
derivations built with realised outputs, and the before/after source file-set
digests are byte-identical.

**Cause.** `devenv tasks run` and `devenv shell -- <script>` execute in the
working directory of whoever invoked them, and `$DEVENV_ROOT` names that same
directory. A relative `cd consumer`, a bare `zig build` and every other
relative path in a task body therefore addressed the caller's project
directory, and there was no other way for a body to reach this build graph.

**Fix.** `devenv.nix` only; no build graph, no source and no native byte
changed. Every existing task body now begins by moving to this SDK's own
directory, taken from the file itself with `builtins.toString ./.` and quoted
with `pkgs.lib.escapeShellArg`, so the answer cannot depend on where the caller
stood. `${./.}` was deliberately not used: that interpolation copies this whole
SDK — all 2810 baseline records and the vendored GMP snapshot — into the store
on every evaluation, and the store is read-only.

The four tasks that install — `sdk:build`, `sdk:build:static`,
`sdk:build:shared`, `sdk:install` — now pass `--prefix` beneath
`$ZIG_LOCAL_CACHE_DIR` (`…/mpfr-install/static`, and `…/mpfr-install/dynamic`
for the shared one) rather than leaving Zig's own default `zig-out` inside the
source tree, and each prints the prefix it chose before building. `sdk:consumer`
keeps its own cache directory, now `…/mpfr-consumer` under the same root, so
the second build root still does not share one manifest with this one. The
compile-only tasks install nothing and were given no `--prefix` they do not
need.
The shell exports `ZIG_LOCAL_CACHE_DIR` and `ZIG_GLOBAL_CACHE_DIR` only when the
caller has not, from `$XDG_CACHE_HOME` or else `$TMPDIR`; a task applies the
same three names in the same order, because `devenv tasks run` does not run the
shell hook. A caller who set none of the three gets a stopped task naming all
three, not an invented directory.

The same pass gave every one of those commands the same flag list, `-j8
--summary all`, plus an explicit `--cache-dir` outside the checkout: a `zig
build` that is not told a cache directory creates `.zig-cache` inside the
source tree, and only a caller's exported environment would have kept it out.
The flags are written once and applied exactly once per command, so no task can
end up with two job flags on one invocation; `sdk:consumer` carries them beside
its own `…/mpfr-consumer` directory, because the two build roots must not share
one manifest. A task now also fills and exports `ZIG_LOCAL_CACHE_DIR` and
`ZIG_GLOBAL_CACHE_DIR` itself, in the shell hook's own order and before it
reaches the compiler, and only where the caller left them unset, so an exported
value is kept exactly as it was. `ZIG_GLOBAL_CACHE_DIR` is deliberately left
alone in the one case where it cannot be derived — a caller who exported only
the local directory, has named an approved mount already, and gets Zig's own
global default, which is outside this checkout — rather than turning a working
caller's invocation into a failure.

**No names changed.** No task was added, renamed or removed: `sdk:consumer` is
the entry the run failed on, and the provenance gate stays what it has always
been — `./check-upstream-baseline.sh`, one command that cds to its own
directory. `devenv` names no task alias for it, and none was added here.

**Bound.** The vendored GMP snapshot is untouched, and the
`-fno-sanitize=function` exception withdrawn in entry 13 stays withdrawn.
Whether the corrected tasks now succeed is `PENDING-VERIFICATION` on the
driver's next canonical devenv gate for this SDK; no build, evaluation or task
run was performed for this entry.

The existing CI installing steps now use `$RUNNER_TEMP/mpfr-native-prefix`
and `$RUNNER_TEMP/mpfr-runtime-prefix`; installed-closure checks and the
runtime consumer follow those same prefixes. Non-installing steps are unchanged.
CI execution is `PENDING-VERIFICATION`; no job was added.

## 16. The current matrix is observed, and fifteen of its 53 cells are four named boundaries — 2026-10-05

**Scope.** Documentation only. No build file, no source file, no native byte and
no upstream file changed, and no gate was run for this entry; the numbers below
are read out of four existing driver receipts.

**Observed.** Four gates, each with its own receipt.

- Native eight cells, `zig build test smoke install -Doptimize=<mode>
  -Dlinkage=<l> -Druntime=false`, static × dynamic crossed with Debug,
  ReleaseSafe, ReleaseFast and ReleaseSmall: exit 0 in all eight,
  `Build Summary: 46/46 steps succeeded; 69/69 tests passed` in every cell.
- Own-loaded eight cells, the same eight configurations with `-Druntime=true` and
  `MPFR_PROVIDER` naming this tree's own shared `libmpfr.so.6.2.2`
  (`provider.kind: "own"`): exit 0 in all eight,
  `Build Summary: 47/47 steps succeeded; 69/69 tests passed` in every cell.
- The 53-cell cohort, receipt `20261004T221720228710Z-45046/mpfr-53-target-8.json`,
  `source_stamp_before == source_stamp_after` (`8dae0747…`), `target_jobs 8`,
  `jobs_per_build 8`: **exit 1**. Raw `pass=19 fail=15 build_only=17 partial=2`;
  corrected `pass 19 / build_only 19 / build_fail 15`. Every executed cell reports
  `tests=69`.
- The compile-only `zig build matrix` baseline, row `baseline-mpfr-matrix`: exit
  0, `Build Summary: 151/151 steps succeeded`, `declared_target_count 6`, all six
  triples named in the run's own step lines, `test_pass_lines: []`.

**`build_only` is not a pass.** Nineteen cells compiled and ran nothing because no
executor was available. Two of them reported `reason: partial_execution` —
`aarch64-maccatalyst` and `arm-freebsd` — and the corrected audit counts both as
`build_only`.

**The fifteen build failures decompose into four boundaries.** Nine NetBSD cells
(`aarch64`, `aarch64_be`, `arm`, `armeb`, `mips`, `mipsel`, `powerpc`, `x86`,
`x86_64`) fail `translate-c` at
`lib/libc/include/generic-netbsd/stdio.h:151:1: error: unknown type name 'pragma'`
under 65 errors. Three 32-bit OpenBSD cells (`arm`, `powerpc`, `x86`) fail at
`lib/compiler/aro/include/stddef.h:8:23: error: typedef redefinition with
different types ('unsigned int' vs '__size_t' (aka 'unsigned long'))`. Two
64-bit MIPS OpenBSD cells (`mips64`, `mips64el`) fail at
`lib/libc/include/generic-openbsd/mips64/endian.h:40:2: error: "__MIPSEL__ or
__MIPSEB__ must be defined to define BYTE_ORDER!!!"`. The fifteenth is
`hexagon-linux`, this package's own documented refusal at `build.zig:592` —
"MPFR has no buildable configuration for this target: GMP has no Hexagon port".
The first fourteen are limits of the vendored libc headers and Aro's reading of
them, below this package's code; none is repaired here and none is a claim that
MPFR is wrong.

**Bound.** The cohort's counts describe the source it stamped and nothing later.
An edit to this graph, to the vendored GMP snapshot or to the private aggregate
that landed after `20261004T221720228710Z-45046` is not covered by them. The
`matrix` baseline is compile-only by its own construction and by the receipt's
`runtime_pass_claimed: false`; it derives no runtime result under any exit code.
The installed C consumer, the fetched consumer, the typed and raw Zig consumers,
the runtime-loaded consumer binary, both Nix derivations, the devenv shell and
the installed licence material all remain `PENDING-VERIFICATION` and are listed
as such in `README.md` §3.
