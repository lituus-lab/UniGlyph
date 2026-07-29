// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 lituus-lab
#ifndef UNIGLYPH_H
#define UNIGLYPH_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

#define UNIGLYPH_VERSION_MAJOR 0
#define UNIGLYPH_VERSION_MINOR 1
#define UNIGLYPH_VERSION_PATCH 0
#define UNIGLYPH_VERSION "0.1.0"

#define UNIGLYPH_VERSION_AT_LEAST(ma, mi, pa) \
  ((UNIGLYPH_VERSION_MAJOR > (ma)) || \
   (UNIGLYPH_VERSION_MAJOR == (ma) && UNIGLYPH_VERSION_MINOR > (mi)) || \
   (UNIGLYPH_VERSION_MAJOR == (ma) && UNIGLYPH_VERSION_MINOR == (mi) && \
    UNIGLYPH_VERSION_PATCH >= (pa)))

#define UNIGLYPH_ABI_VERSION 1

typedef enum {
  UGLY_OK = 0,
  UGLY_ERR_FORMAT = 2,
  UGLY_ERR_UNSUP = 4,
  UGLY_ERR_MEM = 8
} ugly_status;

/* Idempotent NimMain bootstrap. Call once before any other ugly_* entry.
 * Never raises. Single-threaded, reentrant. */
int ugly_init(void);

/* ABI version of this lib (matches UNIGLYPH_ABI_VERSION). */
int ugly_abi_version(void);

/* Static version string; do not free. */
const char *ugly_version(void);

/* Static message for an ugly_* status code. */
const char *ugly_strerror(int code);

#ifdef __cplusplus
}
#endif

#endif /* UNIGLYPH_H */