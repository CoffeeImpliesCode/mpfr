# NOTICE

## GNU MPFR

This repository contains GNU MPFR 4.2.2 in full, as obtained from the canonical
upstream at <https://gitlab.inria.fr/mpfr/mpfr.git>, tag `4.2.2`, commit
`eaa57b856d814af32f97d5e5eb129fb986235323`. `UPSTREAM.md` records the full
provenance.

MPFR is:

> Copyright 2000-2025 Free Software Foundation, Inc.
> Contributed by the Pascaline and Caramba projects, INRIA.
>
> The GNU MPFR Library is free software; you can redistribute it and/or modify
> it under the terms of the GNU Lesser General Public License as published by
> the Free Software Foundation; either version 3 of the License, or (at your
> option) any later version.
>
> The GNU MPFR Library is distributed in the hope that it will be useful, but
> WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
> FITNESS FOR A PARTICULAR PURPOSE. See the GNU Lesser General Public License for
> more details.
>
> You should have received a copy of the GNU Lesser General Public License along
> with the GNU MPFR Library; see the file COPYING.LESSER. If not, see
> <https://www.gnu.org/licenses/>.

The full licence texts are in `COPYING.LESSER` (LGPL-3) and `COPYING` (GPL-3),
both preserved unmodified from upstream. Per-file notices are preserved in
`src/` and in the other upstream directories.

## Upstream's autotools exception

Upstream's `README` records this special exception to the GPL:

> According to the special exception to the GNU General Public License, the
> autotools files compile, config.sub, config.guess, ltmain.sh, m4/libtool.m4 and
> missing are distributed under the same licence of GNU MPFR.

That sentence is written for the release tarball. The Git tree carries the
autotools *inputs* instead of the generated files, and the exception's own list
mostly names generated files that do not exist here: `m4/libtool.m4` is not in
this tree. What the tree does carry is listed by its own notice:

| File | Notice in the file |
| --- | --- |
| `acinclude.m4` | LGPL-3-or-later (upstream notice, lines 1-16) |
| `configure.ac` | LGPL-3-or-later (`AC_COPYRIGHT`, lines 6-24) |
| `Makefile.am`, `src/Makefile.am` | the automake notice: unlimited permission to copy and distribute as long as the notice is preserved (lines 1-11) |
| `mpfr.pc.in`, `m4/.gitignore` | no notice; not a work in itself |
| `autogen.sh`, `version-ext.sh` | no licence notice in this release, as upstream ships them |

The fork builds none of these files and removes none of them. The autotools
build is left in place but unused; see `CHANGELOG.md`.

## GPL-licensed material that ships in this tree

The MPFR library is LGPL, but the tree also carries files under the GNU General
Public License. The full GPL-3 text is preserved in `COPYING`, which satisfies
the "or any later version" option of all of them. They are:

| File | Licence and evidence |
| --- | --- |
| `m4/ax_pthread.m4` | GPL-3-or-later with the Autoconf Macro special exception (lines 58-88) |
| `doc/texinfo.tex` | GPL-3-or-later (lines 8-20) |
| `tools/gitlog-to-changelog` | GPL-3-or-later (lines 6-18) |
| 29 files under `tests/data/` | GPL-2-or-later: generated from Gaston H. Gonnet's FPAccuracy package (see the header of `tests/data/acos`); the remaining files there carry MPFR's own notice or none |

These are build tooling and test data, not part of libmpfr, and this fork builds
neither. They are kept because they are upstream's tree: deleting them would
change the source set that the fork's provenance gate compares against the
pinned commit.

The MPFR manual, `doc/mpfr.texi`, is licensed separately under the GNU Free
Documentation License 1.3 or later, with no Invariant Sections, no Front-Cover
Texts and no Back-Cover Texts (doc/mpfr.texi:30-34). The licence text itself is
`doc/fdl.texi`.

## Licence of the fork's own files

