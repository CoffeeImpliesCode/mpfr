//! Every behaviour test in this package.
//!
//! `zig build test` roots its test compilation here, so one command runs the
//! whole suite, and `zig build check` compiles this same file without running
//! it. What `check` proves is what the files below prove by calling things:
//! Zig analyses a function body only when that body is reached, so the
//! behaviour tests reach the facade's methods with real values rather than
//! naming their declarations. `refAllDecls` on its own would not.
//!
//! There is no file here that walks the surface to prove a body compiles or
//! that a name exists. Every test below asserts an independent known answer, a
//! behavioural boundary, an ownership transition or an error path, and
//! `support.zig` states where each expected value comes from.
//!
//! ## The provider, in the runtime-loading configuration
//!
//! Each test calls `support.requireProvider` before it touches MPFR. In the
//! linked configuration that is a comptime no-op. In the runtime-loading one it
//! loads the shared library named by `MPFR_PROVIDER` and fails the test run if
//! that variable is not set: nothing is linked in that configuration, and a run
//! that was not told which file to load must say so rather than fall back to
//! something.

const std = @import("std");
const mpfr = @import("mpfr");

/// Shared fixtures and the provider requirement. See the file header.
pub const support = @import("support.zig");
/// Directed rounding: the five modes plus the two nearest-to-integer variants.
pub const rounding = @import("rounding_test.zig");
/// Precision, exactness and the `set_prec` versus `prec_round` distinction.
pub const precision = @import("precision_test.zig");
/// Arithmetic, assignment, scaling, and the integer conversions.
pub const arithmetic = @import("arithmetic_test.zig");
/// NaN, infinity, zero, and divide-by-zero flags.
pub const special = @import("special_test.zig");
/// Text rendering and text parsing.
pub const digits = @import("digits_test.zig");
/// Overflow and underflow against the exponent range.
pub const range = @import("range_test.zig");
/// Lifetime, ownership, cache release, and the raw C escape hatch.
pub const lifetime = @import("lifetime_test.zig");

test {
    // Referencing the imported files pulls their tests into this compilation.
    std.testing.refAllDecls(@This());
    // And this keeps any remaining public declaration visible to the compiler.
    std.testing.refAllDecls(mpfr);
}