// SPDX-License-Identifier: LGPL-3.0-or-later
//
// Fork-authored. `FORK-LICENSE.md` records the owner's authorization of that
// grant and why it matches MPFR's own primary upstream terms.

//! Build for the CoffeeImpliesCode/mpfr fork of GNU MPFR 4.2.2.
//!
//! What this builds
//! ----------------
//! The complete MPFR core is compiled from the sources in this repository: no
//! CMake, no autotools, no Make, no download at build time, and no system copy
//! by default. Two inputs that autotools would generate are produced as
//! deterministic build steps instead:
//!
//!  * `mparam.h`, a verbatim copy of `src/mparam_h.in`. That template holds
//!    no `@VAR@` substitution even though `configure.ac:894` runs it through
//!    AC_CONFIG_FILES, so a copy is exactly what configure produces.
//!  * `get_patches.c`, the translation unit implementing `mpfr_get_patches`.
//!    Upstream writes it with `tools/get_patches.sh` from the `PATCHES` file,
//!    which is empty at 4.2.2. `getPatchesSource` below reproduces that script
//!    in Zig so the build needs no shell, and must be kept in step with it.
//!
//! Both are emitted into one `addWriteFiles` directory and compiled from there.
//! Upstream agrees: `nodist_libmpfr_la_SOURCES = $(BUILT_SOURCES)`
//! (src/Makefile.am:79) builds both units in the build directory, so neither
//! has a file under `src/`, and `upstreamSources` below reads `BUILT_SOURCES`
//! to find their names rather than assuming them.
//!
//! The C source list is read out of `libmpfr_la_SOURCES` in `src/Makefile.am`
//! rather than duplicated here, so an upstream rebase cannot silently drop or
//! add a translation unit without this build noticing.
//!
//! GMP
//! ---
//! MPFR cannot be built without GMP. The default is the self-contained route the
//! shared fork contract requires: a `.path` dependency on `vendor/gmp`, which
//! must hold the parent's verified GMP package snapshot. That snapshot must
//! declare the package name "gmp" and expose `dep.artifact("gmp")`.
//! `-Dsystem=gmp` selects an installed GMP instead.
//!
//! Linkage
//! -------
//! `-Dlinkage=static` is the default and is what this build produced before the
//! option existed: `b.addLibrary` with no `.linkage` is a static library.
//! `-Dlinkage=dynamic` builds the shared object instead, and the two differ in
//! three real ways, not in a flag name:
//!
//!  * The shared object carries a real file name, a major-version symlink and a
//!    soname. They come from upstream's own libtool versioning,
//!    `libmpfr_la_LDFLAGS = ... -version-info 8:2:2` (src/Makefile.am:106).
//!    Libtool's library major is `CURRENT - AGE`, and its real name is
//!    `$libname.so.$major.$age.$revision`, so `8:2:2` is `libmpfr.so.6.2.2`
//!    with soname `libmpfr.so.6`. `sharedLibraryVersion` below reads that
//!    triple out of `src/Makefile.am` rather than carrying it as a literal, so
//!    a rebase that changes the versioning cannot leave a stale soname behind.
//!    Position-independent compilation is stated rather than inferred on the
//!    shared route: `Module.pic` is `true` there and left null on the static
//!    route, because null means "the driver decides" and `-fno-PIC` would not.
//!
//!  * GMP is built with the *same* linkage, and that is an upstream rule rather
//!    than a preference. `configure.ac:635-662` refuses a shared libmpfr whose
//!    GMP is not a DLL and refuses a static libmpfr whose GMP is, on every
//!    `*-mingw*` host, with `libgmp isn't provided as a DLL` /
//!    `libgmp is provided as a DLL`. The mechanism behind that check is
//!    `__GMP_LIBGMP_DLL` in `gmp.h`, and `vendor/gmp`'s build sets that macro
//!    from its own linkage, so forwarding one selection to both libraries makes
//!    the pair consistent by construction. `-Dsystem=gmp` cannot forward
//!    anything, so that combination is only as consistent as the installed GMP
//!    the user points at; configure's compile probe is not reproduced here.
//!
//!  * The DLL macros are upstream's own and need no `-D` on this side.
//!    `src/mpfr-impl.h:82-84` defines `__MPFR_WITHIN_MPFR` in every library
//!    translation unit, and `src/mpfr.h:321-331` turns that plus
//!    `__GMP_LIBGMP_DLL` into `__MPFR_DECLSPEC` = export for the library and
//!    import for its users; `src/mpfr-impl.h:251-253` makes the same macro
//!    select `MPFR_WIN_THREAD_SAFE_DLL` and its `_f()` variable accessors. One
//!    linkage choice on the GMP side therefore switches the whole Windows DLL
//!    arrangement, in the library and in the translated declarations, without
//!    this file inventing a macro of its own.
//!
//!  * A dependent's own link line carries GMP, in both linkages, because
//!    `fork/mpfr_all.h` declares all of GMP's public header and this package
//!    publishes that translation as the `c` import. `wireUp` therefore links
//!    the vendored GMP artifact into the public `mpfr` module next to
//!    libmpfr, and the installed `mpfr.pc` ends its `Libs:` line with
//!    upstream's own `-lmpfr -lgmp`. The static route reached that closure
//!    only as a side effect of libmpfr.a's own archive dependency, which is
//!    exactly why the shared route failed to link a consumer that reads
//!    `__gmp_bits_per_limb`: see the comment on the link in `wireUp`.
//!
//! The Windows export surface is the one thing here this build does not
//! enumerate, and it is not for want of an annotation. On the shared route
//! `__MPFR_DECLSPEC` expands to `__GMP_DECLSPEC_EXPORT` (`src/mpfr.h:321-331`),
//! which is `__declspec(dllexport)` (`vendor/gmp/gmp-h.in:104`), so a
//! definition inherits the annotation from the declaration its own header
//! already carries. Upstream does not rely on that: libtool runs `nm` over the
//! objects and writes a `.def` (vendor/gmp/ltmain.sh:4643-4665), and Zig 0.16's
//! build API exposes only `LibraryOptions.win32_module_definition`, which would
//! need a symbol list this repository does not carry.
//!
//! Whether that annotation covers every symbol a Windows DLL ought to export is
//! an observation, not a deduction, so no `.def` is fabricated here - a partial
//! one would silently drop exports - and `-Dtarget=x86_64-windows-gnu
//! -Dlinkage=dynamic` stays for the driver to check either way.
//!
//! Target and CPU options
//! ---------------------
//! `-Dtarget`, `-Dcpu`, `-Dofmt` and `-Ddynamic-linker` are all accepted. This
//! build asks for them through `b.standardTargetOptions`, which delegates to
//! `standardTargetOptionsQueryOnly`, and that function is what declares the
//! four options - `target` at std/Build.zig:1473, `cpu` at :1478, `ofmt` at
//! :1483, `dynamic-linker` at :1488. `-Dcpu=baseline` is therefore not an
//! unknown option here: it parses to `cpu_model = .baseline`
//! (std/Target/Query.zig:282-283), the conservative feature set that
//! `Query.zig:171` documents for cross-compiling, and a packaging derivation
//! may pass it.
//!
//! The other half of that is worth knowing before adding one to any SDK's
//! build: Zig 0.16 fails the build on an option nothing declared.
//! `Build.validateUserInputDidItFail` (std/Build.zig:1644-1651) reports
//! `invalid option: -D<name>` for every entry still marked unused, and only
//! `Build.option` (std/Build.zig:1167-1168) clears that mark. An SDK therefore
//! accepts a flag because it asks for it, and this file asks for nothing it
//! does not use.
//!
//! Targets with no buildable graph
//! -----------------------------
//! One target a caller can name has no buildable graph here, and it is said
//! at configure time, before a single C file is compiled. Nothing is dropped
//! to hide that: `-Dtarget=hexagon-...` fails with `error.UnsupportedTarget`
//! and the reason, and a matrix cell that asks the same question prints the
//! same text instead of being compiled until a C diagnostic appears four
//! hundred lines deep.
//!
//!   * **`hexagon-linux`** — GMP 6.3.0 has no port for this CPU: no
//!     `mpn/hexagon`, no `tune/hexagon.asm`, and `hexagon` appears in neither
//!     `vendor/gmp/configure.ac` nor the `config.sub`/`config.guess` that
//!     `configure` runs (`vendor/gmp/configure:3047-3053`).
//!
//! `refusalFor` is the one place that decision is made. The refusal names the
//! platform fact, the source that records it and the targets that do build,
//! and nothing is substituted for a refused one: no archive, no installed
//! prefix, no test binary, and no claimed result. It is asked of every route,
//! `-Dsystem=gmp` and `-Dsystem=mpfr` included, because
//! `zig/config_gen.zig` has to record a C double format for this CPU
//! whichever GMP the library is compiled against.
//!
//! **`wasm32-wasi` is not in that set, and it builds.** The vendored GMP
//! snapshot selects Zig 0.16's real signal emulation on WASI
//! (`vendor/gmp/build.zig:288-299`): it defines `_WASI_EMULATED_SIGNAL` on
//! the library module, which is the macro wasi-libc's `signal.h` refuses to
//! compile without (`libc/include/wasm-wasi-musl/signal.h:2`), and links
//! `wasi-emulated-signal` on that same module, which is where the reference
//! to `raise` resolves. GMP's `invalid.c` therefore keeps its unconditional
//! `<signal.h>` and its `raise (SIGFPE)` and gets both, rather than a source
//! this file edited around it. `wasm32-wasi` stays in `required_targets`
//! below and the `matrix` step compiles it.
//!
//! Runtime route
//! -------------
//! `-Druntime=true` resolves MPFR's and GMP's symbols through the platform
//! loader at run time instead of linking the archives. It changes three things
//! in this file and nothing else:
//!
//!  * the facade's `c` import becomes `graph.createModule`, the generated
//!    dispatch, built from the same translation step the linked route uses, so
//!    both configurations describe the same header;
//!  * the facade no longer links libmpfr or libgmp. Nothing else does either:
//!    the compiled libraries are still built and installed, because they are
//!    what a `.path` load opens, and the installed prefix is exactly what it
//!    was before the switch;
//!  * the facade does not get the loader core as a direct import. In this
//!    configuration the dispatch re-exports `LoadSource` and `LoadError` from
//!    the one core instance it creates, and a second one would be a second set
//!    of types (`runtime/graph.zig:109-112`). In the linked route the facade does
//!    get it, because there is no dispatch to carry those two declarations.
//!
//! The runtime route is orthogonal to the two system options rather than
//! refused with them. `-Druntime=true -Dsystem=mpfr` builds no library and
//! installs nothing, and that is the point rather than a gap: the dispatch is
//! generated from the installed headers and the caller names the installed
//! library its `load` opens, so the whole runtime arrangement happens outside
//! this package. `-Druntime=true -Dsystem=gmp` still builds and installs
//! libmpfr, against the installed GMP, and the `.path` load opens that library.
//!
//! The rule these routes share with the source-built route is that no native
//! library is linked anywhere in the graph, so every module link in `wireUp`
//! stays inside `if (!runtime_loaded)`. The translator's own query is not one
//! of those: it names the selected `.pc` so both routes read the installed
//! headers, and the generated runtime module never calls `setUpModule`.
//!
//! System mode and header/ABI identity
//! ----------------------------------
//! `-Dsystem=mpfr` links an installed MPFR. In that mode `src/` is deliberately
//! NOT added to the translation's include path, so `<mpfr.h>` resolves to the
//! installed header and the translated declarations describe the library that is
//! actually linked, rather than describing 4.2.2 while linking something older.
//! No fork test compares `MPFR_VERSION_STRING` from the translated header with
//! `mpfr_get_version` from the linked library, and `fork/tests/` reads neither.
//! `fork/tests/lifetime_test.zig:175-207` asks a narrower question instead:
//! whether the provider's exported limb width and its two `mpfr_buildopt_*`
//! answers are the ones these declarations describe. The one version check in
//! this package is `runtime/library.zig:261`, which rejects an empty
//! `mpfr_get_version()` answer and so establishes that the string is non-empty
//! rather than which release produced it. No fork-only shim symbol is expected
//! from an installed MPFR, and none is.
//!
//! Configuration macros
//! --------------------
//! `zig/config_gen.zig` reproduces the facts `configure` computes, from the
//! resolved target rather than from a program run on the build host, and
//! `build.zig` puts every one of them on **both** C command lines: the one
//! that compiles `libmpfr`, and the one `b.addTranslateC` parses
//! `fork/mpfr_all.h` with. A macro that reaches only one of them leaves the
//! translated declarations describing entry points the linked library does
//! not export, and the failure shows up as an undefined symbol at link time
//! with no explanation at the point of cause.
//!
//! Two of MPFR's macros are exactly that kind of declaration switch:
//! `MPFR_WANT_FLOAT128` (`src/mpfr.h:477-485` against
//! `src/set_float128.c:26` and `src/get_float128.c:25`) and
//! `MPFR_WANT_DECIMAL_FLOATS` (`src/mpfr.h:470-475,530-533` against
//! `src/set_d64.c:30`, `src/get_d64.c:31`, `src/set_d128.c:30` and
//! `src/get_d128.c:49`). Neither is set, on either line, because
//! `std.Target` does not record whether the target's C frontend offers
//! `_Float128` or `_Decimal64`/`_Decimal128`; leaving the pair off keeps both
//! sides in step and makes `mpfr_buildopt_float128_p` and
//! `mpfr_buildopt_decimal_p` (`src/buildopt.c:36-53`) report 0 truthfully.
//!
//! `MPFR_USE_INTMAX_T` is the third, and the fork does want it. `src/mpfr.h:
//! 1151-1155` decides whether to declare the `intmax_t` entry points
//! (`mpfr_set_sj`, `mpfr_get_uj`, `mpfr_pow_sj`, ...) from a set of probes over
//! libc header guard macros, and the library compiles them because every unit
//! that defines them defines `MPFR_NEED_INTMAX_H` and then includes
//! `mpfr-impl.h`. The same answer is pinned on both sides: the library gets
//! `HAVE_STDINT_H`, which `src/mpfr-intmax.h:60-68` turns into `<stdint.h>`
//! plus `MPFR_USE_INTMAX_T`, and `fork/mpfr_all.h` defines
//! `MPFR_USE_INTMAX_T` directly for the translation.
//!
//! Steps
//! -----
//!   zig build            install the library, its headers and its metadata
//!   zig build test       run the behaviour suite
//!   zig build smoke      run the deterministic example
//!   zig build run        run the example
//!   zig build check      compile the facade and the example, run nothing
//!   zig build matrix     compile `check` for the required targets, printing
//!                        and skipping any this build refuses
//!
//! `check` and `matrix` compile only; they never execute a target binary.
//!
//! A target named with `-Dtarget=` that this build refuses fails the configure
//! with `error.UnsupportedTarget` and its reason, before anything is compiled;
//! `matrix` prints the same reason for such a cell and compiles the rest.
//!
//! What `zig build` installs
//! ------------------------
//! `-Dsystem=mpfr` installs nothing at all: it links an installed MPFR, so this
//! tree contributes no artefact to that prefix. `-Dsystem=gmp` installs libmpfr,
//! its headers and its metadata, but no GMP: the GMP is the installed library
//! the user selected, which is the same arrangement as upstream's
//! `--with-gmp=system` (`configure.ac:607-662`), and the prefix is closed by
//! that system rather than by this package.
//!
//! With the vendored GMP the installed prefix is closed rather than partial:
//!
//!   lib/libmpfr.a                       static, the default
//!   lib/libmpfr.so.6.2.2 (+ .so.6, .so) -Dlinkage=dynamic
//!   lib/libgmp.a | lib/libgmp.so.*      the GMP the library was linked against
//!   include/mpfr.h, include/mpf2mpfr.h  `include_HEADERS`, src/Makefile.am:30
//!   include/gmp.h, include/gmp-mparam.h,
//!   include/gmp_all.h                  GMP's `gmp_include_HEADERS`, which
//!                                      travel with the GMP artifact
//!   lib/pkgconfig/mpfr.pc               upstream's mpfr.pc.in, substituted
//!   lib/pkgconfig/gmp.pc               upstream's gmp.pc.in from the snapshot,
//!                                      which GMP installs unconditionally
//!                                      (vendor/gmp/Makefile.am:121-122)
//!   share/licenses/mpfr/COPYING*        MPFR's own terms, which LGPL requires
//!   share/licenses/mpfr/{NOTICE.md,     to travel with the code, plus this
//!     FORK-LICENSE.md, UPSTREAM.md,     fork's provenance and licence records
//!     README.upstream.md}
//!   share/licenses/gmp/COPYING*         GMP ships four COPYING files and its
//!                                      licence has to travel with its library
//!
//! The GMP half is not optional. A shared libmpfr has a real `DT_NEEDED` on
//! libgmp, and a static libmpfr has unresolved GMP symbols, so a prefix holding
//! only libmpfr is neither runnable nor linkable.
//!
//! One writer per installed path: `build.zig` installs both licence directories
//! and both pkg-config files, and the packaging layer that owns the documents
//! does not copy them again.

