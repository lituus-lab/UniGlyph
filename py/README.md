<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright 2026 lituus-lab -->
# uniglyph — Python binding

A thin Cython binding over the UniGlyph C ABI: parse TrueType fonts, build
glyph outlines, and render text through UniVector.

```bash
nimble pyLib                                    # native lib for this platform
(cd py && python3 -m pip install -e ".[test]") # build the Cython ext + install (editable, with pytest)
(cd py && python3 -m pytest -q)                 # test
```

`nimble pyLib` builds the shared lib on Linux/macOS and the MSVC static lib on
Windows, so the same commands work everywhere. The subshells keep your shell's
cwd unchanged.

## Example

```python
import uniglyph

uniglyph.version()        # "0.1.0"
uniglyph.abi_version()    # 1
```

The font + glyph + text-rendering surface lands in the 1a sub-phase; this
binding grows with the `ugly_*` ABI.

## API

- `uniglyph.version()`, `abi_version()`, `strerror(code)`, `init()`.

The ABI never raises across the C boundary; failures are mapped to Python
`ValueError` / `MemoryError`.