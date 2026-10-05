# Upstream provenance

This repository is a downstream fork of GNU MPFR. Upstream's own `README`,
`INSTALL`, `NEWS`, `ChangeLog`, `doc/mpfr.texi`, `src/`, `tests/`, `tools/`,
`tune/`, `m4/`, `other/`, `COPYING` and `COPYING.LESSER` are kept verbatim.
Upstream's `README` is additionally preserved a second time, byte-for-byte, as
`README.upstream.md`; see "The preserved upstream README" below.

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
from the pinned commit, by nineteen added lines and zero removed: upstream's 440
bytes are unchanged and 931 bytes of ignore entries, with their reasoning,
follow them. Every fork file (`build.zig`, `build.zig.zon`, `root.zig`, `fork/`,
`consumer/`, the fork Markdown files and `.github/`) is still untracked, so the
fork's first commit is the pinned tree plus that one additive `.gitignore`
change. `NOTICE.md` records why `.gitignore` is the only upstream file the fork
may touch. `UPSTREAM-BASELINE.sha256` records both digests of it.

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

The comparison run on 2026-10-03, after the Zig API alignment copied twelve
authored Zig/documentation files from the supplier, reported one differing
file: `build.zig`, with one extra blank line on the supplier's side after
`check_step.dependOn(&checked_tests.step)`. Every other path and byte matched
at that checkpoint. That was the whole result on that date. It is kept here as
history and it is superseded by the comparison below; it must not be read as
the snapshot's present identity, and no other file in this repository may
restate it as one.

### The comparison as it stands on 2026-10-04

The same command, `diff -rq --exclude=.zig-cache --exclude=zig-out --exclude=.git
gmp mpfr/vendor/gmp`, now reports **26 differing paths and 14 paths the
supplier has and the snapshot does not**. The supplier has moved a long way
past the 2026-10-01 import: it gained a runtime-loading route of its own, the
provider file that route is configured from, a per-SDK packaging set, and a
rewritten provenance and documentation set. GMP's own library is untouched by
all of it: **no C source, no public header, no licence file, no data file and
no upstream test file of GMP's appears in either list**, and every path below
is fork-authored material. The archive digest above is therefore still the
same anchor; what moved is the fork that ships it.

**The 26 differing paths**, grouped by what the difference is, because a bare
`diff` reports them all alike:

| Group | Paths | What the supplier has |
| --- | --- | --- |
| Build graph, real code | `build.zig`, `build.zig.zon`, `root.zig`, `zig/config_gen.zig`, `zig/memory.zig`, `zig/example/main.zig`, `consumer/build.zig`, `consumer/src/main.zig` | the runtime-loading route end to end: `-Druntime` (`gmp/build.zig:137-145`), `@import("runtime/graph.zig")` (`:66`), the install facade that gives an installed binary a search path different from a build-cache one, the `rt` core import, the provider surface and the `LoadSource`/`LoadError` re-exports in `root.zig`, and the derived-language fixes that came with it |
| Tests, real code | `zig/test/root.zig`, `zig/test/known_answers.zig`, `zig/test/ownership.zig`, `zig/test/parsing.zig`, `zig/test/division.zig`, `zig/test/rational_float_random.zig`, `zig/test/alloc_probe.c` | `ensureLoaded()` at the head of every test through a new `zig/test/bootstrap.zig`, and the allocator hooks installed from Zig through a new `zig/test/alloc_probe.zig` rather than only from C: a C probe can reach the setter through a link-time symbol alone, which a runtime build has none of |
| Provenance and CI | `tools/provenance_gate.sh`, `.github/workflows/ci.yml`, `.gitignore`, `CHANGELOG.md`, `FORK-NOTES.md`, `NOTICE.md`, `README.zig.md`, `UPSTREAM.md` | the packaging-aware provenance gate, the CI that runs it, the `.devenv`/`.direnv`/`result` and `*.so.*`/`.dll`/`.dylib` ignore entries, and the records describing all of it |
| Comment and SPDX only | `zig/sources.zig`, `include/gmp_all.h`, `zig/BigInt.zig` | an SPDX line and doc prose: three paragraphs on the `mpn/generic` files intentionally absent from `sources.zig`, the `<obstack.h>` gate paragraph in `gmp_all.h` (`gmp-h.in:275-281` declines the obstack prototypes until `_OBSTACK_H` is defined), and one corrected identifier in a `BigInt.zig` doc comment (`c.mp_set_memory_functions` to `c.__gmp_set_memory_functions`, the name the library exports). No `pub const` list, no declaration and no executable statement differs |

