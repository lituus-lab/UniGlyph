# cython: language_level=3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
"""Cython binding over the UniGlyph C ABI (glyph/text engine)."""
from libc.stddef cimport size_t
from libc.stdint cimport uint8_t, uint32_t
from libc.stdlib cimport free, malloc


cdef extern from "UniGlyph.h":
    const char *ugly_version()
    void   ugly_init()
    int    ugly_abi_version()
    uint32_t ugly_capabilities()
    const char *ugly_strerror(int code)

    # Opaque, library-owned handles (incomplete structs in the header).
    ctypedef struct ugly_font
    ctypedef struct ugly_family
    ctypedef struct ugly_image
    ctypedef struct ugly_color
    ctypedef struct ugly_layout
    ctypedef struct ugly_atlas
    ctypedef struct ugly_bounds:
        float x_min
        float y_min
        float x_max
        float y_max
    ctypedef struct ugly_glyph_info:
        uint32_t glyph
        int face_index
        int line_index
        int cluster
        int codepoint
        float x
        float y
        float x_advance
        float y_advance
        float x_offset
        float y_offset
        ugly_bounds ink_bounds
    ctypedef struct ugly_line_info:
        float baseline_x
        float baseline_y
        float advance
        ugly_bounds typographic_bounds
        ugly_bounds ink_bounds
    ctypedef struct ugly_text_options:
        float letter_spacing
        float word_spacing
        float line_height
        int tab_size
    ctypedef struct ugly_atlas_entry_info:
        uint32_t glyph
        int face_index
        int x
        int y
        int width
        int height
        float bearing_x
        float bearing_y
        float advance

    ugly_font  *ugly_font_load(const char *path)
    int   ugly_font_ascent(ugly_font *f)
    int   ugly_font_descent(ugly_font *f)
    int   ugly_font_units_per_em(ugly_font *f)
    int   ugly_font_line_gap(ugly_font *f)
    int   ugly_font_num_glyphs(ugly_font *f)
    uint32_t ugly_font_glyph_id(ugly_font *f, uint32_t codepoint)
    int   ugly_font_has_glyph(ugly_font *f, uint32_t codepoint)
    uint32_t ugly_font_advance(ugly_font *f, uint32_t glyph)
    int   ugly_font_kerning(ugly_font *f, uint32_t left, uint32_t right)
    int   ugly_font_identity(ugly_font *f, uint8_t *out_identity)
    float ugly_font_line_height(ugly_font *f, float size)
    void  ugly_font_free(ugly_font *f)
    ugly_family *ugly_family_new(ugly_font *font)
    int ugly_family_add(ugly_family *family, ugly_font *font)
    size_t ugly_family_count(ugly_family *family)
    void ugly_family_free(ugly_family *family)

    ugly_image *ugly_image_new(int width, int height)
    int   ugly_image_width(ugly_image *img)
    int   ugly_image_height(ugly_image *img)
    int   ugly_image_channels(ugly_image *img)
    int   ugly_image_pixels(ugly_image *img, unsigned char **out_ptr,
                            size_t *out_len)
    int   ugly_image_encode_png(ugly_image *img, unsigned char **out_data,
                                size_t *out_len)
    void  ugly_image_free(ugly_image *img)

    ugly_color *ugly_color_parse(const char *s)
    ugly_color *ugly_color_rgba(float r, float g, float b, float a)
    void  ugly_color_free(ugly_color *c)

    float ugly_text_width(ugly_font *f, const char *text, float size)
    ugly_layout *ugly_layout_new(ugly_font *font, const char *text, float size,
                                 float max_width, int align, int direction)
    ugly_layout *ugly_layout_new_family(ugly_family *family, const char *text,
                                        float size, float max_width, int align,
                                        int direction)
    ugly_layout *ugly_layout_new_with_options(
        ugly_font *font, const char *text, float size, float max_width,
        int align, int direction, const ugly_text_options *options)
    ugly_layout *ugly_layout_new_family_with_options(
        ugly_family *family, const char *text, float size, float max_width,
        int align, int direction, const ugly_text_options *options)
    float ugly_layout_width(ugly_layout *layout)
    float ugly_layout_height(ugly_layout *layout)
    size_t ugly_layout_line_count(ugly_layout *layout)
    size_t ugly_layout_glyph_count(ugly_layout *layout)
    int ugly_layout_bounds(ugly_layout *layout, int ink, ugly_bounds *out_bounds)
    int ugly_layout_glyph(ugly_layout *layout, size_t index,
                          ugly_glyph_info *out_info)
    int ugly_layout_line(ugly_layout *layout, size_t index,
                         ugly_line_info *out_info)
    void ugly_layout_free(ugly_layout *layout)
    int ugly_render_layout(ugly_image *img, ugly_layout *layout,
                           ugly_color *color, float x, float y)
    int   ugly_render_text(ugly_image *img, ugly_font *f, const char *text,
                           float size, float x, float y, ugly_color *color)
    void  ugly_buffer_free(void *p, size_t len)
    ugly_atlas *ugly_atlas_new(ugly_font *font, const uint32_t *codepoints,
                               size_t count, float size, int width, int padding)
    ugly_atlas *ugly_atlas_new_family(ugly_family *family,
                                      const uint32_t *codepoints,
                                      size_t count, float size, int width,
                                      int padding)
    int ugly_atlas_width(ugly_atlas *atlas)
    int ugly_atlas_height(ugly_atlas *atlas)
    size_t ugly_atlas_entry_count(ugly_atlas *atlas)
    int ugly_atlas_get_entry(ugly_atlas *atlas, size_t index,
                             ugly_atlas_entry_info *out_entry)
    int ugly_atlas_pixels(ugly_atlas *atlas, const unsigned char **out_ptr,
                          size_t *out_len)
    void ugly_atlas_free(ugly_atlas *atlas)


