# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
## UniGlyph/tables — read-only OpenType/TrueType table parsers.
##
## Spec-driven against the OpenType/TrueType specification (ISO/IEC 14496-22
## and the Microsoft OpenType spec). This is an original, read-only parser: it
## never mutates font data and supports only the TrueType outline flavor
## (`glyf`), not CFF/OTF charstrings. No hinting or GPOS/GSUB is applied;
## the parser resolves codepoints, glyph outlines, advances, and legacy
## horizontal kerning. Every read is bounds-checked; a malformed file raises
## `FontError`, which the C ABI traps and maps to `UGLY_ERR_FORMAT`.
import std/[algorithm, strutils]

import UniGlyph/common

type
  FontError* = object of CatchableError
    ## Raised on a truncated, malformed, or unsupported font file.

  GlyphPoint* = object
    ## A contour point in font design units.
    x*: float32
    y*: float32
    onCurve*: bool
  Contour* = seq[GlyphPoint]
  GlyphOutline* = seq[Contour]

  Cmap4* = object
    ## Parsed `cmap` Format 4 subtable (Unicode BMP, segment mapping to deltas).
    segCount*: int
    endCode*: seq[uint16]
    startCode*: seq[uint16]
    idDelta*: seq[int16]
    idRangeOffset*: seq[uint16] # raw byte offset, stored per spec
    idRangeOffsetPos*: seq[int] # byte offset of each entry within the font
    glyphIdArrayPos*: int       # byte offset of the glyphIdArray region
    subtableEnd*: int           # exclusive bound for indirect glyph reads

  Cmap12Group* = object
    startCode*, endCode*, startGlyph*: uint32

  KerningPair* = object
    left*, right*: uint16
    value*: int16
    order: int
    overrides: bool

  Tables* = object
    ## Parsed TrueType tables, kept together with the raw bytes they index.
    bytes*: seq[byte]
    unitsPerEm*: uint16
    indexToLocFormat*: int16
    ascent*: int16
    descent*: int16
    lineGap*: int16
    numGlyphs*: uint16
    numHMetrics*: uint16
    advanceWidths*: seq[uint16] # length numGlyphs (trailing entries repeat the last long metric)
    lsbs*: seq[int16]  # length numGlyphs
    loca*: seq[uint32] # length numGlyphs + 1 (raw glyf offsets)
    glyfOffset*: uint32
    glyfLength*: uint32
    cmap4*: Cmap4
    hasCmap4*: bool
    cmap12*: seq[Cmap12Group]
    kernPairs*: seq[KerningPair]

const
  MaxCompositeDepth* = 8
  MaxComponents* = 64
  ArgWords* = 0x0001'u16       # ARGS_1_AND_2_ARE_WORDS
  ArgXY* = 0x0002'u16          # ARGS_ARE_XY_VALUES
  RoundXY* = 0x0004'u16        # ROUND_XY_TO_GRID (ignored; no hinting)
  HaveScale* = 0x0008'u16      # WE_HAVE_A_SCALE
  MoreComponents* = 0x0020'u16 # MORE_COMPONENTS
  HaveXYScale* = 0x0040'u16    # WE_HAVE_AN_X_AND_Y_SCALE
  Have2x2* = 0x0080'u16        # WE_HAVE_A_TWO_BY_TWO
  ScaledOffset* = 0x0800'u16   # SCALED_COMPONENT_OFFSET
  UnscaledOffset* = 0x1000'u16 # UNSCALED_COMPONENT_OFFSET
  FlagOnCurve* = 0x01'u8
  FlagXShort* = 0x02'u8
  FlagYShort* = 0x04'u8
  FlagRepeat* = 0x08'u8
  FlagXSameOrPos* = 0x10'u8    # x-same (long) or x-positive (short)
  FlagYSameOrPos* = 0x20'u8    # y-same (long) or y-positive (short)

proc check(data: openArray[byte], off, n: int) =
  if off < 0 or off + n > data.len:
    raise newException(FontError,
      "read out of bounds: off=" & $off & " n=" & $n & " len=" & $data.len)

proc readU8(data: openArray[byte], off: int): uint8 =
  check(data, off, 1); data[off]

proc readI8(data: openArray[byte], off: int): int8 =
  check(data, off, 1); cast[int8](data[off])

