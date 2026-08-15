# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
## UniVector and UniImage adapters over completed text layouts.
import UniColor
import UniImage/core as uimg
import UniVector

import UniGlyph/layout

proc renderLayout*(image: var uimg.Image[uint8], layout: TextLayout,
    color: Color, origin = vec2(0'f32, 0'f32)) =
  ## Fill one completed layout without repeating shaping or measurement.
  image.fillPath(layout.combinedPath(origin), color, NonZero)

