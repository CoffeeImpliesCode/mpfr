# Changelog

- Corrected system-provider flags to `-fsys=gmp` and `-fsys=mpfr`, including runtime-loading configurations.

Changes from GNU MPFR 4.2.2.

- Port to Zig 0.17.0.
- Updated devenv tasks to run from the package root and use external caches and install prefixes.
- Added `flake.lock` to the package paths so fetched packages carry the pinned Nix inputs.
- Installed `gmp.pc` beside `mpfr.pc`; `mpfr.pc` keeps `Requires` empty and retains its `-lgmp` link entry.
- Added standalone Nix packaging with static and shared package outputs.
- Added `-Dlinkage=static|dynamic`; static remains the default, and the shared MPFR output includes its shared GMP dependency.
- Added explicit system-library modes for MPFR and GMP.
- Added runtime loading with `-Druntime=true` and an explicit provider selected through `load`.
- Added a Zig package with the `mpfr` module, `mpfr` artifact, translated `c` module and an owning `Float` facade.
- Enabled MPFR's `intmax_t` entry points in the compiled library and translated C interface.
- Changed `Float.parseWhole` to return `ConversionError!void`; use `parsePrefix` to obtain MPFR's ternary result.
- Renamed the `Prefix` outcome field to `ternary` and gave all `Flags` fields a false default.
- `Float.toDigits(0)` now passes zero to `mpfr_get_str` for MPFR's default digit selection.
- Restricted `ConversionError` to `InvalidNumber` and `InvalidBase`; GMP allocation failures are not recoverable through this error set.
