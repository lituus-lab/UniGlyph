# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
# Shell-free: `pwd` and `rm` are unavailable under mingw32-make on Windows.
ifeq ($(origin CC),default)
  ifeq ($(OS),Windows_NT)
    CC := gcc
  else
    CC := cc
  endif
endif

ROOT   := $(CURDIR)/../..
CFLAGS := -I$(ROOT)/include -O2 -Wall -Wextra -std=c11 \
          -DTEST_FONT=\"$(ROOT)/tests/assets/DejaVuSans.ttf\"
LIB    := $(ROOT)/libUniGlyph.a
# libUniGlyph.a references uncompress/compress2 (UniImage PNG/DEFLATE codecs
# via libz FFI); ugly_image_encode_png pulls them in, so a C consumer must
# supply libz itself.
ifeq ($(OS),Windows_NT)
  LIBS := -lz
else
  LIBS := -lz
endif

ifeq ($(OS),Windows_NT)
  BIN  := test_uniglyph.exe
  RUN  := $(BIN)
  RM_F := del /q
else
  BIN  := test_uniglyph
  RUN  := ./$(BIN)
  RM_F := rm -f
endif

.PHONY: all run clean
all: run
run: $(BIN)
	$(RUN)
$(BIN): test_uniglyph.c $(ROOT)/include/UniGlyph.h $(LIB)
	$(CC) $(CFLAGS) -o $(BIN) test_uniglyph.c $(LIB) $(LIBS)
# File target, not phony: `nimble ctest` already built the lib, don't redo it.
$(LIB):
	cd $(ROOT) && nimble clibStatic
clean:
	-$(RM_F) $(BIN)