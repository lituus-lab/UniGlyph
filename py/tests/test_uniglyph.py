# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
"""Self-contained pytest over the ugly_* Cython surface (no fixture)."""
import os

import uniglyph

FONT = os.path.join(
    os.path.dirname(__file__), "..", "..", "tests", "assets", "DejaVuSans.ttf"
)


def test_version():
    assert uniglyph.version() == "1.0.0"
    assert uniglyph.__version__ == "1.0.0"


def test_abi_version():
    assert uniglyph.abi_version() == 1
    assert uniglyph.capabilities() & uniglyph.Capability.NOMINAL_MAPPING
    assert uniglyph.capabilities() & uniglyph.Capability.PAIR_KERNING
    assert not (uniglyph.capabilities()
                & uniglyph.Capability.OPENTYPE_SUBSTITUTION)


def test_strerror_ok():
    assert uniglyph.strerror(0) == "ok"


def test_font_load_and_metrics():
    f = uniglyph.Font(FONT)
    assert f.ascent > 0
    assert f.descent < 0
    assert f.units_per_em == 2048
    assert f.num_glyphs > 100
    a = f.glyph_id(ord("A"))
    v = f.glyph_id(ord("V"))
    assert f.has_glyph(ord("A"))
    assert f.advance(a) > 0
    assert f.kerning(a, v) < 0
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


def test_layout_metrics_glyphs_and_render():
    f = uniglyph.Font(FONT)
    family = uniglyph.FontFamily(f)
    assert len(family) == 1
    layout = uniglyph.Layout(family, "AV\ncenter", 32.0,
                             max_width=180.0, align=1)
    assert layout.width == 180.0
    assert layout.height > 0.0
    assert layout.line_count == 2
    assert len(layout.glyphs()) == 8
    assert layout.glyphs()[0]["line_index"] == 0
    assert layout.glyphs()[-1]["line_index"] == 1
    assert len(layout.lines()) == 2
    assert layout.lines()[1]["baseline"][1] > layout.lines()[0]["baseline"][1]
    bounds = layout.bounds()
    assert bounds[3] > bounds[1]
    image = uniglyph.Image(200, 100)
    layout.render_to(image, uniglyph.Color.parse("#000000"))
    assert any(image.pixels())


def test_layout_spacing_options():
    f = uniglyph.Font(FONT)
    plain = uniglyph.Layout(f, "A A", 32.0)
    spaced = uniglyph.Layout(f, "A A", 32.0, letter_spacing=1.5,
                             word_spacing=2.0, line_height=48.0, tab_size=8)
    assert spaced.glyphs()[0]["x_advance"] > plain.glyphs()[0]["x_advance"]
    assert spaced.height == 48.0


def test_atlas_pixels_and_entries():
    f = uniglyph.Font(FONT)
    atlas = uniglyph.Atlas(f, [ord("A"), ord("V"), ord("A")], 24.0, width=128)
    assert atlas.width == 128
    assert atlas.height > 0
    assert len(atlas.entries()) == 2
    assert len(atlas.pixels()) == atlas.width * atlas.height * 4
