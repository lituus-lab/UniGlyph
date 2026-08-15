# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
## C ABI for UniGlyph. Built --app:staticlib/--app:lib --noMain --mm:arc
## -d:release. Keep in sync with include/UniGlyph.h; tests/c links the header
## against this lib.
##
## Conventions (see the header for the authoritative contract):
##   * Call `ugly_init()` once per process before anything else (it runs the
##     Nim runtime initialiser).
##   * Handles are opaque `void*`. The library owns them; free with the
##     matching `ugly_font_free` / `ugly_image_free` / `ugly_color_free`. NULL is
##     a no-op for every free.
##   * `ugly_image_encode_png` allocates a C-owned buffer; free it with
##     `ugly_buffer_free`. `ugly_image_pixels` *borrows* the image buffer (valid
##     until `ugly_image_free`) and must NOT be freed with `ugly_buffer_free`.
##   * No Nim exception or Defect crosses the ABI: every entry point traps both
##     and maps them to a `UGLY_*` code. Untrusted font bytes and color inputs
##     are parsed under `-d:release` (not `-d:danger`), so Nim's bounds checks
##     stay as defense-in-depth.
import UniGlyph ## facade: Font / loadTtf / typeset / textWidth / vec2 / metrics.
import UniVector ## fillPath + NonZero for rasterising the combined text path.
import UniImage/core as uimg ## the `Image[uint8]` surface held in the image
              ## handle; Nim does not re-export a foreign generic type through
              ## the facade's `export` chain, so the engine is imported directly
              ## (vgraph-clean: UniImage is an engine, not a layer).
import UniImage/formats ## encodeImage + efPng for ugly_image_encode_png.
import UniColor ## Color / parseColor / color / tagSrgb — not re-exported by the
              ## UniGlyph facade, so import UniColor directly.

when defined(danger):
  {.warning: "libUniGlyph built with -d:danger: bounds checks are off and the " &
    "Defect backstops at the ABI boundary cannot fire. Prefer -d:release for a " &
    "hardened parser facing untrusted font bytes and colors.".}

const UniGlyphAbiVersion = 1

type
  FontHandle = ref object
    f: Font
  FamilyHandle = ref object
    family: FontFamily
  ImgHandle = ref object
    img: uimg.Image[uint8]
  ColorHandle = ref object
    color: Color
  LayoutHandle = ref object
    layout: TextLayout
  AtlasHandle = ref object
    atlas: GlyphAtlas
  UglyBounds {.bycopy.} = object
    xMin, yMin, xMax, yMax: float32
  UglyGlyphInfo {.bycopy.} = object
    glyph: uint32
    faceIndex, lineIndex, cluster, codepoint: cint
    x, y, xAdvance, yAdvance, xOffset, yOffset: float32
    inkBounds: UglyBounds
  UglyLineInfo {.bycopy.} = object
    baselineX, baselineY, advance: float32
    typographicBounds, inkBounds: UglyBounds
  UglyTextOptions {.bycopy.} = object
    letterSpacing, wordSpacing, lineHeight: float32
    tabSize: cint
  UglyAtlasEntry {.bycopy.} = object
    glyph: uint32
    faceIndex, x, y, width, height: cint
    bearingX, bearingY, advance: float32

proc NimMain() {.importc.}

proc fontOf(p: pointer): FontHandle {.inline.} = cast[FontHandle](p)
proc familyOf(p: pointer): FamilyHandle {.inline.} = cast[FamilyHandle](p)
proc imgOf(p: pointer): ImgHandle {.inline.} = cast[ImgHandle](p)
proc colorOf(p: pointer): ColorHandle {.inline.} = cast[ColorHandle](p)
proc layoutOf(p: pointer): LayoutHandle {.inline.} = cast[LayoutHandle](p)
proc atlasOf(p: pointer): AtlasHandle {.inline.} = cast[AtlasHandle](p)

proc toC(b: TextBounds): UglyBounds {.inline.} =
  UglyBounds(xMin: b.xMin, yMin: b.yMin, xMax: b.xMax, yMax: b.yMax)

