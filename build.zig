// SPDX-License-Identifier: LGPL-3.0-or-later
//
// Fork-authored. `FORK-LICENSE.md` records the owner's authorization of that
// grant and why it matches MPFR's own primary upstream terms.

//! Build for the CoffeeImpliesCode/mpfr fork of GNU MPFR 4.2.2.
//! Source lists and generated inputs follow `src/Makefile.am` and `BUILT_SOURCES`.
//! Bundled GMP shares MPFR's linkage; Hexagon targets are unsupported (no GMP port).

const std = @import("std");

const config = @import("zig/config_gen.zig");

/// Runtime route's build graph.
const graph = @import("runtime/graph.zig");

const gmp_package = "gmp";

/// Default bundled GMP dependency path.
const vendored_gmp = "vendor/gmp";

const library_name = "mpfr";

/// Upstream's C source list, read from Automake.
const src_makefile_am = @embedFile("src/Makefile.am");

const patches_file = @embedFile("PATCHES");

/// Upstream's pkg-config template; only configure's placeholders are replaced.
const pkg_config_template = @embedFile("mpfr.pc.in");

const version_file = @embedFile("VERSION");

/// GMP's pkg-config template, installed as `gmp.pc`.
const gmp_pkg_config_template = @embedFile("vendor/gmp/gmp.pc.in");

/// GMP's header template, used to derive its package version.

const gmp_header_template = @embedFile("vendor/gmp/gmp-h.in");

/// Derive the shared-library version from upstream's libtool flags (`src/Makefile.am:106`).
fn sharedLibraryVersion(b: *std.Build) std.SemanticVersion {
    const triple = libtoolVersionInfo(b, "libmpfr_la_LDFLAGS");
    return .{ .major = triple.current - triple.age, .minor = triple.age, .patch = triple.revision };
}

/// Parsed libtool `CURRENT:REVISION:AGE` values.
const VersionInfo = struct { current: u32, revision: u32, age: u32 };

