# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
## UniGlyph/common — shared leaf types for the glyph/text engine.
##
## Re-exports the `UniLinalg` vector types the layout layer places glyphs with,
## and defines the small domain primitives (glyph id, metrics records) every
## higher layer builds on. No OpenType or rendering dependencies live here.
import std/math
import UniLinalg
export UniLinalg.Vector2f, UniLinalg.vec2, UniLinalg.`[]`, UniLinalg.x,
  UniLinalg.y, UniLinalg.`+`, UniLinalg.`-`, UniLinalg.`*`, UniLinalg.`/`,
  UniLinalg.`+=`, UniLinalg.`-=`, UniLinalg.`*=`, UniLinalg.`/=`,
  UniLinalg.dot, UniLinalg.lengthSquared, UniLinalg.length, UniLinalg.normalize
export math.sqrt

type
  GlyphId* = uint32
    ## OpenType glyph index. 0 is `.notdef` / missing.
  FontMetrics* = object
    ## Font-wide vertical metrics in design units.
    ascent*: int32
    descent*: int32
    lineGap*: int32
    unitsPerEm*: uint16
  GlyphMetrics* = object
    ## Per-glyph horizontal metrics in design units.
    advanceWidth*: uint32
    leftSideBearing*: int32

  TextBounds* = object
    ## Axis-aligned bounds in pixels. Empty bounds have zero width and height.
    xMin*, yMin*, xMax*, yMax*: float32

proc width*(b: TextBounds): float32 {.inline.} = max(0'f32, b.xMax - b.xMin)
proc height*(b: TextBounds): float32 {.inline.} = max(0'f32, b.yMax - b.yMin)
proc isEmpty*(b: TextBounds): bool {.inline.} = b.width == 0 or b.height == 0

