# Using GNU MPFR 4.2.2 from Zig

Upstream's own `README`, `INSTALL` and `NEWS` are unchanged and remain the
authority on MPFR itself; upstream's `README` is also preserved byte-for-byte as
`README.upstream.md`. This file documents only the Zig package this fork adds.
`README.md` is the canonical fork README: deviations, the build/run/test matrix
and consumption. `UPSTREAM.md` records provenance, `CHANGELOG.md` records what
this fork changed, `NOTICE.md` records licensing, `FORK-LICENSE.md` records the
licence of the fork's own files, and `FORK-NOTES.md` records the issues met
while preparing it.

## Status of this package

The 2026-10-04 contract migration has bounded native-control and stdio results,
recorded in `README.md` section 3 and `FORK-NOTES.md` entries 2 and 14. They
do not establish the full SDK build/test/smoke, cross-target, Nix, devenv or
provenance gates; unreported matrix rows remain PENDING-VERIFICATION.
Earlier observations in the workspace ledger remain history, not claims
about this changed graph. The driver owns verification fields.

The default route has its provider: `vendor/gmp`, this workspace's GMP package
copied in on 2026-10-01, is in this tree and is declared as a `.path` dependency
in `build.zig.zon`, so `zig build` resolves it with no installed GMP and no
download. `UPSTREAM.md`, "Vendored GMP provider", records its identity and the
comparison that was run against the supplier package.

Read that section for what the comparison established rather than for a promise.
The vendored copy has not been byte-identical to the supplier since 2026-10-01,
and as of 2026-10-04 it is well behind: the same `diff -rq` reports 26 differing
paths and 14 paths the supplier has and the snapshot does not. Every one of them
is a fork-authored build, test, packaging or provenance file, and nothing GMP
itself ships changed with them. `UPSTREAM.md` classifies each path and says which
way it is meant to move. `-Dsystem=gmp` and `-Dsystem=mpfr` remain available, and
they are the modes that bypass the snapshot.

The provider now follows this package's linkage. `-Dlinkage=dynamic` builds a
shared `libmpfr` *and* a shared `libgmp` inside the same output, and the shared
`libmpfr` records a real dynamic dependency on it, so a prefix that contains only
`libmpfr.so` is not a closed installation. `NOTICE.md`, "The vendored GMP
provider", records the metadata, the four `COPYING*` files and the allocator
consequences in full.

## What the package gives you

| Name | Kind | What it is |
| --- | --- | --- |
| `mpfr` | module | `root.zig`: the facade described below |
| `mpfr` | artifact | libmpfr as a static archive by default or a shared library under `-Dlinkage=dynamic`, with its public headers attached |
| `c` | module inside `mpfr` | the complete translated public C API |
| linkage | `-Dlinkage=static` (default) or `-Dlinkage=dynamic`, forwarded to the vendored GMP |
| runtime | `-Druntime=false` (default) or `-Druntime=true`, selecting the dispatch described below |

libmpfr is compiled from the sources in this repository. No autotools, no CMake,
no download at build time, and no system MPFR by default.

## Commands

```sh
zig build            # install the static library into zig-out
zig build test       # run the behaviour suite
zig build smoke      # run the deterministic example
zig build run        # the same run step, under its explicit name
zig build check      # compile the facade, the suite and the example; run nothing
zig build matrix     # `check` for the six required targets; run nothing
```

Every one of them also accepts `-Dlinkage=static` or `-Dlinkage=dynamic`, which
selects the artefact that is installed and the linkage of the GMP it links.

`check` and `matrix` compile only. `matrix` covers `x86_64-linux-gnu`,
`aarch64-linux-gnu`, `aarch64-macos-none`, `x86_64-windows-gnu`,
`riscv64-linux-gnu` and `wasm32-wasi`, and unlike `check -Dtarget=<t>` in a loop
it is one entry point for all six. A green matrix is a compile result for six
targets and nothing more; no emulator is presumed and no target binary is run.

