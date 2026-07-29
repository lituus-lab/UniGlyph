# cython: language_level=3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
"""Cython binding over the UniGlyph C ABI (glyph/text engine)."""
cdef extern from "UniGlyph.h":
    int          ugly_init()
    const char  *ugly_version()
    int          ugly_abi_version()
    const char  *ugly_strerror(int code)


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