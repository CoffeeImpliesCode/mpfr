# Licence of the files this fork adds

GNU MPFR is licensed GNU LGPL version 3 or later, and the vendored GMP provider
is LGPL-3-or-later or GPL-2-or-later at the recipient's option. **This file
covers only the files added by this fork.** It does not relicense, replace or
narrow a single upstream or vendored term; `NOTICE.md` remains the inventory of
what is licensed by what.

## The grant

Files added by this fork are licensed under the **GNU Lesser General Public
License, version 3 or later**.

SPDX identifier: `LGPL-3.0-or-later`

The authoritative text is already in this repository, verbatim and unmodified
from upstream tag `4.2.2`:

| File | What it is |
| --- | --- |
| `COPYING` | GNU General Public License, version 3, 29 June 2007 — the licence text the LGPL refers to |
| `COPYING.LESSER` | GNU Lesser General Public License, version 3, 29 June 2007 — the additional permissions on those terms |

Those two files are the whole grant; a second copy here would only give the two
copies somewhere to disagree.

## Why this identifier

The owner authorized per-project licensing for fork-authored additions, matching
the primary upstream terms where appropriate. MPFR's own terms are
LGPL-3-or-later (`src/mpfr.h:7-20`). Upstream's dual offer to a recipient does not
restrict what the owner may choose for independently authored work.

Earlier records describing fork additions as "no licence asserted" described the
state before that authorization and are superseded.

## Who holds the copyright

This repository is a private downstream fork. The fork-authored files are the
work of whoever owns and maintains that downstream repository.

No personal copyright identity is asserted, because none was supplied and none
may be invented. Fork additions are not attributed to the Free Software
Foundation or to INRIA's Pascaline and Caramba projects, who hold the upstream
files listed in `NOTICE.md`; and no endorsement, review or contribution by
upstream is claimed.

## Files covered by this grant

Every path below is authored by this fork and is licensed as stated above.

| Path | What it is |
| --- | --- |
| `build.zig`, `build.zig.zon` | the Zig build graph and the package manifest |
| `zig/config_gen.zig` | the per-target configure facts the build needs |
| `root.zig` | the typed Zig facade |
| `fork/mpfr_all.h` | the aggregate header handed to `translate-c` |
| `fork/tests/*.zig` | the behaviour suite and its support and surface files |
| `fork/example/main.zig` | the runnable example behind `run` and `smoke` |
| `consumer/build.zig`, `consumer/build.zig.zon`, `consumer/src/main.zig` | the downstream consumer package |
| `runtime/graph.zig`, `runtime/generate.zig`, `runtime/library.zig`, `runtime/loader.zig`, `runtime/sync.h`, `runtime/sync.c` | the runtime-loading route: the build-time dispatch generator, this SDK's loader binding, the reusable loader core that binding is built on, and the synchronization shim. `sync.c` is C because its symbols are weak and process-global by design (`runtime/sync.c:3-4`), and `runtime/graph.zig:214-218` compiles it into the `-Druntime=true` dispatch under this SDK's own prefix, `mpfr_rt` (`runtime/graph.zig:58`), so two SDKs in one process cannot collide |
| `.github/workflows/verify.yml` | this repository's own CI |
| `README.md`, `README.zig.md` | this fork's documentation |
| `README.upstream.md` | **not fork work.** Upstream's `README` copied byte-for-byte, kept here so it is never mistaken for fork text. It carries MPFR's own terms and is outside this grant |
| `UPSTREAM.md`, `CHANGELOG.md`, `NOTICE.md`, `FORK-NOTES.md`, `FORK-LICENSE.md` | this fork's provenance and licence records |
| `UPSTREAM-BASELINE.sha256`, `check-upstream-baseline.sh` | the per-file SHA-256 baseline for every upstream byte this package carries, and the gate that verifies it from the package root |
| `package.nix`, `flake.nix`, `flake.lock`, `devenv.nix`, `devenv.yaml`, `.envrc` | this fork's Nix packaging and development environment, and the resolved-input lock the workspace integration owner wrote |
| `.gitignore`, and only the nineteen lines this fork appended to it | the additive change to one upstream file. Upstream's 440 bytes are kept byte-for-byte, nothing is removed, and the appended block is five ignore entries with their reasoning; see `NOTICE.md`, "The one upstream file the fork touches" |
| `vendor/gmp/build.zig`, `vendor/gmp/build.zig.zon`, `vendor/gmp/zig/config_gen.zig` | the GMP fork's build graph, maintained **by this fork** inside the vendored snapshot so GMP's linkage can follow MPFR's. See the note under "Files this grant does not cover"; `UPSTREAM.md` records the divergence and why a re-sync must not revert it |

