# Zig facade API

The facade provides owned `Float` and `Digits` values plus typed rounding, comparison, parsing and state results. The translated C declarations remain available through `c` and retain upstream semantics.

## Types

| Type | Contract |
| --- | --- |
| `Precision`, `Exponent` | MPFR significand precision and binary exponent types. |
| `RoundingMode` | `nearest_even`, `toward_zero`, `toward_positive`, `toward_negative`, `away_from_zero`, `faithful`, `nearest_away`. |
| `Ternary` | `exact`, `above`, `below`: whether the stored result equals, exceeds or is below the exact result. |
| `Flags` | Six exception bits: `underflow`, `overflow`, `nan`, `inexact`, `erange`, `divide_by_zero`. |
| `Order` | `std.math.Order`, from MPFR comparison. |
| `Prefix` | `consumed` input bytes and the parse `ternary`. |
| `ConversionError` | `InvalidNumber` for parsing; `InvalidBase` for digit rendering. |
| `Digits` | Owned digit buffer and exponent, released by `deinit`. |
| `Float` | Owned arbitrary-precision value, released by `deinit`. |

`nearest_away` is accepted only by `roundToNearestAway`. `faithful` does not specify a ternary result or the inexact flag. A `Ternary` result and exception flags are independent; an exact result can still raise a flag.

## Precision and rounding

`min_precision` is 1; `max_precision` is the facade's MPFR precision limit. Use `isValidPrecision` before passing external values to `Float.init`, `resetPrecision` or `roundToPrecision`; an out-of-range precision aborts in MPFR.

Every rounded `Float` operation takes its rounding direction explicitly. `roundToPrecision` keeps the value at a new precision; `resetPrecision` discards it and sets NaN. The integer-rounding methods are `roundToNearestEven`, `roundToNearestAway`, `truncate`, `ceil` and `floor`; each returns `Ternary`.

## `Float` operations

- Construction and storage: `init`, `deinit`, `precision`, `raw`, `rawConst`.
- Precision: `resetPrecision`, `roundToPrecision`.
- Assignment: `set`, `setAbs`, `negateFrom`, `setF64`, `setUnsigned`, `setSigned`, `setPowerOfTwo`.
- Special values: `setNan`, `setInf`, `setZero`.
- Parsing: `parseWhole`, `parsePrefix`.
- Arithmetic: `add`, `sub`, `mul`, `div`, `mulF64`, `sqrt`, `scaleByPowerOfTwo`, `divideByPowerOfTwo`.
- Integer rounding: `roundToNearestEven`, `roundToNearestAway`, `truncate`, `ceil`, `floor`.
- Comparison: `compare`, `compareAbs`, `compareUnsigned`, `compareSigned`, `isUnordered`, `isEqual`.
- Classification: `isNan`, `isInf`, `isZero`, `isRegular`, `isNumber`, `isInteger`, `isSignNegative`, `sign`.
- Conversion: `toF64`, `toSigned`, `toUnsigned`, `fitsSigned`, `fitsUnsigned`, `toDigits`.

Comparison returns an `Order`; check `isUnordered` when either operand may be NaN. Rounding operations that expose MPFR's ternary return a `Ternary`.

## Parsing and digits

`parseWhole(text, base, mode)` requires the entire string to be a number. It returns `error.InvalidNumber` for invalid or trailing input; its value is unspecified on failure. It does not report whether parsing rounded.

`parsePrefix(text, base, mode)` returns `Prefix` with the consumed byte count and ternary result. It returns `error.InvalidNumber` if it consumes no bytes; then `self` contains positive zero.

`isValidBase` accepts `2..62` and `-36..-2`; base zero is invalid. `toDigits(base, digits, mode)` returns `ConversionError!Digits`; `digits == 0` lets MPFR choose the count. `Digits.digits()` borrows its NUL-terminated buffer until `deinit`.

## Ownership

MPFR allocates `Float` and `Digits` storage through GMP; no Zig allocator is involved. Each successful construction owes exactly one `deinit`. Copies alias the same allocation, so release only one copy. `raw()` and `rawConst()` borrow the `Float`'s `mpfr_t`; they are not another owner. Do not call `mpfr_clear` on them or replace the storage with custom MPFR initialization.

## Library state

`Flags` provides `read`, `toRaw`, `fromRaw`, `raise` and `lower`. Module helpers are `flags`, `setFlags`, `clearFlags` and `clearAllFlags`.

Default-state helpers are `defaultPrecision`, `setDefaultPrecision`, `defaultRoundingMode` and `setDefaultRoundingMode`. Exponent-limit helpers are `minimumExponent`, `maximumNegativeExponent`, `minimumPositiveExponent`, `maximumExponent`, `minimumExponentInUse`, `setMinimumExponent`, `maximumExponentInUse` and `setMaximumExponent`; the setters return `bool`.

`version`, `patches` and `tuningCase` return borrowed library strings; do not free them. `freeCaches` releases MPFR caches. `cleanupMemory` releases MPFR/GMP memory pools; upstream recommends calling it before a thread exits.

In the package-built library, flags, default precision and rounding, and exponent limits are process-wide. Synchronise concurrent writes. An installed provider may use thread-local state; `c.mpfr_buildopt_tls_p()` reports that provider's setting.

## Runtime loading

`runtime_loaded` is a comptime `bool`. In a runtime-loaded build, call `load(source)` before other MPFR calls. `LoadSource.path` names a library file; `LoadSource.system` names a library for the platform loader. There is no fallback or unload. The provider must be a shared MPFR library with shared GMP.

`load` returns `LoadError` for open, symbol, ABI or provider failures; a failed attempt can be retried explicitly. Repeating the successful request is harmless; a different request returns `ProviderMismatch`. `loadedSource()` returns the retained request or `null`. Calling `load` in a linked build panics.

## Raw C API

Use `c` for MPFR or GMP functions that the facade does not wrap. The names, types, pointer rules and ownership remain upstream's. A `Float` pointer from `raw()` or `rawConst()` is valid only until that value is deinitialized.