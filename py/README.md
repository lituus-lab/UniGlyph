<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright 2026 lituus-lab -->
# uniglyph — Python binding

A thin Cython binding over the UniGlyph C ABI: load TrueType fonts, retain
fallback families and measured layouts, render through UniVector, and build
renderer-neutral glyph atlases.

```bash
# Linux / macOS
nimble pyLib                                    # native lib for this platform
(cd py && python3 -m pip install -e ".[test]") # build the Cython ext + install (editable, with pytest)
(cd py && python3 -m pytest -q)                 # test
```

```powershell
# Windows (PowerShell)
nimble pyLib                                      # MSVC static lib for the extension
Push-Location py; python -m pip install -e ".[test]"; Pop-Location
Push-Location py; python -m pytest -q;            Pop-Location
```

`nimble pyLib` builds the shared lib on Linux/macOS and the MSVC static lib on
Windows. The Python executable and shell differ by platform: Linux/macOS use
`python3` in a `( ... )` subshell; Windows PowerShell uses `python` with
`Push-Location`/`Pop-Location`. Both keep your shell's cwd unchanged.

## Example

```python
import uniglyph

font = uniglyph.Font("path/to/DejaVuSans.ttf")
img = uniglyph.Image(200, 64)
black = uniglyph.Color.parse("#000000")
uniglyph.render_text(img, font, "Hello", 48.0, x=2.0, y=50.0, color=black)
open("hello.png", "wb").write(img.encode_png())

font.ascent            # design units
font.line_height(48.0) # scaled line height
font.text_width("Hello", 48.0)
font.identity           # 32-byte BLAKE3 identity of the exact source bytes
font.identity_hex       # the same identity as 64 lowercase hex characters

family = uniglyph.FontFamily(font)
layout = uniglyph.Layout(family, "Axis title\nmeasurement", 32.0,
                         max_width=220.0, align=1)
layout.bounds(ink=True)
layout.glyphs()

atlas = uniglyph.Atlas(family, map(ord, "Axis 0123456789"), 24.0)
atlas.entries()
```

## API

- `Font(path)` — load and parse a TrueType font; exact content identity,
  metrics, glyph lookup, advances, kerning, line height, and text width.
- `FontFamily(first, *fallback)` — retain an ordered fallback family.
- `Layout(source, text, size, ...)` — `Direction`, wrapping, `Align`, spacing,
  bounds, glyph placements, and retained raster rendering.
- `Atlas(source, codepoints, size, ...)` — RGBA8 pixels plus deterministic
  glyph rectangles, bearings, advances, and face indices.
- `Image(width, height)` — an RGBA8 surface. Properties `width`, `height`,
  `channels`; methods `pixels()`, `encode_png()`.
- `Color.parse(s)` / `Color.rgba(r, g, b, a=1.0)` — sRGB color.
- `render_text(img, font, text, size, x, y, color)` — lay out `text` single-line
  LTR with baseline origin `(x, y)` and solid-fill it onto `img`.
- `version()`, `abi_version()`, `capabilities()`, `strerror(code)`, `init()`.

The ABI never raises across the C boundary; failures are mapped to Python
`ValueError` / `MemoryError` / `FileNotFoundError`.

Wheels contain the native library and are the standalone Python distribution.
The source archive is a development artifact for a UniGlyph checkout: building
it requires Nim, the sibling Uni* sources, and either `UNIGLYPH_ROOT` pointing
to that checkout or `UNIGLYPH_LIB_DIR` pointing to a compatible prebuilt
library. It is attached to GitHub releases but is intentionally not uploaded
to PyPI, where an ordinary `pip install uniglyph` must select a wheel.