## Notice for new files

Any further fork-authored source or build file should carry:

```
SPDX-License-Identifier: LGPL-3.0-or-later
```

as its own comment, or as the first line of the `.nix` `#` / YAML `#` comment
block, above any other comment. The per-file licence headers already inside
`build.zig`, `root.zig` and the test files record which *upstream* lines those
files mirror; those headers and this grant coexist and neither replaces the
other.

### Files that carry it today

Nineteen of the files above do. Eighteen name the identifier on their first
line:

- `build.zig`, `build.zig.zon`, `root.zig`
- `consumer/src/main.zig`, `fork/example/main.zig`
- all six files under `runtime/`
- `devenv.nix`, `flake.nix`, `package.nix`
- `.github/workflows/verify.yml`
- `vendor/gmp/build.zig`, `vendor/gmp/build.zig.zon`,
  `vendor/gmp/zig/config_gen.zig`

and `check-upstream-baseline.sh` names it in its own comment block below the
shebang, the one place it cannot be the file's first line.

The two `vendor/gmp` files whose SPDX lines the supplier package lacks are kept
deliberately; dropping them would leave a fork-authored file with no identifier.
`UPSTREAM.md` records that decision and the re-sync rule. `flake.lock` is the
other covered file that cannot carry the identifier at all, for a different
reason: Nix writes it as JSON and refuses to parse a file that carries anything
else. The remaining fork-authored files carry no header, which is a choice
rather than an omission.

## Files this grant does not cover

- **Everything upstream.** `src/`, `doc/`, `tests/`, `tools/`, `tune/`, `m4/`,
  `other/`, `examples/`, `README`, `INSTALL`, `NEWS`, `ChangeLog`, `COPYING` and
  `COPYING.LESSER` keep their own terms. `NOTICE.md` lists the ones that are not
  LGPL: GPL-3-or-later tooling, GPL-2-or-later test data, and an FDL-1.3-or-later
  manual.
- **`vendor/gmp`, except the three build-graph files named in the table above.**
  The rest of that directory is a snapshot of a separate GMP package with its own
  `NOTICE.md` and its own four `COPYING*` files, and it keeps GMP's dual licence
  exactly as that snapshot records it. Nothing in this file reaches into it, and
  the three exceptions are covered because this fork maintains them and says so
  at the top of each one.
- **`fork/mpfr_all.h`'s includes.** A fork file that `#include`s upstream's
  `mpfr.h` and `mpf2mpfr.h` does not relicense them.

## Obligations that travel with any distribution

Whatever channel a copy travels over — this private repository, a Nix output, or
an archive — the following stay true, and this file does not weaken them:

- the GPL-3 and LGPL-3 texts travel with the source (`COPYING`,
  `COPYING.LESSER`);
- recipients receive the complete corresponding source of the library, including
  the vendored GMP snapshot the default build links;
- recipients keep the ability to relink against a modified library. On the
  static variant that means `libmpfr.a` beside `libgmp.a`; on the shared variant
  `libmpfr.so` records a real dependency on the shared `libgmp` installed beside
  it, so relocating one without the other is not a closed installation;
- every upstream copyright notice, per-file exception and test/data licence in
  `NOTICE.md` survives unchanged.

This is a record of the terms that apply, not legal advice about a particular
distribution. A private repository is an access decision, not a licence
decision.

## Trademarks

"MPFR", "GNU MPFR", "GMP" and "GNU MP" name the upstream projects. This fork
claims no trademark in them and is not endorsed by either project.