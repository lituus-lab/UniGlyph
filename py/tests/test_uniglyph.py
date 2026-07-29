# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
"""Self-contained pytest over the ugly_* Cython surface (no fixture)."""
import uniglyph


def test_version():
    assert uniglyph.version() == "0.1.0"
    assert uniglyph.__version__ == "0.1.0"


def test_abi_version():
    assert uniglyph.abi_version() == 1


def test_strerror_ok():
    assert uniglyph.strerror(0) == "ok"