<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright 2026 lituus-lab -->
# The Book

nimib book for UniGlyph. `book/index.nim` is compiled and run at docs build
(`nimble docs`), so its code blocks cannot drift from the API. The 1a surface
— load, glyph path, typeset, render to PNG/SVG — is covered in `index.nim`.