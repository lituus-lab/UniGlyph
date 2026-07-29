<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright 2026 lituus-lab -->
# AGENTS.md — UniGlyph

## Build & gates

```bash
nimble install -y
nimble testAll    # Nim debug + release + C ABI
nimble pyTest     # Cython + pytest (needs libUniGlyph.so / UniGlyph.lib)
nimble example    # Nim print-only demo (examples/demo.nim)
nimble ctest      # C ABI smoke test (builds libUniGlyph.a, links tests/c)
nimble cexample   # C print-only demo (examples/c/demo.c, links libUniGlyph.a)
nimble coverage   # gcov + lcov -> coverage/ (needs lcov; linux/macOS)
nimble docs       # nimib book + API reference -> pages/ (needs nimib)
nimble lint
nimble checkVGraph
```

`nimble docs` needs a complete Nim distribution: `--project` builds `dochack`,
which Homebrew's `nim` omits (no `tools/`). choosenim and the CI action ship it.

Sibling engines (UniVector, UniImage, UniColor, UniLinalg, UniMath) are reached
via `--path` in `config.nims` (untagged sibling-repo pattern), not `nimble
requires`. Clone them beside UniGlyph before building the core.

CI: Nim matrix (debug + release) + lint + vgraph + docs + coverage + cabi +
wheels.

## Conventions

- English comments, terse, describe what is done. No "deprecated".
- NimContracts `{.contractual.}` + `require:`/`ensure:`/`body:`, compiled away
  under `-d:release`.
- A postcondition is cheaper than the body: never re-derives the result by
  calling the function itself.
- C ABI (`c_api`): symbols `ugly_*` (prefix `ugly_`); lib `libUniGlyph`; header
  `UniGlyph.h`. The ABI **never raises** — it traps `CatchableError`/`Defect`
  and maps them to `UGLY_*` codes. Built `--app:staticlib`/`--app:lib --noMain
  --mm:arc -d:release` (**not** `-d:danger`, so bounds checks stay as
  defense-in-depth for untrusted font bytes). Handles are opaque `void*`,
  library-owned, freed per-handle (`GC_ref`/`GC_unref`); C-owned string/buffer
  outputs use `allocShared` and are freed by `ugly_buffer_free`. `c_api` imports
  the facade + UniImage + UniColor directly (Nim does not re-export a foreign
  generic type through the `export` chain).
- Layers `common < tables < font < glyph < layout < c_api`, enforced by
  `nimble checkVGraph`. `common` re-exports UniLinalg `Vec2`; `tables` parses
  OpenType/TrueType tables; `font` wraps tables + metrics; `glyph` builds a
  `UniVector.Path` per rune; `layout` places glyphs single-line LTR. The facade
  re-exports the core layers (not `c_api`).
- UniGlyph is an original implementation in the Uni* family idiom. The font
  parser is read-only and spec-driven against the OpenType/TrueType spec
  (ISO/IEC 14496-22 + the Microsoft OpenType spec); glyph outlines are emitted
  as `UniVector.Path` contours and filled via `UniVector.fillPath`. Write it
  fresh; do not reproduce third-party source.
- `book/index.nim` is nimib: its code blocks are compiled and run at docs build,
  so prose that outlives its API breaks the build.
- End covered sources with a blank line. Nim maps a trailing statement one line
  past EOF; without that line lcov aborts on `range`/`unmapped`, and `nimble
  coverage` deliberately suppresses no error so the failure stays visible.

## Scope

Public engine repo of the `lituus-lab` family, above `UniVector` (+ UniImage,
UniColor, UniLinalg) in the dependency DAG, and terminal (nothing in the family
imports UniGlyph yet except the future apps). It replaces the legacy font/text
dependency the media apps currently carry. Apache-2.0, DCO.

### Anti-goals (deferred to later sub-phases or other engines)

- No OTF/CFF charstrings (cubic Type 2 + subrs) — TrueType `glyf` only in 1a.
- No GPOS/GSUB shaping, no kerning (`kern`/GPOS pair-pos), no ligatures.
- No TrueType hinting.
- No font collections (TTC), no SVG fonts.
- No RTL/vertical/complex scripts — single-line LTR only in 1a.
- No multi-line wrap, `Span`/`Arrangement`, alignment, or `TextCase`.
- No stroke text (blocked on UniVector's stroke sub-phase).
- No fallback font chain / system font matching.
- Raster encoding stays UniImage's job; UniGlyph fills an `Image[uint8]` via
  UniVector.