# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
## UniGlyph/font — a loaded TrueType font handle and its metrics.
##
## `loadTtf` reads a file and parses its tables once; outline and metric
## queries are served from the parsed `Tables`. Vertical metrics come from
## `hhea` + `head`, per-glyph advance widths from `hmtx`.
import std/math
import contracts
import UniGlyph/common
import UniGlyph/tables

type
  Font* = ref object
    ## A loaded TrueType font. Holds the parsed tables; outlines and metrics
    ## are read on demand.
    t: Tables

proc readBytes(path: string): seq[byte] =
  let s = readFile(path)
  result = newSeq[byte](s.len)
  if s.len > 0:
    copyMem(result[0].addr, s[0].unsafeAddr, s.len)

proc loadTtf*(path: string): Font {.contractual.} =
  ## Read and parse a TrueType font file. Raises `FontError` on a malformed or
  ## unsupported file.
  require:
    path.len > 0
  body:
    Font(t: parseTables(readBytes(path)))

proc loadTtfFromBytes*(data: seq[byte]): Font {.contractual.} =
  ## Parse a font already held in memory (used by tests and the C ABI).
  require:
    data.len > 0
  body:
    Font(t: parseTables(data))

proc unitsPerEm*(f: Font): int {.contractual.} =
  require:
    not f.isNil
  body:
    int(f.t.unitsPerEm)

proc ascent*(f: Font): int {.contractual.} =
  require:
    not f.isNil
  body:
    int(f.t.ascent)

proc descent*(f: Font): int {.contractual.} =
  require:
    not f.isNil
  body:
    int(f.t.descent)

proc lineGap*(f: Font): int {.contractual.} =
  require:
    not f.isNil
  body:
    int(f.t.lineGap)

proc numGlyphs*(f: Font): int {.contractual.} =
  require:
    not f.isNil
  body:
    int(f.t.numGlyphs)

proc scaleFactor*(f: Font, size: float32): float32 {.contractual.} =
  ## Pixel size per design unit for a target em `size`.
  require:
    not f.isNil and f.t.unitsPerEm > 0'u16
  ensure:
    result >= 0'f32
  body:
    if classify(size) in {fcNan, fcInf, fcNegInf} or size < 0:
      raise newException(ValueError, "font size must be finite and non-negative")
    size / float32(f.t.unitsPerEm)

proc lineHeight*(f: Font, size: float32): float32 {.contractual.} =
  require:
    not f.isNil and f.t.unitsPerEm > 0'u16
  ensure:
    result >= 0'f32
  body:
    if classify(size) in {fcNan, fcInf, fcNegInf} or size < 0:
      raise newException(ValueError, "font size must be finite and non-negative")
    let s = f.scaleFactor(size)
    (float32(f.t.ascent - f.t.descent) + float32(f.t.lineGap)) * s

proc metrics*(f: Font): FontMetrics {.contractual.} =
  require:
    not f.isNil
  ensure:
    result.unitsPerEm > 0'u16
  body:
    FontMetrics(
      ascent: int32(f.t.ascent), descent: int32(f.t.descent),
      lineGap: int32(f.t.lineGap), unitsPerEm: f.t.unitsPerEm)

proc glyphId*(f: Font, rune: int): GlyphId {.contractual.} =
  require:
    not f.isNil
  body:
    cmapLookup(f.t, rune)

proc hasGlyph*(f: Font, rune: int): bool {.contractual.} =
  require:
    not f.isNil
  body:
    f.glyphId(rune) != 0

proc glyphOutline*(f: Font, gid: GlyphId): GlyphOutline {.contractual.} =
  require:
    not f.isNil
  body:
    glyphOutline(f.t, gid)

proc advanceWidth*(f: Font, gid: GlyphId): uint16 {.contractual.} =
  require:
    not f.isNil
  body:
    advanceWidth(f.t, gid)

proc leftSideBearing*(f: Font, gid: GlyphId): int32 {.contractual.} =
  require:
    not f.isNil
  body:
    leftSideBearing(f.t, gid)

proc kerning*(f: Font, left, right: GlyphId): int32 {.contractual.} =
  require:
    not f.isNil
  body:
    int32(kerning(f.t, left, right))

proc glyphBounds*(f: Font, gid: GlyphId): TextBounds {.contractual.} =
  require:
    not f.isNil
  body:
    glyphBounds(f.t, gid)
