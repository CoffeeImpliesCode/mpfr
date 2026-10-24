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

## GNU MP dependency

GMP 6.3.0 comes from the separate [CoffeeImpliesCode/gmp package](https://github.com/CoffeeImpliesCode/gmp), pinned in `build.zig.zon` to commit `c124ccbaf2072c438a7e8def5addc628c65ab74e` at tag `v6.3.0`. Its source provenance and licences are recorded in that package.

## Carried source identity

The package carries 654 upstream paths from GNU MPFR. No pinned MPFR files were removed. `UPSTREAM-BASELINE.sha256` records 653 unchanged paths and one divergence. The only upstream-path change is additive in `.gitignore`: the original 440 bytes remain, followed by 19 fork-added lines.

`README.upstream.md` is a byte-for-byte copy of MPFR's upstream `README` at the pinned commit. Its SHA-256 is `74e733d2cfa1a6f4e6530326ed460f13ac9e4a5d79bb0f682ab67db2c9dc4d5b`.

## Licence scope

`NOTICE.md` lists upstream per-path terms. GNU MPFR's primary licence is LGPL-3-or-later; GPL-licensed tools and test data and the FDL-licensed manual retain their own terms. Fork-authored files listed in `NOTICE.md` are under the grant in `FORK-LICENSE.md`. The separate GMP dependency retains its LGPL-3.0-or-later OR GPL-2.0-or-later terms and its own fork grant.
