# OB-1-05 — Audio I/O abstraction + CoreAudio backend

| | |
|---|---|
| **Stage** | 1 — v0.1 "It makes sound" |
| **Type** | Feature (engine) |
| **Priority** | Blocker |
| **Dependencies** | OB-1-01 |
| **References** | FR-ENG-01, FR-ENG-02, FR-ENG-08, NFR-01, NFR-05, NFR-11 |
| **Estimate** | L |

## Context

All audio I/O sits behind an abstract interface; no CoreAudio types leak into engine code (FR-ENG-08) — this seam is what makes v2's WASAPI/ALSA backends a port rather than a rewrite (NFR-11).

## Scope

1. **Abstract interface** (`engine/src/audio_io/audio_device.h`): device enumeration (id, name, channel counts, supported rates/buffer sizes), open/close/start/stop, a render callback delivering interleaved-or-planar float32 buffers + timestamp, latency reporting (input, output, total round-trip in frames), device-change and default-device-switch notifications. Pure C++, no Apple types.
2. **CoreAudio backend** (`audio_io/coreaudio/`): AudioUnit HAL output (or AUHAL) implementation; sample rates 44.1/48/88.2/96 kHz; buffer sizes 64–2048 with actual granted size reported; graceful handling of device disappearance (fall back to default device, emit notification); aggregate-device tolerance (works, even if not optimally).
3. **Null backend** for tests and CI (renders on a timed thread or on-demand) — the engine test suite must run without audio hardware.
4. **Latency surfacing:** round-trip latency computed and exposed for the ABI snapshot (user-visible per FR-ENG-02; UI display later).
5. Default behaviour: open default output device at 48 kHz / 512 frames on engine start — **no configuration required to make sound** (FR-UX-16 groundwork).

## Technical notes

- The render callback runs on the CoreAudio RT thread and immediately enters engine code marked `[[clang::nonblocking]]` (OB-1-06); this backend does the last allocation-free handoff.
- Device notifications arrive on non-RT threads → post to the engine's event queue, never touch RT state directly.
- No third-party audio-I/O library: CoreAudio directly, keeping the dependency list clean (D1).

## Acceptance criteria

- [ ] Engine code outside `audio_io/coreaudio/` includes no CoreAudio headers (CI seam check passes).
- [ ] A test tone (engine-generated sine) plays through the default device at all four sample rates and at buffer sizes 64, 128, 256, 512, 1024, 2048.
- [ ] Reported round-trip latency at 128 frames / 48 kHz is <10 ms on Apple Silicon (NFR-01) — measured and recorded.
- [ ] Unplugging the active output device mid-playback: no crash, playback resumes on the default device, notification emitted.
- [ ] Null backend drives the full engine test suite in CI with no audio hardware.
- [ ] Human review completed (R4 — audio-thread code).

## Out of scope

- Input/recording (FR-AUD-01, v1.x+). Device-selection UI (preferences screen, later stage).
