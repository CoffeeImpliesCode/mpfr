// SPDX-License-Identifier: LGPL-3.0-or-later
//
// Fork-authored. mpfr's `FORK-LICENSE.md` at this repository's root records the
// owner's authorization of that grant; the snapshot carries no GMP
// `FORK-LICENSE.md` of its own. This is the GMP fork's file inside that
// snapshot, and the supplier package's copy carries no such header, so a
// re-sync must either keep this line deliberately or drop it deliberately.

//! Build of the GMP 6.3.0 fork as a Zig package.
//!
//! What this does, in order:
//!
//!   1. Derives GMP's configuration from the resolved target (limb size, limb
//!      type, endianness, available headers) in `zig/config_gen.zig` and
//!      renders the two headers GMP's `configure` would have produced:
//!      `config.h` from `config.in` and the public `gmp.h` from `gmp-h.in`.
//!   2. Runs GMP's own host table generators (`gen-fib`, `gen-bases`, `gen-fac`,
//!      `gen-sieve`, `gen-psqr`, `gen-trialdivtab`, `gen-jacobitab`) for the
//!      target's limb size, with the arguments the upstream `Makefile.am`
//!      rules use.
//!   3. Compiles the real libgmp sources for the target: `mpz`, `mpq`, `mpf`,
//!      the portable C `mpn` layer, `printf`, `scanf` and the random state
//!      code, with `NO_ASM` and without autotools, CMake, Make or any download
//!      at build time.
//!      A WASI target additionally selects the toolchain's own
//!      signal emulation - the `_WASI_EMULATED_SIGNAL` its `signal.h` demands
//!      and its `libwasi-emulated-signal.a` - because GMP's `invalid.c` and
//!      `errno.c` include `<signal.h>` and raise `SIGFPE`. That is the only
//!      thing WASI changes here, and it changes no source.
//!   4. Exposes the result as the module `gmp` (facade plus the complete
//!      translated C API) and as the library artifact `gmp`, whose
//!      include tree carries the generated `gmp.h`, so a dependent needs only
//!      `dep.artifact("gmp")` or `dep.module("gmp")`.
//!   5. Installs `gmp.pc` beside the library, where upstream installs it
//!      (`Makefile.am:121-122`), so a prefix that ships libgmp also describes
//!      it. `gmpxx.pc` is not installed: upstream adds it only under
//!      `if WANT_CXX`, and this build compiles no C++.
//!
//! `-Dlinkage=static` is the default and is what this file always built.
//! `-Dlinkage=dynamic` builds a shared libgmp and changes three real things
//! together, because they are one decision upstream makes at once:
//!
//!   * the artifact's linkage, and with it the position-independent
//!     compilation of GMP's objects;
//!   * `LIBGMP_DLL` in the generated `gmp.h`, which `gmp-h.in:120-131` turns
//!     into `__GMP_DECLSPEC` and every dependent header reads, including
//!     MPFR's (`src/mpfr.h:321-331`, `src/mpfr-impl.h:251-253`);
//!   * the shared object's name, taken from upstream's own libtool
//!     versioning rather than from a number chosen here.
//!
//! Steps: `zig build` installs the library, `zig build test` runs the tests in
//! the current optimize mode, `zig build smoke` and `zig build run` run the
//! example, `zig build check` compiles the whole public surface for all six
//! supported targets without running anything, and `zig build provenance`
//! re-checks the licence and provenance records.

const std = @import("std");

const config = @import("zig/config_gen.zig");
const sources = @import("zig/sources.zig");

