// SPDX-License-Identifier: LGPL-3.0-or-later
//! MPFR runtime providers must match the translated MPFR/GMP ABI.
//! GMP exports must resolve through the shared libmpfr dependency closure.
//! Keep the handle live: MPFR values and strings use its GMP allocator; state is process-wide.

const rt = @import("rt");

/// Namespaced synchronization functions for this loader instance.
pub const Sync = struct {
    extern fn mpfr_rt_lock() void;
    extern fn mpfr_rt_unlock() void;
    extern fn mpfr_rt_wait() void;
    extern fn mpfr_rt_broadcast() void;
    // C returns unsigned long long, which is u64 on supported targets.
    extern fn mpfr_rt_thread_self() u64;

    pub fn lock() void {
        mpfr_rt_lock();
    }
    pub fn unlock() void {
        mpfr_rt_unlock();
    }
    pub fn wait() void {
        mpfr_rt_wait();
    }
    pub fn broadcast() void {
        mpfr_rt_broadcast();
    }
    pub fn threadSelf() u64 {
        return mpfr_rt_thread_self();
    }
};

/// Configures the loader for this SDK's generated dispatch.
pub fn Config(comptime dispatch: type) type {
    return struct {
        /// Name used in pre-load panic messages.
        pub const library_name = "mpfr";

        /// Generated table and symbol lists from the translated headers.
        pub const table = dispatch.Table;
        pub const symbols = dispatch.symbols;
        pub const optional_symbols = dispatch.optional_symbols;

        /// The project's namespaced synchronization binding.
        pub const sync = Sync;

        pub fn tablePtr() *table {
            return dispatch.tablePtr();
        }

        pub fn ready() *rt.Ready {
            return &dispatch.ready;
        }

        pub fn assign(comptime index: usize, dst: *table, address: *const anyopaque) void {
            dispatch.assign(index, dst, address);
        }

        /// Writes an optional provider address into its table field.
        pub inline fn assignOptional(comptime index: usize, dst: *table, address: *const anyopaque) void {
            dispatch.assignOptional(index, dst, address);
        }

        pub inline fn assignMissing(comptime index: usize, dst: *table) void {
            dispatch.assignMissing(index, dst);
        }

        /// Validates provider requirements before table publication.
        /// Returns a refusal message for `ValidationFailed`.
        pub fn validate(dst: *const table) ?[]const u8 {
            // Compare GMP's exported limb width with the translated header.
            if (dst.__gmp_bits_per_limb.* != dispatch.GMP_NUMB_BITS) {
                return "this provider's GMP reports a different number of bits " ++
                    "per limb than the translated gmp.h describes, so mp_limb_t, " ++
                    "mp_size_t and __mpfr_struct do not mean the same thing on " ++
                    "both sides";
            }

            // These options must match the translated header's missing declarations (src/mpfr.h:470-486, 530-533).
            if (dst.mpfr_buildopt_float128_p() != 0) {
                return "this provider was built with MPFR_WANT_FLOAT128, so it " ++
                    "declares float128 entry points the translated header does not";
            }
            if (dst.mpfr_buildopt_decimal_p() != 0) {
                return "this provider was built with MPFR_WANT_DECIMAL_FLOATS, " ++
                    "so it declares decimal entry points the translated header " ++
                    "does not";
            }

            // Non-empty strings show the provider answered; they do not establish ABI compatibility.
            if (dst.mpfr_get_version()[0] == 0) {
                return "mpfr_get_version() answered with an empty string, so this " ++
                    "provider is not the library this header describes";
            }
            if (dst.mpfr_buildopt_tune_case()[0] == 0) {
                return "mpfr_buildopt_tune_case() answered with an empty string, " ++
                    "which no MPFR_TUNE_CASE can be (src/mparam_h.in:26-85)";
            }

            return null;
        }
    };
}