The owner of this repository authorized a per-project licence for the files this
fork adds, matching the primary upstream terms where appropriate. That grant is
recorded in full, with its SPDX identifier and its complete file inventory, in
`FORK-LICENSE.md`: **LGPL-3.0-or-later**, chosen because MPFR's own primary terms
are LGPL-3-or-later.

The earlier sentence these files used to carry — that they "may be copied and
modified with the repository" — described the state before that authorization.
It is superseded.

The grant never reaches upstream's files, and it never reaches `vendor/gmp`.
Both keep their own terms.

## This fork is private, and that changes nothing

The downstream repository <https://github.com/CoffeeImpliesCode/mpfr> is private.
That is a distribution and access decision, not a licence decision. Every
upstream obligation continues to apply, and in particular:

- Anyone who receives a copy of this repository, inside or outside the
  organisation, receives it under the same terms: LGPL-3-or-later for MPFR,
  GPL-3-or-later for the files listed above, FDL-1.3-or-later for the manual.
- Anyone who receives a copy of the fork's own files, including this file,
  receives them under `FORK-LICENSE.md`: LGPL-3.0-or-later, matching MPFR's own
  primary terms.
- Anyone who receives `vendor/gmp` receives it under GMP's own dual licence as
  that snapshot records it, with all four `COPYING*` files.
- The LGPL's requirements for conveying the licence, the source, and the
  ability to relink against a modified library are unchanged by private
  hosting.
- No GPL-only tool has been added by the fork, and none has been removed from
  upstream's tree.

## The vendored GMP provider

MPFR cannot be built without GMP. `build.zig.zon` declares
`.gmp = .{ .path = "vendor/gmp" }` and `build.zig` refuses to build without it.
There is no `../gmp` path, no archive URL and no installed host GMP in the
default route; `-Dsystem=gmp` selects an installed GMP and is always explicit.

`vendor/gmp` is a snapshot of this workspace's own GMP package, first supplied
on 2026-10-01. It is a fork, not a release tarball unpacked a second time, so
its identity is the identity recorded in its own `UPSTREAM.md` and summarized in
this fork's `UPSTREAM.md`, "Vendored GMP provider": GNU MP 6.3.0, archive
`gmp-6.3.0.tar.xz`, SHA-256
`a3c2b80201b89e68616f4ad30bc66aee4927c3ce50e33929ca819d5c43538898`.

That snapshot carries **four** licence files. GMP is dual licensed and each file
is a real term, not a duplicate:

| File | Term | Bytes | SHA-256 |
| --- | --- | --- | --- |
| `vendor/gmp/COPYING` | GNU GPL version 3, 29 June 2007 | 35147 | `8ceb4b9ee5adedde47b31e975c1d90c73ad27b6b165a1dcd80c7c545eb65b903` |
| `vendor/gmp/COPYING.LESSERv3` | GNU LGPL version 3, 29 June 2007 (the additional permissions) | 7639 | `a853c2ffec17057872340eee242ae4d96cbf2b520ae27d903e1b2fef1a5f9d1c` |
| `vendor/gmp/COPYINGv2` | GNU GPL version 2, June 1991 | 18092 | `8177f97513213526df2cf6184d8ff986c675afb514d4e68a404010521b880643` |
| `vendor/gmp/COPYINGv3` | GNU GPL version 3, 29 June 2007 | 35150 | `e6037104443f9a7829b2aa7c5370d0789a7bda3ca65a0b904cdc0c2e285d9195` |

Keep all four. GMP's own headers offer the choice, and deleting the GPLv2 option
would narrow an upstream term this fork has no authority to narrow.

These are **not** copies of this tree's own licence files, and the differences
are real: `COPYING` here is 35149 bytes with SHA-256
`3972dc9744f6499f0f9b2dbf76696f2ae7ad8af9b23dde66d6af86c9dfb36986`, and
`COPYING.LESSER` is 7652 bytes with SHA-256
`e3a994d82e644b03a792a930f574002658412f62407f5fee083f2555c5f23118`. The GPLv3
wording differs in its FSF contact URL between MPFR's copy and GMP's. Each
project's pair is preserved as its own project shipped it.

