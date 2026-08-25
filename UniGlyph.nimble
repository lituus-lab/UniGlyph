# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
# UniGlyph — glyph/text engine for the lituus-lab Uni* family.
version       = "1.0.0"
author        = "lituus-lab"
description   = "Glyph/text engine for the lituus-lab Uni* family (Nim + C-ABI + Python)"
license       = "Apache-2.0"
srcDir        = "src"

requires "nim >= 2.0.0"
requires "https://github.com/lbartoletti/NimContracts#main"
requires "https://github.com/lituus-lab/UniLinalg#main"
requires "https://github.com/lituus-lab/UniColor#main"
requires "https://github.com/lituus-lab/UniImage#main"
requires "https://github.com/lituus-lab/UniVector#main"
requires "https://github.com/lituus-lab/UniCrypto#main"

task lint, "Fail if nimpretty would reformat a source":
  exec "nim c -r --hints:off -o:build/lint_tool tools/lint.nim"

task checkVGraph, "Fail on an import that climbs the layers in vgraph.cfg":
  exec "nim c -r --hints:off -o:build/vgraph_tool tools/vgraph.nim"

task docsDeps, "Install the docs toolchain (nimib)":
  exec "nimble install -y nimib"

task book, "Build the nimib book (needs nimib)":
  # nimib compiles and runs the book's code blocks: a drift fails the build.
  exec "nim c -r --path:src --hints:off -o:build/book book/index.nim"

task docs, "API reference + book into pages/ — what CI publishes":
  rmDir "pages"
  # Generate each public module explicitly. `--project` forces a JS search
  # index and fails on Nim distributions (notably Homebrew) that omit the
  # compiler's optional tools/dochack source.
  for module in ["common", "tables", "font", "glyph", "shaping", "layout",
      "atlas", "render"]:
    exec "nim doc --index:off --outdir:pages/api --hints:off src/UniGlyph/" &
         module & ".nim"
  exec "nim doc --index:off --outdir:pages/api --hints:off src/UniGlyph.nim"
  exec "nimble book"
  # The book is the landing page; the generated reference sits under api/.
  cpFile "book/index.html", "pages/index.html"

# One entry per Nim test so every task (test, testRelease, testCi*,
# coverage) compiles the same set from a single source of truth.
const testBins = [
  ("test_version", "test_version"),
  ("test_tables", "test_tables"),
  ("test_font", "test_font"),
  ("test_glyph", "test_glyph"),
  ("test_layout", "test_layout"),
  ("test_atlas", "test_atlas"),
  ("test_render", "test_render"),
]

task test, "Nim tests (debug, contracts active)":
  for (name, src) in testBins:
    exec "nim c -r --path:src -o:build/" & name & " tests/" & src & ".nim"

task testRelease, "Nim tests (release, contracts compiled away)":
  for (name, src) in testBins:
    exec "nim c -r -d:release --path:src -o:build/" & name & "_rel tests/" & src & ".nim"

task testCi, "Nim tests (CI subset, debug)":
  for (name, src) in testBins:
    exec "nim c -r --path:src -o:build/" & name & " tests/" & src & ".nim"

task testCiRelease, "Nim tests (CI subset, release)":
  for (name, src) in testBins:
    exec "nim c -r -d:release --path:src -o:build/" & name & "_rel tests/" & src & ".nim"

task testAll, "debug + release + C ABI":
  exec "nimble test"
  exec "nimble testRelease"
  exec "nimble ctest"

task example, "Nim demo (print-only; no file I/O)":
  exec "nim c -r --path:src -o:build/demo examples/demo.nim"

task benchmarkIdentity, "Benchmark font parsing and cached content identity":
  exec "nim c -r -d:release --path:src -o:build/benchmark_font_identity" &
       " benchmarks/benchmark_font_identity.nim"

task uniglyph, "Build the uniglyph CLI (render text to PNG + SVG)":
  exec "nim c --path:src -o:bin/uniglyph bin/uniglyph_cli.nim"

# Nim takes `-o:` literally and appends no platform extension.
const
  sharedLib =
    when defined(windows): "libUniGlyph.dll"
    elif defined(macosx): "libUniGlyph.dylib"
    else: "libUniGlyph.so"
  staticLib = "libUniGlyph.a"  # MinGW `ar` on Windows, so `.a` everywhere.

  # @rpath install_name, so the copy bundled in the wheel is found at import.
  macArgs =
    when defined(macosx): " --passL:\"-Wl,-install_name,@rpath/" & sharedLib & "\""
    else: ""

task clib, "C shared library":
  exec "nim c --app:lib --noMain --mm:arc -d:release -o:" & sharedLib & macArgs &
       " src/UniGlyph/c_api.nim"

