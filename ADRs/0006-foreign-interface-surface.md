<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright 2026 lituus-lab -->
# ADR 0006 — Foreign-interface surface

Status: accepted for 1.0.0

## Context

UniGlyph is a Nim engine, but UniPlot and external consumers also need a stable
C ABI and a Python package. Those bindings must expose the retained, useful
text-engine objects without turning parser internals or UniVector-owned path
objects into a second public ABI.

## Decision

The C ABI and Python binding expose:

- engine version, ABI version, status strings, and shaping capability bits;
- immutable font handles, metrics, glyph lookup, advances, and pair kerning;
- ordered fallback families;
- retained layouts, wrapping/alignment/direction and spacing options, bounds,
  glyph placements, and raster rendering;
- renderer-neutral glyph atlases and borrowed atlas pixels;
- UniImage-backed RGBA images and UniColor-backed colors.

Python is a value/ownership wrapper over that C ABI. It does not reimplement
font parsing, shaping, layout, rendering, or atlas packing.

The following Nim APIs are deliberately not duplicated:

- raw `Tables` and parser diagnostics are available from the explicit
  `UniGlyph/tables` module for tests and parser integrations, but are not
  re-exported by the stable `UniGlyph` facade;
- `GlyphOutline` and `Path` conversion stay in Nim because UniVector owns the
  path abstraction and its own foreign-interface policy;
- direct generic UniImage/UniColor values remain owned by those engines.

The `ugly_` prefix and `UNIGLYPH_ABI_VERSION` are frozen. Additive functions
do not change the ABI version; incompatible layout or ownership changes do.

## Consequences

UniPlot can measure, place, render, and atlas text from Nim or a foreign shell
without importing internal tables. The exclusions are ownership boundaries,
not missing alternate implementations.
