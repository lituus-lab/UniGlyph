# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
import std/[os, unittest]
import UniGlyph
import UniVector
import UniColor
import UniImage/core as uimg
import UniImage/formats

const FontPath = currentSourcePath.parentDir / "assets/DejaVuSans.ttf"

proc whiteBg(img: var uimg.Image[uint8]) =
  for i in 0 ..< img.data.len: img.data[i] = 255

suite "render":
  test "fillPath renders dark pixels for 'Hello'":
    let f = loadTtf(FontPath)
    let size: float32 = 48.0'f32
    let w = int(textWidth(f, "Hello", size)) + 20
    let h = int(f.lineHeight(size)) + 20
    var img = uimg.newImage[uint8](w, h, uimg.csRgba)
    img.whiteBg()
    let baseline = float32(f.ascent) * f.scaleFactor(size) + 10.0'f32
    let ts = typeset(f, "Hello", size, vec2(10.0'f32, baseline))
    let p = ts.combinedPath()
    fillPath(img, p, parseColor("#000000").get, NonZero)
    var dark = false
    for i in countup(0, img.data.len - 4, 4):
      if img.data[i] < 10: dark = true; break
    check dark

  test "encodeImage produces a PNG signature":
    let f = loadTtf(FontPath)
    let size: float32 = 48.0'f32
    var img = uimg.newImage[uint8](100, 80, uimg.csRgba)
    img.whiteBg()
    let ts = typeset(f, "A", size, vec2(10.0'f32, 60.0'f32))
    let p = ts.combinedPath()
    fillPath(img, p, parseColor("#000000").get, NonZero)
    let png = encodeImage(img, efPng)
    check png.len > 8
    check png[0] == 0x89'u8
    check png[1] == 0x50'u8
    # Full 8-byte PNG signature: \x89 P N G \r \n \x1A \n. Asserting every byte
    # makes a malformed header fail rather than pass on the first two alone.
    check png[2] == 0x4E'u8
    check png[3] == 0x47'u8
    check png[4] == 0x0D'u8
    check png[5] == 0x0A'u8
    check png[6] == 0x1A'u8
    check png[7] == 0x0A'u8
