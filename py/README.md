<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright 2026 lituus-lab -->
# uniglyph — Python binding

A thin Cython binding over the UniGlyph C ABI: load TrueType fonts, lay out
single-line text, and render it to PNG through UniVector.

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
```

## API

- `Font(path)` — load and parse a TrueType font; `FileNotFoundError` on a
  missing/unparseable file. Properties `ascent`, `descent`; methods
  `line_height(size)`, `text_width(text, size)`.
- `Image(width, height)` — an RGBA8 surface. Properties `width`, `height`,
  `channels`; methods `pixels()`, `encode_png()`.
- `Color.parse(s)` / `Color.rgba(r, g, b, a=1.0)` — sRGB color.
- `render_text(img, font, text, size, x, y, color)` — lay out `text` single-line
  LTR with baseline origin `(x, y)` and solid-fill it onto `img`.
- `version()`, `abi_version()`, `strerror(code)`, `init()`.

The ABI never raises across the C boundary; failures are mapped to Python
`ValueError` / `MemoryError` / `FileNotFoundError`.