The snapshot's own `vendor/gmp/NOTICE.md` holds the part-by-part breakdown:
libgmp sources, `gmp.h` and `gmp-impl.h` under LGPLv3-or-later or GPLv2-or-later
at the user's option; the upstream `tests/` and `demos/` under GPLv2-or-later;
the `gen-*.c` table generators and `bootstrap.c` under the same dual choice,
run at build time; and GMP's own fork additions under LGPLv3-or-later. That file
governs everything inside `vendor/gmp`, and nothing this fork does reaches into
it.

The fork's CI checks that all four files are present and that the snapshot is
committed, because it is a `.path` dependency a fresh clone must be able to
resolve (`.github/workflows/verify.yml`, licence-and-provenance job).

### Dependency metadata, as the tree actually stands

These are `SOURCE-CONFIRMED` readings of the tree, recorded so the packaging and
the documentation describe the real provider and not a remembered one.

| Property | Where it is read | Value |
| --- | --- | --- |
| package name | `vendor/gmp/build.zig.zon` | `gmp` |
| version | `vendor/gmp/build.zig.zon` | `6.3.0` |
| fingerprint | `vendor/gmp/build.zig.zon` | `0x328f6061da525515` |
| declared SPDX licence | `vendor/gmp/build.zig.zon` | `LGPL-3.0-or-later OR GPL-2.0-or-later` |
| library linkage as found | `vendor/gmp/build.zig:81-85`, applied at `:241` | a declared `-Dlinkage` option defaulting to `.static`, then `.linkage = linkage`; `static` is the default because it is what the snapshot always built |
| installed headers | `vendor/gmp/build.zig:340-342` | `gmp.h`, `gmp-mparam.h`, `gmp_all.h` |
| installed pkg-config file | `vendor/gmp/build.zig:386-396` | `gmp.pc`, rendered from the snapshot's own `gmp.pc.in` and installed to `lib/pkgconfig/gmp.pc`; `gmpxx.pc` is not installed, because it joins `pkgconfig_DATA` only under `WANT_CXX` (`Makefile.am:127-130`) and this build compiles no C++ |
| `__GMP_LIBGMP_DLL` | `vendor/gmp/zig/config_gen.zig:446-450` | **selected by the linkage, not fixed**: `if (p.libgmp_dll) "1" else "0"` at `:450`, with `Params.libgmp_dll` declared at `:69` and set at `:216` |
| shared `libgmp` version numbers | `vendor/gmp/Makefile.am:107-109` | `LIBGMP_LT_CURRENT = 15`, `LIBGMP_LT_REVISION = 0`, `LIBGMP_LT_AGE = 5` |

That `__GMP_LIBGMP_DLL` line is worth reading closely. An earlier state of the
snapshot returned the literal `"0"` there; that is gone. The value is now a
function of the selected linkage, which is what makes the shared route real
rather than nominal.

`build.zig` forwards `-Dlinkage=static|dynamic` to `vendor/gmp/build.zig`, where
it is declared with `b.option`, so a forwarded option is a declared interface
and not one the dependency rejects as unused. The default remains `.static`,
which is the value that was hard-coded before. Three consequences follow, and
they are recorded here as **PENDING-VERIFICATION** because no gate has observed
them:

| | static | dynamic |
| --- | --- | --- |
| `libgmp` in the output | `$out/lib/libgmp.a` | `$out/lib/libgmp.so.10.5.0` with soname `libgmp.so.10` and a `libgmp.so` symlink |
| `__GMP_LIBGMP_DLL` | `0` | `1` |
| how MPFR reaches GMP | GMP's objects linked in from `libgmp.a` | a dynamic dependency on `libgmp.so` |

