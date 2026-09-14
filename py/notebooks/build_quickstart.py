# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
"""Author py/notebooks/quickstart.ipynb, then execute it so the committed file
carries real outputs for GitHub to render. Run from the repo root:

    python3 py/notebooks/build_quickstart.py

CI re-executes the notebook against an installed wheel and compares the fresh
outputs with the committed ones, so a stale value fails the build. Re-run this
after any API change."""
import os

import nbformat as nbf
from nbclient import NotebookClient

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
OUT = os.path.join(HERE, "quickstart.ipynb")

CELLS = [
    ("md", """# UniGlyph — Python quickstart

`uniglyph` is a Cython extension over the UniGlyph C ABI, shipped as a
self-contained wheel: the native library travels inside the package, so
installing it needs neither Nim nor a compiler.

```
pip install lituus-uniglyph
```"""),
    ("md", """## What the engine does, and does not

`capabilities()` is a bitmask of what the shaper implements. Reading it beats
guessing: this build maps codepoints to glyphs and applies pair kerning, and
does not do OpenType substitution, bidirectional reordering or mark
attachment."""),
    ("code", """import uniglyph
from uniglyph import Capability

print("version =", uniglyph.version(), "| abi =", uniglyph.abi_version())
print("has     =", [flag.name for flag in Capability
                    if uniglyph.capabilities() & flag])
print("lacks   =", [flag.name for flag in Capability
                    if not uniglyph.capabilities() & flag])"""),
    ("md", """## A font to read

The wheel carries DejaVu Sans so this notebook renders wherever it is
installed. `importlib.resources` finds it without knowing where that is."""),
    ("code", """import importlib.resources

from uniglyph import Font

FONT = str(importlib.resources.files("uniglyph") / "data" / "DejaVuSans.ttf")
face = Font(FONT)

print("units_per_em =", face.units_per_em)
print("ascent       =", face.ascent)
print("descent      =", face.descent)
print("line_gap     =", face.line_gap)
print("num_glyphs   =", face.num_glyphs)"""),
    ("md", """## Metrics scale from font units

Those numbers are in font units, not pixels. A line at 16 px is
`(ascent - descent + line_gap) / units_per_em * 16`, which the library computes
for you."""),
    ("code", """expected = (face.ascent - face.descent + face.line_gap) / face.units_per_em * 16

print("line_height(16) =", face.line_height(16.0))
print("by hand         =", expected)"""),
    ("md", """## Glyphs and kerning

`glyph_id` maps a codepoint to a glyph index, and a font that lacks the
codepoint says so rather than guessing. Kerning is returned in font units and
is negative where a pair tucks together — `AV` is the textbook case."""),
    ("code", """A, V = face.glyph_id(ord("A")), face.glyph_id(ord("V"))

print("has 'A'          =", face.has_glyph(ord("A")), "-> glyph", A)
print("has U+4E2D       =", face.has_glyph(0x4E2D))
print("advance of 'A'   =", face.advance(A))
print("kerning A then V =", face.kerning(A, V))
print("text_width       =", face.text_width("Hello", 16.0))"""),
    ("md", """## Content identity

`identity` hashes the bytes of the face, so two paths holding the same file
answer the same thing and a re-encoded file does not."""),
    ("code", """print("identity_hex =", face.identity_hex[:32], "...")
print("same file, same identity =", Font(FONT).identity == face.identity)"""),
    ("md", """## Laying out a line

`Layout` shapes text once and answers questions about the result. Its
typographic box spans the full line height; the ink box is what the glyphs
actually cover, which is smaller on both axes."""),
    ("code", """from uniglyph import Layout

line = Layout(face, "Hello, UniGlyph", 16.0)

print("size        =", (line.width, line.height))
print("lines       =", line.line_count)
print("glyphs      =", len(line.glyphs()))
print("typographic =", line.bounds())
print("ink         =", line.bounds(ink=True))"""),
    ("md", """## Wrapping

Give `max_width` and the layout breaks at word boundaries. Each line reports
its own advance, so none of them exceeds the width asked for."""),
    ("code", """wrapped = Layout(face, "the quick brown fox jumps over the lazy dog", 14.0,
                 max_width=120.0)

print("lines  =", wrapped.line_count, "| height =", wrapped.height)
for index, row in enumerate(wrapped.lines()):
    print(f"  line {index} advance = {row['advance']:.4f}")"""),
    ("md", """## A codepoint the font does not have

Shaping does not fail on it: the glyph becomes 0, the `.notdef` box, while the
cluster keeps the codepoint that asked for it. That is what lets a caller
notice and pick a fallback face."""),
    ("code", """missing = Layout(face, "CJK: 中", 16.0)
last = missing.glyphs()[-1]

print("glyph     =", last["glyph"])
print("codepoint =", last["codepoint"], "(U+%04X)" % last["codepoint"])"""),
    ("md", """## Rendering

`render_to` draws a shaped layout onto an RGBA8 image, and `encode_png` hands
back PNG bytes."""),
    ("code", """from uniglyph import Color, Image

image = Image(220, 40)
Layout(face, "Hello, UniGlyph", 24.0).render_to(
    image, Color.parse("#1a1a1a"), 6.0, 30.0)

png = image.encode_png()

print("image     =", (image.width, image.height), "| channels =", image.channels)
print("png magic =", png[:4])"""),
    ("md", "The rendered surface, as PNG bytes the notebook hands to the browser:"),
    ("code", """from IPython.display import Image as Show

Show(data=image.encode_png(), format="png")"""),
    ("md", """## Colors are parsed or built, never constructed

`Color` has no public constructor: `Color.rgba` takes straight-alpha floats in
`[0, 1]`, and `Color.parse` reads a CSS Color 4 string."""),
    ("code", """try:
    Color(26, 26, 26)
except TypeError as exc:
    print("Color(...) ->", exc)

print("parse ok  =", Color.parse("#1a1a1a").__class__.__name__)
print("rgba ok   =", Color.rgba(0.1, 0.1, 0.1).__class__.__name__)"""),
    ("md", """## An atlas for repeated text

`Atlas` rasterises a set of codepoints once into a single sheet, which is what
a GPU renderer samples from. Asking for a codepoint twice does not pack it
twice."""),
    ("code", """from uniglyph import Atlas

atlas = Atlas(face, [ord(c) for c in "AVAW"], 24.0, width=128)
entry = atlas.entries()[0]

print("sheet   =", (atlas.width, atlas.height))
print("entries =", len(atlas.entries()), "for 4 codepoints, A asked twice")
print("first   = glyph %d at (%d, %d), %dx%d" % (
    entry["glyph"], entry["x"], entry["y"], entry["width"], entry["height"]))"""),
]


def main():
    nb = nbf.v4.new_notebook()
    nb.cells = [
        nbf.v4.new_markdown_cell(src) if kind == "md" else nbf.v4.new_code_cell(src)
        for kind, src in CELLS
    ]
    nb.metadata["kernelspec"] = {
        "display_name": "Python 3",
        "language": "python",
        "name": "python3",
    }
    # Execute from the repo root, never from py/: there, `import uniglyph`
    # would resolve to the py/uniglyph source tree instead of the installed
    # package, and the notebook would stop testing what it claims to test.
    NotebookClient(nb, timeout=120, kernel_name="python3",
                   resources={"metadata": {"path": ROOT}}).execute()
    with open(OUT, "w") as f:
        nbf.write(nb, f)
    print(f"wrote {OUT}")


if __name__ == "__main__":
    main()