const std = @import("std");

/// The configuration `configure` would have computed for the resolved target.
const config = @import("zig/config_gen.zig");

/// The runtime route's build half, owned by the API role.
///
/// Only the linked route calls `createCoreModule` and only the runtime route
/// calls `createModule`; the "Runtime route" section above says why neither is
/// called unconditionally.
const graph = @import("runtime/graph.zig");

/// The package name the vendored GMP snapshot must declare.
const gmp_package = "gmp";

/// Where the verified GMP snapshot must live. The shared fork contract forbids a
/// `../gmp` path dependency, an unauthenticated archive URL, and an installed
/// host GMP as the default.
const vendored_gmp = "vendor/gmp";

/// The library and module name this package publishes.
const library_name = "mpfr";

/// Upstream's own source list, read at configure time.
const src_makefile_am = @embedFile("src/Makefile.am");

/// Upstream's applied-patch list, empty at 4.2.2.
const patches_file = @embedFile("PATCHES");

/// Upstream's pkg-config template, installed as `mpfr.pc`.
///
/// Only the `@...@` placeholders `configure` would substitute are replaced;
/// every other byte, including the `Libs` line's `-lmpfr -lgmp`, is upstream's.
const pkg_config_template = @embedFile("mpfr.pc.in");

/// Upstream's release number, the value of `@PACKAGE_VERSION@`.
const version_file = @embedFile("VERSION");

