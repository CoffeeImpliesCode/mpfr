# NOTICE

## GNU MPFR

GNU MPFR 4.2.2 is from <https://gitlab.inria.fr/mpfr/mpfr.git>, tag `4.2.2`, commit `eaa57b856d814af32f97d5e5eb129fb986235323`. See `UPSTREAM.md` for provenance.

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

The full LGPL-3 and GPL-3 texts are in `COPYING.LESSER` and `COPYING`. Per-file notices remain in upstream directories.

## Upstream's autotools exception

Upstream's `README` states:

> According to the special exception to the GNU General Public License, the
> autotools files compile, config.sub, config.guess, ltmain.sh, m4/libtool.m4 and
> missing are distributed under the same licence of GNU MPFR.

The exception is written for the release tarball. This Git tree carries the autotools inputs; `m4/libtool.m4` is absent.

| Files | Notice or term |
| --- | --- |
| `acinclude.m4`, `configure.ac` | LGPL-3-or-later; notices in the files |
| `Makefile.am`, `src/Makefile.am` | Unlimited permission to copy and distribute if the notice is preserved |
| `mpfr.pc.in`, `m4/.gitignore` | No notice; not a work in itself |
| `autogen.sh`, `version-ext.sh` | No licence notice in this release |

## Other upstream material

| Files | Licence and scope |
| --- | --- |
| `m4/ax_pthread.m4` | GPL-3-or-later with the Autoconf Macro special exception |
| `doc/texinfo.tex`, `tools/gitlog-to-changelog` | GPL-3-or-later |
| 29 files under `tests/data/` | GPL-2-or-later; generated from Gaston H. Gonnet's FPAccuracy package. Other files there carry MPFR's notice or none. |
| `doc/mpfr.texi` | GNU FDL-1.3-or-later, with no Invariant Sections, Front-Cover Texts or Back-Cover Texts; text in `doc/fdl.texi` |

The GPL-3 text in `COPYING` covers the GPL-3-or-later files. These tools and data are upstream files, not part of libmpfr.

## Fork-authored files

The repository owner authorized an LGPL-3.0-or-later grant for the fork-authored paths listed below; `FORK-LICENSE.md` contains the grant. Upstream files and `README.upstream.md` are excluded. The grant excludes `vendor/gmp` except the three listed build-graph files, which this fork maintains under the grant. Private hosting does not change these terms.

| Files | Scope |
| --- | --- |
| `build.zig`, `build.zig.zon`, `root.zig`, `zig/config_gen.zig` | Fork build, manifest, facade and target configuration |
| `fork/mpfr_all.h`, `fork/tests/*.zig`, `fork/example/main.zig` | Fork translation aggregate, tests and example |
| `consumer/build.zig`, `consumer/build.zig.zon`, `consumer/src/main.zig` | Downstream consumer package |
| `runtime/graph.zig`, `runtime/generate.zig`, `runtime/library.zig`, `runtime/loader.zig`, `runtime/sync.h`, `runtime/sync.c` | Fork runtime-loading route and synchronization shim |
| `UPSTREAM.md`, `CHANGELOG.md`, `NOTICE.md`, `FORK-NOTES.md`, `README.zig.md`, `README.md` | Fork documentation |
| `UPSTREAM-BASELINE.sha256`, `check-upstream-baseline.sh`, `FORK-LICENSE.md` | Fork provenance and licence records |
| `package.nix`, `flake.nix`, `flake.lock`, `devenv.nix`, `devenv.yaml`, `.envrc` | Fork packaging and development environment |
| `.gitignore` | The nineteen lines appended by this fork; upstream's 440 bytes remain unchanged |
| `vendor/gmp/build.zig`, `vendor/gmp/build.zig.zon`, `vendor/gmp/zig/config_gen.zig` | Fork-authored build files inside the GMP snapshot |

`README.upstream.md` is upstream's `README`, copied byte-for-byte from tag `4.2.2` (SHA-256 `74e733d2cfa1a6f4e6530326ed460f13ac9e4a5d79bb0f682ab67db2c9dc4d5b`). It is not fork-authored and is not covered by the grant. `fork/mpfr_all.h` is fork-authored but includes upstream `src/mpfr.h` and `src/mpf2mpfr.h`; those headers retain LGPL-3 terms.

## Vendored GNU MP

`vendor/gmp` is a separate GNU MP 6.3.0 snapshot. Its terms are independent of MPFR and, except for the three fork-authored build files above, of the fork grant. GNU MP is copyright the Free Software Foundation and contributors; see `vendor/gmp/AUTHORS`, `ChangeLog` and file headers. See `vendor/gmp/NOTICE.md` for the per-path inventory.

| Licence file | Term |
| --- | --- |
| `vendor/gmp/COPYING` | GNU GPL version 3, 29 June 2007 |
| `vendor/gmp/COPYING.LESSERv3` | GNU LGPL version 3, 29 June 2007, additional permissions |
| `vendor/gmp/COPYINGv2` | GNU GPL version 2, June 1991 |
| `vendor/gmp/COPYINGv3` | GNU GPL version 3, 29 June 2007 |

| Files | Licence and scope |
| --- | --- |
| GMP library sources, `gmp.h`, `gmp-impl.h` | LGPLv3-or-later or GPLv2-or-later at the user's option |
| `vendor/gmp/tests/`, `vendor/gmp/demos/` | GPLv2-or-later |
| `vendor/gmp/gen-*.c`, `vendor/gmp/bootstrap.c` | Same dual choice; build-time generators |
| GMP fork additions in `vendor/gmp` | LGPLv3-or-later under the GMP snapshot's own notice |
