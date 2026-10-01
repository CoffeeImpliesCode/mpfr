//! Every behaviour test in this package, plus the compile-only surface exercise.
//!
//! `zig build test` roots its test compilation here, so one command runs the
//! whole suite. `zig build check` compiles this same file without running it.
//!
//! Note on what `check` proves. Zig analyses a function body only when that body
//! is reached, and `std.testing.refAllDecls` merely names a declaration without
//! instantiating anything, so referencing the facade's declarations is not
//! enough on its own. `surface.zig` is therefore part of this compilation and
//! *calls* every public facade method on real values. That, not the
//! `refAllDecls` call below, is what makes `check` analyse all public facade
//! methods.

const std = @import("std");
const mpfr = @import("mpfr");

/// Compile-only exercise of the whole public surface; see the file header.
pub const surface = @import("surface.zig");
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