/// Targets the cross compilation check covers. Six triples including the two
/// ABIs that matter for GMP's limb type, LP64 and LLP64 (Windows), plus a
/// 32-bit pointer target.
const checked_targets = [_][]const u8{
    "x86_64-linux-gnu",
    "aarch64-linux-gnu",
    "aarch64-macos-none",
    "x86_64-windows-gnu",
    "riscv64-linux-gnu",
    "wasm32-wasi",
};

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});
    const use_system_library = b.systemIntegrationOption("gmp", .{});
    // Static is the default because it is what this file always built:
    // `b.addLibrary` with an explicit `.linkage = .static`. A dependent that
    // passes nothing gets the same library it always got.
    const linkage = b.option(
        std.builtin.LinkMode,
        "linkage",
        "Linkage of the libgmp artifact: static (default) or dynamic",
    ) orelse .static;

    // Registered up front so `dep.module("gmp")` resolves for dependents.
    const gmp_module = b.addModule("gmp", .{
        .root_source_file = b.path("root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const library = makeLibrary(b, target, optimize, linkage, gmp_module, use_system_library, true);

    // `pkgconfig_DATA = gmp.pc` (Makefile.am:122) is unconditional upstream, so
    // the library and its metadata are installed together or the installed
    // prefix describes libgmp to nobody. `-Dsystem=gmp` selects an installed
    // GMP and contributes nothing to this prefix - not even metadata naming a
    // library this build did not produce.
    switch (library) {
        .bundled => installPkgConfig(b),
        .system => {},
    }

    const example = addExample(b, target, optimize, gmp_module, library, "gmp-example");
    b.installArtifact(example);

    const smoke_run = b.addRunArtifact(example);
    smoke_run.step.dependOn(b.getInstallStep());
    const smoke_step = b.step("smoke", "Run the example and print deterministic results");
    smoke_step.dependOn(&smoke_run.step);

    const run_step = b.step("run", "Run the example");
    run_step.dependOn(&smoke_run.step);

    const tests = addTests(b, target, optimize, gmp_module, library, "gmp-test");
    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run the test suite");
    test_step.dependOn(&run_tests.step);

    // Cross compilation check: compile the whole public surface, run nothing.
    // The example and the test binary reference every public facade method, so
    // their bodies are instantiated.
    //
    // With no `-Dtarget=` this covers all six checked targets. With one, it
    // covers only that target, which is what lets CI name the target that
    // failed instead of reporting one aggregate result for the matrix.
    const check_step = b.step("check", "Compile the public facade, tests and example");
    if (!target.query.isNative()) {
        addTargetCheck(b, check_step, target.query, .debug, linkage, "gmp-check");
    } else {
        for (checked_targets) |triple| {
            // Zig 0.16's `Target.Query` has no `arch_os_abi` field: a triple is
            // parsed by `std.Build.parseTargetQuery`, which is what
            // `standardTargetOptions` itself uses for `-Dtarget`.
            const query = std.Build.parseTargetQuery(.{ .arch_os_abi = triple }) catch |err| {
                std.debug.panic("gmp: cannot parse checked target {s}: {s}", .{ triple, @errorName(err) });
            };
            addTargetCheck(b, check_step, query, .debug, linkage, b.fmt("gmp-check-{s}", .{triple}));
        }
    }

    addProvenanceStep(b);
}

/// Compiles the library, the facade module, the example and the test binary
/// for one target and attaches them to `check_step`. Nothing is run: a
/// cross-compiled binary cannot run on the host.
fn addTargetCheck(
    b: *std.Build,
    check_step: *std.Build.Step,
    query: std.Target.Query,
    optimize: std.builtin.OptimizeMode,
    linkage: std.builtin.LinkMode,
    name: []const u8,
) void {
    const resolved = b.resolveTargetQuery(query);
    const checked_module = b.createModule(.{
        .root_source_file = b.path("root.zig"),
        .target = resolved,
        .optimize = optimize,
    });
    const checked_library = makeLibrary(b, resolved, optimize, linkage, checked_module, false, false);

    const checked_example = addExample(
        b,
        resolved,
        optimize,
        checked_module,
        checked_library,
        name,
    );
    check_step.dependOn(&checked_example.step);

    const checked_tests = addTests(b, resolved, optimize, checked_module, checked_library, name);
    check_step.dependOn(&checked_tests.step);
}


/// How consumers link GMP: the artifact this build produces, or an installed
/// system library.
const Library = union(enum) {
    bundled: Bundled,
    system,

    const Bundled = struct {
        step: *std.Build.Step.Compile,
        /// Directory holding the generated `gmp.h`. It lives in the build
        /// cache, not in the source tree, so any C source of this build that
        /// includes the public header by name needs it on its own compile
        /// line; linking the artifact does not add include paths.
        include_dir: std.Build.LazyPath,
    };

    fn link(self: Library, module: *std.Build.Module) void {
        switch (self) {
            .bundled => |bundled| module.linkLibrary(bundled.step),
            .system => module.linkSystemLibrary("gmp", .{}),
        }
    }

    /// Extra include path a C source of this build needs. In system library
    /// mode the installed header is found through the default search path, so
    /// nothing is added there.
    fn cIncludeDir(self: Library) ?std.Build.LazyPath {
        return switch (self) {
            .bundled => |bundled| bundled.include_dir,
            .system => null,
        };
    }
};

fn makeLibrary(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    linkage: std.builtin.LinkMode,
    gmp_module: *std.Build.Module,
    use_system_library: bool,
    install: bool,
) Library {
    if (use_system_library) return makeSystemLibrary(b, target, optimize, gmp_module);
    return .{ .bundled = makeBundledLibrary(b, target, optimize, linkage, gmp_module, install) };
}

/// Build the real libgmp from this repository.
fn makeBundledLibrary(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    linkage: std.builtin.LinkMode,
    gmp_module: *std.Build.Module,
    install: bool,
) Library.Bundled {
    const params = config.paramsFor(target.result, optimize, linkage == .dynamic);
    const generated = generate(b, optimize, params);

    const library = b.addLibrary(.{
        .name = "gmp",
        .linkage = linkage,
        // Upstream's `LIBGMP_LT_CURRENT/REVISION/AGE` (Makefile.am:107-109)
        // reach `libgmp_la_LDFLAGS` at Makefile.am:294-295 as
        // `-version-info 15:0:5`; libtool's library major is `CURRENT - AGE`
        // and its real name is `$libname.so.$major.$age.$revision`. A static
        // library has no name to carry a version, hence null there.
        .version = if (linkage == .dynamic) sharedLibraryVersion(b) else null,
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            // `null` on the static route leaves the driver to decide, which is
            // what this build always did; `false` would add `-fno-PIC` and
            // change the default artefact.
            .pic = if (linkage == .dynamic) true else null,
        }),
    });

    // WASI signal emulation, and only for WASI.
    //
    // GMP asks for a signal in two compiled translation units: `invalid.c:37`
    // and `errno.c:37` include `<signal.h>` unconditionally, above every
    // `#ifdef` in the file, and `__gmp_invalid_operation` and `__gmp_exception`
    // call `raise (SIGFPE)` (`invalid.c:80`, `errno.c:52`). This toolchain's
    // `wasm-wasi-musl/signal.h:1-3` is a bare `#error` unless
    // `_WASI_EMULATED_SIGNAL` is defined, so on `wasm32-wasi` those two files
    // are not parseable at all without it, and every diagnostic of a wasm
    // build of this graph is inside those two units. `configure.ac` has no
    // wasm branch, so nothing upstream would set this; the configuration has
    // to come from the target's libc, and it is therefore a property of this
    // build rather than a fact about `config.h`.
    //
    // The provider is the one this toolchain's own WASI sysroot ships:
    // `lib/libc/wasi/libc-bottom-half/signal/signal.c` is compiled into the
    // target's `libwasi-emulated-signal.a`, and `lib/std/zig/target.zig:384`
    // lists `wasi-emulated-signal` among the library names a WASI+musl target
    // is known to have, so the linker resolves that name to that archive with
    // no search path of its own. It delivers a signal synchronously and ends
    // the module through its own exit; it is an emulation over what WASI has,
    // not a POSIX signal namespace.
    //
    // Nothing is surrendered to get there: no source is omitted, no substitute
    // for `raise` is written, no macro is invented, and `HAVE_RAISE` stays 1
    // (`zig/config_gen.zig:262`), which is what keeps `invalid.c:49-51` off its
    // `kill (getpid (), sig)` fallback. Both statements sit inside the
    // `os.tag == .wasi` test, so the other five checked targets are given
    // nothing they did not have before.
    if (target.result.os.tag == .wasi) {
        library.root_module.addCMacro("_WASI_EMULATED_SIGNAL", "1");
        // Linked on the module that holds the reference to `raise`. A
        // dependent that links this archive inherits it, because
        // `Step.Compile.getCompileDependencies(false)` walks a static
        // library's `link_objects` and puts every `system_lib` it finds on
        // the dependee's linker line
        // (`lib/std/Build/Step/Compile.zig:1064-1088`); under
        // `-Dlinkage=dynamic` the same entry is on the shared object's own
        // link line, which is where a dependent would look for it anyway.
        library.root_module.linkSystemLibrary("wasi-emulated-signal", .{});
    }

    // The library sources. `__GMP_WITHIN_GMP` is what upstream's `Makefile.am`
    // passes on `AM_CPPFLAGS`. Nothing else is needed on the command line:
    // `gmp-impl.h` includes the generated `config.h`, so every configuration
    // macro, `NO_ASM` and `HAVE_ALLOCA` included, is already in effect.
    library.root_module.addCSourceFiles(.{
        .files = sources.all,
        .flags = &.{"-D__GMP_WITHIN_GMP"},
    });
    // The two tables GMP generates at build time live in the generated
    // directory, not in the source tree.
    library.root_module.addCSourceFiles(.{
        .root = generated.directory,
        .files = &sources.generated,
        .flags = &.{"-D__GMP_WITHIN_GMP"},
    });
    // One translation unit per operation of every multi-function mpn
    // template. A template cannot be compiled on its own, so none of them is
    // in `sources.all`; each operation is a wrapper that selects one.
    library.root_module.addCSourceFiles(.{
        .root = generated.directory,
        .files = generated.operation_sources,
        .flags = &.{"-D__GMP_WITHIN_GMP"},
    });
    // Generated `gmp.h`, `config.h`, `gmp-mparam.h` and the table headers,
    // which `gmp-impl.h` and a few `mpn` files include by bare name.
    library.root_module.addIncludePath(generated.directory);
    // `gmp-impl.h` and `longlong.h` from the top of the tree.
    library.root_module.addIncludePath(b.path("."));

    // GMP's installed public header set, which is what upstream ships from
    // `gmp_include_HEADERS`: `gmp.h`, generated per target, and
    // `gmp-mparam.h`. Installing them into the artifact's include tree is what
    // puts `gmp.h` on a dependent's compile line, so a dependent needs only
    // `dep.artifact("gmp")` and never the source tree.
    //
    // GMP's internal `config.h` is deliberately not installed. It is private
    // to building this tree, and publishing it would shadow the `config.h` of
    // any autotools-configured dependent, which is the same failure mode as
    // linking new headers against an older installed library.
    library.installHeader(generated.gmp_header, "gmp.h");
    library.installHeader(generated.mparam_header, "gmp-mparam.h");
    library.installHeader(b.path("include/gmp_all.h"), "gmp_all.h");

    gmp_module.addImport("c", translateC(b, target, optimize, generated.directory));
    gmp_module.linkLibrary(library);

    if (install) b.installArtifact(library);
    return .{ .step = library, .include_dir = generated.directory };
}

