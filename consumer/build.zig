//! A separate package that consumes the MPFR fork as a real dependency.
//!
//! This is the proof that a downstream user needs only
//! `b.dependency("mpfr", ...).module("mpfr")` and nothing else: no include
//! paths, no link flags, no C sources of its own, and no `dep.artifact(...)`
//! call of its own either. The published module already carries the linked
//! route's whole closure, so a second link line here would only restate it.
//!
//!   zig build run     run the demonstration and print its results
//!   zig build         compile the demonstration
//!
//! `-Dlinkage` and `-Druntime` are the library's own two delivery options, and
//! they are forwarded verbatim and independently. `-Dlinkage` names which
//! artifact the dependency builds and installs. `-Druntime` says the facade
//! reaches the native entry points through one process-lifetime table that an
//! explicit `load(source)` fills, with nothing linked into the module and both
//! MPFR and GMP arriving through the platform loader. `src/main.zig` is
//! written for both shapes, so every combination is a real program rather than
//! a compile-only configuration: under `mpfr.runtime_loaded` it names a
//! provider with `--provider <path>` or `MPFR_PROVIDER` and loads it once
//! before its first call.
//!
//! The provider is always named and never searched for. In the runtime route
//! nothing is linked into this executable, so where a supported provider comes
//! from is part of this package's build, and the last paragraph of this file
//! says exactly which one it is and why the others are not providers.
//!
//! Neither option is given a default here, so a caller who names neither
//! leaves the library's own defaults in charge: a null user-input option is not
//! passed on at all (`lib/std/Build.zig:435`, `:569-581`).
//!
//! Every line the program prints is a known answer that the program checks
//! before printing it, so a behaviour change is a non-zero exit rather than
//! silently different text. The exact expectations and their provenance are
//! listed at the top of src/main.zig.

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const linkage = b.option(
        std.builtin.LinkMode,
        "linkage",
        "Which delivery of libmpfr the dependency builds: a static archive or a " ++
            "shared library. Forwarded to the library's own -Dlinkage, which " ++
            "also selects the vendored GMP build libmpfr links against. Left " ++
            "unset, the option is not passed on and the library's own default " ++
            "decides.",
    );
    const runtime = b.option(
        bool,
        "runtime",
        "Build the dependency with its runtime-loading dispatch, so the facade " ++
            "reaches MPFR and GMP through one process-lifetime table that an " ++
            "explicit load(source) fills and the module links no archive. " ++
            "Forwarded to the library's own -Druntime, independently of " ++
            "-Dlinkage, which still decides what is delivered and installed. " ++
            "Left unset, the option is not passed on and the library's own " ++
            "default decides.",
    );

    const mpfr_dependency = b.dependency("mpfr", .{
        .target = target,
        .optimize = optimize,
        .linkage = linkage,
        .runtime = runtime,
    });
    // The module is the whole public surface: the facade plus the translated C
    // API as `pub const c = @import("c")`. It also carries the linked route's
    // own closure — the compiled libmpfr and the vendored GMP it is linked
    // against, both attached to that module inside the dependency's own
    // `build.zig` — so nothing is linked again here.
    //
    // A `dep.artifact` call in this package would be a second way in, and
    // under `-Druntime` it would be worse than redundant: the linker would
    // satisfy the dispatch's symbols straight from the archive, `load` would
    // never be reached, and the run would prove nothing about the route it
    // was asked to exercise.
    const mpfr = mpfr_dependency.module("mpfr");

    const exe = b.addExecutable(.{
        .name = "mpfr-consumer",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .imports = &.{.{ .name = "mpfr", .module = mpfr }},
        }),
    });
    b.installArtifact(exe);

    const run = b.addRunArtifact(exe);
    if (b.args) |args| run.addArgs(args);
    b.step("run", "Run the MPFR consumer demonstration").dependOn(&run.step);

    // ## Where the runtime route's provider comes from
    //
    // Under `-Druntime=true` this executable links nothing, so it carries no
    // `DT_NEEDED` and no `DT_RUNPATH`, and `zig build run` on its own cannot
    // produce a provider: this package's `run` step depends on the executable
    // and nothing else, and `std.Build.Dependency` exposes an artifact and a
    // module, never the dependency's install step. That is the same reason the
    // library renders its own `gmp.pc` rather than taking the dependency's
    // (`installGmpPkgConfig`, `build.zig:1153-1162`).
    //
    // The supported provider is the installed shared libmpfr of this
    // repository's own install tree, where libgmp is its sibling:
    //
    //     zig build -Dlinkage=dynamic -Druntime=true install -j8
    //     cd consumer
    //     zig build run -Druntime=true -j8 -- --provider ../zig-out/lib/libmpfr.so.6.2.2
    //
    // The library is built and installed on the runtime route as on the linked
    // one - `installGmpClosure` is not behind any runtime guard
    // (`build.zig:606`, `:616`) - so that tree holds `libmpfr.so.6.2.2` and
    // `libgmp.so.10.5.0` in the same `lib/`. libmpfr records `$ORIGIN`, the
    // directory it was installed into rather than the build cache it was
    // compiled in (`installedLibraryRPath`, `linkInstalledSibling`,
    // `build.zig:970-1009`), so its own `DT_NEEDED` on `libgmp.so.10` resolves
    // with no `LD_LIBRARY_PATH` and no runpath naming a directory that is gone.
    // `MPFR_PROVIDER` names the same file for a run that would rather pass it
    // through the environment.
    //
    // Two other things are not providers, and the reasons are recorded here so
    // that neither is tried and reported as a broken route:
    //
    //   * a build-cache path. libmpfr.so built into a cache records `$ORIGIN`
    //     as that cache directory, while `libgmp.so.10` is emitted into GMP's
    //     own cache directory, and the loader resolves a `DT_NEEDED` through
    //     that one entry. The two artifacts have separate cache directories,
    //     so libmpfr cannot name libgmp from there.
    //   * `dep.artifact("gmp")`. This package declares `mpfr` as its only
    //     dependency (`build.zig.zon`), and the library's build registers its
    //     own `mpfr` artifact and module and no GMP one, so there is no such
    //     artifact to look up, and no install step to depend on either.
}
