# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
"""uniglyph — Python binding over the UniGlyph C library (glyph/text engine)."""
from ._core import (
    Color,
    Font,
    Image,
    abi_version,
    init,
    render_text,
    strerror,
    version,
)

init()

__version__ = version()


__all__ = [
    "Color",
    "Font",
    "Image",
    "__version__",
    "abi_version",
    "init",
    "render_text",
    "strerror",
    "version",
]