All six compile. `wasm32-wasi` builds: the vendored GMP snapshot selects Zig
0.16's real signal emulation on WASI (`vendor/gmp/build.zig:288-299`), which
defines `_WASI_EMULATED_SIGNAL` and links `wasi-emulated-signal`, so
`vendor/gmp/invalid.c`'s unconditional `<signal.h>` and its `raise (SIGFPE)`
both resolve without a source edited around them. `build.zig:148-157` records
the same arrangement.

The same six targets can be driven one at a time when a failure needs to name
its target:

```sh
zig build check -Dtarget=x86_64-windows-gnu
```

In this workspace the driver adds `-j8 --summary all --cache-dir
/home/tmp/gertullj/foundation-libs-cache/mpfr/<target>` to those commands, and
gives the consumer its own cache directory rather than the outer one, because two
build graphs must not share a manifest directory.

### The runtime-loading configuration

`-Druntime=true` replaces the link line with one process-lifetime dispatch table
that an explicit `load` fills. MPFR's symbols and GMP's arrive together, through
the provider's own dependency closure, so the provider must be a shared
`libmpfr` that depends on a shared `libgmp` (`root.zig:263-266`). Nothing is
linked into a consumer built this way, and the option is orthogonal to
`-Dlinkage` rather than refused with it: `-Dlinkage=dynamic` says what is
delivered and installed, `-Druntime=true` says how a program reaches it.

Three declarations carry the configuration, and they are all comptime, so one
source file can serve both shapes:

| Declaration | In a linked build | In a runtime-loading build |
| --- | --- | --- |
| `runtime_loaded` | `false` | `true` |
| `load(source)` | stops the program with a message saying there is nothing to load | opens the library named by `source`, once |
| `loadedSource()` | `null` | the request that succeeded, valid for the life of the process |

`LoadSource` is `.{ .path = "..." }` or `.{ .system = "..." }` and there is no
fallback in either direction: a request that cannot be honoured is an error
(`root.zig:239-245`). Calling `load` twice with the same request succeeds and
changes nothing; calling it with a different one is `ProviderMismatch` and the
provider already in use stays in use (`root.zig:253-261`).

In this repository the supported provider is the installed shared libmpfr of
the package's own install tree:

```sh
zig build -Dlinkage=dynamic -Druntime=true install -j8
cd consumer
zig build run -Druntime=true -j8 -- --provider ../zig-out/lib/libmpfr.so.6.2.2
```

`libmpfr.so.6.2.2` sits beside `libgmp.so.10.5.0` in the same `lib/`, and libmpfr
records `$ORIGIN`, so its own `DT_NEEDED` on `libgmp.so.10` resolves with no
`LD_LIBRARY_PATH`. `MPFR_PROVIDER` names the same file through the environment.
`consumer/build.zig` states this at the build level as well, including why a
build-cache path and `dep.artifact("gmp")` are neither of them a provider.

## Prerequisites

MPFR cannot be built without GMP. The default route is self-contained, as the
shared fork contract requires: the GMP package at `vendor/gmp`, including its own
`build.zig.zon`, declaring the package name `gmp` and exposing
`dep.artifact("gmp")`. That directory is present; the status note above records
what is and is not established about it.

```sh
zig build -Dsystem=gmp      # use an installed GMP instead
zig build -Dsystem=mpfr     # use an installed MPFR instead of building this one
```

`-Dsystem=gmp` builds libmpfr from this tree and links an installed GMP.
`-Dsystem=mpfr` builds no library at all: the tests and the example link the
installed one, and `zig build` has nothing to install. There is no third mode
that mixes a vendored MPFR with a system GMP, because MPFR's own pkg-config
metadata already names GMP: `mpfr.pc.in:10` is `Libs: -L${libdir} -lmpfr -lgmp`,
so a pkg-config link of the installed MPFR resolves `-lgmp` with it.

