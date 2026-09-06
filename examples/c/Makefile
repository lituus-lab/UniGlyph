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
CFLAGS := -I$(ROOT)/include -O2 -Wall -Wextra -std=c11
LIB    := $(ROOT)/libUniGlyph.a
# libUniGlyph.a references libz via UniImage's PNG/DEFLATE codecs; supply it
# even though the print-only demo does not call encode_png today.
ifeq ($(OS),Windows_NT)
  LIBS := -lz
else
  # glibc keeps libm separate, and the archive's UniColor and UniMath objects
  # call pow, hypot and friends. macOS resolves -lm through libSystem.
  LIBS := -lz -lm
endif

ifeq ($(OS),Windows_NT)
  BIN  := demo.exe
  RUN  := $(BIN)
  RM_F := del /q
else
  BIN  := demo
  RUN  := ./$(BIN)
  RM_F := rm -f
endif

.PHONY: all run clean
all: run
run: $(BIN)
	$(RUN)
$(BIN): demo.c $(ROOT)/include/UniGlyph.h $(LIB)
	$(CC) $(CFLAGS) -o $(BIN) demo.c $(LIB) $(LIBS)
# File target, not phony: `nimble cexample` already built the lib, don't redo it.
$(LIB):
	cd $(ROOT) && nimble clibStatic
clean:
	-$(RM_F) $(BIN)