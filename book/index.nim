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
## Resolve a codepoint to a glyph path

`glyphPath` walks `cmap` (format 4, BMP) -> glyph id -> `glyf` contour and
emits a `UniVector.Path` in font design units, applying the quadratic
on/off-curve implicit-midpoint rule from the TrueType spec.
"""

nbCode:
  let pA = font.glyphPath(int('A'))
  echo "glyph 'A' path non-empty: ", pA.commands.len > 0

nbText: """
## Typeset a line of text

`typeset` places glyphs single-line left-to-right using advance widths, with
the y axis flipped (TrueType y is up; image y is down). `origin` is the
baseline. Each slot's path has its translation baked in, so `combinedPath` is
ready to fill.
"""

nbCode:
  import UniLinalg

  let baseline = vec2(1.0'f32, float32(font.ascent) * font.scaleFactor(48'f32) + 1.0'f32)
  let ts = font.typeset("Hello", 48'f32, baseline)
  echo "slots ", ts.slots.len, " advance ", ts.advance
  let combined = ts.combinedPath
  echo "combined path commands ", combined.commands.len

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
(`py/uniglyph/`) expose the same surface: load a font, render text to an image,
encode PNG. The ABI never raises — it traps `CatchableError`/`Defect` and maps
them to `UGLY_*` codes. See `examples/c/demo.c` for a C consumer and
`py/README.md` for the Python quickstart.
"""

nbSave
