//! Downstream consumer example for the MPFR package.

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const linkage = b.option(
        std.lang.LinkMode,
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
    // The dependency module carries the linked route's MPFR/GMP closure.
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
    run.addPassthruArgs();
    b.step("run", "Run the MPFR consumer demonstration").dependOn(&run.step);

    // Runtime mode does not link a provider; this run step does not depend
    // on the dependency's install step.
    // Use installed shared libmpfr: its `$ORIGIN` runpath finds sibling libgmp
    // in the same install directory.
    // Build-cache libraries use separate directories, so they cannot form this
    // provider pair. The `mpfr` dependency exposes no separate `gmp` artifact.
}
