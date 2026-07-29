# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
import std/[os, unittest]
import UniGlyph
import UniVector

const FontPath = currentSourcePath.parentDir / "assets/DejaVuSans.ttf"

suite "glyph":
  test "glyphPath('A') is non-empty":
    let f = loadTtf(FontPath)
    let p = f.glyphPath(ord('A'))
    check p.commands.len > 0

  test "glyphPath of a space is an empty outline":
    let f = loadTtf(FontPath)
    let p = f.glyphPath(ord(' '))
    check p.commands.len == 0

  test "glyphPathAt bakes a translation into the first command":
    let f = loadTtf(FontPath)
    let gid = f.glyphId(ord('A'))
    let p = f.glyphPathAt(gid, 1.0'f32, -1.0'f32, 100.0'f32, 200.0'f32)
    check p.commands.len > 0
    # The first command's start point is the translated first on-curve point.
    check p.start.x >= 100.0'f32
