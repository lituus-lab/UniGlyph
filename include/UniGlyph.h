// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 lituus-lab
#ifndef UNIGLYPH_H
#define UNIGLYPH_H

#include <stddef.h>
#include <stdint.h>

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

/* Opaque, library-owned handles. NULL is a no-op for every `_free`. */
typedef struct ugly_font  ugly_font;
typedef struct ugly_image ugly_image;
typedef struct ugly_color  ugly_color;

/* Idempotent NimMain bootstrap. Call once before any other ugly_* entry.
 * Never raises. Single-threaded, reentrant. */
int ugly_init(void);

/* ABI version of this lib (matches UNIGLYPH_ABI_VERSION). */
int ugly_abi_version(void);

/* Static version string; do not free. */
const char *ugly_version(void);

/* Static message for an ugly_* status code. */
const char *ugly_strerror(int code);

/* ------------------------------- font ------------------------------------- */

/* Load and parse a TrueType font file. NULL on a nil path, missing file, or
 * malformed font. Free with ugly_font_free. */
ugly_font *ugly_font_load(const char *path);

/* Font ascent / descent in design units (0 on a NULL handle). */
int ugly_font_ascent(ugly_font *f);
int ugly_font_descent(ugly_font *f);

/* Scaled line height (ascent - descent + lineGap) at `size` px. */
float ugly_font_line_height(ugly_font *f, float size);

void ugly_font_free(ugly_font *f);

/* ------------------------------- image ------------------------------------ */

/* A zeroed (transparent) RGBA8 image. NULL on bad dimensions. */
ugly_image *ugly_image_new(int width, int height);

int ugly_image_width(ugly_image *img);
int ugly_image_height(ugly_image *img);
int ugly_image_channels(ugly_image *img);

/* Borrow the pixel buffer (no copy). Valid until ugly_image_free; do NOT free
 * with ugly_buffer_free. Empty image -> *outPtr = NULL, *outLen = 0, UGLY_OK. */
int ugly_image_pixels(ugly_image *img, uint8_t **outPtr, size_t *outLen);

/* Encode the image as PNG. On success allocates *outData (free with
 * ugly_buffer_free) and sets *outLen. */
int ugly_image_encode_png(ugly_image *img, uint8_t **outData, size_t *outLen);

void ugly_image_free(ugly_image *img);

/* ------------------------------- color ------------------------------------ */

/* Parse a CSS Color 4 string (hex/rgb/oklch/...). NULL on a nil string or
 * unparseable input. */
ugly_color *ugly_color_parse(const char *s);

/* An sRGB color from straight-alpha floats in [0, 1]. NULL on out-of-gamut. */
ugly_color *ugly_color_rgba(float r, float g, float b, float a);

void ugly_color_free(ugly_color *c);

/* ------------------------------- text ------------------------------------- */

/* Total advance width of `text` at `size` px (no kerning). 0 on a NULL handle
 * or text. */
float ugly_text_width(ugly_font *f, const char *text, float size);

/* Lay out `text` single-line LTR at `size` px with baseline origin (x, y) and
 * solid-fill the combined glyph path with `color` onto `img` (RGBA8, NonZero).
 * UGLY_OK on success, UGLY_ERR_FORMAT on a NULL handle or text. */
int ugly_render_text(ugly_image *img, ugly_font *f, const char *text,
                     float size, float x, float y, ugly_color *color);

/* ------------------------------- buffer ----------------------------------- */

/* Free a buffer returned by ugly_image_encode_png. NULL is a no-op. `len` is
 * ignored. Do NOT use on ugly_image_pixels output. */
void ugly_buffer_free(void *p, size_t len);

#ifdef __cplusplus
}
#endif

#endif /* UNIGLYPH_H */
