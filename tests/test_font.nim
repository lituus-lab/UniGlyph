# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
import std/[os, unittest]
import UniGlyph

when not defined(release) and not defined(danger):
  import contracts

const FontPath = currentSourcePath.parentDir / "assets/DejaVuSans.ttf"

suite "font":
  test "loadTtfFromBytes retains an immutable copy":
    let raw = readFile(FontPath)
    var bytes = newSeq[byte](raw.len)
    copyMem(bytes[0].addr, raw[0].unsafeAddr, raw.len)
    let font = loadTtfFromBytes(bytes)
    let before = font.glyphId(ord('A'))
    let identityBefore = font.fontIdentity
    for i in 0 ..< bytes.len: bytes[i] = 0
    check font.glyphId(ord('A')) == before
    check font.fontIdentity == identityBefore

  test "font identity describes exact source bytes":
    let raw = readFile(FontPath)
    var bytes = newSeq[byte](raw.len)
    copyMem(bytes[0].addr, raw[0].unsafeAddr, raw.len)
    let fromPath = loadTtf(FontPath)
    let fromBytes = loadTtfFromBytes(bytes)
    check fromPath.fontIdentity == fromBytes.fontIdentity
    check fromPath.fontIdentityHex.len == 64
    check fromPath.fontIdentityHex == fromBytes.fontIdentityHex

    bytes[^1] = bytes[^1] xor 1'u8
    let changed = loadTtfFromBytes(bytes)
    check changed.fontIdentity != fromPath.fontIdentity

  when not defined(release) and not defined(danger):
    test "font identity rejects a nil font":
      let missing = Font(nil)
      expect PreConditionDefect:
        discard missing.fontIdentity
      expect PreConditionDefect:
        discard missing.fontIdentityHex

  test "loadTtf reads DejaVuSans metrics":
    let f = loadTtf(FontPath)
    check f.unitsPerEm == 2048
    check f.ascent > 0
    check f.descent < 0
    check f.numGlyphs > 100

  test "glyphId and advanceWidth for 'A'":
    let f = loadTtf(FontPath)
    let gid = f.glyphId(ord('A'))
    check gid != 0
    check f.advanceWidth(gid) > 0

  test "lineHeight is positive and scales with size":
    let f = loadTtf(FontPath)
    check f.lineHeight(16.0'f32) > 0.0'f32
    check f.lineHeight(32.0'f32) > f.lineHeight(16.0'f32)

  test "scaleFactor is size / unitsPerEm":
    let f = loadTtf(FontPath)
    check abs(f.scaleFactor(2048.0'f32) - 1.0'f32) < 1e-4'f32
    expect ValueError:
      discard f.scaleFactor(NaN.float32)
    expect ValueError:
      discard f.lineHeight(Inf.float32)
