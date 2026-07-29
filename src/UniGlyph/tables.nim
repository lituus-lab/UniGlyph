# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
## UniGlyph/tables — read-only OpenType/TrueType table parsers.
##
## Spec-driven against the OpenType/TrueType specification (ISO/IEC 14496-22
## and the Microsoft OpenType spec). This is an original, read-only parser: it
## never mutates font data and supports only the TrueType outline flavor
## (`glyf`), not CFF/OTF charstrings. No hinting, no GPOS/GSUB, no `kern` —
## only what is needed to resolve a codepoint to a glyph outline and its
## advance width. Every read is bounds-checked; a malformed file raises
## `FontError`, which the C ABI traps and maps to `UGLY_ERR_FORMAT`.
import std/strutils

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

proc parseCmap4(data: openArray[byte], sub: int, t: var Tables) =
  let fmt = readU16(data, sub)
  if fmt != 4:
    raise newException(FontError, "expected cmap format 4, got " & $fmt)
  let segCountX2 = readU16(data, sub + 6)
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
  for i in 0 ..< segCount:
    c.endCode[i] = readU16(data, endCodePos + i * 2)
    c.startCode[i] = readU16(data, startCodePos + i * 2)
    c.idDelta[i] = readI16(data, idDeltaPos + i * 2)
    c.idRangeOffset[i] = readU16(data, idRangeOffsetPos + i * 2)
    c.idRangeOffsetPos[i] = idRangeOffsetPos + i * 2
  c.glyphIdArrayPos = glyphIdArrayPos
  t.cmap4 = c
  t.hasCmap4 = true

proc parseCmap(data: openArray[byte], off: int, t: var Tables) =
  let version = readU16(data, off)
  if version != 0:
    raise newException(FontError, "unsupported cmap version: " & $version)
  let numSubtables = readU16(data, off + 2)
  var best = -1
  for i in 0 ..< numSubtables.int:
    let rec = off + 4 + i * 8
    let plat = readU16(data, rec)
    let enc = readU16(data, rec + 2)
    let subOff = readU32(data, rec + 4)
    let subStart = off + subOff.int
    let fmt = readU16(data, subStart)
    if fmt != 4: continue
    # Prefer the Windows BMP subtable (platform 3, encoding 1); otherwise the
    # first Unicode BMP subtable (platform 0).
    if plat == 3 and enc == 1:
      best = subStart
      break
    if plat == 0 and best < 0:
      best = subStart
  if best < 0:
    t.hasCmap4 = false # no BMP subtable; all lookups resolve to .notdef
    return
  parseCmap4(data, best, t)

proc parseSimpleGlyph(data: openArray[byte], base: int): GlyphOutline =
  let numContours = readI16(data, base).int
  if numContours <= 0:
    return newSeq[Contour](0)
  let ptsBase = base + 10 # skip numberOfContours + bbox (4 x int16)
  var endPts = newSeq[uint16](numContours)
  var p = ptsBase
  for i in 0 ..< numContours:
    endPts[i] = readU16(data, p); p += 2
  let numPoints = int(endPts[^1]) + 1
  let instrLen = readU16(data, p); p += 2
  p += int(instrLen) # skip hinting instructions
  # Flags, expanding the repeat shorthand into the expanded array.
  var flags = newSeq[uint8](numPoints)
  var fi = 0
  while fi < numPoints:
    let f = readU8(data, p); p += 1
    flags[fi] = f; inc fi
    if (f and FlagRepeat) != 0:
      let rep = int(readU8(data, p)); p += 1
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
    # Component offsets: two int16 (words) or two int8 (bytes).
    var dx, dy: float32 = 0.0'f32
    if (flags and ArgWords) != 0:
      dx = float32(readI16(data, p)); p += 2
      dy = float32(readI16(data, p)); p += 2
    else:
      dx = float32(readI8(data, p)); p += 1
      dy = float32(readI8(data, p)); p += 1
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
  let numContours = readI16(t.bytes, base)
  if numContours >= 0:
    result = parseSimpleGlyph(t.bytes, base)
  else:
    result = parseCompositeGlyph(t.bytes, base, t, depth, visited)

proc parseTables*(data: seq[byte]): Tables =
  ## Parse the TrueType tables of `data`. Raises `FontError` on a malformed or
  ## unsupported file.
  result.bytes = data
  if data.len < 12:
    raise newException(FontError, "file too small for offset table")
  let sfnt = readU32(data, 0)
  # TrueType flavor is 0x00010000 (or the 'true' alias). CFF ('OTTO') is not
  # supported in 1a.
  if sfnt != 0x00010000'u32 and sfnt != 0x74727565'u32:
    raise newException(FontError, "unsupported sfnt version: " & toHex(sfnt))
  let numTables = readU16(data, 4)
  if data.len < 12 + numTables.int * 16:
    raise newException(FontError, "truncated table directory")
  var entries: seq[TableEntry] = @[]
  for i in 0 ..< numTables.int:
    let base = 12 + i.int * 16
    entries.add((readTag(data, base), readU32(data, base + 8),
      readU32(data, base + 12)))
  let head = findTable(entries, "head")
  result.unitsPerEm = readU16(data, head.offset.int + 18)
  result.indexToLocFormat = readI16(data, head.offset.int + 50)
  let hhea = findTable(entries, "hhea")
  result.ascent = readI16(data, hhea.offset.int + 4)
  result.descent = readI16(data, hhea.offset.int + 6)
  result.lineGap = readI16(data, hhea.offset.int + 8)
  result.numHMetrics = readU16(data, hhea.offset.int + 34)
  let maxp = findTable(entries, "maxp")
  result.numGlyphs = readU16(data, maxp.offset.int + 4)
  parseHmtx(data, findTable(entries, "hmtx").offset.int, result)
  parseLoca(data, findTable(entries, "loca").offset.int, result)
  let glyf = findTable(entries, "glyf")
  result.glyfOffset = glyf.offset
  result.glyfLength = glyf.length
  parseCmap(data, findTable(entries, "cmap").offset.int, result)

proc cmapLookup*(t: Tables, cp: int): GlyphId =
  ## Resolve a Unicode codepoint to a glyph id (0 = `.notdef` / missing).
  if not t.hasCmap4 or cp < 0 or cp > 0xFFFF:
    return 0'u32
  let c = t.cmap4
  for i in 0 ..< c.segCount:
    if int(c.endCode[i]) >= cp:
      if int(c.startCode[i]) > cp:
        return 0'u32
      if c.idRangeOffset[i] == 0:
        return GlyphId((uint32(cp) + uint32(c.idDelta[i])) and 0xFFFF'u32)
      let glyphAddr = c.idRangeOffsetPos[i] + int(c.idRangeOffset[i]) +
        2 * (cp - int(c.startCode[i]))
      let g = readU16(t.bytes, glyphAddr)
      if g == 0:
        return 0'u32
      return GlyphId((uint32(g) + uint32(c.idDelta[i])) and 0xFFFF'u32)
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


