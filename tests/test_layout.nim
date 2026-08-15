# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
import std/[os, unittest]
import UniGlyph
import UniVector

const FontPath = currentSourcePath.parentDir / "assets/DejaVuSans.ttf"

proc readU16(data: openArray[byte], offset: int): uint16 =
  (uint16(data[offset]) shl 8) or uint16(data[offset + 1])

proc readU32(data: openArray[byte], offset: int): uint32 =
  (uint32(data[offset]) shl 24) or (uint32(data[offset + 1]) shl 16) or
    (uint32(data[offset + 2]) shl 8) or uint32(data[offset + 3])

proc putU16(data: var seq[byte], offset: int, value: uint16) =
  data[offset] = byte(value shr 8)
  data[offset + 1] = byte(value and 0xFF)

proc bytesWithoutA(): seq[byte] =
  let raw = readFile(FontPath)
  result = newSeq[byte](raw.len)
  copyMem(result[0].addr, raw[0].unsafeAddr, raw.len)
  var cmap = -1
  for i in 0 ..< int(result.readU16(4)):
    let p = 12 + i * 16
    if raw[p .. p + 3] == "cmap": cmap = int(result.readU32(p + 8))
  var sub = -1
  for i in 0 ..< int(result.readU16(cmap + 2)):
    let p = cmap + 4 + i * 8
    if result.readU16(p) == 3 and result.readU16(p + 2) == 1:
      sub = cmap + int(result.readU32(p + 4))
  let segCount = int(result.readU16(sub + 6)) div 2
  let ends = sub + 14
  let starts = ends + segCount * 2 + 2
  let deltas = starts + segCount * 2
  let ranges = deltas + segCount * 2
  for i in 0 ..< segCount:
    if result.readU16(starts + i * 2) <= uint16(ord('A')) and
        result.readU16(ends + i * 2) >= uint16(ord('A')):
      let ro = result.readU16(ranges + i * 2)
      if ro == 0:
        result.putU16(deltas + i * 2, uint16(0x10000 - ord('A')))
      else:
        let glyphPos = ranges + i * 2 + int(ro) +
          2 * (ord('A') - int(result.readU16(starts + i * 2)))
        result.putU16(glyphPos, 0)
      break