/// GMP's own pkg-config template, installed as `gmp.pc`.
///
/// `vendor/gmp` is a declared path dependency and is listed whole in
/// `build.zig.zon`'s `paths`, so this embed resolves for a package fetched by
/// hash exactly as it does from this tree.
const gmp_pkg_config_template = @embedFile("vendor/gmp/gmp.pc.in");

/// GMP's header template, read for the release number its `configure` would
/// put in `gmp.pc`. Only `gmp-h.in:2338-2340` is ever looked at.
const gmp_header_template = @embedFile("vendor/gmp/gmp-h.in");

/// The shared library's version, read out of upstream's libtool versioning.
///
/// `libmpfr_la_LDFLAGS = $(MPFR_LDFLAGS) $(LIBMPFR_LDFLAGS) -version-info 8:2:2`
/// (src/Makefile.am:106) is libtool's `CURRENT:REVISION:AGE`. Libtool's library
/// major is `CURRENT - AGE`, and its real file name is
/// `$libname.so.$major.$age.$revision` with soname `$libname.so.$major`, so
/// `8:2:2` names `libmpfr.so.6.2.2` and sonames it `libmpfr.so.6`.
///
/// Reading the triple rather than writing `6, 2, 2` is the point: the same
/// `src/Makefile.am` already names libmpfr's source list and its generated
/// units, and a rebase that changed `-version-info` has to be visible here as a
/// build failure rather than as a soname that silently disagrees with upstream.
/// Passing no version at all is the other wrong answer: it would produce an
/// unversioned `libmpfr.so`, which is not the name any libtool-built MPFR on
/// this platform has ever shipped under.
fn sharedLibraryVersion(b: *std.Build) std.SemanticVersion {
    const triple = libtoolVersionInfo(b, "libmpfr_la_LDFLAGS");
    return .{ .major = triple.current - triple.age, .minor = triple.age, .patch = triple.revision };
}

/// Libtool's `CURRENT:REVISION:AGE`, as written in one `lib*_la_LDFLAGS`
/// assignment.
const VersionInfo = struct { current: u32, revision: u32, age: u32 };

/// Parse `-version-info CURRENT:REVISION:AGE` out of `assignment`.
///
/// A missing assignment or a missing or malformed `-version-info` is a build
/// failure naming the file and the assignment, for the same reason
/// `assignmentWords` refuses to guess libmpfr's source list: a wrong soname
/// here would be shipped, and a shorter library would be built.
fn libtoolVersionInfo(b: *std.Build, assignment: []const u8) VersionInfo {
    const flag = "-version-info";
    const words = assignmentWords(b, assignment);
    for (words, 0..) |word, index| {
        // Automake separates a flag from its argument with whitespace, so the
        // triple is the word after the flag, not part of the same token.
        if (!std.mem.eql(u8, word, flag) or index + 1 >= words.len) continue;
        var parts = std.mem.splitScalar(u8, words[index + 1], ':');
        const current = parts.next() orelse continue;
        const revision = parts.next() orelse continue;
        const age = parts.next() orelse continue;
        if (parts.next() != null) continue;
        return .{
            .current = std.fmt.parseInt(u32, current, 10) catch continue,
            .revision = std.fmt.parseInt(u32, revision, 10) catch continue,
            .age = std.fmt.parseInt(u32, age, 10) catch continue,
        };
    }
    @panic(b.fmt(
        "src/Makefile.am no longer carries a '-version-info CURRENT:REVISION:AGE' " ++
            "in {s}; refusing to name the shared library by guesswork",
        .{assignment},
    ));
}

/// GMP's own four licence texts, installed with the GMP artifact.
///
/// GMP is LGPL or GPL (`vendor/gmp/COPYING`, `COPYING.LESSERv3`, `COPYINGv2`,
/// `COPYINGv3`) and ships all four files; an installation of libgmp that drops
/// any of them is not a redistribution of GMP.
const gmp_licence_files = [_][]const u8{
    "COPYING",
    "COPYING.LESSERv3",
    "COPYINGv2",
    "COPYINGv3",
};

/// MPFR's own licence material and the fork's provenance records, installed
/// into `share/licenses/mpfr/`.
///
/// `COPYING` and `COPYING.LESSER` are upstream's terms, which LGPL requires be
/// redistributed with the code; the four records are this fork's own, and they
/// are the ones that say what the fork added and under which grant. All six are
/// installed by this file because this file is the only writer of an installed
/// path in this package: the packaging layer that owns those documents does not
/// install them as well, so a prefix cannot end up carrying GMP's terms and
/// none of MPFR's.
const mpfr_licence_files = [_][]const u8{
    "COPYING",
    "COPYING.LESSER",
    "NOTICE.md",
    "FORK-LICENSE.md",
    "UPSTREAM.md",
    "README.upstream.md",
};

/// The C dialect every libmpfr translation unit is built with.
///
/// `-std=gnu11` is required because MPFR's own public header relies on GNU
/// statement expressions and `__builtin_constant_p` (src/mpfr.h:921-925,
/// 964-1021). It also pins the language the configuration macros assume:
/// `_Static_assert` (ISO C11 6.7.10) and `_Noreturn` (ISO C11 6.7.4) are only
/// guaranteed to exist under it, and `zig/config_gen.zig` defines
/// `MPFR_USE_STATIC_ASSERT` and `MPFR_HAVE_NORETURN` on that basis.
const c_standard = "-std=gnu11";

