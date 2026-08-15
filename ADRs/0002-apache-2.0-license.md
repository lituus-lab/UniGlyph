<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright 2026 lituus-lab -->
# ADR-0002: UniGlyph licensing and font fixtures

- Status: Accepted
- Date: 2026-08-14
- Scope: UniGlyph

## Decision

UniGlyph source is Apache-2.0. It is an original, specification-driven
implementation and does not copy font parser, shaping, rasterizer, or text
layout implementations from third-party libraries.

Font files used as test fixtures retain their own licenses and attribution.
They are never incorporated into `libUniGlyph`, source distributions, or
wheels unless their license and packaging purpose are recorded explicitly.
The repository ships `LICENSE`, `NOTICE`, and DCO contribution terms.
