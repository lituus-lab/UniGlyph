# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
## UniGlyph — umbrella module. Re-exports the public core layers (not c_api,
## which is a separate build target that imports this facade + UniImage +
## UniColor directly).
import UniGlyph/common
from UniGlyph/tables import FontError, GlyphPoint, Contour, GlyphOutline
import UniGlyph/font
import UniGlyph/glyph
import UniGlyph/shaping
import UniGlyph/layout
import UniGlyph/atlas
import UniGlyph/render
export common
export FontError, GlyphPoint, Contour, GlyphOutline
export font
export glyph
export shaping
export layout
export atlas
export render

const UniGlyphVersion* = "1.0.0"
