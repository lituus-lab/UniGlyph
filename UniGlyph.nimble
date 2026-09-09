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

# nimble 0.22 exits 0 even when an `exec` inside a task fails, so a task's exit
# code says nothing about whether its body ran. Each task writes a marker as
# its last statement; `tools/gate.nim` removes the marker, runs the task, and
# fails if it is not there afterwards. `build/unigate canary` is the call that
# proves the gate still bites -- `nimble canary` on its own proves nothing.
const gateExe =
  when defined(windows): "build/unigate.exe" else: "build/unigate"

template done(task: string) =
  mkDir "build/.gate"
  writeFile("build/.gate/" & task & ".ok", "")

proc gate(task: string): string =
  ## `exec gate("test")` -- builds the tool only when it is missing, and that is
  ## deliberate. Every call here happens inside a task the gate binary is
  ## already running, and Windows locks a running executable against being
  ## overwritten. Freshness is enforced where the gate is invoked instead: CI
  ## compiles it at the start of every job, and tools/hooks/gated.sh rebuilds
  ## it when the source is newer.
  if not fileExists(gateExe):
    exec "nim c --hints:off -o:" & gateExe & " tools/gate.nim"
  gateExe & " " & task

task canary, "Must fail: proves the gate still catches a broken build":
  # No `done` here on purpose: the exec below raises, so the marker is never
  # written and the gate reports the failure nimble swallowed.
  exec "nim c -r --hints:off --path:src -o:build/canary tests/canary_broken.nim"


task lint, "Fail if nimpretty would reformat a source":
  exec "nim c -r --hints:off -o:build/lint_tool tools/lint.nim"
  done "lint"

task checkVGraph, "Fail on an import that climbs the layers in vgraph.cfg":
  exec "nim c -r --hints:off -o:build/vgraph_tool tools/vgraph.nim"
  done "checkVGraph"

task docsDeps, "Install the docs toolchain (nimib)":
  exec "nimble install -y nimib"
  done "docsDeps"

task book, "Build the nimib book (needs nimib)":
  # nimib compiles and runs the book's code blocks: a drift fails the build.
  exec "nim c -r --path:src --hints:off -o:build/book book/index.nim"
  done "book"

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
  exec gate("book")
  # The book is the landing page; the generated reference sits under api/.
  cpFile "book/index.html", "pages/index.html"
  done "docs"

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
  done "test"

task testRelease, "Nim tests (release, contracts compiled away)":
  for (name, src) in testBins:
    exec "nim c -r -d:release --path:src -o:build/" & name & "_rel tests/" & src & ".nim"
  done "testRelease"

task testCi, "Nim tests (CI subset, debug)":
  for (name, src) in testBins:
    exec "nim c -r --path:src -o:build/" & name & " tests/" & src & ".nim"
  done "testCi"

task testCiRelease, "Nim tests (CI subset, release)":
  for (name, src) in testBins:
    exec "nim c -r -d:release --path:src -o:build/" & name & "_rel tests/" & src & ".nim"
  done "testCiRelease"

task testAll, "debug + release + C ABI":
  exec gate("test")
  exec gate("testRelease")
  exec gate("ctest")
  done "testAll"

task example, "Nim demo (print-only; no file I/O)":
  exec "nim c -r --path:src -o:build/demo examples/demo.nim"
  done "example"

task benchmarkIdentity, "Benchmark font parsing and cached content identity":
  exec "nim c -r -d:release --path:src -o:build/benchmark_font_identity" &
       " benchmarks/benchmark_font_identity.nim"
  done "benchmarkIdentity"

task uniglyph, "Build the uniglyph CLI (render text to PNG + SVG)":
  exec "nim c --path:src -o:bin/uniglyph bin/uniglyph_cli.nim"
  done "uniglyph"

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
  done "clib"

task clibStatic, "C static library":
  exec "nim c --app:staticlib -d:staticNoAutoInit --noMain --mm:arc -d:release -o:" & staticLib &
       " src/UniGlyph/c_api.nim"
  done "clibStatic"

