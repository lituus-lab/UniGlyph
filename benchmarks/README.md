<!-- SPDX-License-Identifier: Apache-2.0 -->
<!-- Copyright 2026 lituus-lab -->
# UniGlyph benchmarks

Run the font-identity benchmark in release mode:

```sh
nimble benchmarkIdentity
nim c -r -d:release --path:src -o:build/benchmark_font_identity \
  benchmarks/benchmark_font_identity.nim path/to/font.ttf 100 1000000
```

The Nimble task runs the bundled font with 50 load iterations and one million
cached accesses. Use the direct command for a custom font or sample count; its
three trailing arguments are `FONT`, `ITERATIONS`, and `ACCESSES`.

The JSON report separates raw TrueType parsing, the public load path including
the one-time BLAKE3-256 identity, hashing alone, and cached identity access.
Raw parsing and public loading are interleaved in alternating order. Three
untimed warm-up iterations precede measurement, and a monotonic clock measures
each operation.

`observed_load_minus_parse_mean_ns` is a noisy difference between two measured
operations, not an exact attribution of hashing overhead. Allocator state,
cache state, frequency scaling, and system load remain confounders. The
separately measured `hash_mean_ns` is the closest isolated cost but does not
include construction of `Font`. Cached access returns a copied 32-byte value;
a non-inlined harness and checksum prevent loop-invariant hoisting and removal
of the access loop.

The benchmark does not measure shaping, layout, rasterization, GPU work, C or
Python marshalling, and makes no claim about those workloads. Record the JSON,
hardware, power mode, compiler, command, and repetition count with any result.

## Recorded reference

[`results/apple-m4-font-identity-2026-08-16.json`](results/apple-m4-font-identity-2026-08-16.json)
contains all five process-level means and their median for the bundled
493,564-byte font on a 32 GiB Apple M4 Mac mini with Nim 2.2.10. Each process
used 100 interleaved iterations and one million cached accesses after three
warm-ups. It is a local regression reference, not a threshold or a claim about
other hardware.
