# Licence of the files this fork adds

SPDX-License-Identifier: LGPL-3.0-or-later

GNU MPFR is LGPL-3-or-later. The separate GMP dependency is LGPL-3-or-later or GPL-2-or-later, at the recipient's option. This grant covers only fork additions; upstream and dependency terms are unchanged. `NOTICE.md` lists file licences.

## The grant

Files added by this fork are licensed under the **GNU Lesser General Public License, version 3 or later**.

The authoritative text is already in this repository, verbatim and unmodified from upstream tag `4.2.2`:

| File | What it is |
| --- | --- |
| `COPYING` | GNU General Public License, version 3, 29 June 2007 — the licence text the LGPL refers to |
| `COPYING.LESSER` | GNU Lesser General Public License, version 3, 29 June 2007 — the additional permissions on those terms |

Those two files are the complete grant.

## Copyright and attribution

Fork-authored files are the work of this private downstream repository's owner and maintainers. No personal copyright identity was supplied or is asserted. They are not attributed to the Free Software Foundation or INRIA's Pascaline and Caramba projects; no upstream endorsement, review, or contribution is claimed.

## Files covered by this grant

Every path below is authored by this fork and is licensed as stated above.

| Path | What it is |
| --- | --- |
| `build.zig`, `build.zig.zon` | Zig build graph and package manifest |
| `zig/config_gen.zig` | Per-target configure facts |
| `root.zig` | Typed Zig facade |
| `fork/mpfr_all.h` | Aggregate header handed to `translate-c` |
| `fork/tests/*.zig` | Behaviour suite and support files |
| `fork/example/main.zig` | Runnable example behind `run` and `smoke` |
| `consumer/build.zig`, `consumer/build.zig.zon`, `consumer/src/main.zig` | Downstream consumer package |
| `runtime/graph.zig`, `runtime/generate.zig`, `runtime/library.zig`, `runtime/loader.zig`, `runtime/sync.h`, `runtime/sync.c` | Runtime-loading route and synchronization shim; `sync.c` uses weak process-global symbols compiled under the SDK prefix `mpfr_rt` |
| `README.md`, `README.zig.md` | Fork documentation |
| `UPSTREAM.md`, `CHANGELOG.md`, `NOTICE.md`, `FORK-NOTES.md`, `FORK-LICENSE.md` | Fork provenance and licence records |
| `UPSTREAM-BASELINE.sha256`, `check-upstream-baseline.sh` | Upstream-byte baseline and its checker |
| `package.nix`, `flake.nix`, `flake.lock`, `devenv.nix`, `devenv.yaml`, `.envrc` | Nix packaging and development environment |
| `.gitignore` | Only the nineteen lines appended by this fork; upstream's 440 bytes remain unchanged |

## Files this grant does not cover

- **Upstream files:** `src/`, `doc/`, `tests/`, `tools/`, `tune/`, `m4/`, `other/`, `examples/`, `README`, `INSTALL`, `NEWS`, `ChangeLog`, `COPYING`, and `COPYING.LESSER` keep their own terms. `NOTICE.md` identifies GPL-3-or-later tooling, GPL-2-or-later test data, and the FDL-1.3-or-later manual.
- **`README.upstream.md`:** upstream's `README`, copied byte-for-byte; it is outside this grant and carries MPFR's terms.
- **GMP dependency:** the separate package is governed by its own `NOTICE.md`, fork grant, and four `COPYING*` files. This grant does not cover it.
- **Includes of `fork/mpfr_all.h`:** including upstream `mpfr.h` or `mpf2mpfr.h` does not relicense those files.

## Distribution

Distributions include `COPYING`, `COPYING.LESSER`, and complete corresponding source, including the GMP dependency. Preserve the ability to relink: the static variant uses `libmpfr.a` with `libgmp.a`; the shared `libmpfr.so` has a real dependency on shared `libgmp` installed beside it. Preserve every upstream copyright notice, per-file exception, and test/data licence listed in `NOTICE.md`.

## Trademarks

“MPFR,” “GNU MPFR,” “GMP,” and “GNU MP” name the upstream projects. This fork claims no trademark in them and is not endorsed by either project.
