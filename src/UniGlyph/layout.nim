# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
## Renderer-neutral lines and text blocks built from shaped glyph placements.
import std/[math, strutils, unicode]

import UniVector

import UniGlyph/common
import UniGlyph/font
import UniGlyph/glyph
import UniGlyph/shaping

type
  TextAlign* = enum
    taStart
    taCenter
    taEnd

  TextRun* = object
    ## Compatibility slot for the original single-line API.
    path*: Path
    origin*: Vector2f

  TextLine* = object
    run*: GlyphRun
    baseline*: Vector2f
    advance*: float32
    typographicBounds*: TextBounds
    inkBounds*: TextBounds

  TextLayout* = object
    style*: TextStyle
    lines*: seq[TextLine]
    typographicBounds*: TextBounds
    inkBounds*: TextBounds
    width*, height*: float32

  Typeset* = object
    ## Compatibility result for callers using the original API.
    slots*: seq[TextRun]
    advance*: float32

proc unionBounds(a, b: TextBounds): TextBounds =
  if a.isEmpty: return b
  if b.isEmpty: return a
  TextBounds(xMin: min(a.xMin, b.xMin), yMin: min(a.yMin, b.yMin),
    xMax: max(a.xMax, b.xMax), yMax: max(a.yMax, b.yMax))

proc lineMetrics(style: TextStyle): tuple[ascent, descent, height: float32] =
  let face = style.family.faces[0]
  let scale = face.scaleFactor(style.size)
  result.ascent = float32(face.ascent) * scale
  result.descent = float32(-face.descent) * scale
  let natural = face.lineHeight(style.size)
  result.height = if style.lineHeight > 0: style.lineHeight else: natural

