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

  test "codepoint above BMP resolves to .notdef":
    let t = parseTables(loadBytes())
    check cmapLookup(t, 0x1F600) == 0'u32

  test "glyphOutline of a real glyph has at least one contour":
    let t = parseTables(loadBytes())
    let gid = cmapLookup(t, ord('A'))
    let outline = glyphOutline(t, gid)
    check outline.len > 0
    check outline[0].len > 0

  test "truncated bytes raise FontError":
    expect FontError:
      discard parseTables(@[byte 0, 1, 2])

  test "CFF (OTTO) sfnt version is unsupported":
    var buf: seq[byte] = newSeq[byte](64)
    buf[0] = 'O'.uint8; buf[1] = 'T'.uint8
    buf[2] = 'T'.uint8; buf[3] = 'O'.uint8
    expect FontError:
      discard parseTables(buf)
