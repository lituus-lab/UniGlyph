<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright 2026 lituus-lab -->
# ADR-0004: UniGlyph conventions

- Status: Accepted
- Date: 2026-07-27
- Scope: UniGlyph and the conventions inherited from the Uni* template

## Layout

```text
UniGlyph.nimble            package + tasks
config.nims                --path to sibling engines (untagged sibling-repo pattern)
src/UniGlyph.nim           umbrella (re-exports the core layers, not c_api)
src/UniGlyph/common.nim    shared types, re-exports UniLinalg Vec2
src/UniGlyph/tables.nim    read-only OpenType/TrueType table parsers
src/UniGlyph/font.nim      Font type + metrics
src/UniGlyph/glyph.nim     glyphPath(font, rune) -> UniVector.Path
src/UniGlyph/layout.nim    single-line LTR typeset
src/UniGlyph/c_api.nim     C ABI
include/UniGlyph.h         hand-written C header
tests/ tests/c/            Nim + C ABI tests
examples/                  Nim + C demos
py/                        Cython binding + pytest
book/                      nimib book
ADRs/                      0001–0004
.github/workflows/ci.yml   3-OS Nim + C ABI + Python
LICENSE NOTICE CONTRIBUTING.md SECURITY.md .gitignore README.md AGENTS.md CLAUDE.md
```

## Naming

- Nim package/module: `UniGlyph` (PascalCase).
- C library: `libUniGlyph`. C header: `UniGlyph.h`.
- C symbol prefix: `ugly_` (family-fixed, see `UNI_FAMILY_STRUCTURE.md` §6).

## Layers

`common < tables < font < glyph < layout < c_api`, enforced by
`nimble checkVGraph`. `common` re-exports UniLinalg `Vec2`; `tables` parses
OpenType tables; `font` wraps tables + metrics; `glyph` builds a
`UniVector.Path` per rune; `layout` places glyphs single-line LTR; `c_api`
imports the facade + UniImage + UniColor directly (Nim does not re-export a
foreign generic type through the `export` chain). The facade re-exports the
core layers, not `c_api`.

## Conventions

- NimContracts `{.contractual.}` + `require:`/`ensure:`/`body:`, compiled away
  under `-d:release`. The C ABI never raises — it traps `CatchableError`/`Defect`
  and maps them to `UGLY_*` codes. Built `--app:staticlib`/`--app:lib --noMain
  --mm:arc -d:release` (not `-d:danger`, so bounds checks stay as
  defense-in-depth for untrusted font bytes).
- A postcondition is cheaper than the body; it never re-derives the result.
- English comments, terse, describe what is done. No "deprecated".
- UniGlyph is an original implementation. The font parser is read-only and
  spec-driven against the OpenType/TrueType spec (ISO/IEC 14496-22 + the
  Microsoft OpenType spec). Do not reproduce third-party source.

## CI gates

- `nimble testCi` + `testCiRelease` on ubuntu/macOS/Windows.
- `nimble ctest` on linux/macOS/Windows.
- `nimble pyTest` on linux/macOS/Windows.
- `nimble lint`, `nimble checkVGraph`, `nimble docs`, `nimble coverage` on ubuntu.