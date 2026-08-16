// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 lituus-lab
#ifndef UNIGLYPH_H
#define UNIGLYPH_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define UNIGLYPH_VERSION_MAJOR 1
#define UNIGLYPH_VERSION_MINOR 0
#define UNIGLYPH_VERSION_PATCH 0
#define UNIGLYPH_VERSION "1.0.0"

#define UNIGLYPH_VERSION_AT_LEAST(ma, mi, pa) \
  ((UNIGLYPH_VERSION_MAJOR > (ma)) || \
   (UNIGLYPH_VERSION_MAJOR == (ma) && UNIGLYPH_VERSION_MINOR > (mi)) || \
   (UNIGLYPH_VERSION_MAJOR == (ma) && UNIGLYPH_VERSION_MINOR == (mi) && \
    UNIGLYPH_VERSION_PATCH >= (pa)))

#define UNIGLYPH_ABI_VERSION 1
#define UGLY_FONT_IDENTITY_SIZE 32

#define UGLY_CAP_NOMINAL_MAPPING       (1u << 0)
#define UGLY_CAP_PAIR_KERNING          (1u << 1)
#define UGLY_CAP_OPENTYPE_SUBSTITUTION (1u << 2)
#define UGLY_CAP_OPENTYPE_POSITIONING  (1u << 3)
#define UGLY_CAP_COMPLEX_BIDI          (1u << 4)
#define UGLY_CAP_MARK_ATTACHMENT       (1u << 5)

typedef enum {
  UGLY_OK = 0,
  UGLY_ERR_FORMAT = 2,
  UGLY_ERR_UNSUP = 4,
  UGLY_ERR_MEM = 8
} ugly_status;

/* Opaque, library-owned handles. NULL is a no-op for every `_free`. */
typedef struct ugly_font  ugly_font;
typedef struct ugly_family ugly_family;
typedef struct ugly_image ugly_image;
typedef struct ugly_color  ugly_color;
typedef struct ugly_layout ugly_layout;
typedef struct ugly_atlas  ugly_atlas;

typedef struct {
  float x_min, y_min, x_max, y_max;
} ugly_bounds;

typedef struct {
  uint32_t glyph;
  int face_index, line_index, cluster, codepoint;
  /* Baseline placement in layout coordinates; ink_bounds is glyph-relative. */
  float x, y, x_advance, y_advance, x_offset, y_offset;
  ugly_bounds ink_bounds;
} ugly_glyph_info;

typedef struct {
  /* Bounds and baseline are in layout coordinates. */
  float baseline_x, baseline_y, advance;
  ugly_bounds typographic_bounds, ink_bounds;
} ugly_line_info;

typedef struct {
  float letter_spacing, word_spacing, line_height;
  int tab_size;
} ugly_text_options;

typedef struct {
  uint32_t glyph;
  int face_index, x, y, width, height;
  float bearing_x, bearing_y, advance;
} ugly_atlas_entry_info;

typedef enum {
  UGLY_DIRECTION_AUTO = 0,
  UGLY_DIRECTION_LTR = 1,
  UGLY_DIRECTION_RTL = 2
} ugly_direction;

typedef enum {
  /* START/END are logical: right/left respectively for an RTL line. */
  UGLY_ALIGN_START = 0,
  UGLY_ALIGN_CENTER = 1,
  UGLY_ALIGN_END = 2
} ugly_align;

/* Idempotent NimMain bootstrap. Call once before any other ugly_* entry.
 * Never raises. Single-threaded, reentrant. */
int ugly_init(void);

/* ABI version of this lib (matches UNIGLYPH_ABI_VERSION). */
int ugly_abi_version(void);

/* Bitset of UGLY_CAP_* features implemented by this build. */
uint32_t ugly_capabilities(void);

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
int ugly_font_units_per_em(ugly_font *f);
int ugly_font_line_gap(ugly_font *f);
int ugly_font_num_glyphs(ugly_font *f);
uint32_t ugly_font_glyph_id(ugly_font *f, uint32_t codepoint);
int ugly_font_has_glyph(ugly_font *f, uint32_t codepoint);
uint32_t ugly_font_advance(ugly_font *f, uint32_t glyph);
int ugly_font_kerning(ugly_font *f, uint32_t left, uint32_t right);