**The 14 paths only the supplier has:** `runtime/` (six files: `generate.zig`,
`graph.zig`, `loader.zig`, `library.zig`, `sync.h`, `sync.c`),
`zig/provider.zig`, `zig/test/bootstrap.zig`, `zig/test/alloc_probe.zig`,
`FORK-LICENSE.md`, `README.md`, `README.upstream.md`, `UPSTREAM.sha256`,
`package.nix`, `flake.nix`, `flake.lock`, `devenv.nix`, `devenv.yaml`, `.envrc`.

This is a source comparison, not a build or runtime result, and it certifies
nothing about either package's behaviour. Re-run it after each supplier update
and record the new result. No build or gate compares the two source trees.

To re-sync, take the snapshot from the verified GMP package again and re-run
that `diff`; the item in the rebase list below says what has to move with the
graph when it does. A rebase of GMP's fork does not re-verify the archive
digest: read `gmp/UPSTREAM.md` for that.

The CI licence-and-provenance job compares `vendor/gmp` against this section
and fails if the four licence files or the recorded digest are missing. It does
not run the `diff` above and does not certify snapshot identity.

### What this fork now maintains inside the snapshot

Since 2026-10-04 the snapshot is no longer purely a copy. Three files inside
`vendor/gmp` carry fork-authored edits made by this fork, all of them part of
GMP's *build graph* rather than GMP's library:

| File | What this fork changed there |
| --- | --- |
| `vendor/gmp/build.zig` | a `-Dlinkage=static\|dynamic` option declared with `b.option` (`vendor/gmp/build.zig:81-85`), defaulting to the `.static` that was previously hard-coded; the `version` derived from `sharedLibraryVersion(b)` on the dynamic route (`:247`); `paramsFor(target, optimize, linkage == .dynamic)` threading it into the generated `gmp.h`; `linkage` passed through `makeLibrary`, `makeBundledLibrary` and `addTargetCheck`; `Module.pic` true on the dynamic route and null on the static one (`:255`); and a `@embedFile("Makefile.am")` feeding `sharedLibraryVersion`/`libtoolNumber`, which read `LIBGMP_LT_CURRENT/REVISION/AGE` (`Makefile.am:107-109`, reaching `-version-info` at `Makefile.am:294-295`) |
| `vendor/gmp/zig/config_gen.zig` | a `Params.libgmp_dll` field (`:69`), a third `paramsFor` parameter, and the `LIBGMP_DLL` substitution rendering `if (p.libgmp_dll) "1" else "0"` at `:450`. Plus an SPDX header this fork added |
| `vendor/gmp/build.zig.zon` | `"Makefile.am"` at `:51` in `.paths`, because `build.zig` embeds it and a package fetched without it could not resolve the embed. Its SPDX line **converges**: the supplier's carries one too. Its header text does not: it names `mpfr/FORK-LICENSE.md` and records that the snapshot carries no GMP `FORK-LICENSE.md` of its own, which is a fact about the snapshot that a copy would make false |
| — | **nothing else, and that is now a much larger statement than it was.** Of the 26 differing paths in the comparison above, only these three are this fork's edits; every other one is the supplier having moved ahead. No C source, no public header, no licence file, no data file and no test file in the snapshot was ever touched |

