# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
"""Build uniglyph._core, a Cython extension over the UniGlyph C ABI.
Run `nimble pyLib` first so the library is at the repo root."""
import os
import shutil
import sys

from setuptools import Extension, setup
from setuptools.command.build_ext import build_ext as _build_ext
from setuptools.command.sdist import sdist as _sdist
from Cython.Build import cythonize

HERE = os.path.dirname(os.path.abspath(__file__))
CHECKOUT_ROOT = os.path.dirname(HERE)
ROOT = os.environ.get("UNIGLYPH_ROOT", CHECKOUT_ROOT)
CHECKOUT_INCLUDE = os.path.join(ROOT, "include")
SDIST_INCLUDE = os.path.join(HERE, "include")
DIST_LICENSES = os.path.join(HERE, "licenses")
INCLUDE = CHECKOUT_INCLUDE if os.path.exists(CHECKOUT_INCLUDE) else SDIST_INCLUDE
LIB_DIR = os.environ.get("UNIGLYPH_LIB_DIR", ROOT)
PKG_DIR = os.path.join(HERE, "uniglyph")


def sync_distribution_files():
    """Copy canonical repository legal/header files into the Python source."""
    os.makedirs(SDIST_INCLUDE, exist_ok=True)
    source_header = os.path.join(CHECKOUT_ROOT, "include", "UniGlyph.h")
    bundled_header = os.path.join(SDIST_INCLUDE, "UniGlyph.h")
    if os.path.exists(source_header):
        shutil.copy2(source_header, bundled_header)
    elif not os.path.exists(bundled_header):
        raise SystemExit("setup.py: canonical or bundled UniGlyph.h not found")
    os.makedirs(DIST_LICENSES, exist_ok=True)
    for name in ("LICENSE", "NOTICE"):
        source = os.path.join(CHECKOUT_ROOT, name)
        bundled = os.path.join(DIST_LICENSES, name)
        if os.path.exists(source):
            shutil.copy2(source, bundled)
        elif not os.path.exists(bundled):
            raise SystemExit(f"setup.py: canonical or bundled {name} not found")


sync_distribution_files()

# Windows: link a vcc static lib, since MSVC CPython cannot link MinGW output.
# Elsewhere: bundle the shared lib in the package, found through an rpath
# relative to the extension. macOS rejects distutils' -R, hence extra_link_args.
if sys.platform == "win32":
    LIB_NAME, BUNDLED = "UniGlyph.lib", False
    RUNTIME_DIRS, LINK_ARGS, NIMBLE_TASK = [], [], "clibMsvc"
elif sys.platform == "darwin":
    LIB_NAME, BUNDLED = "libUniGlyph.dylib", True
    RUNTIME_DIRS, LINK_ARGS, NIMBLE_TASK = [], ["-Wl,-rpath,@loader_path"], "clib"
else:
    LIB_NAME, BUNDLED = "libUniGlyph.so", True
    RUNTIME_DIRS, LINK_ARGS, NIMBLE_TASK = ["$ORIGIN"], [], "clib"


class build_ext_with_lib(_build_ext):
    """Copy the shared library into the package dir before linking."""

    def run(self):
        src = os.path.join(LIB_DIR, LIB_NAME)
        if not os.path.exists(src):
            raise SystemExit(
                f"setup.py: {src} not found — run `nimble {NIMBLE_TASK}` first."
            )
        if BUNDLED:
            os.makedirs(PKG_DIR, exist_ok=True)
            shutil.copy2(src, os.path.join(PKG_DIR, LIB_NAME))
        super().run()


class sdist_with_header(_sdist):
    """Include the public ABI header while keeping one checkout source."""

    def run(self):
        sync_distribution_files()
        super().run()


ext = Extension(
    "uniglyph._core",
    sources=[os.path.join("uniglyph", "_core.pyx")],
    include_dirs=[INCLUDE],
    library_dirs=[LIB_DIR],
    runtime_library_dirs=RUNTIME_DIRS,
    extra_link_args=LINK_ARGS,
    libraries=["UniGlyph"],
)

setup(
    ext_modules=cythonize([ext], language_level=3),
    cmdclass={"build_ext": build_ext_with_lib, "sdist": sdist_with_header},
    include_package_data=True,
    package_data={"uniglyph": [LIB_NAME]
                  if BUNDLED and "sdist" not in sys.argv else []},
    exclude_package_data={"uniglyph": ["_core.c"]},
    zip_safe=False,
)