task clibStatic, "C static library":
  exec "nim c --app:staticlib -d:staticNoAutoInit --noMain --mm:arc -d:release -o:" & staticLib &
       " src/UniGlyph/c_api.nim"

task clibMsvc, "C static library, MSVC ABI (Windows Python extension)":
  # CPython on Windows is MSVC-built and cannot link MinGW output. MSVC's
  # linker takes the lib name verbatim (no `lib` prefix, unlike MinGW), so the
  # output is `UniGlyph.lib` — the intentional exception to the sharedLib /
  # staticLib naming. setup.py's Windows branch matches: `LIB_NAME =
  # "UniGlyph.lib"` and `libraries=["UniGlyph"]`.
  exec "nim c --cc:vcc --app:staticlib -d:staticNoAutoInit --noMain --mm:arc -d:release" &
       " -o:UniGlyph.lib src/UniGlyph/c_api.nim"

# Nim's MinGW toolchain names it mingw32-make.
let makeExe = if findExe("mingw32-make").len > 0: "mingw32-make" else: "make"

# `make -C`, not `cd dir && make`: nimble's exec runs no shell on Windows.
task ctest, "C ABI tests":
  exec "nimble clibStatic"
  exec makeExe & " -C tests/c"

task cexample, "C demo (print-only consumer of the ugly_* ABI)":
  exec "nimble clibStatic"
  exec makeExe & " -C examples/c"

task pyDeps, "Install Python build deps (setuptools, Cython, pytest) if missing":
  exec "python3 -m pip install --break-system-packages --quiet setuptools wheel \"Cython>=3.0.0\" pytest"

# The extension links the vcc static lib on Windows, the shared lib elsewhere.
task pyLib, "Build the library the Python extension links against":
  when defined(windows):
    exec "nimble clibMsvc"
  else:
    exec "nimble clib"

task buildCython, "Cython extension in-place":
  exec "nimble pyLib"
  exec "nimble pyDeps"
  # nimscript `cd` (lib/system/nimscript.nim) changes the VM cwd for the next
  # exec without a shell, so the task works under nimble's no-shell exec on Windows.
  cd "py"
  exec "python3 setup.py build_ext --inplace"
  cd ".."

task pyTest, "Cython extension + pytest":
  exec "nimble buildCython"
  cd "py"
  exec "python3 -m pytest -q"
  cd ".."

task pyWheel, "wheel":
  exec "nimble pyLib"
  exec "nimble pyDeps"
  cd "py"
  exec "python3 -m pip wheel --no-deps --no-build-isolation --wheel-dir dist ."
  cd ".."

task pySdist, "Python source distribution":
  exec "nimble pyLib"
  exec "nimble pyDeps"
  cd "py"
  exec "python3 setup.py sdist"
  cd ".."

task coverage, "LCOV + HTML coverage report for the Nim sources (needs lcov)":
  # gcov and lcov driven directly, no coco. Linux and macOS only.
  # --debugger:native attributes lines to the .nim sources, not the generated C.
  # --include keeps stdlib out of the capture, where lcov 2.x aborts on Nim's
  # codegen. Nim's native debugger mapping can still attribute a generated C
  # branch a few lines past the end of its source module. genhtml calls this a
  # `range` error, so suppress that mapping-only diagnostic while preserving
  # every other capture and report failure.
  let cache = "build/covcache"
  rmDir cache
  rmDir "coverage"
  rmFile "lcov.info"
  # Each coverage binary gets its own nimcache subdir. Sharing one nimcache
  # across the differently-instrumented `nim c` builds re-instruments the
  # shared stdlib modules with a different gcov counter layout each time, so
  # when the binaries run they write conflicting `.gcda` to the same paths and
  # lcov aborts on `cannot merge previous GCDA file: mismatched number of
  # counters`. `lcov --capture --directory build/covcache` recurses into the
  # subdirs, so aggregation is unchanged.
  const bins = testBins
  let gcovTool = when defined(macosx): " --gcov-tool tools/llvm-gcov.sh" else: ""
  for (name, src) in bins:
    exec "nim c --path:src --nimcache:" & cache & "/" & name &
         " --debugger:native --passC:--coverage --passL:--coverage" &
         " -o:build/test_cov_" & name & " tests/" & src & ".nim"
    exec "./build/test_cov_" & name
  exec "lcov --capture --directory " & cache & " --base-directory ." &
       " --include \"*/src/UniGlyph/*\" --output-file lcov.info --quiet" &
       gcovTool
  exec "genhtml lcov.info --output-directory coverage --legend --quiet" &
       " --ignore-errors range"
  exec "lcov --summary lcov.info"
