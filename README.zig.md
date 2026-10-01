# Using GNU MPFR 4.2.2 from Zig

Upstream's own `README`, `INSTALL` and `NEWS` are unchanged and remain the
authority on MPFR itself. This file documents only the Zig package this fork
adds. `UPSTREAM.md` records provenance, `CHANGELOG.md` records what this fork
changed, `NOTICE.md` records licensing, and `FORK-NOTES.md` records the issues
met while preparing it.

## Status of this package

This is prepared source, not an integrated package. Nothing in it has been run:
no build, test, smoke, cross-target check or formatter has produced a result
here. The commands below are the entry points that exist in `build.zig` and
`consumer/build.zig`, and the gate results belong to whoever runs them.

The default route also has one unmet precondition: `vendor/gmp`, the verified
GMP package snapshot, is not in this tree yet (`UPSTREAM.md`, "Vendored GMP
provider"). Until it is, `zig build` stops with a message naming the fix, and the
`-Dsystem=gmp` / `-Dsystem=mpfr` modes are the only usable ones. No revision or
digest for that snapshot is recorded anywhere, because none has been verified:
do not fill the gap with a guess.

## What the package gives you

| Name | Kind | What it is |
| --- | --- | --- |
| `mpfr` | module | `root.zig`: the facade described below |
| `mpfr` | artifact | the static libmpfr, with its public headers attached |
| `c` | module inside `mpfr` | the complete translated public C API |

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

`check` and `matrix` compile only. `matrix` covers `x86_64-linux-gnu`,
`aarch64-linux-gnu`, `aarch64-macos-none`, `x86_64-windows-gnu`,
`riscv64-linux-gnu` and `wasm32-wasi`, and unlike `check -Dtarget=<t>` in a loop
it is one entry point for all six. A green matrix is a compile result for six
targets and nothing more; no emulator is presumed and no target binary is run.

Five of the six compile. `wasm32-wasi` fails for the provider's reason, not
this package's: the vendored `vendor/gmp/invalid.c:80` reports an invalid
operation by raising `SIGFPE`, and wasi-libc has no signal support, so its
`signal.h` refuses to be included. GMP's own cross gate fails the same way, and
`gmp/FORK-NOTES.md` entry 29 records it there. The target stays in the matrix
and the attempt stays visible; CI marks that one target `continue-on-error`.

The same six targets can be driven one at a time when a failure needs to name
its target:

```sh
zig build check -Dtarget=x86_64-windows-gnu
```

In this workspace the driver adds `-j8 --summary all --cache-dir
/home/tmp/gertullj/foundation-libs-cache/mpfr/<target>` to those commands, and
gives the consumer its own cache directory rather than the outer one, because two
build graphs must not share a manifest directory.

## Prerequisites

MPFR cannot be built without GMP. The default route is self-contained, as the
shared fork contract requires: a copy of the verified GMP package at
`vendor/gmp`, including its own `build.zig.zon`, declaring the package name
`gmp` and exposing `dep.artifact("gmp")`. That directory is not present yet; see
the status note above.

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
exe.root_module.linkLibrary(mpfr_dep.artifact("mpfr"));
```

```zig
// build.zig.zon
.dependencies = .{
    .mpfr = .{ .path = "../mpfr" },
},
```

Linking the artifact is what puts `mpfr.h` on your include path, so a C source
in your package can `#include <mpfr.h>` with no further configuration. A
dependent that only imports the module and never links the artifact gets the
facade without a library, so link the artifact.

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

Every general operation takes its direction explicitly, so MPFR's per-thread
default rounding mode never changes the result of a `Float` call.

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
outside that range (doc/mpfr.texi:1359-1360). Upstream also warns that MPFR
raises the precision internally for correct rounding, so a precision near the
maximum aborts rather than failing gracefully (doc/mpfr.texi:807-812). Call
`isValidPrecision` first when the precision comes from outside your code, and do
not instantiate a value at the maximum in a test or an example: on LP64 that is
about 2^63 bits.

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
`2..62`, or `-2..-36` for upper-case digits (`doc/mpfr.texi:1888-1898`), and
`isValidBase` tests that. When `mpfr_get_str` allocates but the base is invalid,
the error is `InvalidBase`; a failed allocation is `OutOfMemory`.

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
until `deinit`; `Digits` has no mutating accessor.

Zig has no move semantics, so a `Float` copied by value aliases the same limbs
and `deinit` must then be called on exactly one copy. Pass `*Float` and
`*const Float`.

`version()`, `patches()` and `tuningCase()` return borrowed strings owned by the
library, never to be freed; they are not `Digits`.

MPFR's own caches and thread-local pools are released by `mpfr.freeCaches()` and
`mpfr.cleanupMemory()`. Upstream recommends `cleanupMemory` before a thread
exits, and in every thread that used MPFR before the GMP allocator is replaced
(doc/mpfr.texi:1182-1226).

### Raw escape hatch

```zig
const inexact = mpfr.c.mpfr_set_ui_2exp(x.raw(), 1, 10, mpfr.c.MPFR_RNDN);
```

`Float.raw()` is the mutable `mpfr_ptr`, `Float.rawConst()` the
`mpfr_srcptr`. Names, types and semantics are upstream's, including the
`__gmpfr_` prefixes and the `intmax_t` entry points described above.

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

One test is an identity check rather than a pin: it compares the translated
`c.MPFR_VERSION_STRING` with the linked `mpfr.version()`, so a header and library
that disagree fail in `-Dsystem=mpfr` mode instead of misbehaving quietly. Which
release is pinned is the provenance job's business, not the test suite's;
`zig build smoke` prints the version, the tuning case and the patches string.
