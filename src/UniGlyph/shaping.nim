# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
## Renderer-neutral Unicode-to-glyph mapping and horizontal positioning.
import std/[algorithm, math, unicode]

import UniGlyph/common
import UniGlyph/font

type
  ShapingCapability* = enum
    scNominalMapping
    scPairKerning
    scOpenTypeSubstitution
    scOpenTypePositioning
    scComplexBidi
    scMarkAttachment

  ShapingCapabilityError* = object of ValueError

  TextDirection* = enum
    tdAuto
    tdLeftToRight
    tdRightToLeft

  FontFamily* = object
    ## Ordered faces. The first face containing a scalar wins.
    faces*: seq[Font]

  TextStyle* = object
    family*: FontFamily
    size*: float32
    direction*: TextDirection
    letterSpacing*: float32
    wordSpacing*: float32
    lineHeight*: float32
    tabSize*: int

  GlyphPlacement* = object
    glyph*: GlyphId
    faceIndex*: int
    cluster*: int ## Unicode-scalar index within this glyph run.
    codepoint*: int
    xAdvance*, yAdvance*: float32
    xOffset*, yOffset*: float32
    inkBounds*: TextBounds

  GlyphRun* = object
    direction*: TextDirection
    placements*: seq[GlyphPlacement]
    advance*: float32

proc fontFamily*(faces: varargs[Font]): FontFamily =
  ## Construct an ordered fallback family.
  result.faces = @faces

proc textStyle*(font: Font, size: float32,
    direction = tdAuto): TextStyle =
  ## Convenience style for a single face.
  TextStyle(family: fontFamily(font), size: size, direction: direction,
    tabSize: 4)

const UniGlyphCapabilities* = {scNominalMapping, scPairKerning}

proc supports*(capability: ShapingCapability): bool {.inline.} =
  capability in UniGlyphCapabilities

proc isRtl(cp: int): bool {.inline.} =
  (cp >= 0x0590 and cp <= 0x08FF) or
    (cp >= 0xFB1D and cp <= 0xFDFF) or
    (cp >= 0xFE70 and cp <= 0xFEFF)

proc isLtr(cp: int): bool {.inline.} =
  (cp >= 0x0041 and cp <= 0x005A) or
    (cp >= 0x0061 and cp <= 0x007A) or
    (cp >= 0x00C0 and cp <= 0x02AF) or
    (cp >= 0x0370 and cp <= 0x052F)

proc resolvedDirection(codepoints: openArray[int], requested: TextDirection):
    TextDirection =
  if requested != tdAuto: return requested
  for cp in codepoints:
    if isRtl(cp): return tdRightToLeft
    if isLtr(cp): return tdLeftToRight
  tdLeftToRight

proc chooseFace(family: FontFamily, cp: int): int =
  for i, face in family.faces:
    if face.hasGlyph(cp): return i
  if family.faces.len > 0: 0 else: -1

proc scaleBounds(bounds: TextBounds, scale: float32): TextBounds =
  TextBounds(xMin: bounds.xMin * scale, yMin: -bounds.yMax * scale,
    xMax: bounds.xMax * scale, yMax: -bounds.yMin * scale)

proc shape*(style: TextStyle, text: string,
    required: set[ShapingCapability] = {}): GlyphRun =
  ## Map UTF-8 text to positioned glyphs with ordered fallback and legacy
  ## horizontal pair kerning. Newlines are layout separators and are omitted.
  let missing = required - UniGlyphCapabilities
  if missing != {}:
    raise newException(ShapingCapabilityError,
      "requested shaping capability is unavailable")
  if validateUtf8(text) >= 0:
    raise newException(ValueError, "text is not valid UTF-8")
  if style.family.faces.len == 0:
    raise newException(ValueError, "shape requires at least one font face")
  for face in style.family.faces:
    if face.isNil:
      raise newException(ValueError, "font family contains a nil face")
  if classify(style.size) in {fcNan, fcInf, fcNegInf} or style.size <= 0:
    raise newException(ValueError, "text size must be finite and positive")
  if classify(style.letterSpacing) in {fcNan, fcInf, fcNegInf} or
      classify(style.wordSpacing) in {fcNan, fcInf, fcNegInf}:
    raise newException(ValueError, "text spacing must be finite")
  if classify(style.lineHeight) in {fcNan, fcInf, fcNegInf} or
      style.lineHeight < 0:
    raise newException(ValueError, "line height must be finite and non-negative")
  if style.tabSize < 0:
    raise newException(ValueError, "tab size must be non-negative")
  var cps: seq[int]
  for rune in text.runes:
    let cp = int(int32(rune))
    if cp != 0x0A and cp != 0x0D: cps.add cp
  result.direction = resolvedDirection(cps, style.direction)
  var previousGlyph: GlyphId
  var previousFace = -1
  for cluster, cp in cps:
    let faceIndex = chooseFace(style.family, cp)
    if faceIndex < 0: continue
    let face = style.family.faces[faceIndex]
    var glyph = face.glyphId(cp)
    let scale = face.scaleFactor(style.size)
    var advance = float32(face.advanceWidth(glyph)) * scale +
      style.letterSpacing
    if cp == 0x20: advance += style.wordSpacing
    if cp == 0x09:
      let spaceGlyph = face.glyphId(0x20)
      glyph = spaceGlyph
      advance = 0
    result.placements.add GlyphPlacement(glyph: glyph, faceIndex: faceIndex,
      cluster: cluster, codepoint: cp, xAdvance: advance,
      inkBounds: scaleBounds(face.glyphBounds(glyph), scale))
    result.advance += advance
  if result.direction == tdRightToLeft:
    reverse(result.placements)
  result.advance = 0
  for i in 0 ..< result.placements.len:
    let placement = result.placements[i]
    if previousFace == placement.faceIndex:
      let face = style.family.faces[placement.faceIndex]
      let adjustment = float32(face.kerning(previousGlyph, placement.glyph)) *
        face.scaleFactor(style.size)
      result.placements[i - 1].xAdvance += adjustment
      result.advance += adjustment
    if placement.codepoint == 0x09:
      let face = style.family.faces[placement.faceIndex]
      let columns = if style.tabSize > 0: style.tabSize else: 4
      let stop = (float32(face.advanceWidth(placement.glyph)) *
        face.scaleFactor(style.size) + style.letterSpacing +
        style.wordSpacing) * float32(columns)
      if stop > 0:
        result.placements[i].xAdvance =
          (floor(result.advance / stop) + 1'f32) * stop - result.advance
    result.advance += result.placements[i].xAdvance
    previousGlyph = placement.glyph
    previousFace = placement.faceIndex
