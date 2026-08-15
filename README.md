<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright 2026 lituus-lab -->
# UniGlyph

UniGlyph is the pure-Nim text engine for the `lituus-lab` family. It parses
OpenType/TrueType fonts, maps Unicode scalars to positioned glyphs, computes
renderer-independent layout, and turns completed layouts into UniVector paths,
UniImage rasters, or glyph-atlas data.

UniGlyph creates no window and imports no plotting or GPU API. Applications and
renderers consume its measured layouts. In particular, UniPlot uses UniGlyph
for titles, axes, ticks, legends, and annotations while retaining ownership of
plot layout and interaction.

## What's inside now

- `src/UniGlyph/tables`: bounds-checked OpenType/TrueType table parsing.
- `src/UniGlyph/font`: immutable font faces and exact design-unit metrics.
- `src/UniGlyph/glyph`: glyph outlines represented as UniVector paths.
- `src/UniGlyph/shaping.nim`: nominal mapping, ordered fallback, direction,
  stable clusters, spacing, and legacy pair kerning.
- `src/UniGlyph/layout.nim`: explicit lines, wrapping, alignment, typographic
  bounds, and ink bounds.
- `src/UniGlyph/atlas.nim`: deterministic, renderer-neutral RGBA8 glyph atlases.
- `src/UniGlyph/render.nim`: retained-layout raster rendering through UniVector
  and UniImage.
- `src/UniGlyph/c_api.nim`: `ugly_*` C ABI with opaque handles and explicit
  ownership.
- `py/uniglyph`: Python binding over the C ABI.
- `bin/uniglyph_cli.nim`: PNG and SVG text rendering command.

The accepted 1.0 text model, supported tables, script corpus, exclusions, and
verification requirements are specified in
[`ADRs/0005-text-model-and-1.0-contract.md`](ADRs/0005-text-model-and-1.0-contract.md).

## Design

The accepted 1.0 dependency direction is:

```text
common < tables < font < glyph < shaping < layout < atlas/render < c_api
```

`nimble checkVGraph` rejects an import that climbs this graph. Shaping and
layout produce stable values before rendering begins; CPU, vector, and future
GPU consumers therefore share glyph selection, advances, offsets, clusters,
line breaks, and bounds.

Typographic bounds describe line allocation. Ink bounds describe pixels or
paths that can be touched by the glyphs. The two are public, distinct, and
never inferred from one another.

## Scope

The 1.0 contract covers TrueType outlines, Unicode `cmap`, horizontal metrics,
nominal Unicode mapping, legacy pair kerning, fallback, directed runs,
wrapping, alignment, vector paths, raster rendering, and renderer-neutral
glyph atlases.

It deliberately excludes UI toolkits, plotting, GPU resource ownership,
platform font discovery, font editing, GSUB/GPOS complex shaping, full Unicode
bidi, vertical writing, color fonts, variable font axes, CFF/CFF2 outlines,
and hinting. Unsupported requested capabilities produce a typed error instead
of silently changing layout.

## Quickstart

The executable book contains compiled examples for loading, shaping,
measuring, laying out, and rendering text:

```bash
nimble docs
```

The current CLI is built separately:

```bash
nimble uniglyph
./bin/uniglyph render --font tests/assets/DejaVuSans.ttf \
  --text "Hello" --size 48 -o hello.png --svg hello.svg
```

## Build and verification

```bash
nimble install -y
nimble testAll
nimble ctest
nimble pyTest
nimble pyWheel
nimble pySdist
nimble example
nimble cexample
nimble coverage
nimble docs
nimble lint
nimble checkVGraph
```

CI runs Nim debug/release, C ABI, and Python consumers on Linux, macOS, and
Windows. Documentation, coverage, lint, dependency-direction, packaged C ABI,
wheel, and source-distribution consumers are release gates.

## Foreign interfaces

The hand-written C header is `include/UniGlyph.h`; symbols use the frozen
`ugly_` prefix. Callers initialize the Nim runtime through `ugly_init`, retain
opaque handles until the matching free call, and free returned owned buffers
with `ugly_buffer_free`. No Nim exception crosses the ABI.

The Python package delegates parsing, nominal shaping, layout, rendering, and
atlas construction to the same ABI. Python code provides ownership and Python
value conversion only. The deliberate foreign-interface boundaries are listed
in [`ADRs/0006-foreign-interface-surface.md`](ADRs/0006-foreign-interface-surface.md).

## The Uni* family

UniGlyph is above UniVector, UniImage, UniColor, and UniLinalg, and below
UniPlot. Domain engines may depend on UniPlot through optional adapters;
UniGlyph never depends on a domain engine. The family purpose and conventions
are documented in the
[`lituus-lab` organization profile](https://github.com/lituus-lab/.github).

## Provenance & development

The implementation follows the OpenType specification and Unicode standards
and is written without copying third-party parser or shaping source. Test font
fixtures retain their own licenses and attribution.

The repository history is intentionally short and linear. It records an
LLM-assisted engineering and verification pass over a pre-existing family
architecture and hand-written text-engine design; it does not imply that the
underlying typography, file formats, or algorithms were designed from scratch
over the span represented by those commits. The human maintainer reviews and
signs off every contribution under the DCO.

## Benchmarks

A future benchmark suite will separate parsing, nominal shaping, layout, path
construction, rasterization, and Python marshalling while recording its machine
and input corpus. No performance claim or benchmark number is published in
1.0.0 because that reproducible suite is not yet part of the repository.

## AI-assisted contributions

AI assistance is accepted under the same provenance, review, licensing, and
DCO requirements as any other contribution. The human contributor remains
responsible for correctness and for ensuring that generated material does not
reproduce incompatible third-party source.

## License

Apache-2.0. See `LICENSE`, `NOTICE`, and `CONTRIBUTING.md`.