## What the build generates, and where it goes

Two inputs exist only in a release tarball; the Git tree carries neither.
`build.zig` produces both as deterministic build steps, and both land in the
build cache, not in `src/`:

- `mparam.h`, a verbatim copy of `src/mparam_h.in`. The template contains no
  `@VAR@` substitution, so a copy is exactly what `configure` would write.
- `get_patches.c`, the translation unit implementing `mpfr_get_patches`,
  produced by a Zig reproduction of `tools/get_patches.sh` from the `PATCHES`
  file. `PATCHES` is empty at 4.2.2, so the function returns an empty string.

Both are compiled from that generated directory, which is what upstream does
too: `nodist_libmpfr_la_SOURCES = $(BUILT_SOURCES)` (`src/Makefile.am:79`) puts
them in the build directory, and `src/` holds neither file.

The C source list itself is read from `libmpfr_la_SOURCES` and `BUILT_SOURCES`
in `src/Makefile.am` rather than duplicated in `build.zig`, so a rebase cannot
add or drop a translation unit without the build failing loudly. The generated
units are also the ones the build has to emit, which is why the names from
`BUILT_SOURCES` are paired with the two files above rather than joined onto the
`src/` list.

### What `--prefix` writes

`zig build install --prefix <dir>` produces, for the source-built route:

| Path | static | dynamic |
| --- | --- | --- |
| library | `<dir>/lib/libmpfr.a` | `<dir>/lib/libmpfr.so.6.2.2` with soname `libmpfr.so.6` and a `libmpfr.so` symlink |
| public headers | `<dir>/include/mpfr.h`, `<dir>/include/mpf2mpfr.h` | same |
| pkg-config | `<dir>/lib/pkgconfig/mpfr.pc` | same |
| GMP | `<dir>/lib/libgmp.a`, `<dir>/include/gmp.h`, `gmp-mparam.h`, `gmp_all.h` | `<dir>/lib/libgmp.so.10.5.0` with soname `libgmp.so.10` and a `libgmp.so` symlink, same headers |
| GMP terms | `<dir>/share/licenses/gmp/COPYING`, `COPYING.LESSERv3`, `COPYINGv2`, `COPYINGv3` | same |

Both shared version numbers are libtool's arithmetic on upstream's own values,
not chosen here. `src/Makefile.am:106` sets `libmpfr_la_LDFLAGS` to
`-version-info 8:2:2`, so the major is CURRENT-AGE = 6, the age is 2 and the
revision is 2. `libgmp`'s come from the snapshot the same way:
`LIBGMP_LT_CURRENT = 15`, `LIBGMP_LT_REVISION = 0` and `LIBGMP_LT_AGE = 5` at
`vendor/gmp/Makefile.am:107-109` reach `-version-info 15:0:5` at `:294-295`, so
the major is CURRENT-AGE = 10.

