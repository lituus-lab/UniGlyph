<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright 2026 lituus-lab -->
# UniGlyph

Glyph/text engine for the `lituus-lab` `Uni*` family. UniGlyph parses
TrueType outlines and renders text **through UniVector**: it builds a
`UniVector.Path` per glyph and solid-fills it onto a `UniImage` raster surface.
It does not re-implement path or raster math — that is UniVector's job.

The font parser is read-only and spec-driven against the OpenType/TrueType
specification (ISO/IEC 14496-22 + the Microsoft OpenType spec). UniGlyph is an
original implementation; it does not reproduce third-party source.

## Layout

```text
src/UniGlyph.nim            umbrella module (re-exports the core layers)
src/UniGlyph/c_api.nim      C ABI (ugly_* symbols)
include/UniGlyph.h          hand-written C header
tests/ tests/c/             Nim + C ABI tests
examples/                   Nim + C demos
py/                         Cython binding + pytest
book/                       nimib book
ADRs/                       0001 DAG, 0002 license, 0003 engine&shell, 0004 conventions
.github/workflows/ci.yml    3-OS Nim matrix + C ABI + Python
```

## Build

```bash
nimble install -y
nimble test           # Nim, debug (contracts active)
nimble testRelease    # Nim, release (contracts compiled away)
nimble testAll        # debug + release + C ABI
nimble ctest          # C ABI: static lib + tests/c
nimble cexample       # C demo
nimble example        # Nim demo
nimble pyTest         # Cython + pytest
nimble coverage       # gcov + lcov -> coverage/
nimble book           # nimib book -> book/index.html
nimble docs           # book + API reference -> pages/
nimble lint
nimble checkVGraph
```

Sibling engines (UniVector, UniImage, UniColor, UniLinalg, UniMath) are reached
via `--path` (untagged sibling-repo pattern), not `nimble requires`. Clone them
beside UniGlyph before building the core.

## CI

`test`, `cabi` and `python` on ubuntu/macOS/Windows. `consume-cabi` and
`consume-wheel` rebuild against the published artifacts on a machine without Nim,
so what ships is what was tested. `coverage` and `docs` run on ubuntu.

`dco` blocks PRs missing a `Signed-off-by` trailer; `commitizen` blocks PRs whose
commits or title are not [Conventional Commits](https://www.conventionalcommits.org/)
(`CONTRIBUTING.md`).

The same gates run locally with pre-commit: `pip install pre-commit && pre-commit install`
(`CONTRIBUTING.md`).

## AI-assisted contributions

Assistance from AI/LLM tools is welcome on the same terms as any other
contribution.

- **Accountability.** The human contributor is the author and remains fully
  responsible for the change. The DCO sign-off (`Signed-off-by`) is the mechanism:
  by signing you certify the content is yours or properly licensed — this covers
  AI-assisted work, provided you can stand behind it.
- **No third-party contamination.** Ensure AI output introduces no code from a
  third party without a compatible license and attribution. If an LLM reproduced
  protected material, do not submit it.
- **Correctness is yours.** The gates (tests, `nimble lint`, conventional commits,
  pre-commit) catch a lot, but you own the result — review and verify what you
  commit.
- **Atomic commits.** Each commit is one logical change. A PR may stack
  several atomic commits — one monolithic big-bang commit is not.
- **Disclosure.** State in the PR whether AI assistance was used (see the PR
  template). It is not a hard requirement — the DCO remains the gate.

## License

Apache-2.0 (`LICENSE`). DCO sign-off on every commit (`CONTRIBUTING.md`).