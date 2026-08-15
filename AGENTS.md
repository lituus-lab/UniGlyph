<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright 2026 lituus-lab -->
# AGENTS.md — UniGlyph

## Build & gates

```bash
nimble install -y
nimble testAll    # Nim debug + release + C ABI
nimble pyTest     # Cython + pytest (needs libUniGlyph.so / UniGlyph.lib)
nimble pyWheel    # build the Python wheel
nimble pySdist    # build the Python source distribution
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
via `--path` in `config.nims` during family development and are also declared
in `UniGlyph.nimble` so an isolated clone can install them normally.

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
- Target layers `common < tables < font < glyph < shaping < layout <
  atlas/render < c_api`, enforced by `nimble checkVGraph`. Shaping and layout
  are renderer-neutral; vector, raster, and atlas adapters consume the same
  completed layout. The facade re-exports the core layers, not `c_api`.
- UniGlyph depends on UniVector, UniImage, UniColor, and UniLinalg. UniPlot
  consumes UniGlyph; UniGlyph never imports UniPlot, UniGeom, an app, or a GPU
  API. GPU resource ownership stays in the consuming renderer.
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

Public engine repo above UniVector, UniImage, UniColor, and UniLinalg, and below
UniPlot. UniGlyph owns font parsing, nominal Unicode mapping, fallback, measurement,
multiline layout, vector/raster adapters, and renderer-neutral glyph atlases.
The accepted 1.0 surface and exclusions are defined in ADR-0005. Apache-2.0,
DCO.

### 1.0 anti-goals

- No OTF/CFF or CFF2 charstrings; TrueType `glyf` only.
- No GSUB/GPOS complex shaping or combining-mark attachment in 1.0.
- No TrueType hinting.
- No vertical writing, color-font tables, or variable-font axes.
- No platform font discovery; callers provide font bytes or paths.
- No full Unicode bidi paragraph engine; callers may provide resolved run
  direction when the supported resolver cannot determine it.
- No window, event loop, plotting primitive, or GPU API handle.
- Raster encoding stays UniImage's job; UniGlyph fills an `Image[uint8]` via
  UniVector.
