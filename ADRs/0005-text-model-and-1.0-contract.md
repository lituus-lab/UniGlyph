<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright 2026 lituus-lab -->
# ADR-0005: Text model and 1.0 contract

- Status: Accepted
- Date: 2026-08-14
- Scope: UniGlyph

## Context

UniPlot requires deterministic title, tick, legend, annotation, and axis-label
layout across raster, vector, and GPU renderers. Advance width alone is
insufficient: layout also needs ink bounds, line metrics, glyph offsets,
fallback decisions, writing direction, and stable measurement independent of
the selected renderer.

## Decision

UniGlyph 1.0 exposes a renderer-neutral text pipeline:

```text
UTF-8 input
  -> validated Unicode scalar sequence
  -> explicit or inferred direction
  -> font fallback runs
  -> nominal glyph mapping
  -> horizontal pair kerning
  -> lines and text block
  -> vector paths, raster image, or glyph atlas
```

The same shaped layout is consumed by every renderer. A renderer may cache or
batch glyphs but cannot repeat shaping or change advances, offsets, line
breaks, fallback, or bounds.

## Required public model

- `Font`: immutable parsed font data and metrics.
- `FontFamily`: ordered fallback faces.
- `TextStyle`: family, size, direction, spacing, and line height.
- `GlyphPlacement`: glyph id, source face, cluster, advance, offset, and ink
  bounds.
- `GlyphRun`: visually ordered placements, direction, and aggregate advance;
  placements retain their selected fallback face and logical, run-local scalar
  cluster.
- `TextLine`: one glyph run, baseline, typographic bounds, ink bounds, and
  advance.
- `TextLayout`: lines and aggregate typographic and ink bounds; its placements
  retain the source-to-glyph scalar mapping.
- `GlyphAtlas`: pixels plus stable glyph rectangles and bearings, without GPU
  handles or API-specific formats.

All distances exposed by layout are `float32` pixels. Font parser values retain
their exact design-unit integers until scaling. Typographic bounds and ink
bounds are separate values at glyph, line, and block levels.

## Required font and text coverage

The 1.0 parser and shaper support:

- TrueType `glyf` outlines, simple and composite;
- Unicode `cmap` formats 4 and 12;
- horizontal metrics and font-wide typographic metrics;
- legacy horizontal `kern` format 0;
- left-to-right and right-to-left visual ordering selected explicitly or from
  the first strong scalar in the supported ranges;
- stable scalar-to-glyph cluster mapping;
- explicit newlines, width-constrained wrapping, horizontal alignment, line
  spacing, tabs, and font fallback;
- Latin, Greek, Cyrillic, and nominal Hebrew corpus coverage.

OpenType GSUB/GPOS, contextual Arabic shaping, combining-mark attachment,
ligatures, full Unicode bidi paragraph resolution, vertical writing,
color-font tables, variable-font axes, CFF/CFF2 outlines, font hinting, and
platform font discovery are outside the 1.0 contract. Callers requesting an
unsupported shaping capability receive a typed capability error; UniGlyph does
not advertise nominal glyph mapping as complex-script shaping.

## UniPlot contract

UniPlot may rely on these guarantees:

1. Measuring a `TextLayout` performs no rasterization and requires no GPU.
2. Re-rendering the same layout does not alter glyph selection or placement.
3. Rotation and other scene transforms are applied after shaping and layout.
4. Empty input, missing glyphs, malformed UTF-8, non-finite sizes, and
   unavailable requested capabilities have documented deterministic results.
5. Font parsing is bounded against malformed offsets, counts, recursion, and
   allocation sizes.
6. CPU path, raster, and atlas adapters consume the same glyph placements.

Empty input produces one empty line with the natural line height. Malformed
UTF-8 is rejected with `ValueError` in Nim and the corresponding failure value
at foreign boundaries. A single glyph wider than a wrapping width is
indivisible and may exceed that width; all other produced lines respect it.
Without wrapping, tabs advance to configurable column stops. Width-constrained
word wrapping treats Unicode whitespace (including tabs) as break separators
and emits one ASCII space between retained words.

## Verification

- parser tests include truncated and adversarial table corpora;
- shaping fixtures include expected glyph ids, clusters, advances, and
  kerning, not only rendered screenshots;
- layout tests cover empty input, fallback, directed runs,
  wrapping, alignment, and non-finite values;
- renderer tests verify vector paths, non-empty raster coverage, PNG encoding,
  and atlas metadata from the same placement rules;
- Nim, C, and Python tests exercise every supported public operation;
- documentation examples are compiled and executed during the docs gate.

## Consequences

UniGlyph must be completed before UniPlot layout work begins. UniPlot owns
plot-specific placement such as axes and legends; UniGlyph owns only the
measurement and rendering of text blocks passed to it.
