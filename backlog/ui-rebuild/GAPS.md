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

- **Per-track Multi-stem Export**:
  - *Current state*: Master mix stereo export to WAV. Individual stem file rendering (e.g. separate Drums Bus, Bass, Music, Vox wav files) is not yet parallel-rendered in the native engine.
  - *UI Handling*: Stems selector UI reflects selection; export flow renders project master with stem summary indication.
  - *Waiting on*: `ob_engine_export_stems()` in engine library.

- **Non-WAV Export Formats (MP3, AIFF, FLAC)**:
  - *Current state*: Native engine offline renderer exports PCM WAV. Other container/compression formats require external encoders.
  - *UI Handling*: Format selector shows WAV as primary active format, non-PCM options reflect their respective file extensions.
  - *Waiting on*: Native encoders or platform media encoder bridges.

## 3. Extensions & WASM Sandboxing (UI-D-08 / EPIC-6)

- **WASM Extension Runtime Host**:
  - *Current state*: Native CLAP/VST3 plugin hosting and internal DSP stock editors. Standalone sandboxed WASM extension execution runtime is scheduled for EPIC-6.
  - *UI Handling*: Extension manager displays discovered extensions, capability inspection matrix, crash containment card, and enable/disable state.
  - *Waiting on*: WASM sandbox runtime host bridge.
