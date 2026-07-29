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

## Version
"""

nbCode:
  import UniGlyph

  echo "version ", UniGlyphVersion

nbText: """
The core layers (TrueType tables, font metrics, glyph outlines, single-line
layout) and the `ugly_*` C ABI + Python binding land in the 1a sub-phase. This
book grows with the API.

UniGlyph is an original implementation. The font parser is read-only and
spec-driven against the OpenType/TrueType spec (ISO/IEC 14496-22 + the
Microsoft OpenType spec); glyph outlines are emitted as `UniVector.Path`
contours and filled via `UniVector.fillPath`.
"""

nbSave