proc applyOptions(style: var TextStyle; options: ptr UglyTextOptions) =
  if options == nil: return
  style.letterSpacing = options[].letterSpacing
  style.wordSpacing = options[].wordSpacing
  style.lineHeight = options[].lineHeight
  style.tabSize = int(options[].tabSize)

# Status codes — keep in sync with `ugly_status` in UniGlyph.h.
const
  UGLY_OK = cint(0)
  UGLY_ERR_FORMAT = cint(2)         # bad arg / nil handle / unparseable font / bad color
  UGLY_ERR_UNSUP {.used.} = cint(4) # reserved
  UGLY_ERR_MEM = cint(8)            # allocation failed

proc writeBytes(src: seq[byte]; outData: ptr ptr uint8;
    outLen: ptr csize_t): cint =
  ## Copy `src` into a C-owned buffer; caller frees with `ugly_buffer_free`.
  if outData == nil or outLen == nil: return UGLY_ERR_FORMAT
  outData[] = nil
  outLen[] = 0
  let n = src.len
  let buf = allocShared(n)
  if buf == nil: return UGLY_ERR_MEM
  if n > 0: copyMem(buf, unsafeAddr src[0], n)
  outData[] = cast[ptr uint8](buf)
  outLen[] = csize_t(n)
  UGLY_OK

template swallowAbiFaults(body: untyped) =
  ## Run `body` so no CatchableError or Defect crosses the C boundary. Void
  ## mutators use this: the never-raises contract means a faulted mutation is
  ## dropped (the handle keeps its prior state) rather than escaping as a trap.
  try:
    body
  except CatchableError, Defect:
    discard

var nimMainCalled: bool

# Unmangled C symbols, C calling convention, exported from the shared lib.
{.push exportc, cdecl, dynlib.}

proc ugly_init(): cint =
  ## Idempotent NimMain bootstrap. Call once before any other ugly_* entry.
  ## Never raises.
  if not nimMainCalled:
    try: NimMain()
    except CatchableError, Defect: discard
    nimMainCalled = true
  UGLY_OK

proc ugly_abi_version(): cint = cint(UniGlyphAbiVersion)

