# OB-0-04 — Spike P4: FFI round-trip cost for per-frame snapshots

| | |
|---|---|
| **Stage** | 0 — Risk spikes |
| **Type** | Spike (throwaway code) |
| **Priority** | Blocker |
| **Dependencies** | None (parallel with other spikes) |
| **References** | PRD §15.1 P4, NFR-10, R6, D4 |
| **Estimate** | M |

## Context

The UI reads engine state (meters, playhead, voice counts) via lock-free snapshots sampled at frame rate across the `dart:ffi` boundary (NFR-10). If the round-trip cost eats a meaningful slice of the 8.3 ms frame budget, the 120 Hz target dies (R6). Measure it before designing the real ABI.

## Scope

- A small C++ dylib exposing an `extern "C"` function that fills a caller-provided buffer with a **60-value snapshot** (floats: fake meter/playhead data), plus a variant returning a pointer to an internally double-buffered snapshot.
- A writer thread in C++ mutating the snapshot at audio-callback-like rates (e.g. every 3 ms) using a seqlock or double-buffer + atomic index — the actual candidate mechanisms for NFR-10.
- Dart side: bindings via `ffigen`; read the snapshot once per frame inside a ticker for 60 s at 120 Hz.
- Measure: (a) single FFI call overhead, (b) full read-parse-into-Dart-objects cost per frame, (c) allocation behaviour (does the read allocate? GC pressure over 60 s), (d) torn-read detection with the seqlock under contention.
- Compare two data strategies: copying into a Dart `Float32List` vs reading directly from external memory via typed-data views.

## Technical notes

- Measure in profile/release mode.
- This spike's mechanism is the prototype for ADR-002 (the real FFI contract) — write it as if it will be thrown away, but record the design that won.
- Keep code in `spikes/p4_ffi/`.

## Acceptance criteria

- [ ] **Pass condition (PRD §15.1): a 60-value snapshot crosses the boundary in well under one frame budget** — target: total per-frame read cost <0.5 ms, ideally <0.1 ms.
- [ ] Zero Dart allocations per frame in the steady-state read path (verified via DevTools memory profile over 60 s).
- [ ] Seqlock/double-buffer correctness demonstrated (no torn reads observed under a deliberately hostile writer).
- [ ] Numbers and the winning mechanism recorded in ADR-001 and referenced by ADR-002.

## Out of scope

- The command channel (UI→engine) — Stage 1, ADR-002.
- Real engine data.