cdef str _borrow_cstr(const char* s):
    if s == NULL:
        return ""
    return (<bytes>s).decode("ascii")


def init():
    """Idempotent NimMain bootstrap; call once before any other entry."""
    ugly_init()


def version():
    return _borrow_cstr(ugly_version())


def abi_version():
    return ugly_abi_version()


def capabilities():
    """Implemented shaping capability bitset (UGLY_CAP_* in UniGlyph.h)."""
    return ugly_capabilities()


def strerror(int code):
    return _borrow_cstr(ugly_strerror(code))


cdef class Font:
    """A loaded TrueType font. The library owns the handle; freed on GC."""
    cdef ugly_font *_h

    def __cinit__(self):
        self._h = NULL

    def __dealloc__(self):
        if self._h != NULL:
            ugly_font_free(self._h)
            self._h = NULL

    @staticmethod
    cdef Font _wrap(ugly_font *h):
        # __new__ bypasses __init__ (which needs a path); __cinit__ zeroes _h.
        cdef Font r = Font.__new__(Font)
        r._h = h
        return r

    def __init__(self, str path):
        cdef bytes b = path.encode("utf-8")
        self._h = ugly_font_load(<const char*>b)
        if self._h == NULL:
            raise FileNotFoundError(f"failed to load font: {path!r}")

    @property
    def ascent(self):
        return ugly_font_ascent(self._h)

    @property
    def descent(self):
        return ugly_font_descent(self._h)

    @property
    def units_per_em(self):
        return ugly_font_units_per_em(self._h)

    @property
    def line_gap(self):
        return ugly_font_line_gap(self._h)

    @property
    def num_glyphs(self):
        return ugly_font_num_glyphs(self._h)

    def glyph_id(self, int codepoint):
        if codepoint < 0 or codepoint > 0x10FFFF:
            raise ValueError("codepoint outside Unicode range")
        return ugly_font_glyph_id(self._h, <uint32_t>codepoint)

    def has_glyph(self, int codepoint):
        if codepoint < 0 or codepoint > 0x10FFFF:
            return False
        return bool(ugly_font_has_glyph(self._h, <uint32_t>codepoint))

    def advance(self, int glyph):
        if glyph < 0:
            raise ValueError("glyph must be non-negative")
        return ugly_font_advance(self._h, <uint32_t>glyph)

    def kerning(self, int left, int right):
        if left < 0 or right < 0:
            raise ValueError("glyph ids must be non-negative")
        return ugly_font_kerning(self._h, <uint32_t>left, <uint32_t>right)

    def line_height(self, float size):
        return ugly_font_line_height(self._h, size)

    @property
    def identity(self):
        """BLAKE3-256 identity of the exact source font bytes."""
        cdef uint8_t digest[32]
        if ugly_font_identity(self._h, digest) != 0:
            raise ValueError("failed to read font identity")
        return (<char *>digest)[:32]

    @property
    def identity_hex(self):
        return self.identity.hex()

    def text_width(self, str text, float size):
        cdef bytes b = text.encode("utf-8")
        return ugly_text_width(self._h, <const char*>b, size)


