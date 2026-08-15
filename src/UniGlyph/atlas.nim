# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
## Renderer-neutral RGBA8 glyph atlas generation.
import std/[math, unicode]

import UniColor
import UniImage/core as uimg
import UniVector

import UniGlyph/common
import UniGlyph/font
import UniGlyph/glyph
import UniGlyph/shaping

type
  AtlasEntry* = object
    glyph*: GlyphId
    faceIndex*: int
    x*, y*, width*, height*: int
    bearingX*, bearingY*, advance*: float32

  GlyphAtlas* = object
    width*, height*: int
    pixels*: seq[uint8]
    entries*: seq[AtlasEntry]

proc contains(entries: openArray[AtlasEntry], faceIndex: int,
    glyph: GlyphId): bool =
  for entry in entries:
    if entry.faceIndex == faceIndex and entry.glyph == glyph: return true

proc buildGlyphAtlas*(style: TextStyle, codepoints: openArray[int],
    width = 1024, padding = 1): GlyphAtlas =
  ## Pack requested glyphs in deterministic rows. Pixels are RGBA8 and contain
  ## white coverage on transparency; no GPU resource is created.
  if style.family.faces.len == 0:
    raise newException(ValueError, "atlas requires at least one font face")
  if width <= 0 or padding < 0:
    raise newException(ValueError, "invalid atlas dimensions")
  discard shape(style, "") # validate the complete style for an empty atlas too
  result.width = width
  var cursorX = padding
  var cursorY = padding
  var rowHeight = 0
  for cp in codepoints:
    if cp < 0 or cp > 0x10FFFF or (cp >= 0xD800 and cp <= 0xDFFF):
      raise newException(ValueError, "atlas codepoint is not a Unicode scalar")
    let run = shape(style, $Rune(cp))
    if run.placements.len == 0: continue
    let placement = run.placements[0]
    if result.entries.contains(placement.faceIndex, placement.glyph): continue
    let b = placement.inkBounds
    let glyphWidth = max(1, int(ceil(b.width)))
    let glyphHeight = max(1, int(ceil(b.height)))
    if glyphWidth + padding * 2 > width:
      raise newException(ValueError, "glyph is wider than atlas")
    if cursorX + glyphWidth + padding > width:
      cursorX = padding
      cursorY += rowHeight + padding
      rowHeight = 0
    result.entries.add AtlasEntry(glyph: placement.glyph,
      faceIndex: placement.faceIndex, x: cursorX, y: cursorY,
      width: glyphWidth, height: glyphHeight, bearingX: b.xMin,
      bearingY: b.yMin, advance: placement.xAdvance)
    cursorX += glyphWidth + padding
    rowHeight = max(rowHeight, glyphHeight)
  result.height = max(1, cursorY + rowHeight + padding)
  var image = uimg.newImage[uint8](result.width, result.height, uimg.csRgba)
  let white = parseColor("#ffffff").get
  for entry in result.entries:
    let face = style.family.faces[entry.faceIndex]
    let scale = face.scaleFactor(style.size)
    let path = face.glyphPathAt(entry.glyph, scale, -scale,
      float32(entry.x) - entry.bearingX,
      float32(entry.y) - entry.bearingY)
    image.fillPath(path, white, NonZero)
  result.pixels = image.data
