<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright 2026 lituus-lab -->
# Security Policy

Report vulnerabilities via GitHub private vulnerability reporting (Security
tab → "Report a vulnerability"), not via a public issue. Include: description,
impact, minimal reproducer, affected version (`ugly_version()`).

Only the latest released line is supported. The 1.x C ABI is frozen at the
version reported by `ugly_abi_version()`.

## Surface

- C ABI trusts its callers (C pointers, lengths) and never raises; a failure is
  mapped to a `UGLY_*` code. Foreign callers validate untrusted input before
  calling.
- Python binding adds the domain check and raises `ValueError`/`TypeError`.
- The font parser reads untrusted TTF bytes; table and glyph bounds are checked.
  A malformed font returns NULL from `ugly_font_load`, never an exception
  crossing the ABI.
- Call `ugly_init()` once before other operations. Handles are intended for
  single-threaded use and have no concurrent-mutation guarantee.