/// The `NAME=VALUE` text of every configuration macro `zig/config_gen.zig`
/// derives for `target`, in its declared order.
///
/// This one list feeds both C command lines: the compile line takes `-D` plus
/// each entry, and `b.addTranslateC` takes each entry through
/// `defineCMacroRaw`, which appends `-D` and the text itself. Deriving both
/// from one list is what makes it impossible for the library and the
/// translation to disagree about which entry points exist.
fn macroDefinitions(b: *std.Build, target: std.Target) []const []const u8 {
    var out: std.ArrayList([]const u8) = .empty;
    for (config.macros(config.paramsFor(target))) |macro| {
        out.append(b.allocator, b.fmt("{s}={s}", .{ macro.name, macro.value })) catch @panic("OOM");
    }
    return out.items;
}

/// The flags every libmpfr translation unit is compiled with: the C dialect,
/// then one `-D` per entry of `definitions`.
fn cFlags(b: *std.Build, definitions: []const []const u8) []const []const u8 {
    var out: std.ArrayList([]const u8) = .empty;
    out.append(b.allocator, c_standard) catch @panic("OOM");
    for (definitions) |definition| {
        out.append(b.allocator, b.fmt("-D{s}", .{definition})) catch @panic("OOM");
    }
    return out.items;
}

/// The six targets the shared fork contract requires `check` to cover.
const required_targets = [_]struct { name: []const u8, query: std.Target.Query }{
    .{ .name = "x86_64-linux-gnu", .query = .{ .cpu_arch = .x86_64, .os_tag = .linux, .abi = .gnu } },
    .{ .name = "aarch64-linux-gnu", .query = .{ .cpu_arch = .aarch64, .os_tag = .linux, .abi = .gnu } },
    .{ .name = "aarch64-macos-none", .query = .{ .cpu_arch = .aarch64, .os_tag = .macos, .abi = .none } },
    .{ .name = "x86_64-windows-gnu", .query = .{ .cpu_arch = .x86_64, .os_tag = .windows, .abi = .gnu } },
    .{ .name = "riscv64-linux-gnu", .query = .{ .cpu_arch = .riscv64, .os_tag = .linux, .abi = .gnu } },
    .{ .name = "wasm32-wasi", .query = .{ .cpu_arch = .wasm32, .os_tag = .wasi } },
};

/// Why a target has no buildable graph here, in the two halves every refusal
/// in this file is printed from.
///
/// The shape is `lmdb/build.zig:458-464`'s, and for the same reason: the
/// selected target fails the configure with the summary on one line, and the
/// detail says which source records the fact and what does build, so a reader
/// who only has the first line still knows which boundary was hit.
const Refusal = struct {
    /// One line, printed with the target's own triple in front of it.
    summary: []const u8,
    /// The long form: the platform fact, the sources that record it, what was
    /// deliberately not done about it, and the targets that do build.
    detail: []const u8,
};

/// Why `target` cannot be built here, or null when it can.
///
/// One decision, asked from the two places that need it: `build` for the
/// target the user selected, and the `matrix` loop for each cell it walks.
/// Both ask this function, so the selected-target failure and the per-cell
/// exclusion cannot describe the same boundary two different ways — the rule
/// `box2d/build.zig:670-687` states for its own linkage refusal.
///
/// The refusal is asked of every route, `-Dsystem=gmp` and `-Dsystem=mpfr`
/// included. Those two compile no vendored GMP and link an installed library
/// instead, but the Hexagon boundary is this package's own as well:
/// `zig/config_gen.zig:236-272` has to record a C double format for the
/// architecture whichever GMP the library is compiled against.
fn refusalFor(target: std.Build.ResolvedTarget) ?Refusal {
    // A CPU GMP 6.3.0 does not port. The check is on the architecture rather
    // than on the triple because the fact is about the CPU: `hexagon-linux`
    // and any other hexagon target hit the same three records, and none of
    // them names an operating system.
    if (target.result.cpu.arch == .hexagon) {
        return .{
            .summary = "MPFR has no buildable configuration for this target: GMP has no Hexagon port.",
            .detail =
            \\GMP 6.3.0 ships no port for this CPU. There is no mpn/hexagon
            \\directory and no tune/hexagon.asm, and the word "hexagon" appears
            \\in neither vendor/gmp/configure.ac nor the config.sub and
            \\config.guess that the shipped configure runs
            \\(vendor/gmp/configure:3047-3053). It appears only in the
            \\configfsf.guess/configfsf.sub pair, which that configure never
            \\invokes. Upstream's own configure therefore rejects the triple
            \\before it reaches the mpn selection, and --disable-assembly
            \\(configure.ac:2670-2672, which sets path="generic") is the
            \\documented "no assembly for this CPU" fallback rather than a
            \\port.
            \\
            \\Neither of this package's own configuration tables records the CPU
            \\either. vendor/gmp/zig/config_gen.zig:122-171 names every
            \\std.Target.Cpu.Arch it supports and then refuses the rest (:169),
            \\and zig/config_gen.zig:236-272 does the same for the C double
            \\format (:267). Both are these forks' own guards reporting an
            \\architecture they hold no facts for; neither is a compiler
            \\diagnostic, and neither is an MPFR defect.
            \\
            \\Adding an arm to either table would assert ABI facts this
            \\repository cannot check — limb size, endianness and double format
            \\for a CPU GMP does not port — and would claim a build nobody has
            \\run. So the target is refused here, and this text is what the
            \\refusal reports.
            \\
            \\Nothing was substituted: no libmpfr, no libgmp, no test binary and
            \\no installed prefix for this target, and no result is claimed for
            \\one. The target keeps its place in every matrix that walks this
            \\package, and this text is what that cell reports.
            \\
            \\Build for a target this package configures: x86_64-linux-gnu,
            \\aarch64-linux-gnu, aarch64-macos-none, x86_64-windows-gnu,
            \\riscv64-linux-gnu.
            ,
        };
    }

    return null;
}