The shared `libgmp` numbers are libtool's, read out of the snapshot's own
`Makefile.am` rather than chosen. `LIBGMP_LT_CURRENT = 15`,
`LIBGMP_LT_REVISION = 0` and `LIBGMP_LT_AGE = 5` at
`vendor/gmp/Makefile.am:107-109` reach `libgmp_la_LDFLAGS` as
`-version-info 15:0:5` at `vendor/gmp/Makefile.am:294-295`; libtool's major is
CURRENT-AGE = 10, so the real name is `.so.10.5.0` and the soname is `.so.10`.

Two further facts decide how the MPFR output must describe its dependency, and
neither is a matter of taste:

- **The shared route needs `libgmp` beside it.** A shared `libmpfr` records a
  dynamic dependency on the shared `libgmp`, so an output containing only
  `libmpfr.so` is not a closed output. GMP's four `COPYING*` files are installed
  into `$out/share/licenses/gmp/` for that reason.
- **`gmp.pc` is installed, and `mpfr.pc` still does not require it.**
  `build.zig:1146-1159` renders the snapshot's own `vendor/gmp/gmp.pc.in` and
  installs it to `lib/pkgconfig/gmp.pc`, so pkg-config can find it beside
  `mpfr.pc`. `Requires: gmp` is nonetheless left empty, and upstream's
  `mpfr.pc.in:10`, `Libs: -L${libdir} -lmpfr -lgmp`, is preserved verbatim:
  `gmp.pc` declares no dependency of its own, so `Requires: gmp` would only
  restate the `-lgmp` that line already carries (`build.zig:1095-1097`). That
  one line is correct for both linkages here, which is why it is kept rather
  than replaced.

`vendor/gmp` is a snapshot whose licence files are upstream GMP's own, so the
build graph installs those four files from the snapshot rather than inventing a
substitute; the inventory above gives the exact paths and their digests.

### The allocator is part of the dependency, not a version detail

MPFR resolves GMP's allocator on every call rather than calling into it
directly: `src/mpfr-gmp.c:313`, `:324` and `:335` each call
`mp_get_memory_functions` and then invoke the returned function. GMP's memory
hooks are process-wide settings in the GMP image that is actually linked
(`vendor/gmp/memory.c`, `vendor/gmp/mp_set_fns.c`), and
`src/free_cache.c:77-80` records that MPFR's own caches are allocated with
GMP's current allocator, so an application must free them before calling
`mp_set_memory_functions`.

Both linkages of this package come from the same `vendor/gmp` sources and the
same generated `gmp.h`, except for `__GMP_LIBGMP_DLL`: `0` for the static route,
`1` for the shared one. What that single macro changes is the hinge of the whole
shared route:

- `src/mpfr.h:321-331` makes `__MPFR_DECLSPEC` an export decoration only when
  `__GMP_LIBGMP_DLL` is set, so the shared library exports MPFR's entry points
  while the static one does not need to.
- `src/mpfr-impl.h:251-253` turns `MPFR_WIN_THREAD_SAFE_DLL` on only in that
  case, so `__gmpfr_flags` is declared with MPFR's thread attribute and is
  process-local in the static build.

The consequence for this record is narrow and is deliberately not widened: what
this package allocates through is the allocator of the GMP image named in
`UPSTREAM.md`, built from `vendor/gmp`. **No claim is made that MPFR works
against some other GMP build, some other GMP version, some other allocator, or
some other GMP ABI.** Neither a version string nor the presence of
`mp_get_memory_functions` in both libraries establishes any of that. The pair is
bound to the image that is actually linked, in every optimize mode, because GMP's
allocator is a per-process setting of that image and not a property of a header.