Two of the three rows above describe differences that have since **converged**
on the supplier's side, which is why a plain copy no longer breaks what they
used to protect. The supplier declares the same `-Dlinkage` option
(`gmp/build.zig:115-126`) and the same `pic` expression (`:552`); its
`zig/config_gen.zig` carries the same `libgmp_dll` field (`:87`), the same
`paramsFor` parameter (`:216`) and the same substitution (`:528`). The
re-sync item below says what that changes.

Three points need a note each, because a bare `diff` reports them as
differences without saying which way they should move.

**The `.pic` field converges rather than diverges.** Both
`vendor/gmp/build.zig:255` and the supplier's `gmp/build.zig:552` read
`.pic = if (linkage == .dynamic) true else null`, and for the same reason:
`std.Build.Module.CreateOptions.pic` is `?bool`, so `null` emits no flag at all
and preserves the static artefact this package has always built, where `false`
would emit `-fno-PIC` and change it. MPFR's own library module carries the same
field at `build.zig:912`. A future `diff` showing this line on both sides is the
snapshot catching up, not drifting.

**One intentional difference of shape is expected to persist.** The snapshot
derives the shared library's version from the embedded `Makefile.am`
(`sharedLibraryVersion`/`libtoolNumber`, `vendor/gmp/build.zig:598-609`, giving
`major = CURRENT - AGE = 10`); the supplier hardcodes the same three numbers as
one `std.SemanticVersion` literal at `gmp/build.zig:88`. The two positions are
defensible and different: a package is pinned by its own `version`, whereas a
vendored snapshot is re-importable material, and a stale literal in one is
silent. This fork keeps the derivation. MPFR's own soname is derived the same
way, from `libmpfr_la_LDFLAGS` at `src/Makefile.am:106` through the
`assignmentWords` helper the build already used for `libmpfr_la_SOURCES`
(`build.zig:355`, `:1318`), so `libmpfr.so.6.2.2` with soname `libmpfr.so.6` and
`libgmp.so.10.5.0` with soname `libgmp.so.10` are both arithmetic on upstream's
own numbers, and neither is a typed-in constant.

**The SPDX headers on two of those three files are a deliberate divergence, and
the decision is to keep them.** `vendor/gmp/build.zig` and
`vendor/gmp/zig/config_gen.zig` carry
`SPDX-License-Identifier: LGPL-3.0-or-later` in this snapshot; the supplier's
copies of those two files carry no SPDX line at all.
`vendor/gmp/build.zig.zon` carries one on both sides, so that one converges.

Keeping them is the right call, for the same reason the header is there: those
files are maintained by this fork and are covered by `FORK-LICENSE.md`, which
requires every further fork-authored build file to carry the identifier. Dropping
the line would match the supplier byte-for-byte at the cost of leaving a
fork-authored file with no identifier, which is the one outcome both licences
disallow. A re-sync must therefore choose deliberately in both directions: carry
the header across, or record the removal as a licence decision rather than as
drift.

That is a deliberate, recorded divergence inside a vendored tree, not drift:

- `vendor/gmp`'s own `NOTICE.md` says "No upstream source file was modified", and
  that statement is still true. None of the three files in the table above is an
  upstream GMP source file: two are the GMP fork's build graph and the third is
  its manifest.
- GMP's four `COPYING*` files remain the ones upstream shipped, with the digests
  in `NOTICE.md`.
- The `diff -rq` comparison above therefore reports a difference in these files
  that this fork intends. A later comparison must name the divergence rather
  than report it as unexplained, and **a re-sync from the supplier must not
  silently revert it**. What a copy of `build.zig` would revert is no longer
  the `-Dlinkage` option or the `LIBGMP_DLL` substitution - the supplier has
  both, so those converge and a copy keeps them. What it would revert is the
  SPDX headers, the `Makefile.am`-derived version numbers and the `.paths`
  header, all three of which travel nowhere with a graph copy that does not
  also carry the closure the re-sync item below lists.

### Comment-only differences, and which way they move

