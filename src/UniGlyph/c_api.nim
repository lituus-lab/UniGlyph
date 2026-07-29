# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
## C ABI for UniGlyph. Built --app:staticlib/--app:lib --noMain --mm:arc
## -d:release. Keep in sync with include/UniGlyph.h; tests/c links the header
## against this lib.
## The version-only stub holds no facade import yet; commit 4 adds it when the
## full ugly_* surface needs the core layers + UniImage + UniColor.
proc NimMain() {.importc, cdecl.}

const
  UniGlyphAbiVersion* = 1
  UniGlyphVersionC: cstring = "0.1.0"
  UGLY_OK* = cint(0)
  UGLY_ERR_FORMAT* = cint(2)
  UGLY_ERR_UNSUP* = cint(4)
  UGLY_ERR_MEM* = cint(8)

var nimMainCalled: bool

# Unmangled C symbols, C calling convention, exported from the shared lib.
{.push exportc, cdecl, dynlib.}

proc ugly_init(): cint =
  ## Idempotent NimMain bootstrap. Call once before any other ugly_* entry.
  ## Never raises.
  if not nimMainCalled:
    NimMain()
    nimMainCalled = true
  UGLY_OK

proc ugly_abi_version(): cint =
  cint(UniGlyphAbiVersion)

proc ugly_version(): cstring =
  ## Static version string; do not free.
  UniGlyphVersionC

proc ugly_strerror(code: cint): cstring =
  ## Static message for an ugly_* status code.
  case code
  of UGLY_OK: "ok"
  of UGLY_ERR_FORMAT: "format error"
  of UGLY_ERR_UNSUP: "unsupported"
  of UGLY_ERR_MEM: "out of memory"
  else: "unknown error"

{.pop.}
