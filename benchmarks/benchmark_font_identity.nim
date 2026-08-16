# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 lituus-lab
## Measures parsing and content-identity costs without claiming end-to-end text
## rendering performance. Timings use a monotonic clock and interleave the raw
## parser and public loader to reduce ordering bias.
import std/[json, monotimes, os, strutils, times]
import UniCrypto/hash/blake3/blake3 as ublake3
import UniGlyph
import UniGlyph/tables

const DefaultFont = "tests/assets/DejaVuSans.ttf"

proc elapsedNs(action: proc()): int64 =
  let started = getMonoTime()
  action()
  (getMonoTime() - started).inNanoseconds

proc positiveInt(value, name: string): int =
  try:
    result = parseInt(value)
  except ValueError:
    quit(name & " must be a positive integer", QuitFailure)
  if result <= 0:
    quit(name & " must be a positive integer", QuitFailure)

proc measuredIdentity(font: Font): FontIdentity {.noinline.} =
  ## Keep the benchmark from folding the immutable identity out of the loop.
  font.fontIdentity

proc main() =
  let fontPath = if paramCount() >= 1: paramStr(1) else: DefaultFont
  let iterations =
    if paramCount() >= 2: positiveInt(paramStr(2), "iterations") else: 50
  let accesses =
    if paramCount() >= 3: positiveInt(paramStr(3), "accesses") else: 1_000_000
  if not fileExists(fontPath):
    quit("font not found: " & fontPath, QuitFailure)

  let raw = readFile(fontPath)
  var bytes = newSeq[byte](raw.len)
  if raw.len > 0:
    copyMem(bytes[0].addr, raw[0].unsafeAddr, raw.len)

  for _ in 0 ..< 3:
    discard parseTables(bytes)
    discard loadTtfFromBytes(bytes)
    discard ublake3.blake3(bytes)

  var parseNs, loadNs, hashNs: int64
  for i in 0 ..< iterations:
    if (i and 1) == 0:
      parseNs += elapsedNs(proc() = discard parseTables(bytes))
      loadNs += elapsedNs(proc() = discard loadTtfFromBytes(bytes))
    else:
      loadNs += elapsedNs(proc() = discard loadTtfFromBytes(bytes))
      parseNs += elapsedNs(proc() = discard parseTables(bytes))
    hashNs += elapsedNs(proc() = discard ublake3.blake3(bytes))

  let font = loadTtfFromBytes(bytes)
  var accessChecksum = 0'u64
  let accessNs = elapsedNs(proc() =
    for i in 0 ..< accesses:
      let identity = measuredIdentity(font)
      accessChecksum += uint64(identity[i and 31])
  )

  let parseMean = float64(parseNs) / float64(iterations)
  let loadMean = float64(loadNs) / float64(iterations)
  let hashMean = float64(hashNs) / float64(iterations)
  let report = %*{
    "schema": "uniglyph-font-identity-v1",
    "nim": NimVersion,
    "host_os": hostOS,
    "host_cpu": hostCPU,
    "font": fontPath,
    "font_bytes": bytes.len,
    "iterations": iterations,
    "accesses": accesses,
    "parse_mean_ns": parseMean,
    "load_with_identity_mean_ns": loadMean,
    "observed_load_minus_parse_mean_ns": loadMean - parseMean,
    "hash_mean_ns": hashMean,
    "cached_identity_access_mean_ns": float64(accessNs) / float64(accesses),
    "access_checksum": accessChecksum
  }
  echo report.pretty

main()
