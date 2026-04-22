/*
 * Force-include header for building soxr on aarch64 (Apple Silicon).
 *
 * pffft.c in soxr 0.1.3 only checks defined(__arm__) for NEON, but
 * aarch64 compilers define __aarch64__ instead. This shim ensures the
 * NEON code path is taken on 64-bit ARM.
 */
#if defined(__aarch64__) && !defined(__arm__)
#  define __arm__
#endif
