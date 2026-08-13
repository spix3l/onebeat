# OB-2-07 — CLAP hosting: instantiate, process, state

| | |
|---|---|
| **Stage** | 2 — v0.2 "It hosts" |
| **Type** | Feature |
| **Priority** | Blocker |
| **Dependencies** | OB-2-01, OB-2-05 |
| **References** | FR-PLG-01, FR-PLG-08, D5 |
| **Estimate** | L |

## Context

The first real format adapter: CLAP (MIT headers, plain C). It runs inside the helper process, translating between the internal model (OB-2-01) and the CLAP plugin API. Because the internal model is CLAP-shaped, this adapter should be near-1:1 — divergences discovered here are design bugs in OB-2-01 and go back there.

## Scope

1. **Host implementation:** `clap_host` with the core extension set: `params`, `state`, `audio-ports`, `note-ports`, `latency`, `gui` (window plumbing in OB-2-08), `log`, `thread-check`, `timer-support`, `posix-fd-support`. `thread-pool` and `render` recorded as v1.x follow-ups.
2. **Lifecycle mapping:** bundle load → factory → instantiate → activate/deactivate per the internal model's lifecycle; sample-rate/block-size changes handled by deactivate-reconfigure-activate.
3. **Event translation:** internal event list ↔ `clap_input_events`/`clap_output_events`, including param value + modulation events and note expression — lossless both ways.
4. **State:** `clap_plugin_state` save/load as opaque chunks (FR-PLG-08); stored via the engine's state API; periodic checkpoint for crash-restart (OB-2-05).
5. **Parameter sync:** param info rescan, value changes from plugin (gesture begin/end respected), flush path when not processing.
6. **Host identity:** proper `clap_host` name/version/vendor; `clap.features` handling for instrument/effect classification (feeds scanner categories).

## Acceptance criteria

- [ ] Reference free plugins (minimum set: Surge XT, Vital or Odin 2, Airwindows CLAP, u-he demo CLAP) instantiate, produce audio from schedule note events, and respond to parameter changes.
- [ ] State round-trip: set params → save chunk → destroy → recreate → load chunk → identical param values and audible behaviour (verified for 3 plugins).
- [ ] Modulation events reach a plugin that supports them (Surge XT) as modulation, not value overwrites.
- [ ] Latency reported by a lookahead plugin is captured into the model (consumed by PDC in Stage 4).
- [ ] `thread-check` assertions never fire across the test suite.
- [ ] Human review completed (R4).

## Out of scope

- Editor GUI (OB-2-08). Automation recording/curves (OB-2-09 basic; full in Stage 4). VST3/AU (Stage 5).

## Local compatibility note — 13 August 2026

`../daw-contents` contains Keyzone Classic VST and Audio Unit installers only;
their package manifests install `.vst` and `.component` bundles and contain no
CLAP binary. They therefore cannot validate this CLAP ticket. Keep them for the
Stage 5 VST/AU adapters; OB-2-07 needs an actual `.clap` bundle.
