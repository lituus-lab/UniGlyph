// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 lituus-lab
/* demo.c — minimal C consumer of the ugly_* ABI. A demo prints; it does not
 * assert. Build/run via `nimble cexample`. */
#include <stdio.h>
#include "UniGlyph.h"

int main(void) {
  ugly_init();
  printf("UniGlyph %s (ABI v%d)\n", ugly_version(), ugly_abi_version());
  printf("strerror(OK) = %s\n", ugly_strerror(UGLY_OK));
  return 0;
}
