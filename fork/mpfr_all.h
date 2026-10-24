/* mpfr_all.h -- aggregate public header for the Zig translation of GNU MPFR.
 *
 * This file is a fork-only addition; GNU MPFR itself ships no such header.
 *
 * MPFR's public headers are `mpfr.h` and `mpf2mpfr.h`.  `mpfr.h` includes
 * `<gmp.h>`, and its intmax_t entry points (`mpfr_set_sj`, `mpfr_get_uj`,
 * `mpfr_pow_sj`, `mpfr_pown`, ...) are declared only when `intmax_t` is
 * already visible while `mpfr.h` is being parsed.  See src/mpfr.h:1136-1154
 * for the auto-detection rules and src/mpfr.h:33-36 for the
 * `MPFR_USE_INTMAX_T` override the manual recommends.
 *
 * This header therefore includes <stdint.h> first and then pins
 * `MPFR_USE_INTMAX_T` to 1.  That makes the translated ABI identical on every
 * target instead of depending on which libc header the C preprocessor happened
 * to see first.  It matters for the x86_64-windows-gnu target in the fork's
 * cross-compile matrix, where the `_STDINT` / `_STDINT_H_` probes in
 * src/mpfr.h:1151-1154 are not guaranteed to fire under MinGW-w64 headers.
 *
 * <stdio.h> also precedes <mpfr.h>, so GMP and MPFR expose their public
 * FILE-taking entry points with the target libc's own FILE type.
 *
 * The compiled library is pinned the same way, and has to be: the library only
 * defines `__gmpfr_set_sj` and its siblings in the units that reach
 * src/mpfr-intmax.h, so declaring them here without pinning the compile line
 * would describe entry points the linked library never exported.  build.zig
 * gives every libmpfr unit `HAVE_STDINT_H`, which src/mpfr-intmax.h:60-68
 * turns into <stdint.h> plus `MPFR_USE_INTMAX_T` before src/mpfr.h:1151-1155
 * is parsed.  In `-fsys=mpfr` mode this header still pins the macro, which
 * is what doc/mpfr.texi:692-695 recommends for portable user code; the
 * identity check in fork/tests/lifetime_test.zig is what makes an installed
 * library that predates the intmax entry points fail loudly rather than at a
 * link step with no explanation.
 *
 * `MPFR_USE_MINI_GMP` is deliberately left undefined: the shared fork
 * contract forbids substituting mini-gmp for the real GMP.
 *
 * Copyright 2000-2025 Free Software Foundation, Inc.
 * Contributed by the Pascaline and Caramba projects, INRIA.
 *
 * The included GNU MPFR headers are free software; you can redistribute them
 * and/or modify them under the terms of the GNU Lesser General Public License
 * as published by the Free Software Foundation; either version 3 of the
 * License, or (at your option) any later version.  See COPYING.LESSER.
 */

#ifndef MPFR_ALL_H
#define MPFR_ALL_H

/* Must precede <mpfr.h>: mpfr.h never includes <stdint.h> itself, see the
 * comment on `_MPFR_EXP_FORMAT == 4` in src/mpfr.h:194-208. */
#include <stdint.h>
#include <stdio.h>

/* Request the intmax_t-based entry points unconditionally and portably. */
#define MPFR_USE_INTMAX_T 1

#include <mpfr.h>
#include <mpf2mpfr.h>

#endif /* MPFR_ALL_H */
