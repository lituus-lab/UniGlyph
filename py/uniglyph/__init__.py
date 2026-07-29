# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
"""uniglyph — Python binding over the UniGlyph C library (glyph/text engine)."""
from ._core import (
    version,
    abi_version,
    init,
    strerror,
)

__version__ = version()

init()


__all__ = [
    "__version__",
    "abi_version",
    "init",
    "strerror",
    "version",
]