/// Link an installed GMP instead of building this one.
///
/// The translated declarations come from the *system* `gmp.h`, because the
/// generated include directory is deliberately not added to the include line
/// here. The declarations therefore always describe the library that is linked,
/// never the header this source tree would have generated. The facade uses only
/// long standing public GMP API, so it works against any GMP 5 or later
/// installation; the limb size then comes from the installed library, which is
/// exactly what its own header describes.
fn makeSystemLibrary(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    gmp_module: *std.Build.Module,
) Library {
    const translate = b.addTranslateC(.{
        .root_source_file = b.path("include/gmp_all.h"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    translate.linkSystemLibrary("gmp", .{});

    gmp_module.addImport("c", translate.createModule());
    return .system;
}

/// Install `gmp.pc` where upstream installs it.
///
/// `pkgconfigdir = $(libdir)/pkgconfig` and `pkgconfig_DATA = gmp.pc`
/// (Makefile.am:121-122) are unconditional, and `gmpxx.pc` joins them only
/// under `if WANT_CXX` (Makefile.am:127-130), which this build does not select
/// because it compiles no C++. One file is therefore the whole of upstream's
/// pkg-config surface for this library, and a prefix that carried libgmp
/// without it would have no metadata describing the library it ships.
fn installPkgConfig(b: *std.Build) void {
    const out = b.addWriteFiles();
    _ = out.add("gmp.pc", pkgConfigSource(b));
    // `Step.InstallFile.create` records the step without attaching it to the
    // install step, so the dependency has to be made explicit here rather than
    // left to the caller's discretion.
    b.getInstallStep().dependOn(&b.addInstallFile(
        out.getDirectory().path(b, "gmp.pc"),
        "lib/pkgconfig/gmp.pc",
    ).step);
}

/// Upstream's `gmp.pc.in` with the placeholders `configure` fills in.
///
/// Only the `@...@` fields are replaced, so the `Cflags:` and `Libs:` lines
/// stay upstream's own. `Libs: -L${libdir} -lgmp` is the whole dependency
/// record: libgmp has no library dependency of its own, which is what makes
/// it the leaf that closes every consumer's link line.
fn pkgConfigSource(b: *std.Build) []const u8 {
    const substitutions = [_][2][]const u8{
        .{ "@prefix@", "${prefix}" },
        .{ "@exec_prefix@", "${prefix}" },
        .{ "@libdir@", "${prefix}/lib" },
        .{ "@includedir@", "${prefix}/include" },
        // `AC_INIT(GNU MP, GMP_VERSION, ..., gmp)` (configure.ac:40) is where
        // `configure` takes `PACKAGE_NAME` from.
        .{ "@PACKAGE_NAME@", "GNU MP" },
        .{ "@PACKAGE_VERSION@", packageVersion(b) },
    };
    var text: []const u8 = @embedFile("gmp.pc.in");
    for (substitutions) |substitution| {
        text = std.mem.replaceOwned(u8, b.allocator, text, substitution[0], substitution[1]) catch
            @panic("OOM");
    }
    return text;
}

/// GMP's `major.minor.patch`, read out of the three macros upstream's
/// `configure` substitutes into `gmp-h.in`.
///
/// `gmp-h.in:2338-2340` is the source `configure:3619` renders the `VERSION`
/// macro from, and that macro is what `version.c:33` compiles into the
/// exported `gmp_version` string, so the installed metadata names the same
/// release the compiled library reports. `zig/config_gen.zig` commits to the
/// same three numbers for the same reason.
fn packageVersion(b: *std.Build) []const u8 {
    const gmp_header = @embedFile("gmp-h.in");
    return b.fmt("{d}.{d}.{d}", .{
        macroNumber(b, gmp_header, "__GNU_MP_VERSION"),
        macroNumber(b, gmp_header, "__GNU_MP_VERSION_MINOR"),
        macroNumber(b, gmp_header, "__GNU_MP_VERSION_PATCHLEVEL"),
    });
}

/// One number from a `#define NAME value` line of `text`, or a build failure
/// naming the file and the macro.
///
/// A missing or unparsable macro stops the build rather than installing a
/// guessed version: `libtoolNumber` refuses the same way for the same reason,
/// because a wrong number here would be shipped as the library's identity.
fn macroNumber(b: *std.Build, text: []const u8, name: []const u8) u32 {
    const prefix = b.fmt("#define {s}", .{name});
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t");
        if (!std.mem.startsWith(u8, trimmed, prefix)) continue;
        const after = trimmed[prefix.len..];
        // `__GNU_MP_VERSION` *is* a prefix of `__GNU_MP_VERSION_MINOR` and of
        // `__GNU_MP_VERSION_PATCHLEVEL`, so a bare prefix test would let the
        // minor or patchlevel line satisfy the major lookup. Requiring
        // whitespace right after the name is what keeps them apart.
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

/// Translate the public header with `gmp.h` resolved from `include_dir`.
///
/// When `include_dir` is null, the system `gmp.h` is used.
fn translateC(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    include_dir: ?std.Build.LazyPath,
) *std.Build.Module {
    const translate = b.addTranslateC(.{
        .root_source_file = b.path("include/gmp_all.h"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    if (include_dir) |dir| translate.addIncludePath(dir);
    return translate.createModule();
}

const Generated = struct {
    /// Directory holding every generated file: both headers, the two
    /// generated translation units and the template operation wrappers.
    directory: std.Build.LazyPath,
    /// The public headers installed into the artifact's include tree. GMP's
    /// internal `config.h` is generated into `directory` for this build only.
    gmp_header: std.Build.LazyPath,
    mparam_header: std.Build.LazyPath,
    /// Names inside `directory` of the generated mpn template wrappers, one
    /// per operation, each compiled as a translation unit in its own right.
    operation_sources: []const []const u8,
};

/// Render `gmp.h` and `config.h` the way GMP's `configure` would, run the
/// table generators and write the mpn template wrappers, all into one
/// directory.
fn generate(
    b: *std.Build,
    optimize: std.builtin.OptimizeMode,
    params: config.Params,
) Generated {
    const output = b.addWriteFiles();

    const gmp_h_in = @embedFile("gmp-h.in");
    const config_in = @embedFile("config.in");

    const cflags = b.fmt("zig cc -O{s} -DNO_ASM", .{@tagName(optimize)});
    // Each renderer emits the fork's prologue and the substituted template, so
    // a generated header is one buffer and never a runtime `++`.
    const gmp_header = output.add(
        "gmp.h",
        config.renderGmpH(b.allocator, gmp_h_in, params, cflags) catch @panic("OOM"),
    );
    _ = output.add(
        "config.h",
        config.renderConfigH(b.allocator, config_in, params) catch @panic("OOM"),
    );
    // GMP's `configure` links `gmp-mparam.h` to the chosen mpn path directory.
    const mparam_header = output.addCopyFile(b.path("mpn/generic/gmp-mparam.h"), "gmp-mparam.h");

    const limb_bits = b.fmt("{d}", .{params.limb_bits});
    const nail_bits = b.fmt("{d}", .{params.nail_bits});

    // Table generators, built and invoked exactly as upstream's `Makefile.am`
    // does: one host executable per generator, carrying `LIBM_FOR_BUILD` only
    // where the upstream rule passes it, and run with the *target's* limb size
    // and nail count as arguments. The host runs them because they only compute
    // tables; the target chooses their layout.
    const gen_fib = generatorProgram(b, "gen-fib", false);
    const gen_bases = generatorProgram(b, "gen-bases", true);
    const gen_fac = generatorProgram(b, "gen-fac", false);
    const gen_sieve = generatorProgram(b, "gen-sieve", false);
    const gen_psqr = generatorProgram(b, "gen-psqr", true);
    const gen_trialdivtab = generatorProgram(b, "gen-trialdivtab", true);
    const gen_jacobitab = generatorProgram(b, "gen-jacobitab", false);

    _ = output.addCopyFile(runGenerator(b, gen_fib, &.{ "table", limb_bits, nail_bits }), "fib_table.c");
    _ = output.addCopyFile(runGenerator(b, gen_fib, &.{ "header", limb_bits, nail_bits }), "fib_table.h");
    _ = output.addCopyFile(runGenerator(b, gen_bases, &.{ "table", limb_bits, nail_bits }), "mp_bases.c");
    _ = output.addCopyFile(runGenerator(b, gen_bases, &.{ "header", limb_bits, nail_bits }), "mp_bases.h");
    _ = output.addCopyFile(runGenerator(b, gen_fac, &.{ limb_bits, nail_bits }), "fac_table.h");
    _ = output.addCopyFile(runGenerator(b, gen_sieve, &.{limb_bits}), "sieve_table.h");
    _ = output.addCopyFile(runGenerator(b, gen_psqr, &.{ limb_bits, nail_bits }), "perfsqr.h");
    _ = output.addCopyFile(runGenerator(b, gen_trialdivtab, &.{ limb_bits, "8000" }), "trialdivtab.h");
    _ = output.addCopyFile(runGenerator(b, gen_jacobitab, &.{}), "jacobitab.h");

    // One wrapper per operation of every multi-function mpn template. Each
    // wrapper names the operation and includes the template, which is what
    // upstream gets from the symlink `configure` creates at `configure:25553`,
    // with the `-DOPERATION_<name>` that `mpn/Makefile.am:33` derives from the
    // object name.  A bare `-D` names `1`, so each wrapper defines its operation
    // to 1: the templates test `#if OPERATION_<name>`, and an object-like
    // macro with no value leaves that expression empty. Giving each operation
    // its own file also keeps each one its own object file, which a repeated
    // `-D` on a shared source would not.
    var operation_sources: std.ArrayList([]const u8) = .empty;
    for (sources.operations) |operation| {
        const name = b.fmt("{s}.c", .{operation.name});
        _ = output.add(name, b.fmt(
            \\/* Generated by the Zig build: one operation of an mpn/generic
            \\   template, selected as upstream's configure selects it. */
            \\#define OPERATION_{s} 1
            \\#include "{s}"
            \\
        , .{ operation.name, operation.template }));
        operation_sources.append(b.allocator, name) catch @panic("OOM");
    }

    return .{
        .directory = output.getDirectory(),
        .gmp_header = gmp_header,
        .mparam_header = mparam_header,
        .operation_sources = operation_sources.items,
    };
}

/// The shared library's version, read out of upstream's libtool versioning.
///
/// `LIBGMP_LT_CURRENT`, `LIBGMP_LT_REVISION` and `LIBGMP_LT_AGE`
/// (Makefile.am:107-109) are what `libgmp_la_LDFLAGS` passes as
/// `-version-info` (Makefile.am:294-295). Libtool's library major is
/// `CURRENT - AGE`, its real file name is `$libname.so.$major.$age.$revision`
/// and its soname is `$libname.so.$major`, so GMP 6.3.0's `15:0:5` names
/// `libgmp.so.10.5.0` with soname `libgmp.so.10`.
///
/// Reading upstream's numbers instead of writing `10, 5, 0` keeps the soname
/// and `gmp.h` from disagreeing after a rebase; a missing or unparsable
/// assignment stops the build rather than shipping a guessed name.
fn sharedLibraryVersion(b: *std.Build) std.SemanticVersion {
    return .{
        .major = libtoolNumber(b, "LIBGMP_LT_CURRENT") - libtoolNumber(b, "LIBGMP_LT_AGE"),
        .minor = libtoolNumber(b, "LIBGMP_LT_AGE"),
        .patch = libtoolNumber(b, "LIBGMP_LT_REVISION"),
    };
}

/// One number from a `NAME = value` assignment in upstream's `Makefile.am`.
fn libtoolNumber(b: *std.Build, name: []const u8) u32 {
    const prefix = b.fmt("{s}", .{name});
    var lines = std.mem.splitScalar(u8, @embedFile("Makefile.am"), '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t");
        if (!std.mem.startsWith(u8, trimmed, prefix)) continue;
        const after = trimmed[prefix.len..];
        // A name that is only a prefix of another assignment is not this one.
        if (after.len == 0) continue;
        if (after[0] != ' ' and after[0] != '\t' and after[0] != '=') continue;
        const rest = std.mem.trim(u8, after, " \t=");
        return std.fmt.parseInt(u32, rest, 10) catch {
            @panic(b.fmt(
                "vendor/gmp/Makefile.am: {s} is not a number ('{s}'); refusing to " ++
                    "name the shared library by guesswork",
                .{ name, rest },
            ));
        };
    }
    @panic(b.fmt("vendor/gmp/Makefile.am no longer defines {s}", .{name}));
}

/// Build one of GMP's table generators for the host.
///
/// The programs are built for the host because they only compute tables. What
/// decides the target's layout is their argument list, the limb size and the
/// nail count, which `runGenerator` supplies. Upstream builds each generator
/// once and runs it in more than one mode, so `needs_libm` follows that rule
/// and not the individual invocation.
fn generatorProgram(
    b: *std.Build,
    name: []const u8,
    needs_libm: bool,
) *std.Build.Step.Compile {
    const module = b.createModule(.{
        .target = b.graph.host,
        .optimize = .safe,
        .link_libc = true,
    });
    // `gen-*.c` include `bootstrap.c` from the top of the GMP tree.
    module.addIncludePath(b.path("."));
    module.addCSourceFiles(.{ .files = &.{b.fmt("{s}.c", .{name})} });
    if (needs_libm) module.linkSystemLibrary("m", .{});
    return b.addExecutable(.{
        .name = b.fmt("{s}-host", .{name}),
        .root_module = module,
    });
}

/// Run a table generator with the target's parameters, returning its standard
/// output as a generated file.
///
/// Each call is its own run step, so the same generator can be run in several
/// modes without one invocation's output colliding with another's.
fn runGenerator(
    b: *std.Build,
    program: *std.Build.Step.Compile,
    args: []const []const u8,
) std.Build.LazyPath {
    const run = b.addRunArtifact(program);
    run.addArgs(args);
    return run.captureStdOut(.{ .basename = b.fmt("{s}.out", .{program.name}) });
}

/// The example program, shared by `smoke`, `run` and `check`.
fn addExample(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    gmp_module: *std.Build.Module,
    library: Library,
    name: []const u8,
) *std.Build.Step.Compile {
    const module = b.createModule(.{
        .root_source_file = b.path("zig/example/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    module.addImport("gmp", gmp_module);
    library.link(module);
    return b.addExecutable(.{ .name = name, .root_module = module });
}

/// The test binary: behaviour tests plus the allocation probe.
fn addTests(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    gmp_module: *std.Build.Module,
    library: Library,
    name: []const u8,
) *std.Build.Step.Compile {
    const module = b.createModule(.{
        .root_source_file = b.path("zig/test/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    module.addImport("gmp", gmp_module);
    library.link(module);
    // The probe exists only to observe GMP's allocator; it is never part of
    // the library. It includes the public header by name, so it needs the
    // generated include directory on its own compile line.
    if (library.cIncludeDir()) |dir| module.addIncludePath(dir);
    module.addCSourceFiles(.{ .files = &.{"zig/test/alloc_probe.c"} });
    module.addIncludePath(b.path("."));
    return b.addTest(.{ .name = name, .root_module = module });
}

/// Source licence and provenance integrity gate.
///
/// Checks that the upstream licence texts are present and unmodified and that
/// the provenance record still carries the archive digest. It needs no Zig
/// build, so CI can run it first.
fn addProvenanceStep(b: *std.Build) void {
    const run = b.addSystemCommand(&.{"sh"});
    run.addFileArg(b.path("tools/provenance_gate.sh"));
    run.addFileArg(b.path("."));
    run.setName("provenance gate");

    const step = b.step("provenance", "Verify the upstream licence texts and provenance record");
    step.dependOn(&run.step);
}