cdef class Image:
    """An RGBA8 raster surface. The library owns the handle; freed on GC."""
    cdef ugly_image *_h

    def __cinit__(self):
        self._h = NULL

    def __dealloc__(self):
        if self._h != NULL:
            ugly_image_free(self._h)
            self._h = NULL

    @staticmethod
    cdef Image _wrap(ugly_image *h):
        cdef Image r = Image.__new__(Image)
        r._h = h
        return r

    def __init__(self, int width, int height):
        if width <= 0 or height <= 0:
            raise ValueError("width and height must be positive")
        self._h = ugly_image_new(width, height)
        if self._h == NULL:
            raise MemoryError("ugly_image_new returned NULL")

    @property
    def width(self):
        return ugly_image_width(self._h)

    @property
    def height(self):
        return ugly_image_height(self._h)

    @property
    def channels(self):
        return ugly_image_channels(self._h)

    def pixels(self):
        """The pixel buffer as bytes (a copy). RGBA8, row-major."""
        cdef unsigned char *out = NULL
        cdef size_t out_len = 0
        rc = ugly_image_pixels(self._h, &out, &out_len)
        if rc != 0:
            raise ValueError(f"pixels failed: {strerror(rc)}")
        if out == NULL or out_len == 0:
            return b""
        return bytes(<unsigned char[:out_len]>out)

    def encode_png(self):
        """Encode as PNG bytes."""
        cdef unsigned char *out = NULL
        cdef size_t out_len = 0
        rc = ugly_image_encode_png(self._h, &out, &out_len)
        if rc != 0:
            raise ValueError(f"encode_png failed: {strerror(rc)}")
        try:
            return bytes(<unsigned char[:out_len]>out)
        finally:
            ugly_buffer_free(out, out_len)


cdef class FontFamily:
    """Ordered fallback family retaining its font faces."""
    cdef ugly_family *_h

    def __cinit__(self):
        self._h = NULL

    def __dealloc__(self):
        if self._h != NULL:
            ugly_family_free(self._h)
            self._h = NULL

    def __init__(self, Font first, *fallback):
        self._h = ugly_family_new(first._h)
        if self._h == NULL:
            raise MemoryError("failed to allocate font family")
        for face in fallback:
            if not isinstance(face, Font):
                raise TypeError("fallback entries must be Font instances")
            if ugly_family_add(self._h, (<Font>face)._h) != 0:
                raise MemoryError("failed to extend font family")

    def add(self, Font font):
        if ugly_family_add(self._h, font._h) != 0:
            raise MemoryError("failed to extend font family")

    def __len__(self):
        return ugly_family_count(self._h)

