# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
import std/[os, unittest]
import UniGlyph

const FontPath = currentSourcePath.parentDir / "assets/DejaVuSans.ttf"

suite "font":
  test "loadTtfFromBytes retains an immutable copy":
    let raw = readFile(FontPath)
    var bytes = newSeq[byte](raw.len)
    copyMem(bytes[0].addr, raw[0].unsafeAddr, raw.len)
    let font = loadTtfFromBytes(bytes)
    let before = font.glyphId(ord('A'))
    for i in 0 ..< bytes.len: bytes[i] = 0
    check font.glyphId(ord('A')) == before

  test "loadTtf reads DejaVuSans metrics":
    let f = loadTtf(FontPath)
    check f.unitsPerEm == 2048
    check f.ascent > 0
    check f.descent < 0
    check f.numGlyphs > 100

  test "glyphId and advanceWidth for 'A'":
    let f = loadTtf(FontPath)
    let gid = f.glyphId(ord('A'))
    check gid != 0
    check f.advanceWidth(gid) > 0

  test "lineHeight is positive and scales with size":
    let f = loadTtf(FontPath)
    check f.lineHeight(16.0'f32) > 0.0'f32
    check f.lineHeight(32.0'f32) > f.lineHeight(16.0'f32)

  test "scaleFactor is size / unitsPerEm":
    let f = loadTtf(FontPath)
    check abs(f.scaleFactor(2048.0'f32) - 1.0'f32) < 1e-4'f32
    expect ValueError:
      discard f.scaleFactor(NaN.float32)
    expect ValueError:
      discard f.lineHeight(Inf.float32)
