# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
import std/[os, unittest]
import UniGlyph
import UniGlyph/tables

const FontPath = currentSourcePath.parentDir / "assets/DejaVuSans.ttf"

proc loadBytes(): seq[byte] =
  let s = readFile(FontPath)
  result = newSeq[byte](s.len)
  if s.len > 0:
    copyMem(result[0].addr, s[0].unsafeAddr, s.len)

proc readU16(data: openArray[byte], offset: int): uint16 =
  (uint16(data[offset]) shl 8) or uint16(data[offset + 1])

proc readU32(data: openArray[byte], offset: int): uint32 =
  (uint32(data[offset]) shl 24) or (uint32(data[offset + 1]) shl 16) or
    (uint32(data[offset + 2]) shl 8) or uint32(data[offset + 3])

proc putU16(data: var seq[byte], offset: int, value: uint16) =
  data[offset] = byte(value shr 8)
  data[offset + 1] = byte(value and 0xFF)

proc putU32(data: var seq[byte], offset: int, value: uint32) =
  data[offset] = byte((value shr 24) and 0xFF)
  data[offset + 1] = byte((value shr 16) and 0xFF)
  data[offset + 2] = byte((value shr 8) and 0xFF)
  data[offset + 3] = byte(value and 0xFF)

proc tableOffset(data: openArray[byte], wanted: string): int =
  for i in 0 ..< int(readU16(data, 4)):
    let p = 12 + i * 16
    var tag = ""
    for j in 0 ..< 4: tag.add char(data[p + j])
    if tag == wanted: return int(readU32(data, p + 8))
  raise newException(ValueError, "missing test table")

proc tableRecord(data: openArray[byte], wanted: string): int =
  for i in 0 ..< int(readU16(data, 4)):
    let p = 12 + i * 16
    var tag = ""
    for j in 0 ..< 4: tag.add char(data[p + j])
    if tag == wanted: return p
  raise newException(ValueError, "missing test table")

proc withSyntheticCmap12(): seq[byte] =
  ## Reuse the licensed fixture's valid tables and place a format-12 subtable
  ## in unused cmap storage so the parser path has a deterministic fixture.
  result = loadBytes()
  let cmap = tableOffset(result, "cmap")
  let relative = 2500
  result.putU16(cmap + 6, 4) # platform-0 encoding id
  result.putU32(cmap + 8, uint32(relative))
  let p = cmap + relative
  result.putU16(p, 12)
  result.putU16(p + 2, 0)
  result.putU32(p + 4, 28)
  result.putU32(p + 8, 0)
  result.putU32(p + 12, 1)
  result.putU32(p + 16, 0x10300)
  result.putU32(p + 20, 0x10300)
  result.putU32(p + 24, 36)

proc withSyntheticBmpCmap12(): seq[byte] =
  result = withSyntheticCmap12()
  let p = tableOffset(result, "cmap") + 2500
  result.putU32(p + 16, uint32(ord('A')))
  result.putU32(p + 20, uint32(ord('A')))

suite "tables":
  test "DejaVuSans parses and exposes expected head/hhea/maxp fields":
    let t = parseTables(loadBytes())
    check t.unitsPerEm == 2048
    check t.ascent > 0
    check t.descent < 0
    check t.numGlyphs > 100
    check t.hasCmap4

  test "hmtx + loca arrays are numGlyphs-wide":
    let t = parseTables(loadBytes())
    check t.advanceWidths.len == t.numGlyphs.int
    check t.lsbs.len == t.numGlyphs.int
    check t.loca.len == t.numGlyphs.int + 1

  test "cmap format 4 resolves ASCII to distinct non-zero glyph ids":
    let t = parseTables(loadBytes())
    let a = cmapLookup(t, ord('A'))
    let b = cmapLookup(t, ord('B'))
    check a != 0
    check b != 0
    check a != b

  test "font without cmap12 resolves codepoint above BMP to .notdef":
    let t = parseTables(loadBytes())
    check t.cmap12.len == 0
    check cmapLookup(t, 0x10300) == 0'u32

  test "cmap format 12 resolves a supplementary-plane scalar":
    let t = parseTables(withSyntheticCmap12())
    check t.cmap12.len == 1
    check cmapLookup(t, 0x10300) == 36'u32

  test "cmap format 12 takes priority for its BMP mappings":
    let t = parseTables(withSyntheticBmpCmap12())
    check cmapLookup(t, ord('A')) == 36'u32

  test "glyphOutline of a real glyph has at least one contour":
    let t = parseTables(loadBytes())
    let gid = cmapLookup(t, ord('A'))
    let outline = glyphOutline(t, gid)
    check outline.len > 0
    check outline[0].len > 0

  test "legacy kern exposes the AV adjustment":
    let t = parseTables(loadBytes())
    let a = cmapLookup(t, ord('A'))
    let v = cmapLookup(t, ord('V'))
    check kerning(t, a, v) < 0

  test "truncated bytes raise FontError":
    expect FontError:
      discard parseTables(@[byte 0, 1, 2])

  test "table directory cannot point outside the font":
    var data = loadBytes()
    data.putU32(20, high(uint32))
    expect FontError:
      discard parseTables(data)

  test "cmap subtables cannot escape their table":
    var data = loadBytes()
    data.putU32(tableRecord(data, "cmap") + 12, 4)
    expect FontError:
      discard parseTables(data)

  test "CFF (OTTO) sfnt version is unsupported":
    var buf: seq[byte] = newSeq[byte](64)
    buf[0] = 'O'.uint8; buf[1] = 'T'.uint8
    buf[2] = 'T'.uint8; buf[3] = 'O'.uint8
    expect FontError:
      discard parseTables(buf)
