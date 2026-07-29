<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright 2026 lituus-lab -->
# Security Policy

Report vulnerabilities via GitHub private vulnerability reporting (Security
tab → "Report a vulnerability"), not via a public issue. Include: description,
impact, minimal reproducer, affected version (`ugly_version()`).

Only the latest released line is supported. The `0.1.x` C ABI is not yet frozen.

## Surface

- C ABI trusts its callers (C pointers, lengths) and never raises; a failure is
  mapped to a `UGLY_*` code. Foreign callers validate untrusted input before
  calling.
- Python binding adds the domain check and raises `ValueError`/`TypeError`.
- The font parser reads untrusted TTF bytes; table bounds are checked and a
  malformed table yields `UGLY_ERR_FORMAT`, never a trap.
- Single-threaded, reentrant; no global mutable state.