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
  ImgHandle = ref object
    img: uimg.Image[uint8]
  ColorHandle = ref object
    color: Color

proc NimMain() {.importc.}

proc fontOf(p: pointer): FontHandle {.inline.} = cast[FontHandle](p)
proc imgOf(p: pointer): ImgHandle {.inline.} = cast[ImgHandle](p)
proc colorOf(p: pointer): ColorHandle {.inline.} = cast[ColorHandle](p)

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

proc ugly_font_line_height(h: pointer; size: float32): float32 =
  ## Scaled line height (ascent - descent + lineGap) at `size` px.
  if h == nil: return 0'f32
  try: fontOf(h).f.lineHeight(size)
  except CatchableError, Defect: 0'f32

proc ugly_font_free(h: pointer) =
  if h == nil: return
  swallowAbiFaults: GC_unref(fontOf(h))

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
  ## Total advance width of `text` at `size` px (no kerning). 0 on a nil handle
  ## or text.
  if h == nil or text == nil: return 0'f32
  try: textWidth(fontOf(h).f, $text, size)
  except CatchableError, Defect: 0'f32

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
