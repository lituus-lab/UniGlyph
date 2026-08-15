# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
## uniglyph — glyph/text rendering CLI.
##
##   uniglyph render --font PATH --text "Hello" --size 48
##       [--color "#000000"] [--bg "#ffffff"] [-o out.png] [--svg out.svg]
##   Lay out `text` at `size` px and rasterize it to a PNG (via UniVector's
##   scanline fill onto a UniImage surface). With `--svg`, also emit the
##   combined text path as an SVG document. The canvas is sized from ink
##   bounds, with a 1 px padding inset.
import std/[math, os, sequtils, strutils, strformat]
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
  uniglyph inspect --font PATH
  uniglyph measure --font PATH --text "Hello" --size 48 [--width 0]
  uniglyph render --font PATH --text "Hello" --size 48
      [--color "#000000"] [--bg "#ffffff"] [-o out.png] [--svg out.svg]"""
  quit(1)

proc option(args: seq[string], name: string, fallback = ""): string =
  var i = 0
  while i < args.len:
    if args[i] == name:
      if i + 1 >= args.len: die(name & " needs a value")
      return args[i + 1]
    if args[i].startsWith(name & "="):
      return args[i][name.len + 1 ..< args[i].len]
    inc i
  fallback

proc loadFontArg(args: seq[string]): Font =
  let path = option(args, "--font")
  if path.len == 0: die("--font is required")
  try: loadTtf(path)
  except CatchableError as e: die("failed to load font: " & e.msg)

proc sizeArg(args: seq[string]): float32 =
  try: result = parseFloat(option(args, "--size", "48")).float32
  except ValueError: die("--size must be a number")
  if classify(result) in {fcNan, fcInf, fcNegInf} or result <= 0:
    die("--size must be finite and positive")

proc cmdInspect(args: seq[string]) =
  let font = loadFontArg(args)
  echo "unitsPerEm ", font.unitsPerEm
  echo "ascent ", font.ascent
  echo "descent ", font.descent
  echo "lineGap ", font.lineGap
  echo "glyphs ", font.numGlyphs

proc cmdMeasure(args: seq[string]) =
  let font = loadFontArg(args)
  let text = option(args, "--text")
  if text.len == 0: die("--text is required")
  let size = sizeArg(args)
  var maxWidth: float32
  try: maxWidth = parseFloat(option(args, "--width", "0")).float32
  except ValueError: die("--width must be a number")
  if classify(maxWidth) in {fcNan, fcInf, fcNegInf} or maxWidth < 0:
    die("--width must be finite and non-negative")
  let layout = layoutText(textStyle(font, size), text, maxWidth)
  echo "width ", layout.width
  echo "height ", layout.height
  echo "lines ", layout.lines.len
  echo "glyphs ", layout.lines.foldl(a + b.run.placements.len, 0)
  echo "ink ", layout.inkBounds.xMin, " ", layout.inkBounds.yMin, " ",
    layout.inkBounds.xMax, " ", layout.inkBounds.yMax

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
  if classify(size) in {fcNan, fcInf, fcNegInf} or size <= 0:
    die("--size must be finite and positive")

  let font =
    try: loadTtf(fontPath)
    except CatchableError as e: die("failed to load font: " & e.msg)

  let layout = layoutText(textStyle(font, size), text)
  let bounds = layout.inkBounds
  # 1 px padding on every side so glyphs at the edges are not clipped.
  let width = int(ceil(bounds.width)) + 2
  let height = int(ceil(bounds.height)) + 2
  if width <= 0 or height <= 0: die("text has no measurable extent")

  let paint = colorOrDie(color)
  let bgPaint = colorOrDie(bg)
  let origin = vec2(1.0'f32 - bounds.xMin, 1.0'f32 - bounds.yMin)
  let combined = layout.combinedPath(origin)

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
  of "inspect": cmdInspect(args[1 ..< args.len])
  of "measure": cmdMeasure(args[1 ..< args.len])
  of "render": cmdRender(args[1 ..< args.len])
  else: usage()

when isMainModule: main()