pub fn build(b: *std.Build) error{UnsupportedTarget}!void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});
    const use_system_mpfr = b.systemIntegrationOption("mpfr", .{});
    const use_system_gmp = b.systemIntegrationOption("gmp", .{});
    // Static is the default because it is what this package produced before the
    // option existed: `b.addLibrary` with no `linkage` field builds a static
    // library. An absent `-Dlinkage` therefore keeps every existing invocation,
    // CI step and consumer working unchanged.
    const linkage = b.option(
        std.builtin.LinkMode,
        "linkage",
        "Linkage of the installed libmpfr: static (default) or dynamic",
    ) orelse .static;
    // Off by default, so every existing invocation keeps linking. Orthogonal to
    // the two system options: a runtime build over an installed MPFR generates
    // its dispatch from the installed headers and links nothing, which is a
    // runtime arrangement rather than an unsupported combination. See the
    // "Runtime route" section above.
    const runtime_loaded = b.option(
        bool,
        "runtime",
        "Resolve MPFR and GMP through the platform loader at run time instead of linking them",
    ) orelse false;

    // A target this graph cannot build is refused here, at configure time,
    // before `wireUp` wires or compiles anything. The reason is then this
    // build's own and arrives first, where a reader can act on it, instead of
    // a panic from a vendored package's own architecture table
    // (`vendor/gmp/zig/config_gen.zig:169`). `error.UnsupportedTarget` is the
    // typed refusal this workspace already uses for a target it declines
    // (`lmdb/build.zig:529-536`), and Zig 0.16's `runBuild` propagates an error
    // out of `build.zig` (`std/Build.zig:2261-2266`), so a driver reads the
    // reason and the typed error rather than a compile failure.
    //
    // Nothing is built for a refused target and nothing is installed for it:
    // the refusal happens before the first step is created, not after.
    if (refusalFor(target)) |refusal| {
        const triple = target.query.zigTriple(b.allocator) catch @panic("OOM");
        defer b.allocator.free(triple);
        std.log.err("mpfr: {s}: {s}\n{s}", .{ triple, refusal.summary, refusal.detail });
        return error.UnsupportedTarget;
    }

    const native = wireUp(
        b,
        target,
        optimize,
        use_system_mpfr,
        use_system_gmp,
        linkage,
        runtime_loaded,
        true,
    );

    if (native.library) |library| {
        b.installArtifact(library);
        markPublicHeaders(b, library);
        installPkgConfig(b);
        installLicenceRecords(b);
    }
    // Only the published graph installs: the matrix builds the same vendored
    // GMP once per target, and installing each of those would put six copies of
    // libgmp in the prefix. The GMP that the installed libmpfr is linked against
    // is the one this graph built.
    if (native.vendored_gmp) |gmp| installGmpClosure(b, gmp);

    // Both of these run out of the build cache, which is why the facade links
    // the archives with the ordinary `linkLibrary` call and Zig bakes the
    // cache's own directory into each binary: out of the cache that is where
    // the shared objects are. Neither program is ever installed.
    const run_example = b.addRunArtifact(native.example);
    if (b.args) |args| run_example.addArgs(args);
    b.step("run", "Run the deterministic MPFR example").dependOn(&run_example.step);
    b.step("smoke", "Run the deterministic MPFR example and report its output")
        .dependOn(&run_example.step);

    const run_tests = b.addRunArtifact(native.tests);
    b.step("test", "Run the MPFR behaviour suite").dependOn(&run_tests.step);

    // `check` compiles the test binary and the example without running either, so
    // every public facade method is analysed even for a target whose binaries
    // cannot be executed here.
    const check_step = b.step("check", "Compile the facade and the example without running them");
    check_step.dependOn(&native.tests.step);
    check_step.dependOn(&native.example.step);

    // Only the standard target's module is published, so a dependent's
    // `dep.module("mpfr")` always resolves to that one; the matrix builds
    // private modules instead of overwriting it.
    // A cell this graph refuses is printed with its reason and left out of the
    // compile rather than compiled until a C diagnostic appears four hundred
    // lines deep. The cell is not removed from `required_targets` and not
    // removed from any matrix that walks this package, so the exclusion is
    // where a reader of those matrices learns the boundary. The other cells
    // are still compiled: a refusal of one target is not a reason to stop
    // covering the rest, which is the whole point of a matrix step. A printed
    // exclusion is not a pass, and no artifact is produced for it.
    const matrix_step = b.step("matrix", "Compile `check` for the required targets this graph can build");
    for (required_targets) |entry| {
        const cross_target = b.resolveTargetQuery(entry.query);
        if (refusalFor(cross_target)) |refusal| {
            std.debug.print(
                "mpfr: matrix: {s} is NOT covered by this run.\n{s}\n{s}\n",
                .{ entry.name, refusal.summary, refusal.detail },
            );
            continue;
        }
        const cross = wireUp(
            b,
            cross_target,
            optimize,
            use_system_mpfr,
            use_system_gmp,
            linkage,
            runtime_loaded,
            false,
        );
        matrix_step.dependOn(&cross.tests.step);
        matrix_step.dependOn(&cross.example.step);
    }
}

/// The compile steps a single target needs. `library` is absent in system mode,
/// where there is nothing in this repository to build.
const Graph = struct {
    library: ?*std.Build.Step.Compile,
    /// The vendored GMP artifact this graph links against, or null when the
    /// installed-system route was selected. Only the published graph installs
    /// it; see the call in `build`.
    vendored_gmp: ?*std.Build.Step.Compile,
    tests: *std.Build.Step.Compile,
    example: *std.Build.Step.Compile,
};

