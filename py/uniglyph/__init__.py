# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
"""uniglyph — Python binding over the UniGlyph C library (glyph/text engine)."""
from enum import IntEnum, IntFlag

from ._core import (
    Color,
    Atlas,
    Font,
    FontFamily,
    Image,
    Layout,
    abi_version,
    capabilities,
    init,
    render_text,
    strerror,
    version,
)


class Capability(IntFlag):
    NOMINAL_MAPPING = 1 << 0
    PAIR_KERNING = 1 << 1
    OPENTYPE_SUBSTITUTION = 1 << 2
    OPENTYPE_POSITIONING = 1 << 3
    COMPLEX_BIDI = 1 << 4
    MARK_ATTACHMENT = 1 << 5


class Direction(IntEnum):
    AUTO = 0
    LEFT_TO_RIGHT = 1
    RIGHT_TO_LEFT = 2


class Align(IntEnum):
    START = 0
    CENTER = 1
    END = 2

init()

__version__ = version()


__all__ = [
    "Color",
    "Capability",
    "Direction",
    "Align",
    "Atlas",
    "Font",
    "FontFamily",
    "Image",
    "Layout",
    "__version__",
    "abi_version",
    "capabilities",
    "init",
    "render_text",
    "strerror",
    "version",
]
