# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
## UniGlyph — umbrella module. Re-exports the public core layers (not c_api,
## which is a separate build target that imports this facade + UniImage +
## UniColor directly).
import UniGlyph/common
import UniGlyph/tables
import UniGlyph/font
import UniGlyph/glyph
import UniGlyph/layout
export common
export tables
export font
export glyph
export layout

const UniGlyphVersion* = "0.1.0"