`mpfr.pc` is rendered from upstream's `mpfr.pc.in` with only its
`@prefix@`, `@exec_prefix@`, `@libdir@`, `@includedir@` and `@PACKAGE_VERSION@`
placeholders substituted. Its `Libs` line is upstream's, `-L${libdir} -lmpfr
-lgmp`, and `Requires:` is empty: this build installs no `gmp.pc`, so a
`Requires: gmp` would name a file pkg-config cannot find. `-lgmp` on `Libs` is
correct for both linkages here.

`-Dsystem=mpfr` compiles nothing of ours and installs nothing at all. `-Dsystem=gmp`
is not the same shape: it still builds libmpfr from this tree against the
installed GMP and installs it, with both public headers, `lib/pkgconfig/mpfr.pc`
and the six licence and provenance records under `share/licenses/mpfr/`
(`build.zig:603-608`). It installs no GMP — no libgmp, no `lib/pkgconfig/gmp.pc`
and no GMP licence texts — because `installGmpClosure` runs only for the vendored
artifact and `-Dsystem=gmp` selects no vendored GMP (`build.zig:613`). That
prefix is closed by the installed GMP rather than by this package.

## `intmax_t`: the same declarations on every target

`<mpfr.h>` declares the `intmax_t` entry points (`mpfr_set_sj`, `mpfr_get_uj`,
`mpfr_pow_sj`, ...) only when `intmax_t` is already visible while it is parsed,
and it never includes `<stdint.h>` itself. Upstream's own comment calls the
probes it uses non-portable (`src/mpfr.h:1136-1155`), and MPFR's library
sources call those entry points (`src/fits_intmax.c:93`, `src/pow_sj.c:30-32`),
so the decision has to land the same way for the library and the translation.

`fork/mpfr_all.h` therefore includes `<stdint.h>` and then defines
`MPFR_USE_INTMAX_T` to 1 before including `<mpfr.h>` and `<mpf2mpfr.h>`. The
compiled library is pinned the same way, through the switch upstream's own
`src/mpfr-intmax.h:60-68` reads: `build.zig` puts `-DHAVE_STDINT_H=1` on every
libmpfr compile line, so that header includes `<stdint.h>` and defines
`MPFR_USE_INTMAX_T` before `src/mpfr.h` is parsed, and the units that implement
the entry points really compile them. Pinning only the translation would leave
declarations for symbols the library never defined. `x86_64-windows-gnu` is
where this matters most: MinGW-w64 headers do not reliably define the probe
macros, and that target also has a 32-bit `long`.

The translated names carry the `__gmpfr_` prefixes that MPFR's own macros impose
on those entry points (`src/mpfr.h:1162-1179`): `c.__gmpfr_set_sj` is upstream's
`mpfr_set_sj`.

The private aggregate also includes `<stdio.h>` before `<mpfr.h>`, exposing
MPFR and GMP's `FILE *` entry points with the selected target libc's `FILE`
type. Runtime dispatch requires the MPFR/GMP symbols, while declarations
from the libc headers stay directly linked to libc.

## Using it from another package

```zig
// build.zig
const mpfr_dep = b.dependency("mpfr", .{
    .target = target,
    .optimize = optimize,
});
const exe = b.addExecutable(.{
    .name = "my-program",
    .root_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .imports = &.{.{ .name = "mpfr", .module = mpfr_dep.module("mpfr") }},
    }),
});
```

```zig
// build.zig.zon
.dependencies = .{
    .mpfr = .{ .path = "../mpfr" },
},
```

Importing the module carries the linked route's MPFR/GMP closure; do not link
the artifact again. In runtime mode the module deliberately links neither
library: call `mpfr.load` with an explicit provider before using either API.
System MPFR mode uses the selected system headers and library and publishes no
`mpfr` artifact. A separate C source that needs the bundled headers can link
`mpfr_dep.artifact("mpfr")` only in a bundled, linked build; never look up or
link that artifact for runtime or system MPFR mode.

`consumer/` in this repository is exactly that package, built against `..` by
relative path. Run it with:

```sh
cd consumer && zig build run -j8 --summary all --cache-dir .zig-cache
```

It prints `mpfr.version()` and a set of known answers that it checks before
printing, so a behaviour change is a non-zero exit rather than silently
different text. It also exercises the raw escape hatch and the ownership path
where a renderer's buffer is released with `Digits.deinit`.

One block there calls the `__gmpfr_`-prefixed `intmax_t` entry points directly
(`mpfr.c.__gmpfr_set_sj`, `c.__gmpfr_mpfr_get_uj` and their unsigned
counterparts) and reads the value back through the facade. That is the only
place the `MPFR_USE_INTMAX_T` pin is observable from outside: if the library
were compiled without those entry points, nothing in `root.zig` would notice,
and this link would fail.

## The facade

`root.zig` is a thin owned wrapper. It adds Zig types and explicit ownership and
reimplements no MPFR algorithm. The complete translated C API stays available as
`mpfr.c`.

### Types

| Zig | Meaning |
| --- | --- |
| `Precision` | significand width in bits, upstream's `mpfr_prec_t` |
| `Exponent` | binary exponent, upstream's `mpfr_exp_t` |
| `RoundingMode` | the six documented directions, plus `nearest_away` |
| `Ternary` | `exact`, `above`, `below`: the sign of the returned ternary value |
| `Flags` | the six exception flags as a packed struct of bools, backed by `u6` |
| `Digits` | an owning digit string plus its exponent |
| `Order` | `std.math.Order`, from `mpfr_cmp3` |

### Rounding

Every general operation takes its direction explicitly, so MPFR's default
rounding mode never changes the result of a `Float` call. That default is
process-wide rather than per-thread in this build; see "Exception flags" for
the rule that decides it.

```zig
var x = mpfr.Float.init(200);
defer x.deinit();
try x.parseWhole("2.5", 10, .nearest_even);

