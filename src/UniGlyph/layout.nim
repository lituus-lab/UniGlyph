# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
## UniGlyph/layout — single-line left-to-right typesetting.
##
## Places glyphs along a baseline using advance widths from `hmtx`. No kerning,
## no shaping, no wrapping: each rune maps to one glyph and advances by its
## scaled width. The y axis is flipped (TrueType y is up; image y is down), so
## `origin.y` is the baseline and glyphs rise above it for negative screen-y.
import std/unicode

import UniVector

import UniGlyph/font
import UniGlyph/glyph

type
  TextRun* = object
    ## A laid-out glyph slot: its translated path and the pen origin it was
    ## placed at.
    path*: Path
    origin*: Vector2f
  Typeset* = object
    slots*: seq[TextRun]
    advance*: float32 # total advance from the origin (pixels)

proc typeset*(f: Font, text: string, size: float32, origin: Vec2): Typeset =
  ## Lay out `text` on a single left-to-right line at `size` pixels, starting
  ## at `origin` (the baseline). Glyph paths are in pixel units with the
  ## per-glyph translation baked in.
  let s = f.scaleFactor(size)
  var penX = origin.x
  let baselineY = origin.y
  for r in text.runes:
    let gid = f.glyphId(int(int32(r)))
    let p = glyphPathAt(f, gid, s, -s, penX, baselineY)
    result.slots.add TextRun(path: p, origin: vec2(penX, baselineY))
    penX += float32(f.advanceWidth(gid)) * s
  result.advance = penX - origin.x

proc textWidth*(f: Font, text: string, size: float32): float32 =
  ## Total advance width of `text` at `size` pixels, with no kerning.
  let s = f.scaleFactor(size)
  var w: float32 = 0.0'f32
  for r in text.runes:
    w += float32(f.advanceWidth(f.glyphId(int(int32(r))))) * s
  w

proc combinedPath*(ts: Typeset): Path =
  ## Concatenate every slot path into one path (winding preserved).
  result = newPath()
  for slot in ts.slots:
    result.addPath(slot.path)