There is also a duplication hazard worth naming, not solving. A consumer of
`<mpfr.h>` has to link GMP itself — `src/mpfr.h:52` includes `<gmp.h>` and
`mpfr_t` carries `mp_limb_t` — so a process must reach exactly one GMP state, and
GMP's allocator and its other settings are per state. On the shared route the
dynamic loader gives the process one `libgmp`; on the static route GMP's objects
are linked once into the program. Recording the mechanism is this file's job;
guaranteeing one image per process is the integrator's, and it is a real
condition rather than a formality.

### The Windows export surface is unresolved, and stays that way until observed

On ELF and Mach-O targets a shared library exports what the linker keeps, and
the `__MPFR_DECLSPEC` above is decoration rather than the mechanism. A MinGW DLL
is the case where that distinction matters, and it needs stating carefully in
both directions:

- **MPFR's own source text carries no export annotation.** A count of
  `dllexport` across `src/*.c` and `src/*.h` is zero. The four `__declspec` uses
  there are `noreturn` (`src/mpfr-impl.h:167`), `thread` (`src/mpfr-thread.h:36`)
  and `deprecated` (`src/mpfr.h:356`, with a comment at `:363`).
- **Its export decoration is inherited from GMP, and on the shared route it does
  become one.** `src/mpfr.h:321-331` maps `__MPFR_DECLSPEC` to
  `__GMP_DECLSPEC_EXPORT` when `__MPFR_WITHIN_MPFR` and `__GMP_LIBGMP_DLL` are
  both set; `vendor/gmp/gmp-h.in:104` defines `__GMP_DECLSPEC_EXPORT` as
  `__declspec(__dllexport__)` and `:123` defines `__GMP_DECLSPEC` in terms of it.
  So it would be wrong to say this route exports nothing.
- **What source alone does not settle is whether that annotation is sufficient
  for every symbol.** Upstream does not rely on it: it generates a `.def` from
  `nm` over the objects (`vendor/gmp/ltmain.sh:4643-4665`, whose `case` covers
  `*cygwin* | *mingw* | *cegcc*`), and Zig 0.16's build API exposes no way to run
  that. Whether a MinGW DLL built with the annotation exports everything is an
  observation, not a deduction from the headers.

No `.def` was invented. A hand-written export list that omits one symbol fails
later and somewhere else, and a partial list is exactly the failure mode nobody
looks for in a licence record or a build file. So the position is:

- `x86_64-windows-gnu -Dlinkage=dynamic` is **PENDING-VERIFICATION**, and it is
  the most likely failure in this delivery.
- The static route on `x86_64-windows-gnu` is unaffected by this question, since
  there is no export list to produce.
- If a gate observes a missing export, the fix is a generated `.def` from the
  build graph, not a documentation change.

## Fork-added files

The following are additions by this fork. They are licensed
**LGPL-3.0-or-later** under `FORK-LICENSE.md`, which also states the
authorization that grant rests on; they are not covered by MPFR's own licence,
and their individual notices say what each one mirrors.

