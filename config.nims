# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
## UniGlyph build config. UniGlyph renders through UniVector; the sibling
## engines are reached via --path in a family checkout (untagged sibling-repo
## pattern). In an isolated clone, Nimble installs the declared dependencies.
switch("path", "src")
switch("path", "../UniVector/src")
switch("path", "../UniImage/src")
switch("path", "../UniColor/src")
switch("path", "../UniLinalg/src")
# Transitive: UniLinalg imports UniMath (RealField). Reached via --path, not a
# direct engine dep of UniGlyph, so it stays out of vgraph [engines].
switch("path", "../UniMath/src")