Three paths differ from the supplier in a way that changes nothing that
compiles. They are listed separately because they belong to a different
re-sync decision from the build-graph differences above, and because the
direction is the opposite of what this section used to claim: **the supplier
grew these and the snapshot is behind**, so taking the supplier's version
moves the two files the same way every other path moves.

| File | What the supplier added | Effect |
| --- | --- | --- |
| `vendor/gmp/zig/sources.zig` | an SPDX line and three doc paragraphs: which `mpn/generic` files are intentionally absent and why, and that the set is the same for both linkages | none. Every `pub const` source list is identical, so the snapshot compiles the same translation units as the supplier |
| `vendor/gmp/include/gmp_all.h` | an SPDX line and a paragraph on the `<obstack.h>` gate (`gmp-h.in:275-281`) | none. Comment-only, and the snapshot gains 31 lines with no declaration changed |
| `vendor/gmp/zig/BigInt.zig` | one corrected identifier in a doc comment | none. One line of prose |

None of the three is a build-graph divergence and none is a native GMP source
change. A re-sync should take the supplier's version of all three and may
report the result as comment-only; it should not treat them as findings and
must not carry a divergence forward for them.

**The snapshot is not a current copy of the supplier, and this section must not
be read as if it were.** The comparison above lists what actually differs on
2026-10-04: 26 paths and 14 absent ones, against the three fork-authored files
and two comment-only ones this section used to name. The gap is the supplier's
own work after the 2026-10-01 import, and it is expected. Nothing GMP itself
ships changed with it.

Three consequences, and the third is not benign:

- Harmless, and simply true: the supplier's work after the import is not in
  the snapshot. That is what a snapshot of a point in time is.
- Harmless, and worth saying out loud, because it is what makes the drift
  tolerable today: **MPFR's own routes do not reach any of it.**
  `gmpDependency` forwards only `target`, `optimize` and `linkage` to the
  snapshot (`build.zig:1020-1044`) and never forwards `-Druntime`, because
  MPFR's runtime route is its own. `runtime/graph.zig` generates one dispatch
  carrying MPFR's and GMP's symbols together from the translated
  `fork/mpfr_all.h` (`runtime/graph.zig:15`, `:154-155`) and imports nothing
  from the vendored package's `runtime/`, so a snapshot with no `runtime/`
  costs MPFR nothing.
- Not benign, and the reason the re-sync item below is in that order: a re-sync
  that copies the supplier's `build.zig` without its closure does not degrade
  the snapshot, it breaks it. The copied graph's first import is
  `@import("runtime/graph.zig")`, which the snapshot does not carry and its
  `.paths` does not list.

The consequence for provenance is narrow: `vendor/gmp` is no longer byte-equal
to the supplier's tree, so no gate should treat a `diff -rq` result as the
snapshot's identity. The snapshot's own `tools/provenance_gate.sh` is stale for
the same reason; it is not reachable from MPFR's step graph, so its staleness
costs nothing at build or gate time, but it must not be cited as if it were
checking this repository.

## The preserved upstream README

MPFR's `README` is upstream's, not this fork's, and it must never be described
as fork-authored text. It is kept twice on purpose:

| Path | Status |
| --- | --- |
| `README` | upstream's file at tag `4.2.2`, byte-identical to the pinned commit |
| `README.upstream.md` | a byte-for-byte copy of the same file |

| Field | Value |
| --- | --- |
| SHA-256 | `74e733d2cfa1a6f4e6530326ed460f13ac9e4a5d79bb0f682ab67db2c9dc4d5b` |
| Size | 3333 bytes |
| Source | `README` at commit `eaa57b856d814af32f97d5e5eb129fb986235323` |

`README.md` is the fork's own canonical README and is fork work; see
`FORK-LICENSE.md`. It is a different file from `README.upstream.md` and does not
replace it.

## Every carried upstream byte, per file

`UPSTREAM-BASELINE.sha256` is the machine-checkable record of every upstream byte
this package carries: one SHA-256 per path, with the pin, the derivation, the
counts and the one divergence stated in its own header. It is verified from the
repository root by

