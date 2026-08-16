# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
import nimib

nbInit
nb.title = "UniGlyph"

nbText: """
# UniGlyph

Glyph/text engine for the `lituus-lab` Uni* family. UniGlyph parses TrueType
outlines and renders text **through UniVector**: it builds a `UniVector.Path`
per glyph and solid-fills it onto a `UniImage` raster surface.

This page is a nimib book: every Nim block below is compiled and run when the
book is built, and the output shown is what the code actually produced. A
change that breaks the API breaks the docs build, so the two cannot drift apart.

UniGlyph is an original implementation. The font parser is read-only and
spec-driven against the OpenType/TrueType spec (ISO/IEC 14496-22 + the
Microsoft OpenType spec); glyph outlines are emitted as `UniVector.Path`
contours and filled via `UniVector.fillPath`.

## Version
"""

nbCode:
  import UniGlyph

  echo "version ", UniGlyphVersion

nbText: """
## Load a font and read its metrics

`loadTtf` parses the TrueType tables once; vertical metrics come from `hhea` +
`head`, per-glyph advance widths from `hmtx`. The bundled DejaVu Sans ships
under tests/assets/ for CI.
"""

nbCode:
  let font = loadTtf("tests/assets/DejaVuSans.ttf")
  echo "unitsPerEm ", font.unitsPerEm()
  echo "ascent ", font.ascent, " descent ", font.descent
  echo "lineHeight @48px ", font.lineHeight(48'f32)

nbText: """
## Identify exact font content

`fontIdentity` is the complete BLAKE3-256 digest of the bytes supplied to the
loader. UniGlyph computes it once while loading and returns the retained value
thereafter. Loading the same bytes by path or from memory gives the same key,
which lets UniPlot identify prepared text resources without relying on a path,
font name, or process-local pointer.
"""

nbCode:
  let identity = font.fontIdentity
  echo "identity bytes ", identity.len
  echo "identity hex characters ", font.fontIdentityHex.len

nbText: """
## Resolve a codepoint to a glyph path

`glyphPath` walks `cmap` (format 4 or 12) -> glyph id -> `glyf` contour and
emits a `UniVector.Path` in font design units, applying the quadratic
on/off-curve implicit-midpoint rule from the TrueType spec.
"""

nbCode:
  let pA = font.glyphPath(int('A'))
  echo "glyph 'A' path non-empty: ", pA.commands.len > 0

nbText: """
## Shape and measure text

`shape` maps Unicode scalars to nominal glyphs, selects the first face in an
ordered fallback family that contains each scalar, and applies horizontal
`kern` pairs. The result retains glyph ids, source clusters, advances, offsets,
and ink bounds without rasterizing anything.
"""

nbCode:
  import UniLinalg

  let style = textStyle(font, 48'f32)
  let shaped = shape(style, "AV")
  echo "glyphs ", shaped.placements.len, " advance ", shaped.advance
  echo "pair kerning supported ", supports(scPairKerning)
  echo "OpenType substitution supported ", supports(scOpenTypeSubstitution)

nbText: """
## Lay out lines and blocks

`layoutText` keeps typographic bounds separate from ink bounds, preserves
explicit newlines, wraps to a requested width, and aligns each line. A retained
layout can be measured repeatedly or sent to different renderers without
repeating glyph selection and placement.
"""

nbCode:
  let textBlock = layoutText(style, "Axis title\nmeasurement", 220'f32, taCenter)
  echo "lines ", textBlock.lines.len
  echo "block ", textBlock.width, " x ", textBlock.height
  echo "typographic height ", textBlock.typographicBounds.height
  echo "ink height ", textBlock.inkBounds.height

nbText: """
The original `typeset` API remains a single-line convenience over the same
nominal shaping and pair-kerning path. Its origin is a baseline in screen
coordinates, where positive y points downward.
"""

nbCode:
  let baseline = vec2(1.0'f32, float32(font.ascent) * font.scaleFactor(48'f32) + 1.0'f32)
  let ts = font.typeset("Hello", 48'f32, baseline)
  echo "slots ", ts.slots.len, " advance ", ts.advance
  let combined = ts.combinedPath
  echo "combined path commands ", combined.commands.len

nbText: """
## Build a renderer-neutral glyph atlas

An atlas contains RGBA8 coverage and stable rectangles and bearings. It owns no
GPU handle; a WGPU, Metal, Vulkan, or CPU renderer uploads or consumes the same
data according to its own resource policy.
"""

nbCode:
  let atlas = buildGlyphAtlas(style, @[ord('A'), ord('V'), ord('A')], 128)
  echo "atlas ", atlas.width, " x ", atlas.height
  echo "unique entries ", atlas.entries.len
  echo "pixel bytes ", atlas.pixels.len

nbText: """
## Render to PNG and SVG

Fill the combined path onto a `UniImage` RGBA8 surface with `UniVector.fillPath`,
encode PNG with UniImage, and emit the SVG of the same path with
`UniVector.toSvgString`.
"""

nbCode:
  import UniVector
  import UniColor
  import UniImage/core as uimg
  import UniImage/formats

  let width = int(ts.advance) + 2
  let height = int(font.lineHeight(48'f32)) + 2
  let ink = parseColor("#000000").get
  var img = uimg.newImage[uint8](width, height, uimg.csRgba)
  fillPath(img, combined, ink)
  let png = encodeImage(img, efPng, 90)
  echo "png bytes ", png.len, " signature ", png[0], " ", png[1]
  let svg = toSvgString(combined, ink, width, height)
  echo "svg starts with <svg: ", svg[0..3] == "<svg"

nbText: """
## C ABI and Python

The `ugly_*` C ABI (`include/UniGlyph.h`) and the Cython binding
(`py/uniglyph/`) expose fonts and fallback families, retained layouts, glyph
metadata, bounds, raster rendering, atlases, and PNG encoding. The ABI never
raises across C; it maps failures to `UGLY_*` status values or NULL handles.
`ugly_font_identity` copies 32 bytes into caller-owned storage; Python exposes
the same value as `Font.identity` and its lowercase form as `identity_hex`.

## References

- [OpenType specification](https://learn.microsoft.com/en-us/typography/opentype/spec/)
- [Unicode Standard Annex #9: Bidirectional Algorithm](https://unicode.org/reports/tr9/)
- [Unicode Standard Annex #29: Text Segmentation](https://unicode.org/reports/tr29/)
"""

nbSave
