<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright 2026 lituus-lab -->
# ADR-0007: Stable font content identity

- Status: Accepted
- Date: 2026-08-16
- Scope: UniGlyph font values and foreign interfaces

## Context

UniPlot prepares glyph outlines and GPU resources from a `Font`. A bounded
retained-scene cache needs to distinguish exact font inputs before doing that
work. A file path can change, equivalent bytes can come from memory, two font
files can share names and metrics, and a reference address is stable only for
one object in one process.

## Decision

Each successful `loadTtf` or `loadTtfFromBytes` computes BLAKE3-256 over the
complete input byte sequence exactly once. `Font` retains the resulting
32-byte `FontIdentity` alongside its parsed tables. Nim returns the identity by
value; C copies it into a fixed-size caller buffer; Python returns immutable
`bytes`. The hexadecimal helpers are representations of the same 32 bytes.

UniCrypto owns BLAKE3. UniGlyph does not reproduce, truncate, salt, or
reinterpret the digest. The source path, parsed metrics, object address, and
parser version do not participate in it.

## Contracts

- identical source bytes yield identical identities regardless of loader;
- changing any source byte changes the hash input;
- mutating a caller buffer after loading cannot change the retained identity;
- identity lookup performs no parsing, file I/O, allocation in the Nim byte
  form, or rehashing;
- a nil Nim font violates its contract; the C entry reports
  `UGLY_ERR_FORMAT` for a nil font or output pointer.

BLAKE3 collision resistance makes the value suitable for cache identity. It
does not authenticate a font, establish provenance, or make malformed input
valid. Parsing still decides whether loading succeeds.

## Consequences

Font loading gains one full pass over the input bytes. The release benchmark
separates parser time, public load time, isolated hash time, and cached lookup
time so that this cost remains visible. UniPlot can incorporate all 32 bytes in
its canonical scene key without introducing a second font-identity mechanism.
