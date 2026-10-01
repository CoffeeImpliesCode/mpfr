//! A separate package that consumes the MPFR fork as a real dependency.
//!
//! This is the proof that a downstream user needs only
//! `b.dependency("mpfr", ...).module("mpfr")` and nothing else: no include
//! paths, no link flags, no C sources of its own.
//!
//!   zig build run     run the demonstration and print its results
//!   zig build         compile the demonstration
//!
// Every line the program prints is a known answer that the program checks
// before printing it, so a behaviour change is a non-zero exit rather than
// silently different text. The exact expectations and their provenance are
// listed at the top of src/main.zig.

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mpfr_dependency = b.dependency("mpfr", .{
        .target = target,
        .optimize = optimize,
    });
    // The module is the whole public surface: the facade plus the translated C
    // API as `pub const c = @import("c")`.
    const mpfr = mpfr_dependency.module("mpfr");
    // Linking the artifact is what puts MPFR's public headers on this
    // translation unit's include path, so a C source here could `#include
    // <mpfr.h>` with no further configuration.
    mpfr.linkLibrary(mpfr_dependency.artifact("mpfr"));

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
}