```sh
./check-upstream-baseline.sh
```

which the `licence-and-provenance` CI job runs. The gate checks five things:
every carried upstream file still hashes to the pin; every difference from the
pin is one the record declares; the counts in the record are the counts in its
manifest; no carried path is left unaccounted for; and the fork's verbatim copy
still matches the file it copies. `sha256sum -c UPSTREAM-BASELINE.sha256` is a
valid but narrower check, because it says nothing about whether the path set is
complete.

| where the 2810 upstream paths are | |
| --- | --- |
| GNU MPFR 4.2.2 at `eaa57b85`, 654 paths | `src/` 291, `tests/` 258, `tools/` 48, root files 23, `doc/` 18, `examples/` 7, `tune/` 5, `m4/` 2, `other/` 2 |
| GNU MP 6.3.0 under `vendor/gmp/`, 2156 paths | `mpn/` 1341, `tests/` 251, `mpz/` 166, `mpf/` 71, root files 61, `tune/` 61, `demos/` 47, `mini-gmp/` 45, `mpq/` 34, `printf/` 23, `rand/` 16, `doc/` 15, `cxx/` 14, `scanf/` 11 |

2809 of those paths are byte-identical to their pin. The one that is not is
`.gitignore`, recorded in the baseline as a divergence with both digests: the
carried file is upstream's 440 bytes followed by 931 bytes this fork added.

Every digest was derived from the pinned upstream sources, not from this tree:
MPFR from `git fetch --depth 1 origin refs/tags/4.2.2` at the commit above, and
GMP from `gmp-6.3.0.tar.xz`, digest
`a3c2b80201b89e68616f4ad30bc66aee4927c3ce50e33929ca819d5c43538898`, fetched from
`gmplib.org` and `ftp.gnu.org`, which served identical bytes. The record's header
carries the exact commands. The MPFR release archive named above was fetched as a
cross-check and is not the source of any digest: it is a `make dist` product with
572 files rather than the 654 the tag tracks, so the Git tag remains the pin.

Three things are deliberately outside the baseline, and the gate holds each of
them. Upstream's `README` is in the baseline under its upstream name, and
`README.upstream.md` is checked to be byte-identical to it. This fork's own 72
files are listed as fork work, so that a path which is neither upstream nor
declared is a failure rather than an unnoticed gap. Build outputs and `.git` are
not carried bytes. What the baseline deliberately cannot check offline is that
`.gitignore` still keeps every upstream line; that needs upstream's bytes, and
the CI job's own `git diff --numstat` step is what proves it.

## Licence

MPFR is under the GNU Lesser General Public License, version 3 or later. Both
`COPYING` (GPL-3) and `COPYING.LESSER` (LGPL-3) are preserved unchanged, as are
the per-file notices in `src/`. The tree also carries GPL-3-or-later tooling,
GPL-2-or-later test data and the FDL-licensed manual; `NOTICE.md` lists every
such file with its evidence and explains why this fork is private, but that does
not remove any upstream obligation.

The Zig code and packaging this fork adds (`build.zig`, `build.zig.zon`,
`zig/`, `root.zig`, `fork/`, `consumer/`, `.github/workflows/`, `package.nix`,
`flake.nix`, `devenv.nix`, `devenv.yaml`, `.envrc` and the Markdown records) is
fork work and is not covered by the LGPL. The owner authorized a per-project
licence for those additions matching the primary upstream terms where
appropriate, and the grant that follows from that authorization is
**LGPL-3.0-or-later**, recorded with its full file inventory in
`FORK-LICENSE.md`. The notice inside each fork file still says which parts of it
mirror upstream's; neither the per-file notice nor the grant replaces the other.

`vendor/gmp` is not covered by that grant. It is a snapshot of a separate GMP
package and keeps GMP's own dual LGPL-3.0-or-later OR GPL-2.0-or-later offer with
all four of its `COPYING*` files; `NOTICE.md` is the inventory.