/// Wire up the whole package for one resolved target.
///
/// Called once for the standard target and once per entry in
/// `required_targets`, so it must not mutate target-independent state. Only the
/// standard target's facade is published as the `mpfr` module, because
/// `b.addModule` is keyed by name and the last registration would otherwise win
/// for every dependent.
fn wireUp(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    use_system_mpfr: bool,
    use_system_gmp: bool,
    linkage: std.builtin.LinkMode,
    runtime_loaded: bool,
    publish: bool,
) Graph {
    const generated = generateUpstreamSources(b);
    // In `-Dsystem=mpfr` mode the installed MPFR comes with its own GMP, so the
    // vendored GMP include tree must not reach the translation: pointing it at a
    // different GMP's gmp.h would translate declarations the linked library does
    // not implement.
    //
    // `linkage` is forwarded to the vendored GMP unchanged. Upstream's own rule
    // (`configure.ac:635-662`) is that the two libraries must agree, and the
    // macro that decides it, `__GMP_LIBGMP_DLL`, is generated from the GMP
    // library's own linkage; giving both the same value is what makes the pair
    // agree without a second private option on either side.
    //
    // The vendored route is the only one that has an artifact at all: with
    // `-Dsystem=gmp` or `-Dsystem=mpfr` there is nothing of ours to install.
    const gmp = if (use_system_mpfr or use_system_gmp)
        null
    else
        gmpDependency(b, target, optimize, linkage).artifact(gmp_package);
    // The include directory that holds GMP's generated `gmp.h` is the emitted
    // header tree of the GMP artifact: `Step.Compile.installHeader` records a
    // header as travelling with the artifact it is installed from, and
    // `Step.Compile.getEmittedIncludeTree` materialises the whole set as one
    // directory. The system routes add nothing, because the system include path
    // already has `gmp.h`.
    const gmp_include = if (gmp) |artifact| artifact.getEmittedIncludeTree() else null;

    // The configuration `configure` would have computed for this target. One
    // list, consumed twice below: once for the translation, once for the
    // library's compile line.
    const definitions = macroDefinitions(b, target.result);

    // The public C module. `src/` joins the include path in vendored mode only,
    // so system mode translates the installed headers instead.
    const translate = b.addTranslateC(.{
        .root_source_file = b.path("fork/mpfr_all.h"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    if (!use_system_mpfr) translate.addIncludePath(b.path("src"));
    if (gmp_include) |gmp_path| translate.addIncludePath(gmp_path);
    // A module's own `linkSystemLibrary` reaches compile and link lines but
    // never the translator, which reads its own list and hands it to
    // `createModule` below. So the selected `.pc` answer is asked for here,
    // once, and reaches the translation and the module together.
    // `preferred_link_mode` keeps `linkSystemLibrary`'s own default.
    if (use_system_mpfr) {
        translate.linkSystemLibrary(library_name, .{ .use_pkg_config = .force });
    }
    if (use_system_gmp) {
        translate.linkSystemLibrary(gmp_package, .{ .use_pkg_config = .force });
    }

    // `defineCMacroRaw` takes `NAME=VALUE` and appends the `-D` itself.
    for (definitions) |definition| {
        translate.defineCMacroRaw(definition);
    }
    // One translation step, two consumers. The linked route's `c` is the
    // translated header itself; the runtime route's `c` is the generated
    // dispatch, which reads *this* step's output, so both routes describe the
    // header this build selected rather than one of them describing another.
    const c_module = if (runtime_loaded)
        graph.createModule(b, translate, target, optimize)
    else
        translate.createModule();

    var library: ?*std.Build.Step.Compile = null;
    // `-Dsystem=mpfr` compiles nothing of ours: the translation above reads
    // the installed headers and the exported module names the library for its
    // dependents, so what is left of this test is the absence of an artifact
    // to install. `-Dsystem=gmp` on its own still compiles libmpfr, against
    // that GMP.
    if (!use_system_mpfr) {
        library = buildUpstreamLibrary(
            b,
            target,
            optimize,
            use_system_gmp,
            linkage,
            definitions,
            gmp_include,
            gmp,
            generated,
        );
    }

    // The public `mpfr` module: root.zig, with the translated C API imported as
    // "c" so that `pub const c = @import("c")` works for dependents too.
    const mpfr_module = if (publish)
        b.addModule(library_name, .{
            .root_source_file = b.path("root.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        })
    else
        b.createModule(.{
            .root_source_file = b.path("root.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        });
    mpfr_module.addImport("c", c_module);
    // The loader core is a direct import of the facade only in the linked route,
    // where there is no dispatch to carry `LoadSource` and `LoadError` and the
    // facade has to name them itself (root.zig:245,251). In the runtime route the
    // dispatch re-exports both from the single core instance it creates, and a
    // second instance here would be a second set of types
    // (runtime/graph.zig:109-112).
    if (!runtime_loaded) {
        mpfr_module.addImport("rt", graph.createCoreModule(b, target, optimize));
    }
    // Linking the compiled archives is the one thing the runtime route must not
    // do, and it is the only step skipped: the libraries are still built and
    // installed above, and nothing else in the graph referenced them, so the
    // linker cannot resolve a single MPFR or GMP symbol statically.
    if (!runtime_loaded) {
        if (library) |built| {
            // The public module is what every program of this build imports,
            // and every one of those programs is a proof rather than a
            // deliverable: `fork/example/main.zig` and the test root are run by
            // `run`, `smoke` and `test`, and neither is ever installed. This
            // package installs libraries, headers and metadata and no program
            // at all, so there is no installed tree whose `$ORIGIN/../lib` a
            // program of ours would have to find, and the ordinary
            // `linkLibrary` is the right call: Zig bakes in the directory the
            // shared object was really emitted into, which is where the loader
            // has to look when the program runs out of the build cache.
            // `linkInstalledSibling` is the one link in this file that does
            // reach an installed file, and it is the library's own.
            mpfr_module.linkLibrary(built);
            // GMP belongs on the dependent's own link line, not only inside
            // libmpfr. `fork/mpfr_all.h` includes <mpfr.h>, and `mpfr.h`
            // includes <gmp.h>, so the translated module declares GMP's whole
            // function route and its three exported objects -
            // `__gmp_bits_per_limb`, `__gmp_errno`, `__gmp_version`
            // (root.zig:148-152) - and a dependent that reads one of them
            // references the symbol from its own object file.
            //
            // The static route hid that. A static libmpfr's archive dependency
            // on libgmp propagates to every dependent, so the closure was
            // reached without anyone asking for it. A shared libmpfr records a
            // `DT_NEEDED` on libgmp and nothing more, and a linker that does
            // not copy indirect entries - the default since binutils 2.22 -
            // will not satisfy the dependent's own reference to
            // `__gmp_bits_per_limb` out of that indirect library. The closure
            // is therefore stated here once, and stated for both linkages
            // rather than only where a transitive archive used to supply it.
            //
            // `-Dsystem=mpfr` deliberately adds nothing: this file installs
            // upstream's own `mpfr.pc.in` verbatim, and its `Libs:` line ends
            // with `-lmpfr -lgmp`, so the installed system library's own
            // metadata already carries the same closure.
            if (gmp) |vendored| {
                // The same reasoning as the line above, for the second archive
                // on the same link line.
                mpfr_module.linkLibrary(vendored);
            } else if (use_system_gmp) {
                // The same pkg-config route `buildUpstreamLibrary` took, so the
                // installed GMP this library was compiled against and the one a
                // dependent resolves are one library, not two that happen to
                // share a name.
                mpfr_module.linkSystemLibrary(gmp_package, .{ .use_pkg_config = .force });
            }
        } else {
            mpfr_module.linkSystemLibrary(library_name, .{ .use_pkg_config = .force });
        }
    }

    return .{
        .library = library,
        .vendored_gmp = gmp,
        .tests = b.addTest(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path("fork/tests/all_tests.zig"),
                .target = target,
                .optimize = optimize,
                .link_libc = true,
                .imports = &.{.{ .name = library_name, .module = mpfr_module }},
            }),
        }),
        .example = b.addExecutable(.{
            .name = "mpfr-example",
            .root_module = b.createModule(.{
                .root_source_file = b.path("fork/example/main.zig"),
                .target = target,
                .optimize = optimize,
                .link_libc = true,
                .imports = &.{.{ .name = library_name, .module = mpfr_module }},
            }),
        }),
    };
}

/// Compile the whole of libmpfr from this repository.
fn buildUpstreamLibrary(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    use_system_gmp: bool,
    linkage: std.builtin.LinkMode,
    definitions: []const []const u8,
    gmp_include: ?std.Build.LazyPath,
    gmp: ?*std.Build.Step.Compile,
    generated: *std.Build.Step.WriteFile,
) *std.Build.Step.Compile {
    const module = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        // `null` on the static route means "the driver decides", which is what
        // this build did before the option existed; passing `false` there would
        // add `-fno-PIC` and change the default artefact.
        .pic = if (linkage == .dynamic) true else null,
    });
    // The C dialect and one `-D` per configuration macro, from the same
    // `definitions` list the translation got.
    const flags = cFlags(b, definitions);
    module.addCSourceFiles(.{
        .files = upstreamSources(b),
        .flags = flags,
    });
    // The generated units come from the `addWriteFiles` directory, never from
    // `src/`: `nodist_libmpfr_la_SOURCES = $(BUILT_SOURCES)`
    // (src/Makefile.am:79) is built in the build directory. The names still
    // come from upstream's own assignment, so an upstream rebase that adds a
    // generated unit is noticed rather than silently dropped.
    for (builtSources(b)) |name| {
        module.addCSourceFile(.{
            .file = generated.getDirectory().path(b, name),
            .flags = flags,
        });
    }
    // `src/` is needed in addition to the generated directory because the
    // generated `mparam.h` includes its architecture thresholds as
    // `#include "generic/mparam.h"` and `#include "x86_64/mparam.h"`
    // (src/mparam_h.in:26-85), which resolve against the include path and not
    // against the generated file's own directory.
    module.addIncludePath(b.path("src"));
    module.addIncludePath(generated.getDirectory());
    if (gmp_include) |gmp_path| module.addIncludePath(gmp_path);
    if (use_system_gmp) {
        module.linkSystemLibrary(gmp_package, .{ .use_pkg_config = .force });
    } else {
        // libmpfr and libgmp are siblings in `lib/` of the one prefix this
        // installs, so the shared object needs `$ORIGIN` and nothing else:
        // `$ORIGIN/../lib` would be right for a program and wrong for a
        // library, whose own directory is the one its dependency sits in.
        linkInstalledSibling(module, gmp.?, target);
    }

    return b.addLibrary(.{
        .name = library_name,
        // No `-D` is added for the DLL arrangement: `src/mpfr-impl.h:82-84`
        // defines `__MPFR_WITHIN_MPFR` in every library unit, and
        // `__GMP_LIBGMP_DLL` in the generated `gmp.h` turns that into
        // `__MPFR_DECLSPEC` (`src/mpfr.h:321-331`) and into
        // `MPFR_WIN_THREAD_SAFE_DLL` (`src/mpfr-impl.h:251-253`).
        .linkage = linkage,
        // `version` names the shared object: `libmpfr.so.6.2.2` with soname
        // `libmpfr.so.6`. A static library has no name to carry it, which is
        // why the value is null there rather than passed and ignored.
        .version = if (linkage == .dynamic) sharedLibraryVersion(b) else null,
        .root_module = module,
    });
}

/// The runtime search path an installed *library* needs.  A shared library
/// this package installs sits in the same `lib/` as everything it needs, so
/// the entry is the directory it is already in; a library with no
/// non-standard dependency needs none at all.
fn installedLibraryRPath(target: std.Build.ResolvedTarget) ?[]const u8 {
    return switch (target.result.os.tag) {
        .windows, .wasi, .uefi => null,
        else => if (target.result.os.tag.isDarwin()) "@loader_path" else "$ORIGIN",
    };
}

/// Link a shared library this build produces into `module`, and give the
/// artifact the search path its *installed* copy needs and nothing else.
///
/// The one link in this file whose result is installed is libmpfr's own link
/// line, where libgmp is a sibling under the same `lib/`; there the entry is
/// `$ORIGIN`, the directory the library already sits in.
///
/// `Module.linkLibrary` would instead record the directory the shared object
/// was emitted into, because `Step.Compile` appends `-rpath <dir>` for every
/// dynamic artifact a compilation links
/// (`lib/std/Build/Step/Compile.zig:1290-1297`, the block reached from
/// `.other_step`).  That directory is the build cache.  It does not exist
/// once the file is installed, and Nix refuses an installed file that names
/// its own build directory at all, so an installed artifact that carried it
/// could never be packaged -- and on ELF the loader would search a directory
/// that is gone rather than the one that is there.
/// `Module.addObjectFile` puts the very same file on the link line and records
/// no search path at all, which leaves the relocatable entry below as the
/// only one the artifact carries.
fn linkInstalledSibling(
    module: *std.Build.Module,
    library: *std.Build.Step.Compile,
    target: std.Build.ResolvedTarget,
) void {
    // Windows links through the import library and has no rpath, so the
    // ordinary call is the right one there and is kept.
    if (library.linkage != .dynamic or target.result.os.tag == .windows) {
        module.linkLibrary(library);
        return;
    }
    module.addObjectFile(library.getEmittedBin());
    if (installedLibraryRPath(target)) |rpath| module.addRPathSpecial(rpath);
}

/// The vendored GMP artifact, guarded so a missing snapshot is reported with the
/// action needed rather than as a bare path-dependency error.
///
/// The snapshot is looked for under `b.build_root`, which is the directory
/// holding this package's `build.zig.zon`, not the working directory of
/// whatever invoked the build. A dependent that runs `zig build` from its own
/// directory resolves the `.path` dependency relative to this package root,
/// so probing the caller's directory would report a snapshot that is present
/// as missing, or a directory that is not the dependency at all.
fn gmpDependency(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    linkage: std.builtin.LinkMode,
) *std.Build.Dependency {
    if (b.build_root.handle.access(b.graph.io, vendored_gmp, .{})) |_| {} else |_| {
        @panic(
            "mpfr: " ++ vendored_gmp ++ " is missing or unreadable. MPFR cannot be " ++
                "built without GMP, and the shared fork contract requires a " ++
                "self-contained snapshot: copy the verified GMP package there, " ++
                "including its build.zig.zon, or pass -Dsystem=gmp to use an " ++
                "installed GMP instead.",
        );
    }
    // `linkage` is a real user input option of the GMP package: `b.option` there
    // declares it, so forwarding it here is a declared interface rather than an
    // option the dependency would reject as unused. It arrives as the string
    // `-Dlinkage=dynamic` or `-Dlinkage=static`.
    return b.dependency(gmp_package, .{
        .target = target,
        .optimize = optimize,
        .linkage = linkage,
    });
}

/// Mark MPFR's two public headers as travelling with the artifact, so a dependent
/// module that links this library also gets `<mpfr.h>` on its include path.
fn markPublicHeaders(b: *std.Build, library: *std.Build.Step.Compile) void {
    library.installHeader(b.path("src/mpfr.h"), "mpfr.h");
    library.installHeader(b.path("src/mpf2mpfr.h"), "mpf2mpfr.h");
}

/// Install the vendored GMP the library was linked against, plus the licence
/// texts GMP itself ships.
///
/// This closes the installed prefix. A shared libmpfr records a `DT_NEEDED` on
/// libgmp and a static one leaves every `__gmpfr_*` and `mpz_*` reference to
/// the consumer, so a prefix holding only libmpfr is neither loadable nor
/// linkable; GMP's own `gmp_include_HEADERS` travel with the artifact because
/// the GMP package installs them as artifact headers. GMP is LGPL or GPL and
/// ships four separate terms, so all four are installed next to the library
/// they cover.
///
/// GMP's `gmp.pc` is installed here as well, and it has to be rendered here
/// rather than taken from the dependency: `std.Build.Dependency` exposes an
/// artifact and a module, never the dependency's install step, so a `.path`
/// dependency's installed files are reachable only through the artifact this
/// function already installs. Depending on that step instead would also drag in
/// the GMP package's example binary, which `build` deliberately keeps out of
/// this prefix (see the call site).
///
/// MPFR's own terms and this fork's provenance records go to a different
/// directory, `share/licenses/mpfr/`, so an installed prefix carries one
/// licence directory per library it ships rather than one naming only the
/// dependency. `installLicenceRecords` owns that half.
fn installGmpClosure(b: *std.Build, gmp: *std.Build.Step.Compile) void {
    b.installArtifact(gmp);
    installGmpPkgConfig(b);
    for (gmp_licence_files) |name| {
        b.installFile(b.fmt("{s}/{s}", .{ vendored_gmp, name }), b.fmt("share/licenses/gmp/{s}", .{name}));
    }
}

/// Install MPFR's licence texts and this fork's provenance records.
fn installLicenceRecords(b: *std.Build) void {
    for (mpfr_licence_files) |name| {
        b.installFile(name, b.fmt("share/licenses/mpfr/{s}", .{name}));
    }
}

/// Install `mpfr.pc`, rendered from upstream's `mpfr.pc.in`.
///
/// `configure` substitutes five placeholders into that template and installs
/// the result; this does the same five and changes nothing else, so the
/// `Libs:` line keeps upstream's own `-L${libdir} -lmpfr -lgmp`. No `Requires:`
/// is added, and none is needed: `gmp.pc` carries no dependency of its own, so
/// `Requires: gmp` would only restate the `-lgmp` already on this line, and
/// `-lgmp` is what a consumer needs in both linkages, since a shared libmpfr
/// needs libgmp at link time too.
///
/// The directories match what `installArtifact` writes: `lib/` for the library
/// and `include/` for the headers, which is why `libdir` and `includedir` are
/// `${prefix}/lib` and `${prefix}/include` rather than a second layout.
///
/// `prefix` itself is `${pcfiledir}/../..` and nothing else. It cannot be
/// `${prefix}`: that is a self-reference, and pkg-config resolves a variable to
/// its own text when it is being defined, so it expands to the empty string
/// rather than to the install root. Every field written in terms of it then
/// inherits the emptiness — `libdir` becomes `/lib` — and the file describes no
/// directory on the machine at all, so a consumer fails in an installed prefix
/// that has never been moved as readily as in one that has. This file lands at
/// `<root>/lib/pkgconfig/mpfr.pc`, so `${pcfiledir}/../..` *is* `<root>`,
/// resolved by pkg-config when it reads the metadata rather than written into
/// the bytes when the tree was built: the same tree copied anywhere else keeps
/// working. It needs pkg-config 0.29+ or pkgconf.
fn installPkgConfig(b: *std.Build) void {
    const out = b.addWriteFiles();
    _ = out.add("mpfr.pc", pkgConfigSource(b));
    // `Step.InstallFile.create` records a step but does not attach it to the
    // install step, so `b.installFile`, which takes a path relative to the
    // build root, cannot be used for a file that lives in the cache; the
    // dependency has to be made explicit.
    b.getInstallStep().dependOn(&b.addInstallFile(
        out.getDirectory().path(b, "mpfr.pc"),
        "lib/pkgconfig/mpfr.pc",
    ).step);
}

/// Upstream's `mpfr.pc.in` with the five placeholders `configure` fills in.
fn pkgConfigSource(b: *std.Build) []const u8 {
    const substitutions = [_][2][]const u8{
        .{ "@prefix@", "${pcfiledir}/../.." },
        .{ "@exec_prefix@", "${prefix}" },
        .{ "@libdir@", "${prefix}/lib" },
        .{ "@includedir@", "${prefix}/include" },
        .{ "@PACKAGE_VERSION@", std.mem.trim(u8, version_file, " \t\r\n") },
    };
    var text: []const u8 = pkg_config_template;
    for (substitutions) |substitution| {
        text = std.mem.replaceOwned(u8, b.allocator, text, substitution[0], substitution[1]) catch
            @panic("OOM");
    }
    return text;
}

/// Install GMP's `gmp.pc`, rendered from the snapshot's own template.
///
/// GMP installs this file unconditionally - `pkgconfigdir = $(libdir)/pkgconfig`
/// and `pkgconfig_DATA = gmp.pc` (vendor/gmp/Makefile.am:121-122) - so an
/// installed libgmp without it is a prefix that describes nothing. See
/// `installGmpClosure` for why it is rendered here instead of taken from the
/// dependency.
fn installGmpPkgConfig(b: *std.Build) void {
    const out = b.addWriteFiles();
    _ = out.add("gmp.pc", gmpPkgConfigSource(b));
    b.getInstallStep().dependOn(&b.addInstallFile(
        out.getDirectory().path(b, "gmp.pc"),
        "lib/pkgconfig/gmp.pc",
    ).step);
}

/// The snapshot's `gmp.pc.in` with the placeholders its `configure` fills in.
///
/// The same directory substitutions `installPkgConfig` makes, because both
/// files describe artifacts that `installArtifact` puts in `lib/` and headers
/// it puts in `include/`. GMP's template also carries `@PACKAGE_NAME@`, which
/// MPFR's does not.
fn gmpPkgConfigSource(b: *std.Build) []const u8 {
    const substitutions = [_][2][]const u8{
        .{ "@prefix@", "${pcfiledir}/../.." },
        .{ "@exec_prefix@", "${prefix}" },
        .{ "@libdir@", "${prefix}/lib" },
        .{ "@includedir@", "${prefix}/include" },
        // `AC_INIT(GNU MP, GMP_VERSION, ..., gmp)` (vendor/gmp/configure.ac:40)
        // is where GMP's `configure` takes `PACKAGE_NAME` from.
        .{ "@PACKAGE_NAME@", "GNU MP" },
        .{ "@PACKAGE_VERSION@", gmpPackageVersion(b) },
    };
    var text: []const u8 = gmp_pkg_config_template;
    for (substitutions) |substitution| {
        text = std.mem.replaceOwned(u8, b.allocator, text, substitution[0], substitution[1]) catch
            @panic("OOM");
    }
    return text;
}

/// GMP's `major.minor.patch`, read out of the snapshot's own `gmp-h.in`.
///
/// `gmp-h.in:2338-2340` is what GMP's `configure:3619` renders the `VERSION`
/// macro from, and `version.c:33` compiles that macro into the exported
/// `gmp_version` string, so the metadata names the release the library reports
/// rather than one this file remembers.
fn gmpPackageVersion(b: *std.Build) []const u8 {
    return b.fmt("{d}.{d}.{d}", .{
        gmpHeaderMacroNumber(b, "__GNU_MP_VERSION"),
        gmpHeaderMacroNumber(b, "__GNU_MP_VERSION_MINOR"),
        gmpHeaderMacroNumber(b, "__GNU_MP_VERSION_PATCHLEVEL"),
    });
}

/// One number from a `#define NAME value` line of GMP's header template.
///
/// A missing or unparsable macro stops the build naming the file and the
/// macro, because the alternative is installing a version of guesswork as the
/// library's published identity.
fn gmpHeaderMacroNumber(b: *std.Build, name: []const u8) u32 {
    const prefix = b.fmt("#define {s}", .{name});
    var lines = std.mem.splitScalar(u8, gmp_header_template, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t");
        if (!std.mem.startsWith(u8, trimmed, prefix)) continue;
        const after = trimmed[prefix.len..];
        // `__GNU_MP_VERSION` is a prefix of the other two names, so requiring
        // whitespace after the name is what keeps the minor and patchlevel
        // lines from satisfying the major lookup.
        if (after.len == 0) continue;
        if (after[0] != ' ' and after[0] != '\t') continue;
        const value = std.mem.trim(u8, after, " \t");
        return std.fmt.parseInt(u32, value, 10) catch {
            @panic(b.fmt(
                "vendor/gmp/gmp-h.in: {s} is not a number ('{s}'); refusing to " ++
                    "install a pkg-config Version of guesswork",
                .{ name, value },
            ));
        };
    }
    @panic(b.fmt("vendor/gmp/gmp-h.in no longer defines {s}", .{name}));
}

/// Produce the two inputs that autotools would generate.
fn generateUpstreamSources(b: *std.Build) *std.Build.Step.WriteFile {
    const generated = b.addWriteFiles();
    _ = generated.addCopyFile(b.path("src/mparam_h.in"), "mparam.h");
    _ = generated.add("get_patches.c", getPatchesSource(b, patches_file));
    return generated;
}

/// Reproduce `tools/get_patches.sh`, which turns the `PATCHES` file into the
/// `src/get_patches.c` translation unit implementing `mpfr_get_patches`.
///
/// The emitted text is what `tools/get_patches.sh` writes for the same `PATCHES`
/// content. Upstream's script is the reference for the licence header, which must
/// not drift: `PATCHES` is empty at 4.2.2, so the whole file is fixed apart from
/// the return string.
/// The `PATCHES` content is read at build time, so the return string is
/// formatted rather than concatenated: `++` is comptime-only in Zig.
fn getPatchesSource(b: *std.Build, patches: []const u8) []const u8 {
    return b.fmt(
        \\/* mpfr_get_patches -- Patches that have been applied
        \\
        \\Copyright 2007-2025 Free Software Foundation, Inc.
        \\Contributed by the Pascaline and Caramba projects, INRIA.
        \\
        \\This file is part of the GNU MPFR Library.
        \\
        \\The GNU MPFR Library is free software; you can redistribute it and/or modify
        \\it under the terms of the GNU Lesser General Public License as published by
        \\the Free Software Foundation; either version 3 of the License, or (at your
        \\option) any later version.
        \\
        \\The GNU MPFR Library is distributed in the hope that it will be useful, but
        \\WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
        \\or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU Lesser General Public
        \\License for more details.
        \\
        \\You should have received a copy of the GNU Lesser General Public License
        \\along with the GNU MPFR Library; see the file COPYING.LESSER.
        \\If not, see <https://www.gnu.org/licenses/>. */
        \\
        \\#include "mpfr-impl.h"
        \\
        \\const char *
        \\mpfr_get_patches (void)
        \\{{
        \\  return "{s}";
        \\}}
        \\
    , .{patches});
}

/// Every `.c` file of libmpfr that lives in this repository: the
/// `libmpfr_la_SOURCES` list in `src/Makefile.am`, as paths relative to the
/// build root.
///
/// The generated units named by `BUILT_SOURCES` are not here; `builtSources`
/// returns those, and they are compiled out of the `addWriteFiles` directory.
///
/// A missing assignment is fatal rather than silently producing a shorter
/// library, because a subset build is exactly what the shared fork contract
/// forbids.
fn upstreamSources(b: *std.Build) []const []const u8 {
    var out: std.ArrayList([]const u8) = .empty;
    for (assignmentWords(b, "libmpfr_la_SOURCES")) |name| {
        if (!std.mem.endsWith(u8, name, ".c")) continue;
        out.append(b.allocator, b.fmt("src/{s}", .{name})) catch @panic("OOM");
    }
    return out.items;
}

/// The generated `.c` units, named by `BUILT_SOURCES` in `src/Makefile.am`.
///
/// `nodist_libmpfr_la_SOURCES = $(BUILT_SOURCES)` (src/Makefile.am:79) means
/// upstream builds these in the build directory, so each one resolves against
/// the generated include directory and never against `src/`. A `.c` name here
/// that this build does not emit would compile a stale or missing file, so the
/// caller pairs the list with `generateUpstreamSources`.
fn builtSources(b: *std.Build) []const []const u8 {
    var out: std.ArrayList([]const u8) = .empty;
    for (assignmentWords(b, "BUILT_SOURCES")) |name| {
        if (!std.mem.endsWith(u8, name, ".c")) continue;
        out.append(b.allocator, name) catch @panic("OOM");
    }
    return out.items;
}

/// Read one Automake assignment, for example `libmpfr_la_SOURCES`, and return its
/// whitespace-separated words. A line continues while it ends with a backslash.
fn assignmentWords(b: *std.Build, name: []const u8) []const []const u8 {
    const prefix = b.fmt("{s} =", .{name});
    var joined: std.ArrayList(u8) = .empty;
    var lines = std.mem.splitScalar(u8, src_makefile_am, '\n');
    var found = false;

    while (lines.next()) |line| {
        if (!found) {
            if (!std.mem.startsWith(u8, line, prefix)) continue;
            found = true;
            joined.appendSlice(b.allocator, line[prefix.len..]) catch @panic("OOM");
        } else {
            joined.appendSlice(b.allocator, line) catch @panic("OOM");
        }
        if (!std.mem.endsWith(u8, std.mem.trimEnd(u8, joined.items, " \t"), "\\")) break;
    }
    if (!found) {
        @panic(b.fmt(
            "src/Makefile.am no longer defines {s}; refusing to guess libmpfr's source list",
            .{name},
        ));
    }

    var out: std.ArrayList([]const u8) = .empty;
    var words = std.mem.tokenizeAny(u8, joined.items, " \t\\\r\n");
    while (words.next()) |word| {
        out.append(b.allocator, word) catch @panic("OOM");
    }
    return out.items;
}