// doc/mpfr.texi:929-933: 10.1b rounds to 10.0b = 2 at two bits.
try std.testing.expectEqual(mpfr.Ternary.below, x.roundToPrecision(2, .nearest_even));
try std.testing.expectEqual(2.0, x.toF64(.nearest_even));
```

`RoundingMode.nearest_away` corresponds to upstream's `MPFR_RNDNA`, which
upstream marks "DON'T USE" and which only `mpfr_rint` accepts. Reach it with
`Float.roundToNearestAway`, not by passing the mode to a general operation.

The round-to-integer family takes no mode, because each method is `mpfr_rint` in
one fixed direction: `truncate` (toward zero), `ceil`, `floor`,
`roundToNearestEven`, and `roundToNearestAway`. Each returns `Ternary`. The
inexact flag is set exactly when the stored result differs from the operand
(doc/mpfr.texi:3205-3207), so an already-integral value rounds exactly, and a
fractional value such as 1.75 changes under every one of the five — none of them
is a no-op there. `mpfr_rint`'s return value carries more than the sign (0 exact,
±1 for an integer not representable in the destination, ±2 for a non-integer,
doc/mpfr.texi:3200-3204); `Ternary` keeps the sign only.

### The ternary value

Almost every MPFR operation returns an `int`. Its sign carries the meaning: zero
means the stored value is the exact result, positive means it is greater,
negative means it is smaller (doc/mpfr.texi:984-1014). `Ternary` names those
three outcomes. Two consequences are worth internalising:

- An infinite result is **exact** unless it came from overflow, so `1 / 0` is
  exact and only raises `divide_by_zero`.
- A NaN result is **always** exact.

### Precision limits

`mpfr.min_precision` is 1 (`MPFR_PREC_MIN`, `src/mpfr.h:176`) and
`mpfr.max_precision` is derived at compile time from `mpfr_uprec_t` the way
`MPFR_PREC_MAX` is (`src/mpfr.h:177`). `mpfr.isValidPrecision(p)` tests a value
against both ends.

`Float.init` passes its argument straight to `mpfr_init2`, which is undefined
outside that range (doc/mpfr.texi:1359-1360); `Float.resetPrecision` and
`Float.roundToPrecision` carry the same bound (`doc/mpfr.texi:1507-1508`,
3327-3328). The condition is stated at each of those three declarations, not
only here.

An out-of-range precision is not a Zig-mode-dependent check. `mpfr_init2`
guards it with `MPFR_ASSERTN (MPFR_PREC_COND (p))` (`src/init2.c:50-53`), and
`MPFR_WANT_ASSERT` is left at its default 0 (`src/mpfr-impl.h:488-497`), which
keeps `MPFR_ASSERTN` a live test. The process therefore aborts in Debug,
ReleaseSafe, ReleaseFast and ReleaseSmall alike. Upstream also warns that MPFR
raises the precision internally for correct rounding, so a precision near the
maximum asks GMP for an allocation it cannot make (doc/mpfr.texi:807-812).
Call `isValidPrecision` first when the precision comes from outside your code,
and do not instantiate a value at the maximum in a test or an example: on LP64
that is about 2^63 bits.

### Exception flags

`Flags` is a packed struct of six bools in upstream's bit order —
`underflow` (1), `overflow` (2), `nan` (4), `inexact` (8), `erange` (16),
`divide_by_zero` (32), the values in `src/mpfr.h:76-81`. Every field defaults to
`false`, so `Flags.none` is `.{ }` and a partial literal such as
`.{ .inexact = true }` is valid. `toRaw` builds the `mpfr_flags_t` mask
(`src/mpfr.h:73`) from the `MPFR_FLAGS_*` constants and `fromRaw` reads one back;
neither depends on the backing integer's width, which is why that width is not
part of this contract. The backing is `u6` because a packed struct's backing
integer must have exactly the bit width of its fields, and those six bits are
all MPFR ever defines; `u32`, the width of the C `unsigned int`, would not
compile for that reason rather than because it is wrong.

The module-level helpers are `flags()`, `setFlags()`, `clearFlags()` and
`clearAllFlags()`. A flag can only be raised, never cleared, except by an
explicit call (doc/mpfr.texi:1148-1156).

The flags are the calling thread's only when the linked library was built
thread-safe. This package's own build is not: the macros
`zig/config_gen.zig` derives do not include `MPFR_USE_THREAD_SAFE`, so
`MPFR_THREAD_ATTR` expands to nothing (`src/mpfr-thread.h:33-43`) and the flags,
the exponent limits, the default precision and the default rounding direction
are one process-wide word each, shared by every thread (`src/mpfr-impl.h:255-260,
323-325`). `-Dsystem=mpfr` links an installed library instead, and
`mpfr.c.mpfr_buildopt_tls_p()` reports at run time whether that one keeps them
per thread. Threads that write these channels need external synchronisation;
`Float` and `Digits` carry nothing shared.

### Parsing and rendering

`parseWhole(text, base, mode)` requires the entire string to be one number and
returns `error.InvalidNumber` for an empty string and for any trailing
character, because `mpfr_set_str` maps both to `-1` (`src/set_str.c:29-32`). On
failure it leaves `self` unspecified: `mpfr_set_str` returns -1 only after
`mpfr_strtofr` has already run (`src/set_str.c:31-32`).

It returns nothing on success. `mpfr_set_str` has no ternary channel
(`doc/mpfr.texi:1603-1607`), so success says only that the whole string was one
number; a literal this precision cannot hold is rounded silently. When you need
to know whether the text was represented exactly, use `parsePrefix` and read its
ternary.

`parsePrefix` returns `Prefix{ .consumed, .ternary }`: the byte count of the
number at the start of the input and the conversion's ternary value. It fails
only when no bytes were consumed at all. The field is named `ternary`, not
`inexact`, because that is the value MPFR returns.

`toDigits(base, digits, mode)` renders the value; a `digits` count of zero is
passed through unchanged, so MPFR chooses the count itself and performs its own
base validation rather than having the facade precompute it. A base is valid in
`2..62` or `-36..-2`, and `isValidBase` tests exactly that; base `0` is not one
of the accepted values. The digit alphabet follows the range: `2..36` gives
digits and lower-case letters, `-36..-2` digits and upper-case letters, and
`37..62` digits, upper-case then lower-case letters in that order, so above base
10 the successor of the digit `9` depends on the base
(`doc/mpfr.texi:1888-1898`). `toDigits` reports `error.InvalidBase` before any
allocation (`src/get_str.c:2611-2613`), leaving no buffer to release. GMP
allocators must not return `null` (`vendor/gmp/doc/gmp.texi:7487-7490`); the
default allocator aborts on failure (`vendor/gmp/memory.c:53-58`), so this is
not a recoverable conversion error. An unexpected `null` result for a valid
base panics in every optimization mode.

### Ownership

`mpfr_init2` allocates the significand through GMP's configured allocator and
`mpfr_clear` releases it; `mpfr_get_str` allocates its buffer the same way and
`mpfr_free_str` releases it. No Zig allocator is involved anywhere, so a Zig
leak checker has no visibility into this memory: the owning handle is the
contract.

```zig
var x = mpfr.Float.init(64);
defer x.deinit();          // calls mpfr_clear