cdef class Color:
    """A color (tagged space; the ABI exposes sRGB construction)."""
    cdef ugly_color *_h

    def __cinit__(self):
        self._h = NULL

    def __dealloc__(self):
        if self._h != NULL:
            ugly_color_free(self._h)
            self._h = NULL

    @staticmethod
    cdef Color _wrap(ugly_color *h):
        cdef Color r = Color.__new__(Color)
        r._h = h
        return r

    @staticmethod
    def parse(str s):
        """Parse a CSS Color 4 string (hex/rgb/oklch/...)."""
        cdef bytes b = s.encode("utf-8")
        cdef ugly_color *h = ugly_color_parse(<const char*>b)
        if h == NULL:
            raise ValueError(f"color parse failed: {s!r}")
        return Color._wrap(h)

    @staticmethod
    def rgba(float r, float g, float b, float a=1.0):
        """sRGB color from straight-alpha floats in [0, 1]."""
        cdef ugly_color *h = ugly_color_rgba(r, g, b, a)
        if h == NULL:
            raise ValueError("color rgba out of gamut / non-finite")
        return Color._wrap(h)


cdef class Layout:
    """Renderer-neutral shaped and measured text block."""
    cdef ugly_layout *_h

    def __cinit__(self):
        self._h = NULL

    def __dealloc__(self):
        if self._h != NULL:
            ugly_layout_free(self._h)
            self._h = NULL

    def __init__(self, source, str text, float size, float max_width=0.0,
                 int align=0, int direction=0, float letter_spacing=0.0,
                 float word_spacing=0.0, float line_height=0.0,
                 int tab_size=4):
        cdef bytes encoded = text.encode("utf-8")
        cdef ugly_text_options options
        options.letter_spacing = letter_spacing
        options.word_spacing = word_spacing
        options.line_height = line_height
        options.tab_size = tab_size
        if isinstance(source, Font):
            self._h = ugly_layout_new_with_options(
                (<Font>source)._h, <const char*>encoded, size, max_width,
                align, direction, &options)
        elif isinstance(source, FontFamily):
            self._h = ugly_layout_new_family_with_options(
                (<FontFamily>source)._h, <const char*>encoded, size,
                max_width, align, direction, &options)
        else:
            raise TypeError("source must be Font or FontFamily")
        if self._h == NULL:
            raise ValueError("invalid text layout arguments")

    @property
    def width(self):
        return ugly_layout_width(self._h)

    @property
    def height(self):
        return ugly_layout_height(self._h)

    @property
    def line_count(self):
        return ugly_layout_line_count(self._h)

    def bounds(self, bint ink=False):
        cdef ugly_bounds bounds
        cdef int rc = ugly_layout_bounds(self._h, int(ink), &bounds)
        if rc != 0:
            raise ValueError(f"layout bounds failed: {strerror(rc)}")
        return (bounds.x_min, bounds.y_min, bounds.x_max, bounds.y_max)

    def glyphs(self):
        cdef size_t count = ugly_layout_glyph_count(self._h)
        cdef size_t i
        cdef ugly_glyph_info info
        result = []
        for i in range(count):
            if ugly_layout_glyph(self._h, i, &info) != 0:
                raise ValueError("layout glyph lookup failed")
            result.append({"glyph": info.glyph, "face_index": info.face_index,
                           "line_index": info.line_index,
                           "cluster": info.cluster, "codepoint": info.codepoint,
                           "x": info.x, "y": info.y,
                           "x_advance": info.x_advance,
                           "y_advance": info.y_advance,
                           "x_offset": info.x_offset,
                           "y_offset": info.y_offset,
                           "ink_bounds": (info.ink_bounds.x_min,
                                          info.ink_bounds.y_min,
                                          info.ink_bounds.x_max,
                                          info.ink_bounds.y_max)})
        return result

    def lines(self):
        cdef size_t count = ugly_layout_line_count(self._h)
        cdef size_t i
        cdef ugly_line_info info
        result = []
        for i in range(count):
            if ugly_layout_line(self._h, i, &info) != 0:
                raise ValueError("layout line lookup failed")
            result.append({"baseline": (info.baseline_x, info.baseline_y),
                           "advance": info.advance,
                           "typographic_bounds": (
                               info.typographic_bounds.x_min,
                               info.typographic_bounds.y_min,
                               info.typographic_bounds.x_max,
                               info.typographic_bounds.y_max),
                           "ink_bounds": (info.ink_bounds.x_min,
                                          info.ink_bounds.y_min,
                                          info.ink_bounds.x_max,
                                          info.ink_bounds.y_max)})
        return result

    def render_to(self, Image image, Color color, float x=0.0, float y=0.0):
        cdef int rc = ugly_render_layout(image._h, self._h, color._h, x, y)
        if rc != 0:
            raise ValueError(f"render layout failed: {strerror(rc)}")


