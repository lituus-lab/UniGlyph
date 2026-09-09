# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
"""Prove an installed `uniglyph` wheel stands on its own.

`test_uniglyph.py` is the full suite and needs a font, which it takes from
UNIGLYPH_TEST_FONT or from a path relative to the checkout. This module is
copied to a neutral directory and run there, so it may lean on nothing but the
wheel.

The import happens in a child process: importing at module level puts the whole
session at the mercy of a native fault, and pytest captures stdout and stderr
during collection, losing the buffer when the process dies. A child hands back
its own output and exit status, so a crash is reported instead of swallowed.
"""
import subprocess
import sys
import textwrap


def run_in_child(body):
    """Run `body` in a fresh interpreter, returning it whole for assertions."""
    return subprocess.run(
        [sys.executable, "-c", textwrap.dedent(body)],
        capture_output=True, text=True, timeout=120)


def describe(done):
    return (f"exit {done.returncode}\n"
            f"--- stdout ---\n{done.stdout}\n"
            f"--- stderr ---\n{done.stderr}")


def test_the_package_imports_at_all():
    done = run_in_child("""
        import faulthandler
        faulthandler.enable()
        import uniglyph
        print("imported")
    """)
    assert done.returncode == 0, describe(done)
    assert "imported" in done.stdout, describe(done)


def test_the_engine_answers_through_the_bundled_library():
    done = run_in_child("""
        import faulthandler
        faulthandler.enable()
        import uniglyph
        print(uniglyph.version())
        print(uniglyph.abi_version())
    """)
    assert done.returncode == 0, describe(done)
    version, abi = done.stdout.split()
    assert version
    assert int(abi) > 0


def test_capabilities_and_errors_come_from_the_engine():
    # Both cross into the shared library rather than stopping at the extension.
    done = run_in_child("""
        import faulthandler
        faulthandler.enable()
        import uniglyph
        print(bool(uniglyph.capabilities() & uniglyph.Capability.NOMINAL_MAPPING))
        print(uniglyph.strerror(0))
    """)
    assert done.returncode == 0, describe(done)
    nominal, message = done.stdout.split("\n")[:2]
    assert nominal == "True", describe(done)
    assert message == "ok", describe(done)


def test_an_image_is_allocated_and_encodes_a_png():
    # No font needed: the raster and the PNG codec are the library's own.
    done = run_in_child("""
        import faulthandler
        faulthandler.enable()
        import uniglyph
        image = uniglyph.Image(8, 4)
        png = image.encode_png()
        print(image.width, image.height, image.channels)
        print(png[:4] == b"\\x89PNG", len(png) > 0)
    """)
    assert done.returncode == 0, describe(done)
    shape, png = done.stdout.split("\n")[:2]
    assert shape == "8 4 4", describe(done)
    assert png == "True True", describe(done)


def test_a_missing_font_is_refused_rather_than_crashing():
    done = run_in_child("""
        import faulthandler
        faulthandler.enable()
        import uniglyph
        try:
            uniglyph.Font("no/such/font.ttf")
        except FileNotFoundError as failure:
            print("refused:", type(failure).__name__)
    """)
    assert done.returncode == 0, describe(done)
    assert done.stdout.startswith("refused: FileNotFoundError"), describe(done)