proc ugly_capabilities(): uint32 =
  for capability in UniGlyphCapabilities:
    result = result or (1'u32 shl ord(capability))

proc ugly_version(): cstring =
  ## Static engine version string; do not free. Never raises.
  cstring(UniGlyphVersion)

proc ugly_strerror(code: cint): cstring =
  ## Static message for an ugly_* status code.
  case code
  of UGLY_OK: cstring"ok"
  of UGLY_ERR_FORMAT: cstring"bad argument / nil handle / unparseable font / bad color"
  of UGLY_ERR_UNSUP: cstring"unsupported operation"
  of UGLY_ERR_MEM: cstring"out of memory"
  else: cstring"unknown error"

# ------------------------------- font ---------------------------------------

proc ugly_font_load(path: cstring): pointer =
  ## Load and parse a TrueType font file. NULL on a nil path, missing file, or
  ## malformed font. Never raises (FontError is trapped).
  if path == nil: return nil
  try:
    let f = loadTtf($path)
    let h = FontHandle(f: f)
    GC_ref(h)
    cast[pointer](h)
  except CatchableError, Defect:
    nil

proc ugly_font_ascent(h: pointer): cint =
  ## Font ascent in design units (0 on a nil handle).
  if h == nil: return 0
  cint(fontOf(h).f.ascent)

proc ugly_font_descent(h: pointer): cint =
  ## Font descent in design units (0 on a nil handle).
  if h == nil: return 0
  cint(fontOf(h).f.descent)

proc ugly_font_units_per_em(h: pointer): cint =
  if h == nil: return 0
  cint(fontOf(h).f.unitsPerEm)

proc ugly_font_line_gap(h: pointer): cint =
  if h == nil: return 0
  cint(fontOf(h).f.lineGap)

proc ugly_font_num_glyphs(h: pointer): cint =
  if h == nil: return 0
  cint(fontOf(h).f.numGlyphs)

proc ugly_font_glyph_id(h: pointer; codepoint: uint32): uint32 =
  if h == nil or codepoint > 0x10FFFF'u32: return 0
  uint32(fontOf(h).f.glyphId(int(codepoint)))

proc ugly_font_has_glyph(h: pointer; codepoint: uint32): cint =
  if h == nil or codepoint > 0x10FFFF'u32: return 0
  cint(fontOf(h).f.hasGlyph(int(codepoint)))

proc ugly_font_advance(h: pointer; glyph: uint32): uint32 =
  if h == nil: return 0
  uint32(fontOf(h).f.advanceWidth(GlyphId(glyph)))

proc ugly_font_kerning(h: pointer; left, right: uint32): cint =
  if h == nil: return 0
  cint(fontOf(h).f.kerning(GlyphId(left), GlyphId(right)))

proc ugly_font_line_height(h: pointer; size: float32): float32 =
  ## Scaled line height (ascent - descent + lineGap) at `size` px.
  if h == nil: return 0'f32
  try: fontOf(h).f.lineHeight(size)
  except CatchableError, Defect: 0'f32

proc ugly_font_free(h: pointer) =
  if h == nil: return
  swallowAbiFaults: GC_unref(fontOf(h))

proc ugly_family_new(font: pointer): pointer =
  if font == nil: return nil
  try:
    let h = FamilyHandle(family: fontFamily(fontOf(font).f))
    GC_ref(h)
    cast[pointer](h)
  except CatchableError, Defect:
    nil

proc ugly_family_add(h, font: pointer): cint =
  if h == nil or font == nil: return UGLY_ERR_FORMAT
  try:
    familyOf(h).family.faces.add fontOf(font).f
    UGLY_OK
  except CatchableError, Defect:
    UGLY_ERR_MEM

proc ugly_family_count(h: pointer): csize_t =
  if h == nil: 0 else: csize_t(familyOf(h).family.faces.len)

proc ugly_family_free(h: pointer) =
  if h == nil: return
  swallowAbiFaults: GC_unref(familyOf(h))

# ------------------------------- image --------------------------------------

proc ugly_image_new(width, height: cint): pointer =
  ## A zeroed (transparent) RGBA8 image. NULL on bad dimensions or allocation
  ## failure.
  if width <= 0 or height <= 0: return nil
  try:
    let img = uimg.newImage[uint8](int(width), int(height), uimg.csRgba)
    let h = ImgHandle(img: img)
    GC_ref(h)
    cast[pointer](h)
  except CatchableError, Defect:
    nil

proc ugly_image_width(h: pointer): cint =
  if h == nil: return 0
  cint(imgOf(h).img.width)

proc ugly_image_height(h: pointer): cint =
  if h == nil: return 0
  cint(imgOf(h).img.height)

proc ugly_image_channels(h: pointer): cint =
  if h == nil: return 0
  cint(imgOf(h).img.channels)

proc ugly_image_pixels(h: pointer; outPtr: ptr ptr uint8;
    outLen: ptr csize_t): cint =
  ## Borrow the pixel buffer (no copy). `*outPtr` is valid until `h` is freed;
  ## do NOT free it with `ugly_buffer_free`. Empty image -> `*outPtr = NULL`,
  ## `*outLen = 0`, `UGLY_OK`.
  if outPtr == nil or outLen == nil: return UGLY_ERR_FORMAT
  outPtr[] = nil
  outLen[] = 0
  if h == nil: return UGLY_ERR_FORMAT
  let hh = imgOf(h)
  if hh.img.data.len == 0: return UGLY_OK
  outPtr[] = cast[ptr uint8](addr hh.img.data[0])
  outLen[] = csize_t(hh.img.data.len)
  UGLY_OK

proc ugly_image_encode_png(h: pointer; outData: ptr ptr uint8;
    outLen: ptr csize_t): cint =
  ## Encode the image as PNG. On success allocates `*outData` (free with
  ## `ugly_buffer_free`) and sets `*outLen`.
  if outData == nil or outLen == nil: return UGLY_ERR_FORMAT
  outData[] = nil
  outLen[] = 0
  if h == nil: return UGLY_ERR_FORMAT
  try:
    let bytes = encodeImage(imgOf(h).img, efPng, 90)
    if bytes.len == 0: return UGLY_ERR_FORMAT
    writeBytes(bytes, outData, outLen)
  except CatchableError, Defect:
    UGLY_ERR_FORMAT

proc ugly_image_free(h: pointer) =
  if h == nil: return
  swallowAbiFaults: GC_unref(imgOf(h))

# ------------------------------- color --------------------------------------

proc ugly_color_parse(s: cstring): pointer =
  ## Parse a CSS Color 4 string (hex/rgb/oklch/...). NULL on a nil string or
  ## unparseable input. Never raises (parseColor returns a Result).
  if s == nil: return nil
  let r = parseColor($s)
  if not r.isOk: return nil
  try:
    let h = ColorHandle(color: r.get)
    GC_ref(h)
    cast[pointer](h)
  except CatchableError, Defect:
    nil

proc ugly_color_rgba(r, g, b, a: float32): pointer =
  ## An sRGB color from straight-alpha floats in [0, 1]. NULL on an
  ## out-of-gamut / non-finite input.
  let cr = color(tagSrgb, r, g, b, a)
  if not cr.isOk: return nil
  try:
    let h = ColorHandle(color: cr.get)
    GC_ref(h)
    cast[pointer](h)
  except CatchableError, Defect:
    nil

proc ugly_color_free(h: pointer) =
  if h == nil: return
  swallowAbiFaults: GC_unref(colorOf(h))

# ------------------------------- text ---------------------------------------

proc ugly_text_width(h: pointer; text: cstring; size: float32): float32 =
  ## Total advance width of `text` at `size` px (including pair kerning). 0 on a nil handle
  ## or text.
  if h == nil or text == nil: return 0'f32
  try: textWidth(fontOf(h).f, $text, size)
  except CatchableError, Defect: 0'f32

proc ugly_layout_new(font: pointer; text: cstring; size, maxWidth: float32;
    align, direction: cint): pointer =
  ## Shape and lay out UTF-8 text. NULL denotes invalid input or unsupported
  ## enum values.
  if font == nil or text == nil: return nil
  if align < 0 or align > cint(ord(high(TextAlign))): return nil
  if direction < 0 or direction > cint(ord(high(TextDirection))): return nil
  try:
    let style = textStyle(fontOf(font).f, size, TextDirection(direction))
    let h = LayoutHandle(layout: layoutText(style, $text, maxWidth,
      TextAlign(align)))
    GC_ref(h)
    cast[pointer](h)
  except CatchableError, Defect:
    nil

proc ugly_layout_new_with_options(font: pointer; text: cstring;
    size, maxWidth: float32; align, direction: cint;
    options: ptr UglyTextOptions): pointer =
  if font == nil or text == nil: return nil
  if align < 0 or align > cint(ord(high(TextAlign))): return nil
  if direction < 0 or direction > cint(ord(high(TextDirection))): return nil
  try:
    var style = textStyle(fontOf(font).f, size, TextDirection(direction))
    style.applyOptions(options)
    let h = LayoutHandle(layout: layoutText(style, $text, maxWidth,
      TextAlign(align)))
    GC_ref(h)
    cast[pointer](h)
  except CatchableError, Defect:
    nil

proc ugly_layout_new_family(family: pointer; text: cstring;
    size, maxWidth: float32; align, direction: cint): pointer =
  if family == nil or text == nil: return nil
  if align < 0 or align > cint(ord(high(TextAlign))): return nil
  if direction < 0 or direction > cint(ord(high(TextDirection))): return nil
  try:
    let style = TextStyle(family: familyOf(family).family, size: size,
      direction: TextDirection(direction), tabSize: 4)
    let h = LayoutHandle(layout: layoutText(style, $text, maxWidth,
      TextAlign(align)))
    GC_ref(h)
    cast[pointer](h)
  except CatchableError, Defect:
    nil

proc ugly_layout_new_family_with_options(family: pointer; text: cstring;
    size, maxWidth: float32; align, direction: cint;
    options: ptr UglyTextOptions): pointer =
  if family == nil or text == nil: return nil
  if align < 0 or align > cint(ord(high(TextAlign))): return nil
  if direction < 0 or direction > cint(ord(high(TextDirection))): return nil
  try:
    var style = TextStyle(family: familyOf(family).family, size: size,
      direction: TextDirection(direction), tabSize: 4)
    style.applyOptions(options)
    let h = LayoutHandle(layout: layoutText(style, $text, maxWidth,
      TextAlign(align)))
    GC_ref(h)
    cast[pointer](h)
  except CatchableError, Defect:
    nil

proc ugly_layout_width(h: pointer): float32 =
  if h == nil: 0'f32 else: layoutOf(h).layout.width

proc ugly_layout_height(h: pointer): float32 =
  if h == nil: 0'f32 else: layoutOf(h).layout.height

proc ugly_layout_line_count(h: pointer): csize_t =
  if h == nil: 0 else: csize_t(layoutOf(h).layout.lines.len)

proc ugly_layout_glyph_count(h: pointer): csize_t =
  if h == nil: return 0
  for line in layoutOf(h).layout.lines:
    result += csize_t(line.run.placements.len)

proc ugly_layout_bounds(h: pointer; ink: cint;
    outBounds: ptr UglyBounds): cint =
  if h == nil or outBounds == nil: return UGLY_ERR_FORMAT
  outBounds[] = toC(if ink != 0: layoutOf(h).layout.inkBounds
    else: layoutOf(h).layout.typographicBounds)
  UGLY_OK

proc ugly_layout_glyph(h: pointer; index: csize_t;
    outInfo: ptr UglyGlyphInfo): cint =
  if h == nil or outInfo == nil: return UGLY_ERR_FORMAT
  var current: csize_t
  for lineIndex, line in layoutOf(h).layout.lines:
    var pen = 0'f32
    for placement in line.run.placements:
      if current == index:
        outInfo[] = UglyGlyphInfo(glyph: uint32(placement.glyph),
          faceIndex: cint(placement.faceIndex), lineIndex: cint(lineIndex),
          cluster: cint(placement.cluster), codepoint: cint(
              placement.codepoint),
          x: line.baseline.x + pen + placement.xOffset,
          y: line.baseline.y + placement.yOffset, xAdvance: placement.xAdvance,
          yAdvance: placement.yAdvance, xOffset: placement.xOffset,
          yOffset: placement.yOffset, inkBounds: toC(placement.inkBounds))
        return UGLY_OK
      inc current
      pen += placement.xAdvance
  UGLY_ERR_FORMAT

proc ugly_layout_line(h: pointer; index: csize_t;
    outInfo: ptr UglyLineInfo): cint =
  if h == nil or outInfo == nil or index >= layoutOf(
      h).layout.lines.len.csize_t:
    return UGLY_ERR_FORMAT
  let line = layoutOf(h).layout.lines[int(index)]
  outInfo[] = UglyLineInfo(baselineX: line.baseline.x,
    baselineY: line.baseline.y, advance: line.advance,
    typographicBounds: toC(line.typographicBounds),
    inkBounds: toC(line.inkBounds))
  UGLY_OK

proc ugly_layout_free(h: pointer) =
  if h == nil: return
  swallowAbiFaults: GC_unref(layoutOf(h))

proc ugly_render_layout(img, layout, color: pointer; x, y: float32): cint =
  if img == nil or layout == nil or color == nil: return UGLY_ERR_FORMAT
  try:
    imgOf(img).img.renderLayout(layoutOf(layout).layout, colorOf(color).color,
      vec2(x, y))
    UGLY_OK
  except CatchableError, Defect:
    UGLY_ERR_FORMAT

proc ugly_atlas_new(font: pointer; codepoints: ptr uint32; count: csize_t;
    size: float32; width, padding: cint): pointer =
  if font == nil or (count > 0 and codepoints == nil): return nil
  try:
    var cps = newSeq[int](int(count))
    let input = cast[ptr UncheckedArray[uint32]](codepoints)
    for i in 0 ..< cps.len:
      if input[i] > 0x10FFFF'u32: return nil
      cps[i] = int(input[i])
    let h = AtlasHandle(atlas: buildGlyphAtlas(textStyle(fontOf(font).f, size),
      cps, int(width), int(padding)))
    GC_ref(h)
    cast[pointer](h)
  except CatchableError, Defect:
    nil

proc ugly_atlas_new_family(family: pointer; codepoints: ptr uint32;
    count: csize_t; size: float32; width, padding: cint): pointer =
  if family == nil or (count > 0 and codepoints == nil): return nil
  try:
    var cps = newSeq[int](int(count))
    let input = cast[ptr UncheckedArray[uint32]](codepoints)
    for i in 0 ..< cps.len:
      if input[i] > 0x10FFFF'u32: return nil
      cps[i] = int(input[i])
    let style = TextStyle(family: familyOf(family).family, size: size)
    let h = AtlasHandle(atlas: buildGlyphAtlas(style, cps, int(width),
      int(padding)))
    GC_ref(h)
    cast[pointer](h)
  except CatchableError, Defect:
    nil

proc ugly_atlas_width(h: pointer): cint =
  if h == nil: 0 else: cint(atlasOf(h).atlas.width)

proc ugly_atlas_height(h: pointer): cint =
  if h == nil: 0 else: cint(atlasOf(h).atlas.height)

proc ugly_atlas_entry_count(h: pointer): csize_t =
  if h == nil: 0 else: csize_t(atlasOf(h).atlas.entries.len)

proc ugly_atlas_get_entry(h: pointer; index: csize_t;
    outEntry: ptr UglyAtlasEntry): cint =
  if h == nil or outEntry == nil or index >= atlasOf(
      h).atlas.entries.len.csize_t:
    return UGLY_ERR_FORMAT
  let entry = atlasOf(h).atlas.entries[int(index)]
  outEntry[] = UglyAtlasEntry(glyph: uint32(entry.glyph),
    faceIndex: cint(entry.faceIndex), x: cint(entry.x), y: cint(entry.y),
    width: cint(entry.width), height: cint(entry.height),
    bearingX: entry.bearingX, bearingY: entry.bearingY,
    advance: entry.advance)
  UGLY_OK

proc ugly_atlas_pixels(h: pointer; outPtr: ptr ptr uint8;
    outLen: ptr csize_t): cint =
  if h == nil or outPtr == nil or outLen == nil: return UGLY_ERR_FORMAT
  let atlas = atlasOf(h)
  outLen[] = csize_t(atlas.atlas.pixels.len)
  outPtr[] = if atlas.atlas.pixels.len == 0: nil
    else: cast[ptr uint8](addr atlas.atlas.pixels[0])
  UGLY_OK

proc ugly_atlas_free(h: pointer) =
  if h == nil: return
  swallowAbiFaults: GC_unref(atlasOf(h))

proc ugly_render_text(img: pointer; font: pointer; text: cstring;
    size: float32; x, y: float32; color: pointer): cint =
  ## Lay out `text` single-line LTR at `size` px with baseline origin `(x, y)`
  ## and solid-fill the combined glyph path with `color` onto `img` (RGBA8,
  ## NonZero winding). `UGLY_OK` on success, `UGLY_ERR_FORMAT` on a nil handle
  ## or text.
  if img == nil or font == nil or text == nil or color == nil:
    return UGLY_ERR_FORMAT
  if size <= 0'f32: return UGLY_ERR_FORMAT
  try:
    let f = fontOf(font).f
    let baseline = vec2(x, y)
    let ts = typeset(f, $text, size, baseline)
    let path = ts.combinedPath
    fillPath(imgOf(img).img, path, colorOf(color).color, NonZero)
    UGLY_OK
  except CatchableError, Defect:
    UGLY_ERR_FORMAT

# ------------------------------- buffer -------------------------------------

proc ugly_buffer_free(p: pointer; len: csize_t) =
  ## Free a buffer returned by `ugly_image_encode_png`. NULL is a no-op. `len`
  ## is ignored (kept for symmetry with the allocator). Do NOT use on
  ## `ugly_image_pixels`.
  if p == nil: return
  swallowAbiFaults: deallocShared(p)

{.pop.}
