# Upstream provenance

This repository is a downstream fork of GNU MPFR. Upstream's own `README`,
`INSTALL`, `NEWS`, `ChangeLog`, `doc/mpfr.texi`, `src/`, `tests/`, `tools/`,
`tune/`, `m4/`, `other/`, `COPYING` and `COPYING.LESSER` are kept verbatim.

## Pinned release

| Field | Value |
| --- | --- |
| Canonical upstream | <https://gitlab.inria.fr/mpfr/mpfr.git> |
| Release tag | `4.2.2` |
| Annotated tag object | `736ef3903ce50fc592268f69b6895c73da6adfb4` |
| Commit | `eaa57b856d814af32f97d5e5eb129fb986235323` |
| Commit date | 2025-03-20 10:15:52 +0100 |
| Commit subject | `ChangeLog update with tools/update-changelog` |
| Upstream release page | <https://www.mpfr.org/mpfr-4.2.2/> |
| Optional archive fallback | <https://www.mpfr.org/mpfr-current/mpfr-4.2.2.tar.xz> — **not used** |

The Git repository was reachable, so the archive fallback was not needed and the
import is a real Git import, not a hash-pinned archive. The release page is still
where upstream publishes patch warnings; at this tag `PATCHES` is empty, so
`mpfr_get_patches()` returns an empty string.

## How the sources arrived

```
git clone https://gitlab.inria.fr/mpfr/mpfr.git mpfr
cd mpfr
git checkout 4.2.2
```

The clone is full. These values were read out of this repository's own history;
each one names the command that produced it, so a later reader can re-derive it
instead of trusting the table:

| Property | Command | Value |
| --- | --- | --- |
| commits reachable from the pinned commit | `git rev-list --count HEAD` | 12397 |
| commits reachable from every fetched ref | `git rev-list --count --all` | 15166 |
| tags fetched | `git tag \| wc -l` | 142 |
| oldest commit | `git rev-list --max-parents=0 HEAD` | `b28347ab59db2a99168a17c3e1804000069199aa`, 1999-06-09, `Initial revision` |
| truncated history? | `test -f .git/shallow` | no |
| `.git` size | `du -sh .git` | 192M |

So upstream history is preserved rather than squashed into a single import
commit. The local branch `main` points at the tag, so the fork's first commit
sits directly on top of `eaa57b85`.

Working-tree state as prepared: among tracked files only `.gitignore` differs
from the pinned commit, by ten added lines and zero removed. Every fork file
(`build.zig`, `build.zig.zon`, `root.zig`, `fork/`, `consumer/`, the fork
Markdown files and `.github/`) is still untracked, so the fork's first commit is
the pinned tree plus that one additive `.gitignore` change. `NOTICE.md` records
why `.gitignore` is the only upstream file the fork may touch.

Remotes:

| Remote | URL |
| --- | --- |
| `origin` | <https://github.com/CoffeeImpliesCode/mpfr.git> (this fork, private) |
| `upstream` | <https://gitlab.inria.fr/mpfr/mpfr.git> (canonical) |

A configured remote is not a publication receipt: this fork has not been pushed.

## Vendored GMP provider

MPFR cannot be built without GMP. `build.zig.zon` declares a `.path`
dependency on `vendor/gmp`, and `build.zig` resolves it relative to this
package's own root rather than the caller's working directory. There is no
`../gmp` path, no archive URL and no installed host GMP in the default route;
`-Dsystem=gmp` selects an installed GMP and is always explicit.

`vendor/gmp` is a copy of this workspace's verified GMP package, taken on
2026-10-01 after that package's own gates had been observed. It is the GMP
fork's own source tree, not a GMP release tarball unpacked a second time, so
its identity is the identity recorded there:

| item | value |
| --- | --- |
| release | GNU MP 6.3.0 |
| archive | `gmp-6.3.0.tar.xz` |
| primary URL | <https://gmplib.org/download/gmp/gmp-6.3.0.tar.xz> |
| mirror URL | <https://ftp.gnu.org/gnu/gmp/gmp-6.3.0.tar.xz> |
| SHA256 of that archive | `a3c2b80201b89e68616f4ad30bc66aee4927c3ce50e33929ca819d5c43538898` |
| upstream SCM | <https://gmplib.org/repo/gmp/> (Mercurial; no commit SHA exists) |

