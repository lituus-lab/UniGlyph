# cython: language_level=3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
"""Cython binding over the UniGlyph C ABI (glyph/text engine)."""
from libc.stddef cimport size_t


cdef extern from "UniGlyph.h":
    const char *ugly_version()
    void   ugly_init()
    int    ugly_abi_version()
    const char *ugly_strerror(int code)

    # Opaque, library-owned handles (incomplete structs in the header).
    ctypedef struct ugly_font
    ctypedef struct ugly_image
    ctypedef struct ugly_color

    ugly_font  *ugly_font_load(const char *path)
    int   ugly_font_ascent(ugly_font *f)
    int   ugly_font_descent(ugly_font *f)
    float ugly_font_line_height(ugly_font *f, float size)
    void  ugly_font_free(ugly_font *f)

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
    int   ugly_render_text(ugly_image *img, ugly_font *f, const char *text,
                           float size, float x, float y, ugly_color *color)
    void  ugly_buffer_free(void *p, size_t len)


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

    def line_height(self, float size):
        return ugly_font_line_height(self._h, size)

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


def render_text(Image img, Font font, str text, float size,
                float x, float y, Color color):
    """Lay out `text` single-line LTR at `size` px with baseline origin (x, y)
    and solid-fill the combined glyph path with `color` onto `img` (RGBA8)."""
    cdef bytes b = text.encode("utf-8")
    rc = ugly_render_text(img._h, font._h, <const char*>b, size, x, y, color._h)
    if rc != 0:
        raise ValueError(f"render_text failed: {strerror(rc)}")