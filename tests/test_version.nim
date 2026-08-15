# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
import std/unittest
import UniGlyph

suite "version":
  test "UniGlyphVersion is 1.0.0":
    check UniGlyphVersion == "1.0.0"