The two URLs were fetched on 2026-09-30 and produced byte identical archives
under `gmplib.org` and `gnu.org`. The detached signature was downloaded and
inspected but its key is not in this machine's keyring, so the signature is
**unverified**; the digest is the integrity anchor.

Observed on 2026-10-01: `diff -rq --exclude=.zig-cache --exclude=zig-out
--exclude=.git gmp mpfr/vendor/gmp` reports no difference, so the snapshot is
byte identical to the verified package apart from build outputs and the Git
directory, which are not part of the dependency. The snapshot carries GMP's
four licence files, `COPYING`, `COPYING.LESSERv3`, `COPYINGv2` and `COPYINGv3`,
which travel with it because GMP is LGPL-3-or-later; see `NOTICE.md`.

To re-sync, take the snapshot from the verified GMP package again and re-run
that `diff`. A rebase of GMP's fork does not re-verify the archive digest: read
`gmp/UPSTREAM.md` for that.

The CI licence-and-provenance job compares `vendor/gmp` against this section
and fails if the four licence files or the recorded digest are missing.

## Licence

MPFR is under the GNU Lesser General Public License, version 3 or later. Both
`COPYING` (GPL-3) and `COPYING.LESSER` (LGPL-3) are preserved unchanged, as are
the per-file notices in `src/`. The tree also carries GPL-3-or-later tooling,
GPL-2-or-later test data and the FDL-licensed manual; `NOTICE.md` lists every
such file with its evidence and explains why this fork is private, but that does
not remove any upstream obligation.

The Zig code this fork adds (`build.zig`, `build.zig.zon`, `root.zig`, `fork/`,
`consumer/`, `.github/workflows/`) is fork work and is not covered by the LGPL;
the notice in each file says which parts are upstream's.

## Re-syncing with a newer upstream release

```sh
git fetch upstream --tags
git checkout -b rebase/4.2.x upstream/4.2.2     # or the newer tag
git rebase main
```

After any rebase, check these, because they are the places where the fork makes
assumptions about upstream's text:

1. `libmpfr_la_SOURCES` and `BUILT_SOURCES` in `src/Makefile.am`. `build.zig`
   reads both at configure time and fails loudly if either assignment
   disappears, so a rebase that renames them cannot silently build a subset. The
   two are also read as upstream reads them: `BUILT_SOURCES` is built in the
   build directory (`nodist_libmpfr_la_SOURCES`, `src/Makefile.am:79`), so its
   units are compiled out of the generated directory and not out of `src/`.
2. `src/mparam_h.in`. `build.zig` copies it verbatim to `mparam.h`; that is only
   correct while the template contains no `@VAR@` substitution.
3. `tools/get_patches.sh`. `build.zig` reproduces it in `getPatchesSource`,
   including the licence header. If upstream changes the header text, copy the
   new text across.
4. `src/mpfr.h:885-1021`. The facade mirrors a list of macros there. See
   `FORK-NOTES.md` entry 1 for the full list and for what breaks if it moves.
5. `src/mpfr.h:1136-1155`. The aggregate header `fork/mpfr_all.h` pins
   `MPFR_USE_INTMAX_T` to work around this auto-detection block, and the
   compile line pins `HAVE_STDINT_H`, which is what `src/mpfr-intmax.h:60-68`
   turns into the same macro before `mpfr.h` is parsed. Both halves have to move
   together or the translation declares entry points the library never built.
   See `FORK-NOTES.md` entry 2.
6. `vendor/gmp`. Re-run the snapshot's own provenance record before reusing it,
   and re-read the section above: a rebase does not re-verify the provider.
7. `.github/workflows/verify.yml` and the pinned commit it compares against. The
   provenance job's `git diff` gate names the commit explicitly; a rebase to a
   newer tag must update the tag, the commit in `UPSTREAM.md` and the CI gate
   together.

## What this fork does not carry over

Nothing is deleted. Upstream's autotools build is left in place but unused: this
fork compiles libmpfr with Zig and never invokes `configure`, `make`,
`autoreconf` or CMake. `PATCHES` is empty at 4.2.2, so `mpfr_get_patches()`
returns an empty string.