/* Copy the BLAKE3-256 identity of the exact source bytes into caller-owned
 * storage. out_identity must point to at least UGLY_FONT_IDENTITY_SIZE
 * writable bytes. Returns UGLY_ERR_FORMAT if either argument is NULL. */
int ugly_font_identity(ugly_font *f,
                       uint8_t out_identity[UGLY_FONT_IDENTITY_SIZE]);

/* Scaled line height (ascent - descent + lineGap) at `size` px. */
float ugly_font_line_height(ugly_font *f, float size);

void ugly_font_free(ugly_font *f);

/* Ordered fallback family. The family retains each face. */
ugly_family *ugly_family_new(ugly_font *font);
int ugly_family_add(ugly_family *family, ugly_font *font);
size_t ugly_family_count(ugly_family *family);
void ugly_family_free(ugly_family *family);

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

/* Single-line advance at `size` px, including pair kerning. CR/LF are ignored.
 * Returns 0 on a NULL handle or text. */
float ugly_text_width(ugly_font *f, const char *text, float size);

/* Build a measured text block. max_width=0 disables wrapping. */
ugly_layout *ugly_layout_new(ugly_font *font, const char *text, float size,
                             float max_width, int align, int direction);
ugly_layout *ugly_layout_new_family(ugly_family *family, const char *text,
                                    float size, float max_width, int align,
                                    int direction);
ugly_layout *ugly_layout_new_with_options(ugly_font *font, const char *text,
                                          float size, float max_width,
                                          int align, int direction,
                                          const ugly_text_options *options);
ugly_layout *ugly_layout_new_family_with_options(
    ugly_family *family, const char *text, float size, float max_width,
    int align, int direction, const ugly_text_options *options);
float ugly_layout_width(ugly_layout *layout);
float ugly_layout_height(ugly_layout *layout);
size_t ugly_layout_line_count(ugly_layout *layout);
size_t ugly_layout_glyph_count(ugly_layout *layout);
int ugly_layout_bounds(ugly_layout *layout, int ink, ugly_bounds *out_bounds);
int ugly_layout_glyph(ugly_layout *layout, size_t index,
                      ugly_glyph_info *out_info);
int ugly_layout_line(ugly_layout *layout, size_t index,
                     ugly_line_info *out_info);
void ugly_layout_free(ugly_layout *layout);

int ugly_render_layout(ugly_image *img, ugly_layout *layout,
                       ugly_color *color, float x, float y);

/* Lay out `text` single-line LTR at `size` px with baseline origin (x, y) and
 * solid-fill the combined glyph path with `color` onto `img` (RGBA8, NonZero).
 * UGLY_OK on success, UGLY_ERR_FORMAT on a NULL handle or text. */
int ugly_render_text(ugly_image *img, ugly_font *f, const char *text,
                     float size, float x, float y, ugly_color *color);

/* ------------------------------- atlas ------------------------------------ */

ugly_atlas *ugly_atlas_new(ugly_font *font, const uint32_t *codepoints,
                           size_t count, float size, int width, int padding);
ugly_atlas *ugly_atlas_new_family(ugly_family *family,
                                  const uint32_t *codepoints, size_t count,
                                  float size, int width, int padding);
int ugly_atlas_width(ugly_atlas *atlas);
int ugly_atlas_height(ugly_atlas *atlas);
size_t ugly_atlas_entry_count(ugly_atlas *atlas);
int ugly_atlas_get_entry(ugly_atlas *atlas, size_t index,
                         ugly_atlas_entry_info *out_entry);
/* Borrowed RGBA8 pixels, valid until ugly_atlas_free. */
int ugly_atlas_pixels(ugly_atlas *atlas, const uint8_t **out_ptr,
                      size_t *out_len);
void ugly_atlas_free(ugly_atlas *atlas);

/* ------------------------------- buffer ----------------------------------- */

/* Free a buffer returned by ugly_image_encode_png. NULL is a no-op. `len` is
 * ignored. Do NOT use on ugly_image_pixels output. */
void ugly_buffer_free(void *p, size_t len);

#ifdef __cplusplus
}
#endif

#endif /* UNIGLYPH_H */
