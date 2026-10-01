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

## Documentation licence

`README.zig.md`, `UPSTREAM.md`, `CHANGELOG.md`, `FORK-NOTES.md` and this file
are fork work. They may be copied and modified with the repository.

## This fork is private, and that changes nothing

The downstream repository <https://github.com/CoffeeImpliesCode/mpfr> is private.
That is a distribution and access decision, not a licence decision. Every
upstream obligation continues to apply, and in particular:

- Anyone who receives a copy of this repository, inside or outside the
  organisation, receives it under the same terms: LGPL-3-or-later for MPFR,
  GPL-3-or-later for the files listed above, FDL-1.3-or-later for the manual.
- The LGPL's requirements for conveying the licence, the source, and the
  ability to relink against a modified library are unchanged by private
  hosting.
- No GPL-only tool has been added by the fork, and none has been removed from
  upstream's tree.

## The vendored GMP provider: pending

`build.zig.zon` declares a `.path` dependency on `vendor/gmp`, and `build.zig`
refuses to build without it. That directory is **not present** in this tree yet:
the shared fork contract requires the parent to supply a verified GMP package
snapshot, and no verified snapshot exists so far. `UPSTREAM.md`, "Vendored GMP
provider", records the precondition deliberately, with no revision and no digest,
because none has been read or verified.

When the snapshot lands it brings its own licence terms with it. GNU GMP is
LGPL-3-or-later and ships four `COPYING*` files; all four must travel with the
snapshot, and its revision and integrity data must be recorded in `UPSTREAM.md`
in the same change. The fork's CI checks both conditions as soon as the
directory exists (`.github/workflows/verify.yml`, last step of the
licence-and-provenance job).

## Fork-added files

The following are additions by this fork and are not covered by MPFR's licence.
They carry their own short notices where a notice is appropriate.

| File | Notice |
| --- | --- |
| `build.zig` | fork work; reproduces `tools/get_patches.sh` and cites it |
| `build.zig.zon` | fork work |
| `root.zig` | fork work; documents the upstream lines it mirrors |
| `fork/mpfr_all.h` | fork work; states that the included MPFR headers remain LGPL-3 |
| `fork/tests/*.zig` | fork work |
| `fork/example/main.zig` | fork work |
| `consumer/*` | fork work |
| `UPSTREAM.md`, `CHANGELOG.md`, `NOTICE.md`, `FORK-NOTES.md`, `README.zig.md` | fork work |
| `.github/workflows/verify.yml` | fork work |

`fork/mpfr_all.h` is worth singling out: it is a fork file, but it `#include`s
upstream's `mpfr.h` and `mpf2mpfr.h`, which remain LGPL-3. Including an LGPL
header does not relicense it.

## The one upstream file the fork touches

`.gitignore` gains two entries from the fork under a marked comment: the Zig
build's `/.zig-cache/` and `/zig-out/`. Upstream's 37 entries are kept
byte-for-byte and nothing is removed. Every other upstream-tracked path is
byte-identical to the pinned commit; the CI provenance gate checks exactly that,
by content rather than by a hand-written list. See `CHANGELOG.md` and
`FORK-NOTES.md` entry 11.

## Trademarks

"MPFR", "GNU MPFR" and "GMP" are used to refer to the upstream projects. Neither
this fork nor its authors claim any trademark in them.