## Nix packaging and upstream identity

`package.nix`, `flake.nix`, `devenv.nix`, `devenv.yaml` and `.envrc` are fork
files and change no upstream bytes. Three things they deliberately do not do:

- they do not import a workspace sibling. `package.nix` builds from `./.`, and
  GMP comes from the in-tree `vendor/gmp` snapshot, so the derivation is
  standalone and needs no `../gmp`.
- they do not fetch a source. There is no `fetchFromGitHub`, no `fetchurl` and no
  hash to invent; the source is this repository.
- they do not restate the C build. `build.zig` already derives libmpfr's source
  list and every configuration macro from the target, and a second copy of that
  logic in a derivation would be a version that the test suite never exercises.

The nixpkgs revisions are named in `flake.nix` and `devenv.yaml`. The resolved
node sets belong in `flake.lock` and `devenv.lock`, which the workspace's lock
owner writes rather than this record. As of 2026-10-04 the two are in different
states, and the difference is deliberate rather than an omission:

- `flake.lock` **is** present at this repository's root, and `build.zig.zon`'s
  `.paths` **does** list it, immediately after `flake.nix`. A fetched package
  therefore carries the resolved node set and not only the unpinned
  `flake.nix`, which would otherwise describe a revision without naming a hash.
  The entry follows the file: naming a lock that is absent is a package
  resolution failure, not a warning.
- `devenv.lock` **is not** present at this repository's root, and `.paths`
  correctly does not list it. `devenv.yaml` pins the nixpkgs input, so the
  shell resolves without one. The moment that file is written, `.paths` gains
  the name in the same step, for the reason in the bullet above.


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
   and re-read the comparison above: a rebase of MPFR does not re-verify the
   provider. A re-sync is not a file copy, and the order below is the part that
   breaks things. **Take the supplier's build graph and its closure together,
   or take neither.** The supplier's `build.zig` opens with
   `const runtime = @import("runtime/graph.zig");` (`gmp/build.zig:66`) and
   calls `runtime.createModule` and `runtime.createCoreModule` on both routes;
   the snapshot has no `runtime/` directory at all. Copying `build.zig` alone
   therefore does not degrade the snapshot, it fails, and the failure is
   invisible in a local tree because the tree that still builds is the one
   that was not copied. What must move with the graph, in one step:
   - `runtime/` - six files: `generate.zig`, `graph.zig`, `loader.zig`,
     `library.zig`, `sync.h`, `sync.c`.
   - `zig/provider.zig`, which the supplier's `root.zig:124` imports.
   - `"runtime"` in `vendor/gmp/build.zig.zon`'s `.paths`
     (`gmp/build.zig.zon:29`). A `.paths` entry for a directory the snapshot
     does not ship is a package resolution failure, not a warning, and the
     copied `build.zig` imports that directory whether or not `-Druntime` is
     ever passed.
   - the test-side closure, or the copied `zig/test/root.zig` does not compile:
     `zig/test/bootstrap.zig` and `zig/test/alloc_probe.zig`, together with the
     `ensureLoaded()` call at the head of every test in the copied files.
   - the call sites the supplier's signatures changed underneath:
     `makeLibrary` (`gmp/build.zig:473-483`), `needsBothLoaders`,
     `addInstallFacade`, `addTargetCheck` and `addTests`. The snapshot's
     `makeLibrary` takes seven parameters (`vendor/gmp/build.zig:214-222`) and
     the supplier's takes nine, with two of them new (`system_linkage` and
     `runtime_loaded`), so a half-copied graph does not compile.

   Two premises in the record this item replaces were false as of 2026-10-04,
   and a copy would now destroy the thing they protected rather than preserve
   it:
   - **`-Dlinkage` is no longer a divergence.** The supplier declares the same
     option at `gmp/build.zig:115-126` and the same `pic` expression at `:552`,
     for the same reasons. Copying the supplier's `build.zig` no longer
     removes the option MPFR forwards; it replaces a 735-line graph with a
     1095-line one and brings the closure above with it.
   - **`Params.libgmp_dll` is no longer a divergence either.** The supplier's
     `zig/config_gen.zig` carries the field (`:87`), the `paramsFor` parameter
     (`:216`) and the `LIBGMP_DLL` substitution (`:528`). A copy no longer puts
     `__GMP_LIBGMP_DLL` back to a fixed `0` and un-declares the exports at
     `src/mpfr.h:321-331`.

   What is still this fork's, and what a copy would silently revert:
   - the SPDX headers on `vendor/gmp/build.zig` and
     `vendor/gmp/zig/config_gen.zig`. The supplier's copies of those two files
     carry no SPDX line; the snapshot's do, because they are fork-authored files
     under `FORK-LICENSE.md`. Keep them, or record the removal as a licence
     decision - never let a file copy drop a fork-authored file's licence
     identifier without anyone deciding to. `vendor/gmp/build.zig.zon` carries
     one on both sides and converges, but its header text is a statement about
     the snapshot and does not travel with the SPDX line.
   - the version derivation. Keep the `@embedFile("Makefile.am")` arithmetic
     (`vendor/gmp/build.zig:598-609`) over the supplier's literal
     (`gmp/build.zig:88`), and keep `"Makefile.am"` in `.paths`
     (`vendor/gmp/build.zig.zon:51`) for the embed, whatever the copied
     `build.zig` does or does not need it for.
   - `vendor/gmp/zig/sources.zig`, `vendor/gmp/include/gmp_all.h` and
     `vendor/gmp/zig/BigInt.zig` carry no divergence to preserve. Take the
     supplier's versions, record the result as comment-only, and do not treat
     them as findings.
   - the GMP library itself: no C source, no public header, no licence file, no
     data file and no test file was touched, so a re-sync must not report any of
     them as differing.
   - The 26 differing and 14 absent paths in the comparison above are the
     supplier moving ahead, not drift this fork introduced. Re-run that
     comparison after the sync and record what is left: a re-sync is finished
     when the remainder is only the divergences this item lists.
