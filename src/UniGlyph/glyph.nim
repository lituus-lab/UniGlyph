# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
## UniGlyph/glyph — turn a TrueType glyph outline into a `UniVector.Path`.
##
## Each contour is converted with the quadratic on/off-curve
## implicit-midpoint rule from the TrueType spec: between two consecutive
## off-curve points an on-curve midpoint is implied, and a trailing off-curve
## control closes onto the start. The path is emitted in design units by
## default; the layout layer bakes a scale, y-flip, and translation in via
## `glyphPathAt` so no `Path` transform is needed downstream.
import UniVector

import UniGlyph/common
import UniGlyph/tables
import UniGlyph/font

proc mid(a, b: GlyphPoint): GlyphPoint =
  GlyphPoint(x: (a.x + b.x) * 0.5'f32, y: (a.y + b.y) * 0.5'f32, onCurve: true)

proc contourToPath(path: var Path, pts: seq[GlyphPoint],
    sx, sy, dx, dy: float32) =
  let n = pts.len
  if n == 0: return
  # If every point is off-curve, synthesize a closed curve of implicit
  # on-curve midpoints with each original point as a quadratic control.
  var anyOn = false
  for p in pts:
    if p.onCurve: anyOn = true; break
  if not anyOn:
    let start = mid(pts[^1], pts[0])
    path.moveTo(sx * start.x + dx, sy * start.y + dy)
    for i in 0 ..< n:
      let q = pts[i]
      let onStop = mid(q, pts[(i + 1) mod n])
      path.quadraticCurveTo(
        sx * q.x + dx, sy * q.y + dy,
        sx * onStop.x + dx, sy * onStop.y + dy)
    path.closePath()
    return
  # Start from the first on-curve point (search wraps for contours that begin
  # with an off-curve run).
  var startIdx = 0
  if not pts[0].onCurve:
    for i in 0 ..< n:
      if pts[i].onCurve: startIdx = i; break
  path.moveTo(sx * pts[startIdx].x + dx, sy * pts[startIdx].y + dy)
  var ctrl: GlyphPoint
  var haveCtrl = false
  for k in 1 ..< n:
    let p = pts[(startIdx + k) mod n]
    if p.onCurve:
      if haveCtrl:
        path.quadraticCurveTo(
          sx * ctrl.x + dx, sy * ctrl.y + dy,
          sx * p.x + dx, sy * p.y + dy)
        haveCtrl = false
      else:
        path.lineTo(sx * p.x + dx, sy * p.y + dy)
    else:
      if haveCtrl:
        # Two consecutive off-curves: emit a quad to their implicit midpoint,
        # then carry the new point as the next control.
        let m = mid(ctrl, p)
        path.quadraticCurveTo(
          sx * ctrl.x + dx, sy * ctrl.y + dy,
          sx * m.x + dx, sy * m.y + dy)
        ctrl = p
      else:
        ctrl = p
        haveCtrl = true
  if haveCtrl:
    path.quadraticCurveTo(
      sx * ctrl.x + dx, sy * ctrl.y + dy,
      sx * pts[startIdx].x + dx, sy * pts[startIdx].y + dy)
  path.closePath()

proc glyphPathAt*(f: Font, gid: GlyphId, sx, sy, dx, dy: float32): Path =
  ## Build a `UniVector.Path` for `gid` with coordinates mapped by
  ## `x' = sx*x + dx`, `y' = sy*y + dy`. Used by the layout layer to bake a
  ## pixel scale, y-flip, and translation into the path in one pass.
  result = newPath()
  for contour in f.glyphOutline(gid):
    contourToPath(result, contour, sx, sy, dx, dy)

proc glyphPath*(f: Font, gid: GlyphId): Path =
  ## Build a `UniVector.Path` for `gid` in font design units.
  glyphPathAt(f, gid, 1.0'f32, 1.0'f32, 0.0'f32, 0.0'f32)

proc glyphPath*(f: Font, rune: int): Path =
  ## Build a `UniVector.Path` for the given Unicode codepoint.
  glyphPath(f, f.glyphId(rune))