var d = try x.toDigits(10, 20, .nearest_even);
defer d.deinit();          // calls mpfr_free_str
```

`Digits.digits()` returns a borrowed sentinel-terminated slice that is valid
until `deinit`. There is no mutating accessor, but `Digits.buffer` is a
reachable field and writable in place, because upstream allows editing the
string as long as its length is unchanged when it is freed
(`doc/mpfr.texi:1950-1953`) and `mpfr_free_str` frees `strlen(str) + 1` bytes
(`doc/mpfr.texi:1945-1948`). Editing digits or the sign is safe; shortening the
string, dropping the sentinel or writing past it is not.

Zig has no move semantics, so a `Float` copied by value aliases the same limbs
and the same allocation, and `deinit` must then be called on exactly one copy:
calling it through two copies is a double `mpfr_clear`. `Digits` is the same
shape, and two `mpfr_free_str` calls on one buffer are a double free.
`Digits.deinit` poisons the variable it is called on, which bounds a repeat
through that variable and protects no alias; `Float.deinit` does not even do
that. Pass `*Float` and `*const Float`.

`Float.raw()` is `&self.inner`, so a pointer from it names that `Float`'s own
storage rather than the significand. It is valid until `deinit`, it does not
follow a copy, and it is not a second owner: do not pass it to `mpfr_clear`,
`mpfr_free_cache` or anything else that ends the variable's life, because
`Float.deinit` still owes that one `mpfr_clear`.

`version()`, `patches()` and `tuningCase()` return borrowed strings owned by the
library, never to be freed; they are not `Digits`.

MPFR's own caches and pools are released by `mpfr.freeCaches()` and
`mpfr.cleanupMemory()`. Upstream recommends `cleanupMemory` before a thread
exits, and in every thread that used MPFR before the GMP allocator is replaced
(doc/mpfr.texi:1182-1226).

### Raw escape hatch

```zig
const inexact = mpfr.c.mpfr_set_ui_2exp(x.raw(), 1, 10, mpfr.c.MPFR_RNDN);
```

`Float.raw()` is the mutable `mpfr_ptr`, `Float.rawConst()` the `mpfr_srcptr`,
and their borrow and ownership rules are in "Ownership" above. Names, types and
semantics are upstream's, including the `__gmpfr_` prefixes and the `intmax_t`
entry points described above. Everything upstream declares that this facade
does not wrap is reached the same way: `mpfr_printf` and the other output
entry points, `mpfr_out_str`, `mpfr_fms`, the `mpfr_const_*` caches, and every
width- and type-suffixed integer variant.

The private aggregate declares the `FILE *` entry points, including
`mpfr_out_str`. The bounded `__gmpfr_fprintf` proof produced exactly
`4.20e+01\n` (nine bytes) in real streams and stdout in 16/16 linked/loaded
delivery cells (details: `FORK-NOTES.md` entry 2). Native calls pass scalar
varargs, `c.__gmpfr_fprintf(stream, "%.*Re\n", precision, value)`; runtime
dispatch takes `.{ precision, value }` as its third argument. Use a `c_int`
precision and an `mpfr_srcptr` value. The tested null stream terminated by
native signal, not a checked error: pass stdout or a successfully opened
stream. All loaded cells used the same existing Debug-dynamic provider;
this is not independent external-ABI or per-mode-provider certification.

One obligation travels with the escape hatch in the other direction. Through
`raw()` a caller can put a `Float` into a state `Float.deinit` does not know how
to release: `mpfr_custom_init_set` and `MPFR_DECL_INIT` put the significand in
caller-owned storage (`src/mpfr.h:1047`, 857-859), and `mpfr_clear` does not
free storage it did not allocate. Do not use either through this module; `init`
is the only construction a `Float` supports.

## With Nix

`package.nix` is one source-only derivation, called by both `flake.nix` and
`devenv.nix`. It builds from this repository alone: no `../` workspace import,
no host account, node or store path, no download at build time. The two variants
are attributes of one SDK, not separate SDKs.

```sh
devenv shell                    # the canonical development environment
nix build .#static              # static libmpfr beside static libgmp
nix build .#shared              # shared libmpfr with a real dependency on shared libgmp
devenv build outputs.static     # the same, from inside the devenv shell
devenv build outputs.shared
```

The development shell does not contain this package. Entering it must not
require building the library; it carries the compiler and the tools, and the SDK
is built on demand through `outputs.static` / `outputs.shared`. `.envrc` wires
the same environment into `direnv`, and `use devenv` takes the same options as
`devenv shell`.

`devenv task` names the same entry points the shell offers directly:
`sdk:build`, `sdk:build:static`, `sdk:build:shared`, `sdk:test`,
`sdk:test:release-safe`, `sdk:smoke`, `sdk:check`, `sdk:matrix`, `sdk:consumer`
and `sdk:install`.

Each task runs in this SDK's own directory whatever directory invoked it:
`devenv tasks run` and `devenv shell -- <script>` execute in the caller's
working directory, and `$DEVENV_ROOT` is that same directory, which for a
shell entered with `--from path:<sdk>` holds no build graph at all. The four
installing tasks — `sdk:build`, `sdk:build:static`, `sdk:build:shared` and
`sdk:install` — pass `--prefix` beneath `$ZIG_LOCAL_CACHE_DIR` rather than
leaving Zig's `zig-out` default inside the checkout, and `sdk:consumer` takes
its own `--cache-dir` there; the compile-only tasks install nothing. The
provenance gate is `./check-upstream-baseline.sh`, not a task.

The build graph owns every installed artifact, header, licence file and `.pc`,
so it is the single writer of each installed path and the derivation copies
nothing. MPFR's own terms and records go to `$out/share/licenses/mpfr/`, GMP's
four `COPYING*` files to `$out/share/licenses/gmp/`.

No Nix derivation here promises a wholly static executable. `static` names the
artefact installed — `libmpfr.a` beside `libgmp.a` — and nothing more.

## Tests

`fork/tests/` is a behaviour suite, not a port of upstream's `make check`.
Upstream's own suite lives in `tests/` and is left untouched; run it with
upstream's autotools build if you want it.

`fork/tests/surface.zig` calls every public facade method and every module-level
function on real values, with an assertion beside each call, and `zig build
check` compiles it. That is what makes `check` analyse the whole public surface:
`std.testing.refAllDecls` names a declaration without instantiating its body, so
it would not prove it.

Every expected value in `fork/tests/` is an independent known answer:

- values quoted from the manual, with the line range in the test;
- values taken from upstream's own test suite, cited by file and line;
- values derived by exact rational arithmetic from the definition of a correctly
  rounded conversion.

Round trips through MPFR's own code only supplement those; the provenance of each
group is described at the top of `fork/tests/support.zig`.

No test compares the translated `c.MPFR_VERSION_STRING` with the linked
`mpfr.version()`; nothing under `fork/tests/` reads either of them. The one
place a version string is checked at all is the runtime route's provider probe
(`runtime/library.zig:253-264`), which asks the loaded library for
`mpfr_get_version()` and rejects an answer whose first byte is the terminator.
What that establishes is that the string is non-empty — that an entry point
answered — and not which release produced it. Which release is pinned is the
provenance job's business; `zig build smoke` prints the version, the tuning case
and the patches string.
