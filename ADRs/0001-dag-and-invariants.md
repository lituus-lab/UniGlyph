<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright 2026 lituus-lab -->
# ADR-0001: UniGlyph dependency direction

- Status: Accepted
- Date: 2026-08-14
- Scope: UniGlyph

## Decision

UniGlyph is the text engine above UniVector. It parses fonts, shapes text,
computes layout, and converts glyph outlines into UniVector paths. Raster
surfaces and codecs remain owned by UniImage; colors remain owned by UniColor;
fixed-size vectors remain owned by UniLinalg.

The dependency edges are:

```text
UniGlyph --> UniVector
UniGlyph --> UniImage
UniGlyph --> UniColor
UniGlyph --> UniLinalg
```

UniPlot consumes UniGlyph. UniGlyph never imports UniPlot, UniGeom, an
application shell, or a GPU API. GPU glyph atlases are represented as engine
data; upload and draw commands belong to the consuming renderer.

## Invariants

1. `tables` has no rendering dependency.
2. `font` depends on parsed tables, never on layout or rendering.
3. `glyph` converts outlines to paths but does not place text.
4. `shaping` produces positioned glyph identities without rasterizing them.
5. `layout` consumes shaping and font metrics without owning image buffers.
6. `render` adapts a completed layout to UniVector and UniImage.
7. `c_api` may combine all public layers but contains no text algorithms.
8. No module imports UniPlot or an application.

`nimble checkVGraph` enforces this order:

```text
common < tables < font < glyph < shaping < layout < atlas/render < c_api
```
