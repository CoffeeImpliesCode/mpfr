//! Derives MPFR's compile-time configuration from the resolved Zig target.
//! Only features supported by that target are defined.

const std = @import("std");

/// Target facts used to select MPFR's configuration macros.
pub const Params = struct {
    /// Whether the target stores the most-significant byte first.
    big_endian: bool,
    /// Whether C `double` is IEEE binary64 with address-ordered bit-fields.
    ieee_binary64_double: bool,
};

/// A configuration macro represented as a compiler definition.
pub const Macro = struct {
    /// Macro name, using `configure`'s spelling.
    name: []const u8,
    /// Replacement text for the compiler definition.
    value: []const u8,
};

/// Derives configuration facts from the resolved target.
/// Panics if its C `double` format is not recorded.
pub fn paramsFor(target: std.Target) Params {
    return .{
        .big_endian = target.cpu.arch.endian() == .big,
        .ieee_binary64_double = hasIeeeBinary64Double(target.cpu.arch),
    };
}

/// Number of entries returned by `macros`.
pub const macro_count = 13;

/// Returns the target's configuration macros in stable order.
/// Only known-true features are defined.
pub fn macros(p: Params) [macro_count]Macro {
    return .{
        // Standard headers required by the selected C dialect.

        // C11 provides `stdarg.h`, used by MPFR's variadic APIs.
        .{ .name = "HAVE_STDARG", .value = "1" },

        // C99 provides `stdint.h` for MPFR's `intmax_t` declarations.
        .{ .name = "HAVE_STDINT_H", .value = "1" },

        // C99 provides `inttypes.h` for MPFR's `intmax_t` declarations.
        .{ .name = "HAVE_INTTYPES_H", .value = "1" },

        // `wchar.h` provides `wint_t` for MPFR's wide-character formatting.
        .{ .name = "HAVE_WCHAR_H", .value = "1" },

        // C language features guaranteed by GNU C11 or Clang.

        // C99 guarantees `long long`, used by integer and printf APIs.
        .{ .name = "HAVE_LONG_LONG", .value = "1" },

        // C99 provides `va_copy`, avoiding an unsafe `va_list` byte copy.
        .{ .name = "HAVE_VA_COPY", .value = "1" },

        // Clang's `alloca` builtin supports MPFR's bounded stack temporaries.
        .{ .name = "HAVE_ALLOCA", .value = "1" },

        // Clang supports `attribute(mode)` for width-specific integer types.
        .{ .name = "HAVE_ATTRIBUTE_MODE", .value = "1" },

        // C11 provides `_Noreturn`.
        .{ .name = "MPFR_HAVE_NORETURN", .value = "1" },

        // Clang provides `__builtin_unreachable`.
        .{ .name = "MPFR_HAVE_BUILTIN_UNREACHABLE", .value = "1" },

        // C11 provides `_Static_assert`, used for MPFR's ABI checks.
        .{ .name = "MPFR_USE_STATIC_ASSERT", .value = "1" },

        // Endianness is selected from the resolved target.

        // Define exactly one integer-endianness macro for the target.
        .{
            .name = if (p.big_endian) "HAVE_BIG_ENDIAN" else "HAVE_LITTLE_ENDIAN",
            .value = "1",
        },

        // Select the target's IEEE binary64 encoding.
        .{
            .name = if (p.big_endian)
                "HAVE_DOUBLE_IEEE_BIG_ENDIAN"
            else
                "HAVE_DOUBLE_IEEE_LITTLE_ENDIAN",
            .value = "1",
        },
    };
}

// Architectures whose C ABI uses IEEE binary64 `double`.
fn hasIeeeBinary64Double(arch: std.Target.Cpu.Arch) bool {
    return switch (arch) {
        .x86_64,
        .aarch64,
        .aarch64_be,
        .powerpc64,
        .powerpc64le,
        .riscv64,
        .riscv64be,
        .s390x,
        .mips64,
        .mips64el,
        .loongarch64,
        .sparc64,
        .wasm64,
        .x86,
        .arm,
        .armeb,
        .thumb,
        .thumbeb,
        .riscv32,
        .riscv32be,
        .powerpc,
        .powerpcle,
        .mips,
        .mipsel,
        .sparc,
        .loongarch32,
        .wasm32,
        => true,

        else => @panic(
            "mpfr: the C double format of this architecture is not recorded; " ++
                "add it to hasIeeeBinary64Double in zig/config_gen.zig",
        ),
    };
}

// Features not represented by the target or not enabled by this build:
// - Thread safety, assertions, logging, warnings, coverage and prediction
//   remain at upstream defaults.
// - Long-double and locale details use MPFR's generic paths; the target does
//   not record their C-library formats.
// - Float128, decimal floating point and mini-GMP are disabled. The target
//   does not describe those C formats, and this build links external GMP.
// - GMP internals and ABI-derived macros are left to MPFR. Macros used only by
//   tests or benchmarks are not library build inputs.