7. `src/Makefile.am:106`. `libmpfr_la_LDFLAGS` carries
   `-version-info 8:2:2`, from which the shared route's soname is derived
   (CURRENT-AGE = 6, so `libmpfr.so.6`, real name `libmpfr.so.6.2.2`). A rebase
   that changes those three numbers changes the soname a consumer links
   against. `tools/ck-version-info` is what upstream uses to keep them in step
   with the release series.
8. `mpfr.pc.in`. Its `Libs` line is preserved verbatim and installed to
   `$out/lib/pkgconfig/mpfr.pc`; a rebase that changes it changes the installed
   link metadata.
9. `README.upstream.md`. It is a byte-for-byte copy of upstream's `README`. A
   rebase replaces `README` and must replace the copy with it, and update the
   digest recorded above. Two files with the same content and two different
   digests is the failure this item exists to prevent.
10. `.github/workflows/verify.yml` and the pinned commit it compares against. The
    provenance job's `git diff` gate names the commit explicitly; a rebase to a
    newer tag must update the tag, the commit in `UPSTREAM.md` and the CI gate
    together.
11. `UPSTREAM-BASELINE.sha256`. Every digest in it was taken from the pinned
    upstream sources, so a rebase invalidates all of them at once. Re-derive it
    the way its own header says -- `git fetch --depth 1` the new tag, `git
    archive` it, and re-hash -- rather than editing the digests in place. Run
    `./check-upstream-baseline.sh` afterwards, and expect it to name every
    manifest line, because a changed tree is exactly what it exists to report.

## What this fork does not carry over

Nothing is deleted. Upstream's autotools build is left in place but unused: this
fork compiles libmpfr with Zig and never invokes `configure`, `make`,
`autoreconf` or CMake. `PATCHES` is empty at 4.2.2, so `mpfr_get_patches()`
returns an empty string.
