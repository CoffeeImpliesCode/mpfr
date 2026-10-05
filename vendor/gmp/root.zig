//! Zig package root for the GMP 6.3.0 fork: the real GNU Multiple Precision
//! Arithmetic Library, built from the complete source tree with the portable C
//! backend (`NO_ASM`, mpn path `generic`), and published two ways.
//!
//!   * `dep.artifact("gmp")` is the static `libgmp` this tree builds, with the
//!     generated `gmp.h` in its include tree, for a C or `translate-c`
//!     dependent. `dep.module("gmp")` is the same library, linked, plus:
//!     * `gmp.c` — the complete translated GMP API, stdio and `va_list`
//!       functions included, which is the escape hatch for anything the
//!       facade does not cover;
//!     * `gmp.BigInt`, `gmp.Rational`, `gmp.Float` and `gmp.Rand` — owned Zig
//!       types with explicit `deinit`;
//!     * `gmp.DivisionMode`, `gmp.Division`, `gmp.OwnedString`,
//!       `gmp.ParseError`, `gmp.FormatError` — the facade's public result and
//!       error types;
//!     * `gmp.version`, `gmp.versionString`, `gmp.upstream_version` and
//!       `gmp.limb_bits`.
//!   * `zig build -fsys=gmp` links an installed GMP instead of compiling this
//!     tree, and the translated declarations then come from the installed
//!     `gmp.h`. See README.zig.md.
//!
//! What this module deliberately does not do: no library code here installs
//! allocator hooks, so GMP's own allocator stays in force; it does not run an
//! install step, so a dependent that wants headers on disk has a C build this
//! package does not perform; and GMP 6.3 has neither `mpf_const_pi` nor
//! `mpf_set_inf`, so there is no constant or special-value setter here. MPFR
//! is the separate package that provides a pi constant and an explicit
//! rounding mode.
//!
//! The shortest sequence that uses it, from a dependent package's `build.zig`:
//!
//! ```zig
//! const gmp_dep = b.dependency("gmp", .{ .target = target, .optimize = optimize });
//! module.addImport("gmp", gmp_dep.module("gmp"));
//! ```
//!
//! and from Zig source:
//!
//! ```zig
//! const std = @import("std");
//! const gmp = @import("gmp");
//!
//! pub fn main() !void {
//!     var value = try gmp.BigInt.parse("123456789012345678901234567890", 10);
//!     defer value.deinit();
//!     var buffer: [64]u8 = undefined;
//!     std.debug.print("{s}\n", .{try value.writeTo(&buffer, 10)});
//! }
//! ```
//!
//! Memory follows GMP: values are allocated by GMP's own allocator and freed
//! by `mpz_clear`, `mpq_clear` or `mpf_clear`, and a random state by
//! `gmp_randclear`. Those hooks are library-global, so a program that replaces
//! them through `c.mp_set_memory_functions` changes the allocator for every
//! value this package owns. Strings GMP allocates are returned as
//! `OwnedString` and released through GMP's own free function with the size of
//! the block, which is what GMP's allocator contract asks for; nothing here
//! borrows a pointer beyond the lifetime of its owner.
//!
//! Every `init` and every `parse` produces one owned value and every one of
//! them has exactly one `deinit`. Zig has no move, so a copy made by
//! assignment is a second name for one GMP allocation and releasing both is a
//! double free.
//!
//! Text crosses into GMP the way GMP reads it: `parse` and `setStr` take a
//! sentinel terminated `[:0]const u8` and hand the pointer straight over, and
//! `writeTo` returns the caller's own buffer as one, so rendered text can be
//! parsed again without a copy in between. Base 0 does not mean the same thing
//! at every call site: `mpz_set_str` and `mpq_set_str` read it as prefix
//! detection, `mpf_set_str` as base 10.
//!
//! See README.zig.md for what the portable backend costs.

const std = @import("std");

/// The complete translated GMP C API.
pub const c = @import("c");

/// The facade files, taken whole: each wraps its type and its supporting
/// declarations in one file, and `@import` of a path yields that file's own
/// namespace rather than the type it declares.
const bigint = @import("zig/BigInt.zig");
const rational = @import("zig/Rational.zig");
const float = @import("zig/Float.zig");
const rand = @import("zig/Rand.zig");

/// Owned integer, GMP `mpz_t`.
pub const BigInt = bigint.BigInt;

/// Owned rational number, GMP `mpq_t`.
pub const Rational = rational.Rational;

/// Owned binary floating point number, GMP `mpf_t`.
pub const Float = float.Float;

/// Owned random state, GMP `gmp_randstate_t`.
pub const Rand = rand.Rand;

/// GMP version this package was built from, as encoded in the generated
/// `gmp.h` (`__GNU_MP_VERSION` and friends).
pub const version = .{
    .major = c.__GNU_MP_VERSION,
    .minor = c.__GNU_MP_VERSION_MINOR,
    .patchlevel = c.__GNU_MP_VERSION_PATCHLEVEL,
};

/// Upstream release this fork tracks.
pub const upstream_version = "6.3.0";

/// Bits per limb of the generated `gmp.h`, which is ABI critical: 64 on every
/// 64-bit target including LLP64 Windows, 32 on 32-bit pointer targets.
pub const limb_bits = c.GMP_LIMB_BITS;

/// Render the GMP version of the generated header, for diagnostics.
///
/// Returns `error.NoSpaceLeft` when `buffer` is too short, in which case
/// `buffer` holds as much of the version as fitted and must be discarded. The
/// result borrows `buffer`.
pub fn versionString(buffer: []u8) ![]u8 {
    return std.fmt.bufPrint(buffer, "{d}.{d}.{d}", .{ version.major, version.minor, version.patchlevel });
}

/// Division rounding modes, re-exported for convenience.
pub const DivisionMode = bigint.DivisionMode;

/// Result of `BigInt.div`, both parts owned by the caller.
pub const Division = bigint.Division;

/// A NUL terminated string allocated by GMP, released with `deinit`.
pub const OwnedString = BigInt.OwnedString;

/// Errors from parsing.
pub const ParseError = bigint.ParseError;

/// Errors from rendering into caller owned storage.
pub const FormatError = bigint.FormatError;

/// Compile-time and run-time exercise of every public facade method.
///
/// `zig build check` compiles this for every supported target so the whole
/// facade is instantiated; `zig build test` also runs it natively.
pub const api_exercise = @import("zig/api_exercise.zig");

test {
    @import("std").testing.refAllDeclsRecursive(@This());
}
