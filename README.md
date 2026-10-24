# MPFR 4.2.2 as a Zig package

This package builds GNU MPFR 4.2.2 and provides a typed Zig facade to its public C API.
It targets Zig 0.17.0 and uses the vendored GMP snapshot by default.

## Source deviations from upstream

- `.gitignore` adds rules for Zig, Nix, devenv and direnv build state.
- No upstream C source, header, test, documentation or licence file is modified.
- Fork-owned additions provide the facade (`root.zig`), C translation header (`fork/mpfr_all.h`), target configuration (`zig/config_gen.zig`), runtime loader and dispatch (`runtime/`), and example, tests and consumer (`fork/`, `consumer/`).

## Build deviations

- `build.zig` replaces autotools for this package and reads the upstream C source list from `src/Makefile.am`.
- The build generates `mparam.h` from `src/mparam_h.in` and `get_patches.c` from `PATCHES` in the build directory.
- Target-derived configuration macros are shared by C compilation and `translate-c`; the build enables the `intmax_t` API and does not enable float128, decimal floating point, mini-GMP or thread-safe caches.
- Vendored GMP and MPFR use matching static or dynamic linkage. The install graph includes the bundled libraries, public headers, pkg-config files and licence records; system-provider routes install only artifacts built by this package.
- Dynamic library versioning comes from MPFR's makefile metadata. The runtime-loaded module dispatches MPFR and GMP symbols through the platform loader; libc remains directly linked.

## Support matrix

The package build graph declares these compile targets:

| Target | Note |
| --- | --- |
| `x86_64-linux-gnu` | |
| `aarch64-linux-gnu` | |
| `aarch64-macos-none` | |
| `x86_64-windows-gnu` | Dynamic DLL export coverage is not guaranteed; static linkage is unaffected. |
| `riscv64-linux-gnu` | |
| `wasm32-wasi` | Vendored GMP uses WASI signal emulation. |

Known boundaries: Hexagon is refused because vendored GMP has no port. NetBSD reaches an Aro `_Pragma` limitation in libc's stdio header; 32-bit OpenBSD reaches an Aro `stddef` conflict, and MIPS64 OpenBSD headers lack libc's expected byte-order macro.

## Consumption

Add the package to a consumer's `build.zig.zon`:

```sh
zig fetch --save git+https://github.com/CoffeeImpliesCode/mpfr#v4.2.2
```

Import the `mpfr` module in `build.zig`:

```zig
const dep = b.dependency("mpfr", .{ .target = target, .optimize = optimize });
exe.root_module.addImport("mpfr", dep.module("mpfr"));
```

The module is named `mpfr`; the library artifact is also named `mpfr` and is available as `dep.artifact("mpfr")`. The module carries the linked route's MPFR/GMP closure.

| Option | Effect |
| --- | --- |
| `-Dlinkage=static` (default) or `dynamic` | Selects the MPFR artifact linkage; bundled GMP uses the same linkage. |
| `-fsys=gmp` | Uses an installed GMP while building MPFR. |
| `-fsys=mpfr` | Uses installed MPFR headers and library; this package builds no MPFR artifact. |
| `-Druntime=true` | Uses runtime dispatch instead of linking MPFR and GMP; call `load` with an explicit provider before other MPFR calls. |
