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
//! System mode and header/ABI identity
//! ----------------------------------
//! `-Dsystem=mpfr` links an installed MPFR. In that mode `src/` is deliberately
//! NOT added to the translation's include path, so `<mpfr.h>` resolves to the
//! installed header and the translated declarations describe the library that is
//! actually linked, rather than describing 4.2.2 while linking something older.
//! `fork/tests/lifetime_test.zig` compares `MPFR_VERSION_STRING` from the
//! translated header with `mpfr_get_version` from the linked library, which
//! makes that identity checkable instead of assumed. No fork-only shim symbol
//! is expected from an installed MPFR, and none is.
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
//!   zig build            install the static library
//!   zig build test       run the behaviour suite
//!   zig build smoke      run the deterministic example
//!   zig build run        run the example
//!   zig build check      compile the facade and the example, run nothing
//!   zig build matrix     compile `check` for the six required targets
//!
//! `check` and `matrix` compile only; they never execute a target binary.

const std = @import("std");

/// The configuration `configure` would have computed for the resolved target.
const config = @import("zig/config_gen.zig");

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

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});
    const use_system_mpfr = b.systemIntegrationOption("mpfr", .{});
    const use_system_gmp = b.systemIntegrationOption("gmp", .{});

    const native = wireUp(b, target, optimize, use_system_mpfr, use_system_gmp, true);

    if (native.library) |library| {
        b.installArtifact(library);
        markPublicHeaders(b, library);
    }

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
    const matrix_step = b.step("matrix", "Compile `check` for the six required targets");
    for (required_targets) |entry| {
        const cross = wireUp(
            b,
            b.resolveTargetQuery(entry.query),
            optimize,
            use_system_mpfr,
            use_system_gmp,
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
    publish: bool,
) Graph {
    const generated = generateUpstreamSources(b);
    // In `-Dsystem=mpfr` mode the installed MPFR comes with its own GMP, so the
    // vendored GMP include tree must not reach the translation: pointing it at a
    // different GMP's gmp.h would translate declarations the linked library does
    // not implement.
    const gmp_include = if (use_system_mpfr)
        null
    else
        gmpIncludePath(b, target, optimize, use_system_gmp);

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
    // `defineCMacroRaw` takes `NAME=VALUE` and appends the `-D` itself.
    for (definitions) |definition| {
        translate.defineCMacroRaw(definition);
    }
    const c_module = translate.createModule();

    var library: ?*std.Build.Step.Compile = null;
    if (use_system_mpfr) {
        c_module.linkSystemLibrary(library_name, .{ .use_pkg_config = .yes });
    } else {
        library = buildUpstreamLibrary(
            b,
            target,
            optimize,
            use_system_gmp,
            definitions,
            gmp_include,
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
    if (library) |built| {
        mpfr_module.linkLibrary(built);
    } else {
        mpfr_module.linkSystemLibrary(library_name, .{ .use_pkg_config = .yes });
    }

    return .{
        .library = library,
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
    definitions: []const []const u8,
    gmp_include: ?std.Build.LazyPath,
    generated: *std.Build.Step.WriteFile,
) *std.Build.Step.Compile {
    const module = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
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
        module.linkSystemLibrary(gmp_package, .{ .use_pkg_config = .yes });
    } else {
        module.linkLibrary(gmpDependency(b, target, optimize).artifact(gmp_package));
    }

    return b.addLibrary(.{ .name = library_name, .root_module = module });
}

/// The include directory that holds GMP's generated `gmp.h`.
///
/// For the vendored route that is the emitted header tree of the GMP artifact:
/// `Step.Compile.installHeader` records a header as travelling with the artifact
/// it is installed from, and `Step.Compile.getEmittedIncludeTree` materialises
/// the whole set as one directory. For the system route there is nothing to add,
/// because the system include path already has it.
fn gmpIncludePath(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    use_system_gmp: bool,
) ?std.Build.LazyPath {
    if (use_system_gmp) return null;
    return gmpDependency(b, target, optimize).artifact(gmp_package).getEmittedIncludeTree();
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
    return b.dependency(gmp_package, .{ .target = target, .optimize = optimize });
}

/// Mark MPFR's two public headers as travelling with the artifact, so a dependent
/// module that links this library also gets `<mpfr.h>` on its include path.
fn markPublicHeaders(b: *std.Build, library: *std.Build.Step.Compile) void {
    library.installHeader(b.path("src/mpfr.h"), "mpfr.h");
    library.installHeader(b.path("src/mpf2mpfr.h"), "mpf2mpfr.h");
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
