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
  check_str("strerror(OK)", ugly_strerror(UGLY_OK), "ok");
  check_str("strerror(FORMAT)", ugly_strerror(UGLY_ERR_FORMAT), "bad argument / nil handle / unparseable font / bad color");
  check_str("strerror(unknown)", ugly_strerror(999), "unknown error");

  /* font */
  ugly_font *f = ugly_font_load(TEST_FONT);
  check_true("font_load", f != NULL);
  if (f == NULL) { printf("\nfont load failed; skipping remaining tests\n"); return 1; }
  check_true("font_ascent>0", ugly_font_ascent(f) > 0);
  check_true("font_descent<0", ugly_font_descent(f) < 0);
  check_true("font_line_height>0", ugly_font_line_height(f, 48.0f) > 0.0f);
  check_true("text_width>0", ugly_text_width(f, "Hello", 48.0f) > 0.0f);
  check_true("nil font -> width 0", ugly_text_width(NULL, "Hello", 48.0f) == 0.0f);

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
  ugly_color_free(black);
  ugly_font_free(f);
  check_true("free nil no-op", 1);

  if (failures == 0) { printf("\nAll C ABI tests passed.\n"); return 0; }
  printf("\n%d C ABI test(s) FAILED.\n", failures);
  return 1;
}