proc makeLine(style: TextStyle, text: string, baselineY: float32): TextLine =
  result.run = shape(style, text)
  result.advance = result.run.advance
  result.baseline = vec2(0'f32, baselineY)
  let metrics = lineMetrics(style)
  result.typographicBounds = TextBounds(xMin: 0, yMin: baselineY -
    metrics.ascent,
    xMax: result.advance, yMax: baselineY + metrics.descent)
  var pen = 0'f32
  var hasInk = false
  for placement in result.run.placements:
    let b = placement.inkBounds
    let positioned = TextBounds(
      xMin: pen + placement.xOffset + b.xMin,
      yMin: baselineY + placement.yOffset + b.yMin,
      xMax: pen + placement.xOffset + b.xMax,
      yMax: baselineY + placement.yOffset + b.yMax)
    if not b.isEmpty:
      result.inkBounds = if hasInk: unionBounds(result.inkBounds, positioned)
        else: positioned
      hasInk = true
    pen += placement.xAdvance

proc explicitLines(text: string): seq[string] =
  result = @[""]
  for rune in text.runes:
    let cp = int(int32(rune))
    if cp == 0x0A:
      result.add ""
    elif cp != 0x0D:
      result[^1].add($rune)

proc splitLongWord(style: TextStyle, word: string,
    maxWidth: float32): seq[string] =
  var scalars: seq[string]
  for rune in word.runes: scalars.add $rune
  var first = 0
  while first < scalars.len:
    var lo = first + 1
    var hi = scalars.len
    var best = first + 1 # one scalar is indivisible even when it is too wide
    while lo <= hi:
      let mid = (lo + hi) div 2
      let candidate = scalars[first ..< mid].join("")
      if shape(style, candidate).advance <= maxWidth:
        best = mid
        lo = mid + 1
      else:
        hi = mid - 1
    result.add scalars[first ..< best].join("")
    first = best

proc layoutText*(style: TextStyle, text: string, maxWidth = 0'f32,
    align = taStart): TextLayout =
  ## Shape explicit lines and optionally wrap at Unicode spaces.
  if validateUtf8(text) >= 0:
    raise newException(ValueError, "text is not valid UTF-8")
  if style.family.faces.len == 0:
    raise newException(ValueError, "layout requires at least one font face")
  for face in style.family.faces:
    if face.isNil:
      raise newException(ValueError, "font family contains a nil face")
  if maxWidth < 0 or classify(maxWidth) in {fcNan, fcInf, fcNegInf}:
    raise newException(ValueError, "maxWidth must be finite and non-negative")
  result.style = style
  let metrics = lineMetrics(style)
  var logicalLines: seq[string]
  for paragraph in explicitLines(text):
    if maxWidth <= 0 or shape(style, paragraph).advance <= maxWidth:
      logicalLines.add paragraph
      continue
    var current = ""
    for word in unicode.splitWhitespace(paragraph):
      if shape(style, word).advance > maxWidth:
        if current.len > 0:
          logicalLines.add current
          current = ""
        let fragments = splitLongWord(style, word, maxWidth)
        for i in 0 ..< fragments.len - 1:
          logicalLines.add fragments[i]
        current = fragments[^1]
        continue
      let candidate = if current.len == 0: word else: current & " " & word
      if current.len > 0 and shape(style, candidate).advance > maxWidth:
        logicalLines.add current
        current = word
      else:
        current = candidate
    logicalLines.add current
  if logicalLines.len == 0: logicalLines = @[""]
  var maxAdvance = 0'f32
  for i, lineText in logicalLines:
    var line = makeLine(style, lineText, metrics.ascent + float32(i) *
        metrics.height)
    maxAdvance = max(maxAdvance, line.advance)
    result.lines.add line
  result.width = if maxWidth > 0: maxWidth else: maxAdvance
  var hasInk = false
  for i in 0 ..< result.lines.len:
    var dx = 0'f32
    case align
    of taStart:
      if result.lines[i].run.direction == tdRightToLeft:
        dx = result.width - result.lines[i].advance
    of taCenter: dx = (result.width - result.lines[i].advance) * 0.5'f32
    of taEnd:
      if result.lines[i].run.direction == tdLeftToRight:
        dx = result.width - result.lines[i].advance
    result.lines[i].baseline = vec2(dx, result.lines[i].baseline.y)
    var tb = result.lines[i].typographicBounds
    tb.xMin += dx; tb.xMax += dx
    result.lines[i].typographicBounds = tb
    var ib = result.lines[i].inkBounds
    if not ib.isEmpty:
      ib.xMin += dx; ib.xMax += dx
      result.lines[i].inkBounds = ib
    result.typographicBounds = if i == 0: tb
      else: TextBounds(xMin: min(result.typographicBounds.xMin, tb.xMin),
        yMin: min(result.typographicBounds.yMin, tb.yMin),
        xMax: max(result.typographicBounds.xMax, tb.xMax),
        yMax: max(result.typographicBounds.yMax, tb.yMax))
    if not ib.isEmpty:
      result.inkBounds = if hasInk: unionBounds(result.inkBounds, ib) else: ib
      hasInk = true
  result.height = float32(result.lines.len) * metrics.height

proc combinedPath*(layout: TextLayout, origin = vec2(0'f32, 0'f32)): Path =
  ## Convert a completed layout to a single UniVector path.
  result = newPath()
  for line in layout.lines:
    var penX = origin.x + line.baseline.x
    let baselineY = origin.y + line.baseline.y
    for placement in line.run.placements:
      let face = layout.style.family.faces[placement.faceIndex]
      let scale = face.scaleFactor(layout.style.size)
      result.addPath(face.glyphPathAt(placement.glyph, scale, -scale,
        penX + placement.xOffset, baselineY + placement.yOffset))
      penX += placement.xAdvance

proc typeset*(f: Font, text: string, size: float32, origin: Vec2): Typeset =
  ## Compatibility single-line layout. New code should retain `TextLayout`.
  let style = textStyle(f, size)
  let shaped = shape(style, text)
  var penX = origin.x
  for placement in shaped.placements:
    let scale = f.scaleFactor(size)
    let path = f.glyphPathAt(placement.glyph, scale, -scale,
      penX + placement.xOffset, origin.y + placement.yOffset)
    result.slots.add TextRun(path: path, origin: vec2(penX, origin.y))
    penX += placement.xAdvance
  result.advance = shaped.advance

proc textWidth*(f: Font, text: string, size: float32): float32 =
  ## Shaped single-line advance including pair kerning.
  shape(textStyle(f, size), text).advance

proc combinedPath*(ts: Typeset): Path =
  result = newPath()
  for slot in ts.slots: result.addPath(slot.path)