proc readU16(data: openArray[byte], off: int): uint16 =
  check(data, off, 2)
  (uint16(data[off]) shl 8) or uint16(data[off + 1])

proc readI16(data: openArray[byte], off: int): int16 =
  cast[int16](readU16(data, off))

proc readU32(data: openArray[byte], off: int): uint32 =
  check(data, off, 4)
  (uint32(data[off]) shl 24) or (uint32(data[off + 1]) shl 16) or
    (uint32(data[off + 2]) shl 8) or uint32(data[off + 3])

proc readF2Dot14(data: openArray[byte], off: int): float32 =
  float32(readI16(data, off)) / 16384.0'f32

proc readTag(data: openArray[byte], off: int): string =
  check(data, off, 4)
  result = newString(4)
  for i in 0 ..< 4: result[i] = char(data[off + i])

type
  TableEntry = tuple[tag: string, offset: uint32, length: uint32]

proc findTable(entries: openArray[TableEntry], tag: string): TableEntry =
  for e in entries:
    if e.tag == tag: return e
  raise newException(FontError, "missing table: " & tag)

proc optionalTable(entries: openArray[TableEntry], tag: string,
    entry: var TableEntry): bool =
  for e in entries:
    if e.tag == tag:
      entry = e
      return true

proc requireLength(entry: TableEntry, minimum: uint32) =
  if entry.length < minimum:
    raise newException(FontError, "truncated table: " & entry.tag)

proc parseCmap12(data: openArray[byte], sub, tableEnd: int, t: var Tables) =
  if sub + 16 > tableEnd:
    raise newException(FontError, "truncated cmap format 12 header")
  if readU16(data, sub) != 12'u16:
    raise newException(FontError, "expected cmap format 12")
  let length = int(readU32(data, sub + 4))
  if length < 16 or sub + length > tableEnd:
    raise newException(FontError, "cmap format 12 exceeds cmap table")
  check(data, sub, length)
  let count = int(readU32(data, sub + 12))
  if count > (length - 16) div 12:
    raise newException(FontError, "truncated cmap format 12 groups")
  var previousEnd: uint32 = 0
  for i in 0 ..< count:
    let p = sub + 16 + i * 12
    let group = Cmap12Group(
      startCode: readU32(data, p), endCode: readU32(data, p + 4),
      startGlyph: readU32(data, p + 8))
    if group.startCode > group.endCode or group.endCode > 0x10FFFF'u32:
      raise newException(FontError, "invalid cmap format 12 group")
    let span = group.endCode - group.startCode
    if group.startGlyph > high(uint32) - span or
        group.startGlyph + span >= uint32(t.numGlyphs):
      raise newException(FontError, "cmap format 12 glyph range is invalid")
    if i > 0 and group.startCode <= previousEnd:
      raise newException(FontError, "unsorted cmap format 12 groups")
    t.cmap12.add group
    previousEnd = group.endCode

proc parseHmtx(data: openArray[byte], off: int, t: var Tables) =
  if t.numHMetrics > t.numGlyphs:
    raise newException(FontError,
      "numberOfHMetrics exceeds numGlyphs")
  setLen(t.advanceWidths, t.numGlyphs.int)
  setLen(t.lsbs, t.numGlyphs.int)
  var p = off
  var lastAdv: uint16 = 0
  for i in 0 ..< t.numHMetrics.int:
    lastAdv = readU16(data, p)
    t.advanceWidths[i] = lastAdv
    t.lsbs[i] = readI16(data, p + 2)
    p += 4
  for i in t.numHMetrics.int ..< t.numGlyphs.int:
    t.advanceWidths[i] = lastAdv
    t.lsbs[i] = readI16(data, p)
    p += 2

proc parseLoca(data: openArray[byte], off: int, t: var Tables) =
  setLen(t.loca, t.numGlyphs.int + 1)
  var p = off
  case t.indexToLocFormat
  of 0:
    for i in 0 ..< t.loca.len:
      t.loca[i] = uint32(readU16(data, p)) * 2'u32
      p += 2
  of 1:
    for i in 0 ..< t.loca.len:
      t.loca[i] = readU32(data, p)
      p += 4
  else:
    raise newException(FontError,
      "invalid indexToLocFormat: " & $t.indexToLocFormat)

