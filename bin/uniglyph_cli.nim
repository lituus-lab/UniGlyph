# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
## uniglyph — glyph/text rendering CLI.
##
##   uniglyph render --font PATH --text "Hello" --size 48
##       [--color "#000000"] [--bg "#ffffff"] [-o out.png] [--svg out.svg]
##   Lay out `text` at `size` px and rasterize it to a PNG (via UniVector's
##   scanline fill onto a UniImage surface). With `--svg`, also emit the
##   combined text path as an SVG document. The canvas is sized to the text
##   advance width and the font line height, with a 1 px padding inset.
import std/[os, strutils, strformat]
import UniGlyph
import UniVector
import UniColor
import UniImage/core as uimg
import UniImage/formats

proc die(msg: string) {.noreturn.} =
  stderr.writeLine "error: " & msg
  quit(1)

proc colorOrDie(s: string): Color =
  let r = parseColor(s)
  if r.isOk: r.get else: die("invalid color: " & s)

proc usage() =
  stderr.writeLine """usage:
  uniglyph render --font PATH --text "Hello" --size 48
      [--color "#000000"] [--bg "#ffffff"] [-o out.png] [--svg out.svg]"""
  quit(1)

proc cmdRender(args: seq[string]) =
  var fontPath = ""
  var text = ""
  var size = 48'f32
  var color = "#000000"
  var bg = "#ffffff"
  var pngOut = "out.png"
  var svgOut = ""
  var i = 0
  while i < args.len:
    let a = args[i]
    if a.startsWith("--font="):
      fontPath = a[7 ..< a.len]
    elif a == "--font":
      if i + 1 >= args.len: die("--font needs a value")
      fontPath = args[i + 1]; i += 1
    elif a.startsWith("--text="):
      text = a[7 ..< a.len]
    elif a == "--text":
      if i + 1 >= args.len: die("--text needs a value")
      text = args[i + 1]; i += 1
    elif a.startsWith("--size="):
      try: size = parseFloat(a[7 ..< a.len]).float32
      except ValueError: die("--size must be a number: " & a)
    elif a == "--size":
      if i + 1 >= args.len: die("--size needs a value")
      try: size = parseFloat(args[i + 1]).float32
      except ValueError: die("--size must be a number: " & args[i + 1])
      i += 1
    elif a.startsWith("--color="):
      color = a[8 ..< a.len]
    elif a == "--color":
      if i + 1 >= args.len: die("--color needs a value")
      color = args[i + 1]; i += 1
    elif a.startsWith("--bg="):
      bg = a[5 ..< a.len]
    elif a == "--bg":
      if i + 1 >= args.len: die("--bg needs a value")
      bg = args[i + 1]; i += 1
    elif a.startsWith("-o="):
      pngOut = a[3 ..< a.len]
    elif a == "-o":
      if i + 1 >= args.len: die("-o needs a value")
      pngOut = args[i + 1]; i += 1
    elif a.startsWith("--svg="):
      svgOut = a[6 ..< a.len]
    elif a == "--svg":
      if i + 1 >= args.len: die("--svg needs a value")
      svgOut = args[i + 1]; i += 1
    else:
      usage()
    i += 1
  if fontPath.len == 0: die("--font is required")
  if text.len == 0: die("--text is required")
  if size <= 0: die("--size must be positive")

  let font =
    try: loadTtf(fontPath)
    except CatchableError as e: die("failed to load font: " & e.msg)

  let s = font.scaleFactor(size)
  let tw = textWidth(font, text, size)
  let lh = font.lineHeight(size)
  let ascentPx = float32(font.ascent) * s
  # 1 px padding on every side so glyphs at the edges are not clipped.
  let width = int(tw) + 2
  let height = int(lh) + 2
  if width <= 0 or height <= 0: die("text has no measurable extent")

  let paint = colorOrDie(color)
  let bgPaint = colorOrDie(bg)
  let baseline = vec2(1.0'f32, ascentPx + 1.0'f32)
  let ts = typeset(font, text, size, baseline)
  let combined = ts.combinedPath

  var img = uimg.newImage[uint8](width, height, uimg.csRgba)
  var bgPath = newPath()
  bgPath.rect(0.0'f32, 0.0'f32, width.float32, height.float32)
  fillPath(img, bgPath, bgPaint)
  fillPath(img, combined, paint)

  let png = encodeImage(img, efPng, 90)
  writeFile(pngOut, cast[string](png))
  var wrote = &"wrote {pngOut} ({width}x{height})"
  if svgOut.len > 0:
    let svg = toSvgString(combined, paint, width, height)
    writeFile(svgOut, svg)
    wrote &= &" and {svgOut}"
  echo wrote

proc main() =
  let args = commandLineParams()
  if args.len < 1: usage()
  case args[0]
  of "render": cmdRender(args[1 ..< args.len])
  else: usage()

when isMainModule: main()