suite "layout":
  test "typeset lays out one slot per rune":
    let f = loadTtf(FontPath)
    let ts = typeset(f, "Hello", 48.0'f32, vec2(0.0'f32, 60.0'f32))
    check ts.slots.len == 5
    check ts.advance > 0.0'f32

  test "textWidth matches the typeset advance":
    let f = loadTtf(FontPath)
    let w = textWidth(f, "Hello", 48.0'f32)
    let ts = typeset(f, "Hello", 48.0'f32, vec2(0.0'f32, 60.0'f32))
    check abs(w - ts.advance) < 1e-3'f32

  test "combinedPath is non-empty":
    let f = loadTtf(FontPath)
    let ts = typeset(f, "Hello", 48.0'f32, vec2(0.0'f32, 60.0'f32))
    let p = ts.combinedPath()
    check p.commands.len > 0

  test "advance scales with size":
    let f = loadTtf(FontPath)
    let small = typeset(f, "Hello", 16.0'f32, vec2(0.0'f32, 60.0'f32)).advance
    let big = typeset(f, "Hello", 64.0'f32, vec2(0.0'f32, 60.0'f32)).advance
    check big > small

  test "shape applies pair kerning":
    let f = loadTtf(FontPath)
    let style = textStyle(f, 2048'f32)
    let run = shape(style, "AV")
    let raw = float32(f.advanceWidth(f.glyphId(ord('A'))) +
      f.advanceWidth(f.glyphId(ord('V'))))
    check run.advance < raw

  test "layout preserves explicit lines and typographic metrics":
    let f = loadTtf(FontPath)
    let layout = layoutText(textStyle(f, 32'f32), "first\nsecond")
    check layout.lines.len == 2
    check layout.height > f.lineHeight(32'f32)
    check layout.typographicBounds.height > 0
    let leadingEmpty = layoutText(textStyle(f, 32'f32), "\nA")
    check leadingEmpty.typographicBounds.yMin == 0'f32
    check leadingEmpty.typographicBounds.height > f.lineHeight(32'f32)

  test "wrapping splits a word that exceeds the width":
    let f = loadTtf(FontPath)
    let layout = layoutText(textStyle(f, 20'f32), "abcdefghij", 30'f32)
    check layout.lines.len > 1
    for line in layout.lines:
      check line.advance <= 30'f32

  test "fallback records the selected face":
    let missingA = loadTtfFromBytes(bytesWithoutA())
    let fallback = loadTtf(FontPath)
    let style = TextStyle(family: fontFamily(missingA, fallback), size: 20'f32)
    let run = shape(style, "A")
    check run.placements.len == 1
    check run.placements[0].faceIndex == 1

  test "nominal corpus covers Latin Greek Cyrillic and Hebrew":
    let f = loadTtf(FontPath)
    let run = shape(textStyle(f, 20'f32), "AΩЖא")
    check run.placements.len == 4
    for placement in run.placements:
      check placement.glyph != 0

  test "empty input is stable and malformed UTF-8 is rejected":
    let f = loadTtf(FontPath)
    let empty = layoutText(textStyle(f, 20'f32), "")
    check empty.lines.len == 1
    check empty.lines[0].run.placements.len == 0
    check empty.height == f.lineHeight(20'f32)
    expect ValueError:
      discard shape(textStyle(f, 20'f32), "\xFF")
    expect ValueError:
      discard layoutText(textStyle(f, 20'f32), "\xFF")

  test "right-to-left run keeps logical clusters":
    let f = loadTtf(FontPath)
    let run = shape(textStyle(f, 20'f32, tdRightToLeft), "abc")
    check run.placements.len == 3
    check run.placements[0].cluster == 2
    check run.placements[^1].cluster == 0
    check shape(textStyle(f, 20'f32), "🙂א").direction == tdRightToLeft
    let layout = layoutText(textStyle(f, 20'f32, tdRightToLeft), "abc",
      200'f32, taStart)
    check layout.lines[0].baseline.x == 200'f32 - layout.lines[0].advance

  test "right-to-left kerning follows visual glyph order":
    let f = loadTtf(FontPath)
    let run = shape(textStyle(f, 2048'f32, tdRightToLeft), "AV")
    let v = f.glyphId(ord('V'))
    let a = f.glyphId(ord('A'))
    check run.placements[0].glyph == v
    check run.placements[0].xAdvance ==
      float32(int32(f.advanceWidth(v)) + f.kerning(v, a))

  test "tabs advance to configurable stops":
    let f = loadTtf(FontPath)
    var style = textStyle(f, 20'f32)
    style.tabSize = 4
    let tabbed = shape(style, "A\tB")
    let spaced = shape(style, "A    B")
    check tabbed.advance != shape(style, "AB").advance
    check tabbed.advance <= spaced.advance
    check tabbed.placements[1].glyph == f.glyphId(ord(' '))
    check tabbed.placements[1].inkBounds.isEmpty

  test "invalid sizes are rejected":
    let f = loadTtf(FontPath)
    expect ValueError:
      discard shape(textStyle(f, 0'f32), "A")
    expect ValueError:
      discard layoutText(textStyle(f, 12'f32), "A", -1'f32)
    expect ValueError:
      discard shape(TextStyle(family: fontFamily(Font(nil)), size: 12'f32), "A")
    expect ValueError:
      discard layoutText(TextStyle(family: fontFamily(Font(nil)), size: 12'f32), "A")

  test "unsupported shaping capability fails explicitly":
    let f = loadTtf(FontPath)
    check supports(scPairKerning)
    check not supports(scOpenTypeSubstitution)
    expect ShapingCapabilityError:
      discard shape(textStyle(f, 12'f32), "ffi", {scOpenTypeSubstitution})