proc parseCmap4(data: openArray[byte], sub, tableEnd: int, t: var Tables) =
  if sub + 4 > tableEnd:
    raise newException(FontError, "truncated cmap format 4 header")
  let fmt = readU16(data, sub)
  if fmt != 4:
    raise newException(FontError, "expected cmap format 4, got " & $fmt)
  let length = int(readU16(data, sub + 2))
  if length < 16: raise newException(FontError, "invalid cmap format 4 length")
  if sub + length > tableEnd:
    raise newException(FontError, "cmap format 4 exceeds cmap table")
  check(data, sub, length)
  let segCountX2 = readU16(data, sub + 6)
  if segCountX2 == 0 or (segCountX2 and 1'u16) != 0:
    raise newException(FontError, "invalid cmap format 4 segment count")
  let segCount = segCountX2.int div 2
  var c: Cmap4
  c.segCount = segCount
  setLen(c.endCode, segCount)
  setLen(c.startCode, segCount)
  setLen(c.idDelta, segCount)
  setLen(c.idRangeOffset, segCount)
  setLen(c.idRangeOffsetPos, segCount)
  # Layout: endCode[segCount], reservedPad, startCode[segCount],
  # idDelta[segCount], idRangeOffset[segCount], glyphIdArray[].
  let endCodePos = sub + 14
  let startCodePos = endCodePos + segCount * 2 + 2
  let idDeltaPos = startCodePos + segCount * 2
  let idRangeOffsetPos = idDeltaPos + segCount * 2
  let glyphIdArrayPos = idRangeOffsetPos + segCount * 2
  if glyphIdArrayPos > sub + length:
    raise newException(FontError, "truncated cmap format 4 arrays")
  for i in 0 ..< segCount:
    c.endCode[i] = readU16(data, endCodePos + i * 2)
    c.startCode[i] = readU16(data, startCodePos + i * 2)
    c.idDelta[i] = readI16(data, idDeltaPos + i * 2)
    c.idRangeOffset[i] = readU16(data, idRangeOffsetPos + i * 2)
    c.idRangeOffsetPos[i] = idRangeOffsetPos + i * 2
    if c.startCode[i] > c.endCode[i]:
      raise newException(FontError, "invalid cmap format 4 segment")
    if i > 0 and c.endCode[i] < c.endCode[i - 1]:
      raise newException(FontError, "unsorted cmap format 4 segments")
    if i > 0 and c.startCode[i] <= c.endCode[i - 1]:
      raise newException(FontError, "overlapping cmap format 4 segments")
  c.glyphIdArrayPos = glyphIdArrayPos
  c.subtableEnd = sub + length
  t.cmap4 = c
  t.hasCmap4 = true

proc parseCmap(data: openArray[byte], off, length: int, t: var Tables) =
  if length < 4:
    raise newException(FontError, "truncated cmap table")
  let tableEnd = off + length
  let version = readU16(data, off)
  if version != 0:
    raise newException(FontError, "unsupported cmap version: " & $version)
  let numSubtables = readU16(data, off + 2)
  if 4 + int(numSubtables) * 8 > length:
    raise newException(FontError, "truncated cmap encoding records")
  var best4 = -1
  var best12 = -1
  for i in 0 ..< numSubtables.int:
    let rec = off + 4 + i * 8
    let plat = readU16(data, rec)
    let enc = readU16(data, rec + 2)
    let subOff = readU32(data, rec + 4)
    let subStart = off + subOff.int
    if subStart < off or subStart + 2 > tableEnd:
      raise newException(FontError, "cmap subtable outside cmap table")
    let fmt = readU16(data, subStart)
    if fmt == 12 and (plat == 0 or (plat == 3 and enc == 10)):
      if best12 < 0 or (plat == 3 and enc == 10): best12 = subStart
    elif fmt == 4 and (plat == 0 or (plat == 3 and enc == 1)):
      if best4 < 0 or (plat == 3 and enc == 1): best4 = subStart
  if best4 >= 0: parseCmap4(data, best4, tableEnd, t)
  if best12 >= 0: parseCmap12(data, best12, tableEnd, t)

proc parseKern(data: openArray[byte], off, length: int, t: var Tables) =
  ## Parse horizontal format-0 pairs from the OpenType `kern` table.
  check(data, off, length)
  if length < 4 or readU16(data, off) != 0'u16: return
  let count = int(readU16(data, off + 2))
  var p = off + 4
  for _ in 0 ..< count:
    if p + 6 > off + length:
      raise newException(FontError, "truncated kern subtable header")
    check(data, p, 6)
    let subLength = int(readU16(data, p + 2))
    if subLength < 6: raise newException(FontError, "invalid kern subtable")
    if p + subLength > off + length:
      raise newException(FontError, "kern subtable exceeds kern table")
    check(data, p, subLength)
    let coverage = readU16(data, p + 4)
    let format = coverage shr 8
    let horizontal = (coverage and 1'u16) != 0
    let minimum = (coverage and 2'u16) != 0
    let crossStream = (coverage and 4'u16) != 0
    if format == 0 and horizontal and not minimum and not crossStream:
      if subLength < 14:
        raise newException(FontError, "truncated kern format-0 header")
      let pairCount = int(readU16(data, p + 6))
      if 14 + pairCount * 6 > subLength:
        raise newException(FontError, "truncated kern pairs")
      for i in 0 ..< pairCount:
        let q = p + 14 + i * 6
        t.kernPairs.add KerningPair(left: readU16(data, q),
          right: readU16(data, q + 2), value: readI16(data, q + 4),
          order: t.kernPairs.len, overrides: (coverage and 8'u16) != 0)
    p += subLength

proc parseSimpleGlyph(data: openArray[byte], base: int): GlyphOutline =
  let numContours = readI16(data, base).int
  if numContours <= 0:
    return newSeq[Contour](0)
  let ptsBase = base + 10 # skip numberOfContours + bbox (4 x int16)
  var endPts = newSeq[uint16](numContours)
  var p = ptsBase
  for i in 0 ..< numContours:
    endPts[i] = readU16(data, p); p += 2
    if i > 0 and endPts[i] <= endPts[i - 1]:
      raise newException(FontError, "invalid glyph contour endpoints")
  let numPoints = int(endPts[^1]) + 1
  let instrLen = readU16(data, p); p += 2
  check(data, p, int(instrLen))
  p += int(instrLen) # skip hinting instructions
  # Flags, expanding the repeat shorthand into the expanded array.
  var flags = newSeq[uint8](numPoints)
  var fi = 0
  while fi < numPoints:
    let f = readU8(data, p); p += 1
    flags[fi] = f; inc fi
    if (f and FlagRepeat) != 0:
      let rep = int(readU8(data, p)); p += 1
      if fi + rep > numPoints:
        raise newException(FontError, "glyph flag repeat exceeds point count")
      for _ in 0 ..< rep:
        if fi < numPoints: flags[fi] = f
        inc fi
  # X coordinates: short-positive / short-negative / long-delta / same.
  var xs = newSeq[float32](numPoints)
  var xv: int32 = 0
  for i in 0 ..< numPoints:
    let f = flags[i]
    if (f and FlagXShort) != 0:
      let d = int32(readU8(data, p)); p += 1
      xv += (if (f and FlagXSameOrPos) != 0: d else: -d)
    elif (f and FlagXSameOrPos) == 0:
      xv += int32(readI16(data, p)); p += 2
    xs[i] = float32(xv)
  # Y coordinates follow the same rule with the y flag bits.
  var ys = newSeq[float32](numPoints)
  var yv: int32 = 0
  for i in 0 ..< numPoints:
    let f = flags[i]
    if (f and FlagYShort) != 0:
      let d = int32(readU8(data, p)); p += 1
      yv += (if (f and FlagYSameOrPos) != 0: d else: -d)
    elif (f and FlagYSameOrPos) == 0:
      yv += int32(readI16(data, p)); p += 2
    ys[i] = float32(yv)
  # Split the flat point list into contours by the endPtsOfContours ranges.
  result = newSeq[Contour](numContours)
  var start = 0
  for c in 0 ..< numContours:
    let lastIdx = int(endPts[c])
    for i in start .. lastIdx:
      result[c].add GlyphPoint(
        x: xs[i], y: ys[i], onCurve: (flags[i] and FlagOnCurve) != 0)
    start = lastIdx + 1

proc readGlyphOutlineAt(t: Tables, gid: uint16, depth: int,
    visited: var set[uint16]): GlyphOutline

proc parseCompositeGlyph(data: openArray[byte], base: int, t: Tables,
    depth: int, visited: var set[uint16]): GlyphOutline =
  if depth > MaxCompositeDepth:
    raise newException(FontError, "composite glyph recursion too deep")
  result = newSeq[Contour](0)
  var p = base + 10 # skip numberOfContours (int16) + bbox (4 x int16)
  var components = 0
  while true:
    inc components
    if components > MaxComponents:
      raise newException(FontError, "too many composite components")
    let flags = readU16(data, p); p += 2
    let glyphIndex = readU16(data, p); p += 2
    if glyphIndex >= t.numGlyphs:
      raise newException(FontError, "composite glyph index out of range")
    # Arguments are either x/y offsets or parent/component point indices.
    var arg1, arg2: int
    if (flags and ArgWords) != 0:
      if (flags and ArgXY) != 0:
        arg1 = int(readI16(data, p)); arg2 = int(readI16(data, p + 2))
      else:
        arg1 = int(readU16(data, p)); arg2 = int(readU16(data, p + 2))
      p += 4
    else:
      if (flags and ArgXY) != 0:
        arg1 = int(readI8(data, p)); arg2 = int(readI8(data, p + 1))
      else:
        arg1 = int(readU8(data, p)); arg2 = int(readU8(data, p + 1))
      p += 2
    # Affine: identity by default; scale, x/y scale, or full 2x2.
    var m00, m11: float32 = 1.0'f32
    var m01, m10: float32 = 0.0'f32
    if (flags and HaveScale) != 0:
      m00 = readF2Dot14(data, p); m11 = m00; p += 2
    elif (flags and HaveXYScale) != 0:
      m00 = readF2Dot14(data, p); p += 2
      m11 = readF2Dot14(data, p); p += 2
    elif (flags and Have2x2) != 0:
      m00 = readF2Dot14(data, p); p += 2
      m01 = readF2Dot14(data, p); p += 2
      m10 = readF2Dot14(data, p); p += 2
      m11 = readF2Dot14(data, p); p += 2
    # Recurse into the referenced glyph, guarding against cycles.
    if glyphIndex in visited:
      raise newException(FontError, "composite glyph cycle")
    visited.incl glyphIndex
    let sub = readGlyphOutlineAt(t, glyphIndex, depth + 1, visited)
    visited.excl glyphIndex
    var dx, dy: float32
    if (flags and ArgXY) != 0:
      dx = float32(arg1)
      dy = float32(arg2)
      if (flags and ScaledOffset) != 0 and (flags and UnscaledOffset) != 0:
        raise newException(FontError, "conflicting composite offset flags")
      if (flags and ScaledOffset) != 0:
        let rawX = dx
        let rawY = dy
        dx = m00 * rawX + m01 * rawY
        dy = m10 * rawX + m11 * rawY
    else:
      var parentPoints, componentPoints: seq[GlyphPoint]
      for contour in result:
        for point in contour: parentPoints.add point
      for contour in sub:
        for point in contour:
          componentPoints.add GlyphPoint(
            x: m00 * point.x + m01 * point.y,
            y: m10 * point.x + m11 * point.y,
            onCurve: point.onCurve)
      if arg1 >= parentPoints.len or arg2 >= componentPoints.len:
        raise newException(FontError, "composite point index out of range")
      dx = parentPoints[arg1].x - componentPoints[arg2].x
      dy = parentPoints[arg1].y - componentPoints[arg2].y
    for contour in sub:
      var tc: Contour = @[]
      for pt in contour:
        tc.add GlyphPoint(
          x: m00 * pt.x + m01 * pt.y + dx,
          y: m10 * pt.x + m11 * pt.y + dy,
          onCurve: pt.onCurve)
      result.add tc
    if (flags and MoreComponents) == 0:
      break

proc readGlyphOutlineAt(t: Tables, gid: uint16, depth: int,
    visited: var set[uint16]): GlyphOutline =
  if gid >= t.numGlyphs: return newSeq[Contour](0)
  let start = t.loca[gid]
  let ends = t.loca[gid + 1]
  if ends <= start: return newSeq[Contour](0) # empty glyph
  let base = int(t.glyfOffset) + int(start)
  let limit = int(t.glyfOffset) + int(ends)
  if limit - base < 10:
    raise newException(FontError, "truncated glyph header")
  let numContours = readI16(t.bytes, base)
  if numContours >= 0:
    result = parseSimpleGlyph(t.bytes.toOpenArray(base, limit - 1), 0)
  else:
    result = parseCompositeGlyph(t.bytes.toOpenArray(base, limit - 1), 0, t,
      depth, visited)

proc parseTables*(data: seq[byte]): Tables =
  ## Parse the TrueType tables of `data`. Raises `FontError` on a malformed or
  ## unsupported file.
  result.bytes = newSeq[byte](data.len)
  if data.len > 0:
    copyMem(result.bytes[0].addr, data[0].unsafeAddr, data.len)
  if data.len < 12:
    raise newException(FontError, "file too small for offset table")
  let sfnt = readU32(data, 0)
  # TrueType flavor is 0x00010000 (or the 'true' alias). CFF ('OTTO') is not
  # supported in 1.0.
  if sfnt != 0x00010000'u32 and sfnt != 0x74727565'u32:
    raise newException(FontError, "unsupported sfnt version: " & toHex(sfnt))
  let numTables = readU16(data, 4)
  if numTables == 0 or numTables > 4096:
    raise newException(FontError, "invalid table count")
  if data.len < 12 + numTables.int * 16:
    raise newException(FontError, "truncated table directory")
  var entries: seq[TableEntry] = @[]
  for i in 0 ..< numTables.int:
    let base = 12 + i.int * 16
    let entry: TableEntry = (tag: readTag(data, base),
      offset: readU32(data, base + 8), length: readU32(data, base + 12))
    if uint64(entry.offset) + uint64(entry.length) > uint64(data.len):
      raise newException(FontError, "table outside font: " & entry.tag)
    entries.add(entry)
  let head = findTable(entries, "head")
  head.requireLength(54)
  result.unitsPerEm = readU16(data, head.offset.int + 18)
  if result.unitsPerEm < 16 or result.unitsPerEm > 16384:
    raise newException(FontError, "invalid unitsPerEm")
  result.indexToLocFormat = readI16(data, head.offset.int + 50)
  let hhea = findTable(entries, "hhea")
  hhea.requireLength(36)
  result.ascent = readI16(data, hhea.offset.int + 4)
  result.descent = readI16(data, hhea.offset.int + 6)
  result.lineGap = readI16(data, hhea.offset.int + 8)
  result.numHMetrics = readU16(data, hhea.offset.int + 34)
  let maxp = findTable(entries, "maxp")
  maxp.requireLength(6)
  result.numGlyphs = readU16(data, maxp.offset.int + 4)
  if result.numGlyphs == 0:
    raise newException(FontError, "font has no glyphs")
  if result.numHMetrics == 0 or result.numHMetrics > result.numGlyphs:
    raise newException(FontError, "invalid numberOfHMetrics")
  let hmtx = findTable(entries, "hmtx")
  let requiredHmtx = uint32(result.numHMetrics) * 4'u32 +
    uint32(result.numGlyphs - result.numHMetrics) * 2'u32
  hmtx.requireLength(requiredHmtx)
  parseHmtx(data, hmtx.offset.int, result)
  let loca = findTable(entries, "loca")
  let locaStride = if result.indexToLocFormat == 0: 2'u32 else: 4'u32
  loca.requireLength((uint32(result.numGlyphs) + 1'u32) * locaStride)
  parseLoca(data, loca.offset.int, result)
  let glyf = findTable(entries, "glyf")
  result.glyfOffset = glyf.offset
  result.glyfLength = glyf.length
  for i in 0 ..< result.loca.len:
    if result.loca[i] > result.glyfLength or
        (i > 0 and result.loca[i] < result.loca[i - 1]):
      raise newException(FontError, "invalid loca offset")
  let cmap = findTable(entries, "cmap")
  parseCmap(data, cmap.offset.int, cmap.length.int, result)
  if not result.hasCmap4 and result.cmap12.len == 0:
    raise newException(FontError, "no supported Unicode cmap")
  var kern: TableEntry
  if optionalTable(entries, "kern", kern):
    parseKern(data, kern.offset.int, kern.length.int, result)
    result.kernPairs.sort(proc(a, b: KerningPair): int =
      if a.left != b.left: cmp(a.left, b.left)
      elif a.right != b.right: cmp(a.right, b.right)
      else: cmp(a.order, b.order))
    var merged: seq[KerningPair]
    for pair in result.kernPairs:
      if merged.len == 0 or merged[^1].left != pair.left or
          merged[^1].right != pair.right:
        merged.add pair
      else:
        let value = if pair.overrides: int32(pair.value)
          else: int32(merged[^1].value) + int32(pair.value)
        merged[^1].value = int16(max(int32(low(int16)),
          min(int32(high(int16)), value)))
    result.kernPairs = merged

proc cmapLookup*(t: Tables, cp: int): GlyphId =
  ## Resolve a Unicode codepoint to a glyph id (0 = `.notdef` / missing).
  if cp < 0 or cp > 0x10FFFF:
    return 0'u32
  if t.cmap12.len > 0:
    var lo = 0
    var hi = t.cmap12.len
    while lo < hi:
      let mid = (lo + hi) div 2
      let group = t.cmap12[mid]
      if uint32(cp) < group.startCode: hi = mid
      elif uint32(cp) > group.endCode: lo = mid + 1
      else:
        let glyph = group.startGlyph + uint32(cp) - group.startCode
        return if glyph < uint32(t.numGlyphs): GlyphId(glyph) else: 0'u32
  if cp > 0xFFFF or not t.hasCmap4:
    return 0'u32
  let c = t.cmap4
  for i in 0 ..< c.segCount:
    if int(c.endCode[i]) >= cp:
      if int(c.startCode[i]) > cp:
        return 0'u32
      if c.idRangeOffset[i] == 0:
        let glyph = (uint32(cp) + uint32(c.idDelta[i])) and 0xFFFF'u32
        return if glyph < uint32(t.numGlyphs): GlyphId(glyph) else: 0'u32
      let glyphAddr = c.idRangeOffsetPos[i] + int(c.idRangeOffset[i]) +
        2 * (cp - int(c.startCode[i]))
      if glyphAddr < c.glyphIdArrayPos or glyphAddr + 2 > c.subtableEnd:
        raise newException(FontError, "cmap format 4 glyph index out of bounds")
      let g = readU16(t.bytes, glyphAddr)
      if g == 0:
        return 0'u32
      let glyph = (uint32(g) + uint32(c.idDelta[i])) and 0xFFFF'u32
      return if glyph < uint32(t.numGlyphs): GlyphId(glyph) else: 0'u32
  0'u32

proc glyphOutline*(t: Tables, gid: GlyphId): GlyphOutline =
  ## Return the outline contours of glyph `gid`. Empty for missing/empty
  ## glyphs. Composite glyphs are resolved recursively with a depth and cycle
  ## guard.
  if gid >= t.numGlyphs.uint32: return newSeq[Contour](0)
  let gid16 = uint16(min(gid, uint32(t.numGlyphs)))
  var visited: set[uint16] = {gid16}
  result = readGlyphOutlineAt(t, gid16, 0, visited)

proc advanceWidth*(t: Tables, gid: GlyphId): uint16 =
  if gid < t.numGlyphs.uint32: t.advanceWidths[int(gid)] else: 0'u16

proc leftSideBearing*(t: Tables, gid: GlyphId): int32 =
  if gid < t.numGlyphs.uint32: int32(t.lsbs[int(gid)]) else: 0'i32

proc kerning*(t: Tables, left, right: GlyphId): int16 =
  ## Legacy horizontal pair adjustment in design units.
  if left > high(uint16).uint32 or right > high(uint16).uint32: return 0
  let l = uint16(left)
  let r = uint16(right)
  var lo = 0
  var hi = t.kernPairs.len
  while lo < hi:
    let mid = (lo + hi) div 2
    let pair = t.kernPairs[mid]
    if pair.left < l or (pair.left == l and pair.right < r): lo = mid + 1
    elif pair.left > l or (pair.left == l and pair.right > r): hi = mid
    else: return pair.value
  0

proc glyphBounds*(t: Tables, gid: GlyphId): TextBounds =
  ## Exact header bounds in design units, before scaling.
  if gid >= t.numGlyphs.uint32: return
  let start = t.loca[int(gid)]
  let ends = t.loca[int(gid) + 1]
  if ends <= start: return
  if ends - start < 10:
    raise newException(FontError, "truncated glyph header")
  let p = int(t.glyfOffset + start)
  result = TextBounds(xMin: float32(readI16(t.bytes, p + 2)),
    yMin: float32(readI16(t.bytes, p + 4)),
    xMax: float32(readI16(t.bytes, p + 6)),
    yMax: float32(readI16(t.bytes, p + 8)))
  if result.xMin > result.xMax or result.yMin > result.yMax:
    raise newException(FontError, "invalid glyph bounds")