cdef class Atlas:
    """RGBA8 glyph atlas with renderer-neutral entry metadata."""
    cdef ugly_atlas *_h

    def __cinit__(self):
        self._h = NULL

    def __dealloc__(self):
        if self._h != NULL:
            ugly_atlas_free(self._h)
            self._h = NULL

    def __init__(self, source, codepoints, float size, int width=1024,
                 int padding=1):
        cdef size_t count
        cdef uint32_t *raw = NULL
        cdef size_t i
        values = list(codepoints)
        count = len(values)
        if count > 0:
            raw = <uint32_t*>malloc(count * sizeof(uint32_t))
            if raw == NULL:
                raise MemoryError()
        try:
            for i in range(count):
                value = int(values[i])
                if value < 0 or value > 0x10FFFF:
                    raise ValueError("codepoint outside Unicode range")
                raw[i] = <uint32_t>value
            if isinstance(source, Font):
                self._h = ugly_atlas_new((<Font>source)._h, raw, count, size,
                                         width, padding)
            elif isinstance(source, FontFamily):
                self._h = ugly_atlas_new_family((<FontFamily>source)._h, raw,
                                                count, size, width, padding)
            else:
                raise TypeError("source must be Font or FontFamily")
        finally:
            free(raw)
        if self._h == NULL:
            raise ValueError("invalid glyph atlas arguments")

    @property
    def width(self):
        return ugly_atlas_width(self._h)

    @property
    def height(self):
        return ugly_atlas_height(self._h)

    def entries(self):
        cdef size_t count = ugly_atlas_entry_count(self._h)
        cdef size_t i
        cdef ugly_atlas_entry_info entry
        result = []
        for i in range(count):
            if ugly_atlas_get_entry(self._h, i, &entry) != 0:
                raise ValueError("atlas entry lookup failed")
            result.append({"glyph": entry.glyph, "face_index": entry.face_index,
                           "x": entry.x, "y": entry.y, "width": entry.width,
                           "height": entry.height, "bearing_x": entry.bearing_x,
                           "bearing_y": entry.bearing_y,
                           "advance": entry.advance})
        return result

    def pixels(self):
        cdef const unsigned char *out = NULL
        cdef size_t out_len = 0
        cdef int rc = ugly_atlas_pixels(self._h, &out, &out_len)
        if rc != 0:
            raise ValueError(f"atlas pixels failed: {strerror(rc)}")
        if out == NULL or out_len == 0:
            return b""
        return bytes(<const unsigned char[:out_len]>out)

def render_text(Image img, Font font, str text, float size,
                float x, float y, Color color):
    """Lay out `text` single-line LTR at `size` px with baseline origin (x, y)
    and solid-fill the combined glyph path with `color` onto `img` (RGBA8)."""
    cdef bytes b = text.encode("utf-8")
    rc = ugly_render_text(img._h, font._h, <const char*>b, size, x, y, color._h)
    if rc != 0:
        raise ValueError(f"render_text failed: {strerror(rc)}")