task clibMsvc, "C static library, MSVC ABI (Windows Python extension)":
  # CPython on Windows is MSVC-built and cannot link MinGW output. MSVC's
  # linker takes the lib name verbatim (no `lib` prefix, unlike MinGW), so the
  # output is `UniGlyph.lib` — the intentional exception to the sharedLib /
  # staticLib naming. setup.py's Windows branch matches: `LIB_NAME =
  # "UniGlyph.lib"` and `libraries=["UniGlyph"]`.
  exec "nim c --cc:vcc --app:staticlib -d:staticNoAutoInit --noMain --mm:arc -d:release" &
       " -o:UniGlyph.lib src/UniGlyph/c_api.nim"
  done "clibMsvc"

# Nim's MinGW toolchain names it mingw32-make.
let makeExe = if findExe("mingw32-make").len > 0: "mingw32-make" else: "make"

# `make -C`, not `cd dir && make`: nimble's exec runs no shell on Windows.
task ctest, "C ABI tests":
  exec gate("clibStatic")
  exec makeExe & " -C tests/c"
  done "ctest"

task cexample, "C demo (print-only consumer of the ugly_* ABI)":
  exec gate("clibStatic")
  exec makeExe & " -C examples/c"
  done "cexample"

task pyDeps, "Install Python build deps (setuptools, Cython, pytest) if missing":
  exec "python3 -m pip install --break-system-packages --quiet setuptools wheel \"Cython>=3.0.0\" pytest"
  done "pyDeps"

# The extension links the vcc static lib on Windows, the shared lib elsewhere.
task pyLib, "Build the library the Python extension links against":
  when defined(windows):
    exec gate("clibMsvc")
  else:
    exec gate("clib")
  done "pyLib"

task buildCython, "Cython extension in-place":
  exec gate("pyLib")
  exec gate("pyDeps")
  # nimscript `cd` (lib/system/nimscript.nim) changes the VM cwd for the next
  # exec without a shell, so the task works under nimble's no-shell exec on Windows.
  cd "py"
  exec "python3 setup.py build_ext --inplace"
  cd ".."
  done "buildCython"

task pyTest, "Cython extension + pytest":
  exec gate("buildCython")
  cd "py"
  exec "python3 -m pytest -q"
  cd ".."
  done "pyTest"

task pyWheel, "wheel":
  exec gate("pyLib")
  exec gate("pyDeps")
  cd "py"
  exec "python3 -m pip wheel --no-deps --no-build-isolation --wheel-dir dist ."
  cd ".."
  done "pyWheel"

task pySdist, "Python source distribution":
  exec gate("pyLib")
  exec gate("pyDeps")
  cd "py"
  exec "python3 setup.py sdist"
  cd ".."
  done "pySdist"

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
  # `mismatch` is the one capture suppression, and it is not optional: lcov 2.x
  # checks its own end line for a function against gcov's, and Nim's generated
  # destructors disagree -- tables.nim's rttiDestroy, 98 against 91. Every
  # other lcov error still fails the task.
  exec "lcov --capture --directory " & cache & " --base-directory ." &
       " --include \"*/src/UniGlyph/*\" --output-file lcov.info --quiet" &
       " --ignore-errors mismatch" & gcovTool
  # gcov can attribute a final generated expression to EOF + 1, and that one
  # artefact answers to two names: lcov 2.0, the version ubuntu-latest installs,
  # calls it `unmapped` and rejects `range` as a category outright, while 2.5
  # calls it `range`. Ask which one is there rather than assume.
  let genhtmlRange =
    if gorgeEx("genhtml --version").output.contains("LCOV version 2.0"):
      " --ignore-errors unmapped"
    else: " --filter range --ignore-errors range"
  exec "genhtml lcov.info" & genhtmlRange &
       " --output-directory coverage --legend --quiet"
  exec "lcov --summary lcov.info"
  done "coverage"
