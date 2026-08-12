# OB-1-09 — Transport: play, stop, tempo, position

| | |
|---|---|
| **Stage** | 1 — v0.1 "It makes sound" |
| **Type** | Feature (engine) |
| **Priority** | High |
| **Dependencies** | OB-1-06, OB-1-07 |
| **References** | PRD §10 v0.1, FR-ENG-01 |
| **Estimate** | M |

## Context

The transport is the engine's clock: sample-accurate position, tempo, and play state, driving the schedule cursor (OB-1-07) and reported to the UI via the snapshot (OB-1-10).

## Scope

1. **Transport state:** playing/stopped, position in samples (canonical) with derived musical time (bars/beats/ticks at the current tempo and 4/4 meter), tempo in BPM (20–999, double precision), loop region (start/end, on/off).
2. **Commands** (via the ABI command queue): play, stop, seek (bars/beats or samples), set tempo, set loop region. Applied at block boundaries; seek while playing is click-safe (voices released with fade).
3. **Musical-time mapping** centralized in one `TimeMap` class (samples ↔ beats at constant tempo), designed so Stage 3+ tempo *changes* (FR-SEQ-11) extend it rather than replace it — the mapping is already a function of position, not a constant.
4. Loop wrap: cursor wraps sample-accurately; notes spanning the loop boundary handled (note-offs emitted at wrap).
5. Snapshot fields: position, tempo, play state, loop region — consumed by OB-1-10.

## Acceptance criteria

- [ ] Play/stop/seek/tempo commands round-trip from a test harness through the command queue and take effect at the next block boundary.
- [ ] A 4-bar loop at 120 BPM wraps sample-accurately (offline render: wrap point verified to the exact sample; no hanging notes).
- [ ] Tempo change while playing does not glitch and keeps musical position continuous.
- [ ] `TimeMap` unit-tested for round-trip precision across rates 44.1–96 kHz.
- [ ] Human review completed (R4).

## Out of scope

- Tempo/time-signature *tracks* (FR-SEQ-11, v1.x). Metronome, count-in.
