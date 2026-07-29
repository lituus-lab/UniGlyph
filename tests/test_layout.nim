# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
import std/[os, unittest]
import UniGlyph
import UniVector

const FontPath = currentSourcePath.parentDir / "assets/DejaVuSans.ttf"

suite "layout":
  test "typeset lays out one slot per rune":
    let f = loadTtf(FontPath)
    let ts = typeset(f, "Hello", 48.0'f32, vec2(0.0'f32, 60.0'f32))
    check ts.slots.len == 5
    check ts.advance > 0.0'f32

  test "textWidth matches the typeset advance":
    let f = loadTtf(FontPath)
    let w = textWidth(f, "Hello", 48.0'f32)
    let ts = typeset(f, "Hello", 48.0'f32, vec2(0.0'f32, 60.0'f32))
    check abs(w - ts.advance) < 1e-3'f32

  test "combinedPath is non-empty":
    let f = loadTtf(FontPath)
    let ts = typeset(f, "Hello", 48.0'f32, vec2(0.0'f32, 60.0'f32))
    let p = ts.combinedPath()
    check p.commands.len > 0

  test "advance scales with size":
    let f = loadTtf(FontPath)
    let small = typeset(f, "Hello", 16.0'f32, vec2(0.0'f32, 60.0'f32)).advance
    let big = typeset(f, "Hello", 64.0'f32, vec2(0.0'f32, 60.0'f32)).advance
    check big > small
