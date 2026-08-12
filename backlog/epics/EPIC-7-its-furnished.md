# EPIC-7 — v0.7 "It's furnished"

**Exit criterion (PRD §10):** browser and soundpack indexing, core effects, sampler polish, presets, waveform thumbnails shipped.
**Depends on:** Stage 6 closed (built-ins are written against the public API from now on — FR-EXT-08 applies to everything this epic builds).
**Status:** epic.
**Key references:** FR-SND-01…08, FR-BIP-01/04/05/06/07, FR-PLG-13, FR-SEQ-01 leftovers; OQ-5 recruiting begins here.

## Scope

**In:** **content browser**: user-configurable folders (FR-SND-01), persistent incremental index (FR-SND-07), folder tree + name search + audition-on-click with tempo sync (FR-SND-03), drag-and-drop to rack/playlist/sampler incl. from Finder (FR-SND-04 — mechanism proven in OB-0-03), formats WAV/AIFF/FLAC/MP3/Ogg (FR-SND-02 — decoders under MIT-compatible licences only), optional `pack.json` manifest + tag filtering (FR-SND-05/06), waveform thumbnails generated/cached (FR-SND-08); **sampler completed** to FR-BIP-01 (multi-format, tuning, looping, ADSR, filter) with its **Flutter UI docked, tokens, per FR-BIP-07** (design screen `onebeat-plugin-builtin.html`); **core effects** (FR-BIP-04): parametric EQ, compressor, delay, reverb, limiter — as public-API built-ins; utilities as feasible (FR-BIP-05, S); **preset system** shared by built-ins and extensions (FR-BIP-06); plugin browser upgrades: search/categories/favourites/hiding (FR-PLG-13).

**Out:** packaged single-file soundpack (FR-SND-09, C); marketplace (W); drum/slicer + subtractive synth (FR-BIP-02/03, S — schedule only if pace allows, else v1.x).

## Risks / watch

- DSP quality is audible craft (G5's engine-side twin): budget listening/tuning time for the effects; golden-render + null tests are necessary but not sufficient.
- Indexing large libraries (100k samples) — incremental scan performance and DB choice matter; test with a big corpus early.
- **Begin OQ-5 recruiting now** (5 usability testers for Stage 8) — lead time is long.

## Candidate tickets (~12)

1. Content index: store, watcher, incremental rescan, corruption recovery.
2. Browser UI: tree, search, audition (tempo-synced loop preview), drag sources.
3. Finder DnD integration productionised (from OB-0-03 findings).
4. Waveform thumbnail pipeline (generate, cache, invalidate).
5. `pack.json` manifest + tag filter UI.
6. Sampler: full FR-BIP-01 feature set (engine).
7. Sampler UI: docked Flutter panel per design (FR-BIP-07 pattern established).
8. EQ + compressor (public API, docked UIs).
9. Delay + reverb + limiter.
10. Preset system: save/load/browse, shared namespace for built-ins + extensions.
11. Plugin browser: search/categories/favourites/hiding.
12. v0.7 exit verification + OQ-5 recruitment checkpoint.
