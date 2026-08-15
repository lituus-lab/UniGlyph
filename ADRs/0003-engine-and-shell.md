<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright 2026 lituus-lab -->
# ADR-0003: UniGlyph engine and foreign interfaces

- Status: Accepted
- Date: 2026-08-14
- Scope: UniGlyph

## Decision

- The text engine, parser, shaping, layout, metrics, atlas generation, and
  rendering adapters are implemented in Nim.
- `src/UniGlyph/c_api.nim` is a translation boundary with opaque handles,
  explicit ownership, status values, and no escaping Nim exception.
- `include/UniGlyph.h` is hand-written and checked by compiled C consumers.
- Static and shared libraries use `--mm:arc --noMain -d:release`; bounds and
  overflow checks remain enabled while parsing untrusted font bytes.
- The Python binding uses Cython over the same C ABI. It does not reimplement
  shaping or layout in Python.
- Windows, GUI toolkit, plotting, GPU, and application event-loop integration
  belong to consumers. UniGlyph has no UI and creates no window.

Every public domain operation is either exposed through C and Python or listed
as an intentional foreign-interface exclusion with its reason. Binding scope
is not deferred to future consumer requests.