| File | Notice |
| --- | --- |
| `build.zig` | fork work; reproduces `tools/get_patches.sh` and cites it |
| `build.zig.zon` | fork work |
| `root.zig` | fork work; documents the upstream lines it mirrors |
| `fork/mpfr_all.h` | fork work; states that the included MPFR headers remain LGPL-3 |
| `fork/tests/*.zig` | fork work |
| `fork/example/main.zig` | fork work |
| `consumer/*` | fork work |
| `runtime/graph.zig`, `runtime/generate.zig`, `runtime/library.zig`, `runtime/loader.zig`, `runtime/sync.h`, `runtime/sync.c` | fork work; the runtime-loading route — the build-time dispatch generator, this SDK's loader binding, the reusable loader core that binding is built on, and the synchronization shim, whose weak process-global symbols `runtime/graph.zig:214-218` compiles into the `-Druntime=true` dispatch under this SDK's own prefix `mpfr_rt` (`runtime/graph.zig:58`), so two SDKs in one process cannot collide. `build.zig:300` imports `runtime/graph.zig` on both routes, because it also supplies the linked route's core types; what `-Druntime=true` changes is that its dispatch module, and `sync.c` with it, replaces the translated C module instead of the compiled archives being linked |
| `UPSTREAM.md`, `CHANGELOG.md`, `NOTICE.md`, `FORK-NOTES.md`, `README.zig.md` | fork work |
| `UPSTREAM-BASELINE.sha256`, `check-upstream-baseline.sh` | fork work; the per-file SHA-256 baseline for every upstream byte this package carries, and the gate that verifies it from the package root |
| `.github/workflows/verify.yml` | fork work |
| `zig/config_gen.zig` | fork work; derives the per-target configure facts |
| `README.md` | fork work; the canonical fork README |
| `README.upstream.md` | upstream's `README`, byte-for-byte; preserved, never authored |
| `FORK-LICENSE.md` | fork work; records the grant for everything in this table |
| `package.nix`, `flake.nix`, `flake.lock`, `devenv.nix`, `devenv.yaml`, `.envrc` | fork work; Nix packaging, the development environment, and the resolved-input lock the workspace integration owner wrote. `flake.lock` is Nix-generated JSON, so it is the one fork file that cannot carry an SPDX header; the grant below covers it anyway |
| `vendor/gmp/build.zig`, `vendor/gmp/build.zig.zon`, `vendor/gmp/zig/config_gen.zig` | fork work **inside** the vendored snapshot, maintained here so GMP's linkage follows MPFR's; see "The vendored GMP provider". Their SPDX headers are a deliberate divergence from the supplier package |

Nineteen fork-authored files carry `SPDX-License-Identifier: LGPL-3.0-or-later`.
Eighteen name it on their first line — `build.zig`, `build.zig.zon`,
`root.zig`, `consumer/src/main.zig`, `fork/example/main.zig`, the six files
under `runtime/`, `devenv.nix`, `flake.nix`, `package.nix`,
`.github/workflows/verify.yml` and the three `vendor/gmp` files above — and
`check-upstream-baseline.sh` names it in its own comment below the shebang. The
rest of the tree carries none, which is a choice rather than an omission: the
identifier is a licence statement, not a style rule, and `FORK-LICENSE.md` lists
which files have it and why.

`README.upstream.md` is the one row that is not fork-authored text: it is
upstream's `README` copied verbatim, with SHA-256
`74e733d2cfa1a6f4e6530326ed460f13ac9e4a5d79bb0f682ab67db2c9dc4d5b`, matching
`README` itself and the file at the pinned commit `4.2.2`. It carries
MPFR's terms like any other upstream file, and its presence in this table records
that the fork did not write it.

`fork/mpfr_all.h` is worth singling out: it is a fork file, but it `#include`s
upstream's `mpfr.h` and `mpf2mpfr.h`, which remain LGPL-3. Including an LGPL
header does not relicense it.

## The one upstream file the fork touches

`.gitignore` is the one upstream-tracked file the fork has ever changed, and it
changes additively. Upstream's 440 bytes, 37 lines, are kept byte-for-byte at the
top; 931 bytes and nineteen lines follow them, five ignore entries with their
reasoning in comments: the Zig build's `/.zig-cache/` and `/zig-out/`, and the
`/result`, `/.devenv*` and `/.direnv*` that `nix build` and `devenv`/`direnv`
leave at the repository root. Nothing is removed. Every other upstream-tracked
path is byte-identical to the pinned commit: the CI provenance gate checks
exactly that, by content rather than by a hand-written list, and
`UPSTREAM-BASELINE.sha256` records the SHA-256 of both the upstream file and the
carried one. That record also covers `vendor/gmp`, which the `git diff` against
the MPFR commit cannot see at all. See `CHANGELOG.md` and `FORK-NOTES.md`
entry 11.

## Trademarks

"MPFR", "GNU MPFR" and "GMP" are used to refer to the upstream projects. Neither
this fork nor its authors claim any trademark in them.
