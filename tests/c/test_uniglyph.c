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

int main(void) {
  ugly_init();
  check_str("version", ugly_version(), UNIGLYPH_VERSION);
  check_int("abi_version", ugly_abi_version(), UNIGLYPH_ABI_VERSION);
  check_str("strerror(OK)", ugly_strerror(UGLY_OK), "ok");
  check_str("strerror(FORMAT)", ugly_strerror(UGLY_ERR_FORMAT), "format error");
  check_str("strerror(unknown)", ugly_strerror(999), "unknown error");

  if (failures == 0) { printf("\nAll C ABI tests passed.\n"); return 0; }
  printf("\n%d C ABI test(s) FAILED.\n", failures);
  return 1;
}