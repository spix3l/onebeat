# OB-1-08 — Minimal built-in sampler

| | |
|---|---|
| **Stage** | 1 — v0.1 "It makes sound" |
| **Type** | Feature (engine) |
| **Priority** | High |
| **Dependencies** | OB-1-06, OB-1-07 |
| **References** | FR-BIP-01 (subset), PRD §10 v0.1 |
| **Estimate** | M |

## Context

v0.1 needs one sound source so "a note plays without glitching". This is the seed of the real sampler (FR-BIP-01) — keep the DSP clean, but don't gold-plate: tuning/looping/filter come in Stage 7.

## Scope

1. **Audio file loading** via `dr_libs` (`dr_wav` now; AIFF/FLAC/MP3 later per FR-SND-02): decode to float32 on a **worker thread**, never the audio thread; sample data handed to the RT side through the same publish pattern as the schedule.
2. **Sampler instrument** implementing the engine's internal instrument interface (a first, minimal version of the format-agnostic processor interface — event-in, audio-out, prepare/release lifecycle): note-on triggers playback of the loaded sample; pitch shifting by playback-rate resampling (linear interpolation is acceptable in v0.1); velocity → gain; fixed polyphony (e.g. 32 voices) with voice stealing; short anti-click fade-out on note-off/steal.
3. **A default sound** bundled (one MIT/CC0 one-shot, licence recorded) so the app makes sound with zero user files.
4. Unit tests: offline render of a known note sequence against a golden checksum; voice-stealing behaviour; RT-safety (no allocation on trigger — voices pre-allocated).

## Acceptance criteria

- [ ] A WAV loads off-thread and a schedule note-on plays it, pitched by note number, scaled by velocity.
- [ ] 32 simultaneous voices render without RTSan violations or dropouts at 128-frame buffers.
- [ ] Note-off and voice-steal are click-free (verified by rendered-output inspection test: no sample-to-sample jump above threshold).
- [ ] Golden-render test in CI (null backend, deterministic).
- [ ] Human review completed (R4 — audio-thread code).

## Out of scope

- ADSR, filter, looping, multi-format, UI (Stage 7 / FR-BIP-01 full scope). Time-stretch (v2).
