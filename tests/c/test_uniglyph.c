// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 lituus-lab
#include <stdio.h>
#include <string.h>
#include "UniGlyph.h"

static int failures = 0;

static void check_str(const char *name, const char *got, const char *want) {
  if (strcmp(got, want) != 0) { printf("FAIL %s: got \"%s\" want \"%s\"\n", name, got, want); failures++; }
  else printf("ok   %s = \"%s\"\n", name, got);
}

static void check_int(const char *name, int got, int want) {
  if (got != want) { printf("FAIL %s: got %d want %d\n", name, got, want); failures++; }
  else printf("ok   %s = %d\n", name, got);
}

static void check_true(const char *name, int cond) {
  if (!cond) { printf("FAIL %s\n", name); failures++; }
  else printf("ok   %s\n", name);
}

int main(void) {
  ugly_init();
  check_str("version", ugly_version(), UNIGLYPH_VERSION);
  check_int("abi_version", ugly_abi_version(), UNIGLYPH_ABI_VERSION);
  check_true("capabilities nominal", (ugly_capabilities() & UGLY_CAP_NOMINAL_MAPPING) != 0);
  check_true("capabilities no GSUB", (ugly_capabilities() & UGLY_CAP_OPENTYPE_SUBSTITUTION) == 0);
  check_str("strerror(OK)", ugly_strerror(UGLY_OK), "ok");
  check_str("strerror(FORMAT)", ugly_strerror(UGLY_ERR_FORMAT), "bad argument / nil handle / unparseable font / bad color");
  check_str("strerror(unknown)", ugly_strerror(999), "unknown error");

  /* font */
  ugly_font *f = ugly_font_load(TEST_FONT);
  check_true("font_load", f != NULL);
  if (f == NULL) { printf("\nfont load failed; skipping remaining tests\n"); return 1; }
  check_true("font_ascent>0", ugly_font_ascent(f) > 0);
  check_true("font_descent<0", ugly_font_descent(f) < 0);
  check_int("font_units_per_em", ugly_font_units_per_em(f), 2048);
  check_true("font_num_glyphs", ugly_font_num_glyphs(f) > 100);
  uint32_t glyph_a = ugly_font_glyph_id(f, 'A');
  uint32_t glyph_v = ugly_font_glyph_id(f, 'V');
  check_true("font_has_glyph", ugly_font_has_glyph(f, 'A'));
  check_true("font_glyph_id", glyph_a != 0 && glyph_v != 0);
  check_true("font_advance", ugly_font_advance(f, glyph_a) > 0);
  check_true("font_kerning", ugly_font_kerning(f, glyph_a, glyph_v) < 0);
  check_true("font_line_height>0", ugly_font_line_height(f, 48.0f) > 0.0f);
  check_true("text_width>0", ugly_text_width(f, "Hello", 48.0f) > 0.0f);
  check_true("nil font -> width 0", ugly_text_width(NULL, "Hello", 48.0f) == 0.0f);

  ugly_family *family = ugly_family_new(f);
  check_true("family_new", family != NULL);
  check_int("family_add", ugly_family_add(family, f), UGLY_OK);
  check_int("family_count", (int)ugly_family_count(family), 2);

  /* measured layout */
  ugly_layout *layout = ugly_layout_new_family(family, "AV\ncenter", 32.0f,
                                                180.0f, UGLY_ALIGN_CENTER,
                                                UGLY_DIRECTION_LTR);
  check_true("layout_new", layout != NULL);
  check_true("layout_width", ugly_layout_width(layout) == 180.0f);
  check_true("layout_height", ugly_layout_height(layout) > 0.0f);
  check_int("layout_line_count", (int)ugly_layout_line_count(layout), 2);
  check_true("layout_glyph_count", ugly_layout_glyph_count(layout) == 8);
  ugly_bounds bounds;
  check_int("layout_bounds", ugly_layout_bounds(layout, 0, &bounds), UGLY_OK);
  check_true("layout_bounds height", bounds.y_max > bounds.y_min);
  ugly_glyph_info glyph_info;
  check_int("layout_glyph", ugly_layout_glyph(layout, 0, &glyph_info), UGLY_OK);
  check_true("layout_glyph advance", glyph_info.x_advance > 0.0f);
  check_int("layout_glyph line", glyph_info.line_index, 0);
  check_true("layout_glyph position", glyph_info.x > 0.0f && glyph_info.y > 0.0f);
  ugly_line_info line_info;
  check_int("layout_line", ugly_layout_line(layout, 1, &line_info), UGLY_OK);
  check_true("layout_line baseline", line_info.baseline_y > 0.0f);
  ugly_text_options options = {1.5f, 2.0f, 48.0f, 8};
  ugly_layout *spaced = ugly_layout_new_family_with_options(
      family, "A A", 32.0f, 0.0f, UGLY_ALIGN_START,
      UGLY_DIRECTION_LTR, &options);
  check_true("layout_with_options", spaced != NULL);
  check_true("layout_custom_line_height", ugly_layout_height(spaced) == 48.0f);

  /* color + image + render */
  ugly_color *black = ugly_color_parse("#000000");
  check_true("color_parse", black != NULL);
  ugly_image *img = ugly_image_new(200, 64);
  check_true("image_new", img != NULL);
  check_int("image_width", ugly_image_width(img), 200);
  check_int("image_height", ugly_image_height(img), 64);
  check_int("image_channels", ugly_image_channels(img), 4);

  int rc = ugly_render_text(img, f, "Hello", 48.0f, 2.0f, 50.0f, black);
  check_int("render_text", rc, UGLY_OK);
  check_int("render_text nil img", ugly_render_text(NULL, f, "Hello", 48.0f, 2.0f, 50.0f, black), UGLY_ERR_FORMAT);
  check_int("render_layout", ugly_render_layout(img, layout, black, 0.0f, 0.0f), UGLY_OK);

  /* renderer-neutral atlas */
  const uint32_t atlas_codepoints[] = {'A', 'V', 'A'};
  ugly_atlas *atlas = ugly_atlas_new(f, atlas_codepoints, 3, 24.0f, 128, 1);
  check_true("atlas_new", atlas != NULL);
  check_int("atlas_width", ugly_atlas_width(atlas), 128);
  check_true("atlas_height", ugly_atlas_height(atlas) > 0);
  check_int("atlas_entry_count", (int)ugly_atlas_entry_count(atlas), 2);
  ugly_atlas_entry_info atlas_entry;
  check_int("atlas_get_entry", ugly_atlas_get_entry(atlas, 0, &atlas_entry), UGLY_OK);
  check_true("atlas_entry dimensions", atlas_entry.width > 0 && atlas_entry.height > 0);
  const uint8_t *atlas_px = NULL;
  size_t atlas_len = 0;
  check_int("atlas_pixels", ugly_atlas_pixels(atlas, &atlas_px, &atlas_len), UGLY_OK);
  check_true("atlas_pixels borrowed", atlas_px != NULL && atlas_len > 0);

  /* PNG encode signature: 89 50 4E 47 (\x89PNG) */
  uint8_t *png = NULL;
  size_t pngLen = 0;
  rc = ugly_image_encode_png(img, &png, &pngLen);
  check_int("encode_png", rc, UGLY_OK);
  check_true("png nonempty", png != NULL && pngLen >= 4);
  if (png != NULL && pngLen >= 4) {
    check_true("png signature", png[0] == 0x89 && png[1] == 0x50 && png[2] == 0x4e && png[3] == 0x47);
  }
  ugly_buffer_free(png, pngLen);

  /* pixels borrow: non-NULL for a 200x64 RGBA image */
  uint8_t *px = NULL;
  size_t pxLen = 0;
  check_int("image_pixels", ugly_image_pixels(img, &px, &pxLen), UGLY_OK);
  check_true("pixels borrowed", px != NULL && pxLen == (size_t)(200 * 64 * 4));

  ugly_image_free(img);
  ugly_atlas_free(atlas);
  ugly_layout_free(layout);
  ugly_layout_free(spaced);
  ugly_family_free(family);
  ugly_color_free(black);
  ugly_font_free(f);
  check_true("free nil no-op", 1);

  if (failures == 0) { printf("\nAll C ABI tests passed.\n"); return 0; }
  printf("\n%d C ABI test(s) FAILED.\n", failures);
  return 1;
}
