# Fork notes

## Source changes

| File | Change and reason |
| --- | --- |
| `.gitignore` | Adds ignores for `/.zig-cache/`, `/zig-out/`, `/result`, `/.devenv*`, and `/.direnv*` so local build state stays out of source changes. |

`.gitignore` is the only changed upstream file; no upstream C source, public header, test, documentation, or licence file is modified.

### Fork-owned source

| File | Change and reason |
| --- | --- |
| `root.zig` | Adds an owned Zig facade over the C API; it uses real C entry points for macro-backed operations and mirrors only predicates without function equivalents. |
| `fork/mpfr_all.h` | Includes `stdint.h` and `stdio.h`, then enables `MPFR_USE_INTMAX_T` so translation exposes the same intmax and stream API as the compiled library. |
| `zig/config_gen.zig` | Derives configuration macros from the target so translation and C compilation agree. |
| `runtime/generate.zig` | Builds the dispatch from translated declarations, routing provider symbols by prefix instead of maintaining a second symbol list. |
| `runtime/graph.zig` | Wires the generated dispatch and loader into the runtime-loaded module. |
| `runtime/loader.zig` | Adds a process-wide loader that publishes complete provider tables and allows retry after a failed load. |
| `runtime/library.zig` | Checks GMP limb width and enabled MPFR features before accepting the translated provider ABI. |
| `fork/example/main.zig`, `fork/tests/`, `consumer/src/main.zig` | Add an example, facade tests, and a dependency example; the lifetime test compares translated and linked version identity. |

## Build graph

- `build.zig` replaces autotools for the package build and reads MPFR's C source list from `src/Makefile.am`; missing source-list assignments are errors, not silent omissions.
- The graph copies `src/mparam_h.in` to the generated `mparam.h` because it has no substitutions; it reproduces `tools/get_patches.sh` in Zig to generate `get_patches.c` from `PATCHES`.
- Generated units compile from the build directory. The source directory remains an include path for MPFR's architecture-specific parameter headers.
- `zig/config_gen.zig` derives feature macros from the resolved target and applies the same definitions to C compilation and `translate-c`. The library uses `HAVE_STDINT_H`; `fork/mpfr_all.h` enables `MPFR_USE_INTMAX_T` for translation.
- Configuration defines only target-known features. Float128, decimal floating point, mini-GMP, GMP internals, and thread-safe caches are not enabled; generic paths cover unrecorded long-double and locale formats.
- `-Dcpu=baseline` constrains Zig code generation only; MPFR configuration comes from the resolved target, not its CPU feature set.
- The default provider is the GMP URL dependency in `build.zig.zon`. MPFR and bundled GMP use the same static or dynamic linkage; `-fsys=gmp` selects an installed GMP, while `-fsys=mpfr` translates its installed headers and produces no MPFR artifact. The lifetime test checks header/library version identity in system mode.
- Dynamic linkage derives the shared-library version from MPFR's makefile metadata and enables PIC. `-Druntime=true` instead dispatches translated MPFR and GMP symbols through the platform loader; libc declarations stay directly linked.
- Runtime loading requires the translated provider symbols and validates limb width and disabled float128/decimal options before publishing the dispatch table.
- Zig 0.17 uses `@Int` for the signed integer types in the facade's precision and exponent bounds.
- Only the standard target publishes the `mpfr` module; matrix targets use private modules so target order cannot change dependency resolution.
- MPFR takes GMP's artifact, generated public headers, generated `gmp.pc`, and licence texts from the dependency graph. The default install contains both libraries. System-provider modes install only artifacts this package builds.
- `check` and `matrix` compile targets but do not execute their binaries.

## Platform boundaries

The required compile matrix is `x86_64-linux-gnu`, `aarch64-linux-gnu`, `aarch64-macos-none`, `x86_64-windows-gnu`, `riscv64-linux-gnu`, and `wasm32-wasi`. The WASI route uses the GMP package's signal emulation.

- Hexagon targets are refused because GMP has no Hexagon port.
- NetBSD targets reach an Aro limitation on `_Pragma` in libc's stdio header. `arm-openbsd`, `powerpc-openbsd`, and `x86-openbsd` hit an Aro `stddef` conflict; MIPS64 OpenBSD headers lack the byte-order macro expected by libc.
- MinGW GNU shared builds inherit export annotations from GMP headers but have no generated `.def` export list, so complete DLL export coverage is not guaranteed. Static linkage is unaffected.
