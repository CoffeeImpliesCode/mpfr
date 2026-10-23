# Upstream provenance

## GNU MPFR

| Field | Value |
| --- | --- |
| Project | GNU MPFR |
| Canonical upstream | <https://gitlab.inria.fr/mpfr/mpfr.git> |
| Release | 4.2.2; tag `4.2.2` |
| Annotated tag object | `736ef3903ce50fc592268f69b6895c73da6adfb4` |
| Commit | `eaa57b856d814af32f97d5e5eb129fb986235323` |
| Commit date | 2025-03-20 10:15:52 +0100 |
| Release page | <https://www.mpfr.org/mpfr-4.2.2/> |
| Imported paths | 654 |

The source was imported from Git with `git clone https://gitlab.inria.fr/mpfr/mpfr.git` and `git checkout 4.2.2`. The optional archive `https://www.mpfr.org/mpfr-current/mpfr-4.2.2.tar.xz` was not used.

## Vendored GNU MP

| Field | Value |
| --- | --- |
| Project | GNU MP 6.3.0 |
| Snapshot | `vendor/gmp`, copied from this workspace's GMP package on 2026-10-01 |
| Archive | `gmp-6.3.0.tar.xz` |
| Primary URL | <https://gmplib.org/download/gmp/gmp-6.3.0.tar.xz> |
| Mirror URL | <https://ftp.gnu.org/gnu/gmp/gmp-6.3.0.tar.xz> |
| Archive SHA-256 | `a3c2b80201b89e68616f4ad30bc66aee4927c3ce50e33929ca819d5c43538898` |
| Upstream SCM | Mercurial; no commit SHA exists |
| Imported paths | 2156 |

## Carried source identity

The package carries 2810 upstream paths: 654 from GNU MPFR and 2156 from GNU MP. No pinned upstream files were removed. `UPSTREAM-BASELINE.sha256` records one digest per path; 2809 paths match their source. The only upstream-path change is additive in `.gitignore`: the original 440 bytes remain, followed by 19 fork-added lines.

`README.upstream.md` is a byte-for-byte copy of MPFR's upstream `README` at the pinned commit. Its SHA-256 is `74e733d2cfa1a6f4e6530326ed460f13ac9e4a5d79bb0f682ab67db2c9dc4d5b`.

In `vendor/gmp`, `build.zig`, `build.zig.zon` and `zig/config_gen.zig` contain fork-authored build changes. No GMP library source, public header, licence file, test or data file was modified. The imported path counts, digests and `.gitignore` divergence are recorded in `UPSTREAM-BASELINE.sha256`.

## Licence scope

`NOTICE.md` lists upstream per-path terms. GNU MPFR's primary licence is LGPL-3-or-later; GPL-licensed tools and test data and the FDL-licensed manual retain their own terms. Fork-authored files listed in `NOTICE.md` are under the grant in `FORK-LICENSE.md`. The three fork-maintained build files in `vendor/gmp` are included in that grant; the rest of `vendor/gmp` is excluded and retains GNU MP's LGPL-3.0-or-later OR GPL-2.0-or-later terms in its four `COPYING*` files.