/// Parse libtool's version triple or refuse a guessed shared-library name.
fn libtoolVersionInfo(b: *std.Build, assignment: []const u8) VersionInfo {
    const flag = "-version-info";
    const words = assignmentWords(b, assignment);
    for (words, 0..) |word, index| {
        // Automake stores the flag argument as the next word.
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

/// GMP's four licence files, installed with its library.
const gmp_licence_files = [_][]const u8{
    "COPYING",
    "COPYING.LESSERv3",
    "COPYINGv2",
    "COPYINGv3",
};

/// MPFR's licence files and fork provenance records installed under `share/licenses/mpfr/`.
const mpfr_licence_files = [_][]const u8{
    "COPYING",
    "COPYING.LESSER",
    "NOTICE.md",
    "FORK-LICENSE.md",
    "UPSTREAM.md",
    "README.upstream.md",
};

/// GNU C11 is required by MPFR's public header (`src/mpfr.h:921-925`).
const c_standard = "-std=gnu11";

/// Target-derived macros shared by C compilation and header translation.
/// One list keeps the library ABI and translated declarations aligned.
fn macroDefinitions(b: *std.Build, target: std.Target) []const []const u8 {
    var out: std.ArrayList([]const u8) = .empty;
    for (config.macros(config.paramsFor(target))) |macro| {
        out.append(b.allocator, b.fmt("{s}={s}", .{ macro.name, macro.value })) catch @panic("OOM");
    }
    return out.items;
}

/// Build C flags from the dialect and configuration macros.
fn cFlags(b: *std.Build, definitions: []const []const u8) []const []const u8 {
    var out: std.ArrayList([]const u8) = .empty;
    out.append(b.allocator, c_standard) catch @panic("OOM");
    for (definitions) |definition| {
        out.append(b.allocator, b.fmt("-D{s}", .{definition})) catch @panic("OOM");
    }
    return out.items;
}

/// Targets covered by the compile-only matrix.
const required_targets = [_]struct { name: []const u8, query: std.Target.Query }{
    .{ .name = "x86_64-linux-gnu", .query = .{ .cpu_arch = .x86_64, .os_tag = .linux, .abi = .gnu } },
    .{ .name = "aarch64-linux-gnu", .query = .{ .cpu_arch = .aarch64, .os_tag = .linux, .abi = .gnu } },
    .{ .name = "aarch64-macos-none", .query = .{ .cpu_arch = .aarch64, .os_tag = .macos, .abi = .none } },
    .{ .name = "x86_64-windows-gnu", .query = .{ .cpu_arch = .x86_64, .os_tag = .windows, .abi = .gnu } },
    .{ .name = "riscv64-linux-gnu", .query = .{ .cpu_arch = .riscv64, .os_tag = .linux, .abi = .gnu } },
    .{ .name = "wasm32-wasi", .query = .{ .cpu_arch = .wasm32, .os_tag = .wasi } },
};

/// Source-backed summary and detail for an unsupported target.
const Refusal = struct {
    /// One-line platform boundary.
    summary: []const u8,
    /// Source-backed reason and supported target list.
    detail: []const u8,
};

/// Return the refusal for an unsupported target.
/// Both the selected target and matrix use this decision.
fn refusalFor(target: std.Build.ResolvedTarget) ?Refusal {
    // GMP 6.3.0 has no Hexagon port; refuse every target with this CPU.
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
    // Static linkage preserves the package's default.
    const linkage = b.option(
        std.builtin.LinkMode,
        "linkage",
        "Linkage of the installed libmpfr: static (default) or dynamic",
    ) orelse .static;
    // Runtime loading is independent of the system-library options.
    const runtime_loaded = b.option(
        bool,
        "runtime",
        "Resolve MPFR and GMP through the platform loader at run time instead of linking them",
    ) orelse false;

    // Refuse unsupported targets before creating any build steps.
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
    // Install vendored GMP only for the published target graph.
    if (native.vendored_gmp) |gmp| installGmpClosure(b, gmp);

    const run_example = b.addRunArtifact(native.example);
    if (b.args) |args| run_example.addArgs(args);
    b.step("run", "Run the deterministic MPFR example").dependOn(&run_example.step);
    b.step("smoke", "Run the deterministic MPFR example and report its output")
        .dependOn(&run_example.step);

    const run_tests = b.addRunArtifact(native.tests);
    b.step("test", "Run the MPFR behaviour suite").dependOn(&run_tests.step);

    const check_step = b.step("check", "Compile the facade and the example without running them");
    check_step.dependOn(&native.tests.step);
    check_step.dependOn(&native.example.step);

    // Publish only the standard target's module; matrix graphs stay private.
    // Skip refused cells and compile the remaining targets.
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

/// Build steps for one resolved target.
const Graph = struct {
    library: ?*std.Build.Step.Compile,
    /// Vendored GMP dependency, absent in system mode.
    vendored_gmp: ?*std.Build.Step.Compile,
    tests: *std.Build.Step.Compile,
    example: *std.Build.Step.Compile,
};

/// Build one target graph; only `publish` registers its `mpfr` module.
/// Matrix invocations must not mutate target-independent state.
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
    // System MPFR must use its installed GMP headers, not the vendored tree.
    // Upstream's MinGW checks require matching linkage (`configure.ac:635-662`).
    const gmp = if (use_system_mpfr or use_system_gmp)
        null
    else
        gmpDependency(b, target, optimize, linkage).artifact(gmp_package);
    // Use headers emitted with the GMP artifact; system routes already have them.
    const gmp_include = if (gmp) |artifact| artifact.getEmittedIncludeTree() else null;

    // Share target-derived macros between translation and C compilation.
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
    // Supply system libraries to translation separately from module linking.
    if (use_system_mpfr) {
        translate.linkSystemLibrary(library_name, .{ .use_pkg_config = .force });
    }
    if (use_system_gmp) {
        translate.linkSystemLibrary(gmp_package, .{ .use_pkg_config = .force });
    }

    for (definitions) |definition| {
        translate.defineCMacroRaw(definition);
    }
    // Runtime dispatch consumes this translation's output.
    const c_module = if (runtime_loaded)
        graph.createModule(b, translate, target, optimize)
    else
        translate.createModule();

    var library: ?*std.Build.Step.Compile = null;
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
    // The linked facade imports loader types directly; runtime dispatch re-exports them.
    // Avoid a second loader-core instance in runtime mode.
    if (!runtime_loaded) {
        mpfr_module.addImport("rt", graph.createCoreModule(b, target, optimize));
    }
    // Runtime mode must not link the compiled MPFR or GMP libraries.
    if (!runtime_loaded) {
        if (library) |built| {
            // Link the public module to the build artifact; the installed library's link is separate.
            mpfr_module.linkLibrary(built);
            // Translated headers expose GMP symbols, so dependents must link GMP directly.
            // Shared `libmpfr`'s indirect `DT_NEEDED` does not satisfy direct references.
            // System `mpfr.pc` supplies its own `-lgmp` closure.
            if (gmp) |vendored| {
                // Add the same bundled GMP artifact explicitly.
                mpfr_module.linkLibrary(vendored);
            } else if (use_system_gmp) {
                // Resolve the same system GMP selected for compilation.
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

/// Compile MPFR from the repository sources.
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
        // Leave static PIC unspecified; dynamic libraries require PIC.
        .pic = if (linkage == .dynamic) true else null,
    });
    const flags = cFlags(b, definitions);
    module.addCSourceFiles(.{
        .files = upstreamSources(b),
        .flags = flags,
    });
    // Automake builds `BUILT_SOURCES` in the build directory (`src/Makefile.am:79`).
    // Read the assignment so added generated units cannot be omitted.
    for (builtSources(b)) |name| {
        module.addCSourceFile(.{
            .file = generated.getDirectory().path(b, name),
            .flags = flags,
        });
    }
    // `mparam.h` includes architecture headers relative to `src/` (`src/mparam_h.in:26-85`).
    module.addIncludePath(b.path("src"));
    module.addIncludePath(generated.getDirectory());
    if (gmp_include) |gmp_path| module.addIncludePath(gmp_path);
    if (use_system_gmp) {
        module.linkSystemLibrary(gmp_package, .{ .use_pkg_config = .force });
    } else {
        // MPFR and GMP share `lib/`, so the installed library uses `$ORIGIN`.
        // `$ORIGIN/../lib` is the executable layout, not the library layout.
        linkInstalledSibling(module, gmp.?, target);
    }

    return b.addLibrary(.{
        .name = library_name,
        // MPFR's headers derive DLL macros from bundled GMP (`src/mpfr.h:321-331`).
        .linkage = linkage,
        // Static archives do not carry a shared-object version.
        .version = if (linkage == .dynamic) sharedLibraryVersion(b) else null,
        .root_module = module,
    });
}

/// Return a loader-relative path for installed shared dependencies, when supported.
fn installedLibraryRPath(target: std.Build.ResolvedTarget) ?[]const u8 {
    return switch (target.result.os.tag) {
        .windows, .wasi, .uefi => null,
        else => if (target.result.os.tag.isDarwin()) "@loader_path" else "$ORIGIN",
    };
}

/// Link a shared library without embedding its build-cache rpath.
/// Installed MPFR and GMP are siblings, so use a loader-relative path.
fn linkInstalledSibling(
    module: *std.Build.Module,
    library: *std.Build.Step.Compile,
    target: std.Build.ResolvedTarget,
) void {
    // Windows uses the import library and does not need an rpath.
    if (library.linkage != .dynamic or target.result.os.tag == .windows) {
        module.linkLibrary(library);
        return;
    }
    module.addObjectFile(library.getEmittedBin());
    if (installedLibraryRPath(target)) |rpath| module.addRPathSpecial(rpath);
}

/// Resolve bundled GMP from this package root and report a missing snapshot clearly.
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
    // Forward the selected linkage to the bundled GMP package.
    return b.dependency(gmp_package, .{
        .target = target,
        .optimize = optimize,
        .linkage = linkage,
    });
}

/// Install MPFR's public headers with its library artifact.
fn markPublicHeaders(b: *std.Build, library: *std.Build.Step.Compile) void {
    library.installHeader(b.path("src/mpfr.h"), "mpfr.h");
    library.installHeader(b.path("src/mpf2mpfr.h"), "mpf2mpfr.h");
}

/// Install vendored GMP, its pkg-config file, and licence files.
fn installGmpClosure(b: *std.Build, gmp: *std.Build.Step.Compile) void {
    b.installArtifact(gmp);
    installGmpPkgConfig(b);
    for (gmp_licence_files) |name| {
        b.installFile(b.fmt("{s}/{s}", .{ vendored_gmp, name }), b.fmt("share/licenses/gmp/{s}", .{name}));
    }
}

/// Install MPFR's licence files and fork provenance records.
fn installLicenceRecords(b: *std.Build) void {
    for (mpfr_licence_files) |name| {
        b.installFile(name, b.fmt("share/licenses/mpfr/{s}", .{name}));
    }
}

/// Render upstream's `mpfr.pc.in` with its configure substitutions.
/// Preserve `-lmpfr -lgmp` and a relocatable prefix.
fn installPkgConfig(b: *std.Build) void {
    const out = b.addWriteFiles();
    _ = out.add("mpfr.pc", pkgConfigSource(b));
    // Attach the generated pkg-config file to the install step.
    b.getInstallStep().dependOn(&b.addInstallFile(
        out.getDirectory().path(b, "mpfr.pc"),
        "lib/pkgconfig/mpfr.pc",
    ).step);
}

/// Render upstream's `mpfr.pc.in` template.
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

/// Render GMP's required `gmp.pc` from the vendored template (`vendor/gmp/Makefile.am:121-122`).
fn installGmpPkgConfig(b: *std.Build) void {
    const out = b.addWriteFiles();
    _ = out.add("gmp.pc", gmpPkgConfigSource(b));
    b.getInstallStep().dependOn(&b.addInstallFile(
        out.getDirectory().path(b, "gmp.pc"),
        "lib/pkgconfig/gmp.pc",
    ).step);
}

/// Render the vendored GMP pkg-config template with its configure substitutions.
fn gmpPkgConfigSource(b: *std.Build) []const u8 {
    const substitutions = [_][2][]const u8{
        .{ "@prefix@", "${pcfiledir}/../.." },
        .{ "@exec_prefix@", "${prefix}" },
        .{ "@libdir@", "${prefix}/lib" },
        .{ "@includedir@", "${prefix}/include" },
        // Upstream sets `PACKAGE_NAME` to `GNU MP` (`vendor/gmp/configure.ac:40`).
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

/// Read GMP's version from its `gmp-h.in` template.
fn gmpPackageVersion(b: *std.Build) []const u8 {
    return b.fmt("{d}.{d}.{d}", .{
        gmpHeaderMacroNumber(b, "__GNU_MP_VERSION"),
        gmpHeaderMacroNumber(b, "__GNU_MP_VERSION_MINOR"),
        gmpHeaderMacroNumber(b, "__GNU_MP_VERSION_PATCHLEVEL"),
    });
}

/// Parse a numeric `#define` from the GMP header template or refuse.
fn gmpHeaderMacroNumber(b: *std.Build, name: []const u8) u32 {
    const prefix = b.fmt("#define {s}", .{name});
    var lines = std.mem.splitScalar(u8, gmp_header_template, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t");
        if (!std.mem.startsWith(u8, trimmed, prefix)) continue;
        const after = trimmed[prefix.len..];
        // Require a token boundary to distinguish the version macro names.
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

/// Produce the generated inputs listed by Automake.
fn generateUpstreamSources(b: *std.Build) *std.Build.Step.WriteFile {
    const generated = b.addWriteFiles();
    _ = generated.addCopyFile(b.path("src/mparam_h.in"), "mparam.h");
    _ = generated.add("get_patches.c", getPatchesSource(b, patches_file));
    return generated;
}

/// Reproduce upstream's `tools/get_patches.sh` for the current `PATCHES` content.
/// Keep the generated licence header aligned with the script.
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

/// Read MPFR's C source list from `src/Makefile.am`.
/// Missing assignments fail rather than build a partial library.
fn upstreamSources(b: *std.Build) []const []const u8 {
    var out: std.ArrayList([]const u8) = .empty;
    for (assignmentWords(b, "libmpfr_la_SOURCES")) |name| {
        if (!std.mem.endsWith(u8, name, ".c")) continue;
        out.append(b.allocator, b.fmt("src/{s}", .{name})) catch @panic("OOM");
    }
    return out.items;
}

/// Read generated C sources from Automake's `BUILT_SOURCES`.
/// These are compiled from the generated directory, not `src/`.
fn builtSources(b: *std.Build) []const []const u8 {
    var out: std.ArrayList([]const u8) = .empty;
    for (assignmentWords(b, "BUILT_SOURCES")) |name| {
        if (!std.mem.endsWith(u8, name, ".c")) continue;
        out.append(b.allocator, name) catch @panic("OOM");
    }
    return out.items;
}

/// Read an Automake assignment, joining backslash continuations.
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
