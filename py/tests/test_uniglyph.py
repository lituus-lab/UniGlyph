# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
"""Self-contained pytest over the ugly_* Cython surface (no fixture)."""
import os

import uniglyph

FONT = os.path.join(
    os.path.dirname(__file__), "..", "..", "tests", "assets", "DejaVuSans.ttf"
)


def test_version():
    assert uniglyph.version() == "0.1.0"
    assert uniglyph.__version__ == "0.1.0"


def test_abi_version():
    assert uniglyph.abi_version() == 1


def test_strerror_ok():
    assert uniglyph.strerror(0) == "ok"


def test_font_load_and_metrics():
    f = uniglyph.Font(FONT)
    assert f.ascent > 0
    assert f.descent < 0
    assert f.line_height(48.0) > 0.0
    assert f.text_width("Hello", 48.0) > 0.0


def test_font_load_missing():
    import pytest

    with pytest.raises(FileNotFoundError):
        uniglyph.Font("no/such/font.ttf")


def test_render_text_png():
    f = uniglyph.Font(FONT)
    img = uniglyph.Image(200, 64)
    assert img.width == 200
    assert img.height == 64
    assert img.channels == 4
    black = uniglyph.Color.parse("#000000")
    uniglyph.render_text(img, f, "Hello", 48.0, 2.0, 50.0, black)
    png = img.encode_png()
    assert png[:4] == b"\x89PNG"
    assert len(png) > 4
    # The raster actually changed: a blank surface encodes to a different PNG.
    blank = uniglyph.Image(200, 64)
    assert png != blank.encode_png()


def test_render_text_bad_handle():
    import pytest

    f = uniglyph.Font(FONT)
    img = uniglyph.Image(200, 64)
    black = uniglyph.Color.parse("#000000")
    # None for img must surface as a ValueError from the ABI (nil handle).
    with pytest.raises((ValueError, TypeError)):
        uniglyph.render_text(None, f, "Hello", 48.0, 2.0, 50.0, black)


def test_color_rgba():
    c = uniglyph.Color.rgba(0.2, 0.4, 0.8, 1.0)
    assert c is not None