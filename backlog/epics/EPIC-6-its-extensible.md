# EPIC-6 — v0.6 "It's extensible"

**Exit criterion (PRD §10):** an external developer writes a working extension from the docs alone.
**Depends on:** Stage 5 closed (API should cover a stable feature surface).
**Status:** epic.
**Key references:** FR-EXT-01…09, FR-SEQ-13, D6, G4, R11; ADR-005; design screens `onebeat-console.html`, `onebeat-console-live.html`, `onebeat-console-save.html`, `onebeat-ext-mgr.html`, `onebeat-ext-empty.html`, `onebeat-ext-panel.html`.

## Scope

**In:** **ADR-005 + public API v1 defined in WIT** (FR-EXT-01): project-model read/write via the command bus, transport, selection, notifications — versioned, documented; **WASM runtime** (Wasmtime C API or WAMR — decide in ADR-005) with capability-scoped access (FR-EXT-02), **off the audio thread only** (D6); **script console** per the 3 designed screens (FR-EXT-03): interactive, live-reload, save/load scripts; extension packaging + in-app install/discovery (FR-EXT-04) per the extension-manager screens; failure containment — trap/timeout/memory caps, an extension can never destabilise host or audio thread (FR-EXT-09); **built-ins ported to the public API with CI enforcement** (FR-EXT-08, G4): the sampler and core effects call only public API; a CI check (link/include audit) blocks private access; extension points for generators/note transforms/file importers (FR-EXT-06, at least generators shipped, FR-SEQ-13); bindable to actions/shortcuts (FR-EXT-05) via the OB-3-14 action registry.

**Out:** audio-rate WASM DSP (post-1.0 research, D6); extension marketplace; extension-contributed workspace panels (FR-EXT-07 — needs Stage 8's workspace; ticket lands there or v1.x).

## Risks / watch

- R11: if the public API can't express the built-ins, it can't serve anyone — port the sampler *first* and let its needs drive API v1, not vice versa.
- WIT/component-model toolchain churn: pin versions; the ABI stability promise is ours, not the toolchain's.
- Documentation is the exit criterion: docs are a deliverable ticket, not a byproduct — external-tester dry run required.

## Candidate tickets (~11)

1. ADR-005: API surface v1 in WIT; runtime choice; capability model.
2. WASM runtime embedding: instantiation, sandbox limits, capability grants.
3. Host API implementation: model read/write via command bus, notifications.
4. Script console UI (3 designed screens) + REPL execution model.
5. Extension package format + loader + in-app manager (3 designed screens).
6. Failure containment: traps, timeouts, memory caps, kill/reload UX.
7. Port built-in sampler onto public API (drives API gaps).
8. FR-EXT-08 CI enforcement check.
9. Generator extension point + one shipped example (e.g. arpeggiator).
10. Action/shortcut/MIDI binding for extensions (FR-EXT-05).
11. v0.6 exit: external developer builds an extension from docs alone (recruited tester, recorded session); docs shipped.
