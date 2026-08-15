# OneBeat UI Rebuild — Backend & Engine ABI Gaps

This document tracks backend engine and ABI capabilities required by the UI designs that are not yet exposed by the engine ABI (planned for EPIC-4 and beyond). Per Phase D wiring requirements, the UI presents disabled/stub affordances for these items rather than fake logic.

## 1. Mixer & Routing (UI-D-05 / EPIC-4)

- **Dynamic Send Matrix ABI**:
  - *Current state*: Master output gain and stereo meter snapshot are exposed. Per-track sends (`→ Reverb Send`, `→ Delay`) and pre/post fader routing switches are not yet in the C ABI.
  - *UI Handling*: Displayed with stub values and disabled affordances with `pre/post` and send slider levels.
  - *Waiting on*: Engine command `cmdSetTrackSendLevel` and `ob_engine_track_sends_read`.

- **Sidechain Routing Graph ABI**:
  - *Current state*: Sidechain ducking visual tags (`↓ SC in`) and routing inspector cards are rendered from track metadata. Dynamic audio-rate sidechain key input routing graph is not yet configurable via FFI.
  - *UI Handling*: Surfaces `SidechainCard` with toggle and amount controls mapped to presenter state.
  - *Waiting on*: Dynamic bus routing and sidechain key assignment API in `libonebeat_engine`.

## 2. Audio Export (UI-D-06 / EPIC-4)

The dialog now offers exactly what the engine renders: a format, a sample rate
and a destination folder (`ob_engine_export_start`, ABI 1.17). Bit depth, range
and stem selectors were removed rather than disabled — an option the engine
cannot honour is a description of a render nobody is performing.

- **Per-track Multi-stem Export**:
  - *Current state*: the master mix only. Rendering one file per channel needs a render pass per stem in the engine.
  - *UI Handling*: not offered. The dialog does not mention stems.
  - *Waiting on*: `ob_engine_export_stems()` in the engine library.

- **Compressed Export Formats (MP3, FLAC)**:
  - *Current state*: uncompressed 24-bit PCM, as WAV or AIFF. Compressed containers need an encoder the engine does not vendor.
  - *UI Handling*: not offered.
  - *Waiting on*: native encoders or platform media encoder bridges.

- **Export Range and Bit Depth**:
  - *Current state*: the whole arrangement, plus a two-second tail, at 24-bit.
  - *UI Handling*: not offered.
  - *Waiting on*: a loop/selection region the model owns (the loop region is derived from the arrangement today), and a depth choice worth asking about.

## 3. Extensions & WASM Sandboxing (UI-D-08 / EPIC-6)

- **WASM Extension Runtime Host**:
  - *Current state*: Native CLAP/VST3 plugin hosting and internal DSP stock editors. Standalone sandboxed WASM extension execution runtime is scheduled for EPIC-6.
  - *UI Handling*: Extension manager displays discovered extensions, capability inspection matrix, crash containment card, and enable/disable state.
  - *Waiting on*: WASM sandbox runtime host bridge.
