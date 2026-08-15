# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
import std/[os, unittest]
import UniGlyph

const FontPath = currentSourcePath.parentDir / "assets/DejaVuSans.ttf"

suite "glyph atlas":
  test "atlas packs unique glyphs and produces coverage":
    let font = loadTtf(FontPath)
    let atlas = buildGlyphAtlas(textStyle(font, 32'f32),
      @[ord('A'), ord('V'), ord('A')], width = 128)
    check atlas.entries.len == 2
    check atlas.width == 128
    check atlas.height > 0
    check atlas.pixels.len == atlas.width * atlas.height * 4
    var covered = false
    for alpha in countup(3, atlas.pixels.high, 4):
      if atlas.pixels[alpha] != 0: covered = true; break
    check covered

  test "invalid width is rejected":
    let font = loadTtf(FontPath)
    expect ValueError:
      discard buildGlyphAtlas(textStyle(font, 32'f32), @[ord('A')], width = 0)

  test "invalid Unicode scalars are rejected":
    let font = loadTtf(FontPath)
    expect ValueError:
      discard buildGlyphAtlas(textStyle(font, 32'f32), @[0xD800])

  test "empty atlases still validate the text style":
    let font = loadTtf(FontPath)
    expect ValueError:
      discard buildGlyphAtlas(textStyle(font, 0'f32), newSeq[int]())
