# OneBeat — Product Requirements Document

**Version:** 1.0 — Baseline
**Date:** 12 August 2026
**Author:** Business Analysis
**Licence:** MIT
**Status:** Approved baseline. Supersedes v0.1, v0.2, v0.3.
**Companion:** *OneBeat Domain Model Specification v1.0*

This is the consolidated baseline. All technology decisions are locked, all discovery questions are resolved, and §15 is written as the direct input to the UI prototyping phase.

---

## 1. Executive Summary

**OneBeat** is an open-source, MIT-licensed digital audio workstation built around FL Studio's pattern-based production workflow. It hosts third-party plugins (CLAP, VST3, AU), accepts user soundpacks, and ships with a small suite of built-in instruments and effects. macOS first; Windows and Linux are a v2 target rather than an exclusion.

OneBeat is differentiated on two axes at once:

1. **Architecture** — open, documented, scriptable internals, where extensions are first-class and the built-in plugins are written against the same public API everyone else gets.
2. **Craft** — a DAW that is pleasant to look at, quick to learn, and whose interface the user can rearrange to suit how they work.

Feature parity with FL Studio is the long-term north star and explicitly **not** a release goal. v1.0 delivers one complete, beautiful, learnable production workflow.

---

## 2. Problem Statement

**Every mature DAW is a closed box.** FL Studio, Ableton, Logic and Bitwig are proprietary; behaviour cannot be modified and extension is limited to what the vendor exposes. Open-source DAWs (Ardour, LMMS, Zrythm) are open in licence but were not architected for extensibility as a primary concern, and most look and feel like engineering artefacts rather than creative instruments.

**The gap:** no DAW is simultaneously *deeply modifiable* and *pleasant to use*. These have historically been treated as opposed. They are not; they have simply never been resourced together.

**Why now:** VST3 moved to the **MIT License** in October 2025 (VST 3.8), replacing the proprietary/GPLv3 dual model — permissively-licensed plugin hosting became legal, and was not before. **CLAP** is MIT-licensed, community-governed, requires no SDK contract, and has moved past early-adopter status (Bitwig, REAPER, FL Studio, Studio One).

---

## 3. Vision & Positioning

> **A DAW you can take apart, rearrange, and want to look at.**

| | FL Studio | LMMS | Ardour | Bitwig | **OneBeat** |
|---|---|---|---|---|---|
| Licence | Proprietary | GPLv2 | GPLv2 | Proprietary | **MIT** |
| Workflow | Pattern-based | Pattern-based | Linear | Hybrid | **Pattern-based** |
| Scripting | Limited | None | Lua | Control surfaces | **WASM, core-level** |
| Extensibility | Plugin API only | Fork required | Plugin + Lua | Plugin API only | **Plugin + extension + script** |
| UI craft | Dense, dated | Poor | Functional | Excellent | **Target: Bitwig-class** |
| Layout control | Fixed | Fixed | Fixed | Fixed | **Fully user-arrangeable** |
| Learnability | Steep | Moderate | Steep | Moderate | **Target: best in class** |
| Platforms | Win/macOS | All | All | All | **macOS v1, all v2** |

Bitwig is the honest benchmark on both differentiators. OneBeat's claim is not that it beats Bitwig on features, but that it offers comparable craft with an MIT licence, an open extension model, and a workspace the user controls.

**Positioning caveat, retained deliberately:** FL Studio's user base is predominantly Windows and FL already ships a native macOS build, so "FL workflow on Mac" is not an unmet need. The FL reference is a **workflow** reference. The genuine gap is licence + extensibility + craft.

---

## 4. Target Users

**Primary — "The Tinkerer-Producer."** Makes music and writes code. Wants a DAW that bends to their workflow. Needs a competent DAW *and* a real API; will abandon OneBeat if either half is weak.

**Secondary — "The Contributor."** Audio-adjacent developer looking for a well-architected project with clean module boundaries and a permissive licence.

**Tertiary — "The Curious Beginner."** Wants to make a beat without a week of tutorials. Not the design target for v1, but §8.1 is written so this user is not actively excluded — if a beginner can navigate OneBeat, the primary user certainly can.

---

## 5. Goals & Non-Goals

| ID | Goal | Measure |
|---|---|---|
| G1 | A complete track can be produced and exported without leaving OneBeat | Pattern → arrangement → mix → export |
| G2 | Third-party plugins load and run reliably | ≥90% of the compatibility set |
| G3 | A plugin crash never destroys user work | Crash contained; state recoverable |
| G4 | The extension API is real, not decorative | Built-ins use only public API (CI-enforced) |
| G5 | OneBeat is beautiful | Design tokens before UI code; §8.1 criteria |
| G6 | OneBeat is learnable | First sound <60 s; loop exported <15 min, unaided |
| G7 | OneBeat is contributable | Clone-to-build <15 min; ≥3 external contributors by v1.0 |

### Non-goals for v1.0

| Non-goal | Rationale |
|---|---|
| **FL Studio feature parity** | ~28 years of commercial development. Parity as release scope guarantees OneBeat never ships. |
| **VST2** | Licences unobtainable since 2018; format permanently closed. State plainly to users — some legacy plugins will never load. |
| **Windows / Linux** | Deferred, not excluded. Platform-specific code confined to defined seams so v2 is a port, not a rewrite. |
| **AAX** | Requires Avid NDA; incompatible with MIT. |
| **Competitive built-in instrument suite** | A second product. See §8.7. |
| **FL project import** | Undocumented proprietary format, legally grey, high effort. Deferred indefinitely. |
| **Docked inline plugin editor panels** | Consequence of D3.2 — third-party plugin editors are floating native windows. |
| **Lane grouping / folder lanes** | Deferred to v1.x; schema reserves the field (DM-Q1). |
| **Notation, video, cloud collaboration, mobile, stem separation** | Out of scope. |

---

## 6. Technology Decisions (locked)

### D1 — Licence: **MIT**
*Consequences:* **JUCE excluded** (AGPLv3 or commercial only). **libsndfile excluded** (LGPL — problematic for static linking into an MIT application). Every dependency must be MIT / Apache-2.0 / BSD / ISC / public domain, enforced by CI (NFR-09).

### D2 — Core language: **C++20**
The case for Rust rested on real-time and memory safety with a solo developer and AI agents. Two things overturned it:

1. **The C++ tooling gap closed.** RealtimeSanitizer is in mainline Clang (LLVM 20+, macOS supported). Functions marked `[[clang::nonblocking]]` raise a runtime error on any call to `malloc`, `free`, `pthread_mutex_lock`, a syscall, or anything else non-deterministic — and the same attribute drives compile-time Function Effect Analysis. With ASan, UBSan and TSan alongside, most of Rust's advantage is recoverable through tooling.
2. **Rust's guarantee lapses where the risk concentrates.** Hosting VST3 from Rust means large `unsafe` blocks wrapping a COM interface — no borrow-checker protection at exactly the boundary where third-party code causes damage.

*Consequences:* VST3's SDK **is** C++ (reference implementation, no bindings). AU is reachable via Objective-C++ directly. CLAP is a plain C header. The published body of audio DSP work is C/C++, which also means agent assistance is far better-informed here. **Cost:** memory safety becomes a discipline rather than a guarantee — see R4 and NFR-08.

### D3 — UI: **Flutter / Dart**
- The "not native" objection doesn't apply to DAWs — FL, Ableton and Bitwig are all fully custom-drawn. There is no native look to lose.
- `CustomPainter` suits piano rolls, waveforms and meters better than a native declarative toolkit.
- Hot reload materially changes UI iteration speed for a solo developer, directly serving G5.
- Cross-platform is restored, resolving the tension between the Linux-heavy contributor pool and a macOS-only product.
- Total layout control, which D9 depends on.

**D3.1** — All OneBeat UI is Flutter. One rendering world, not two.

**D3.2** — **Third-party plugin editors are floating native windows.** VST3, AU and CLAP all return an `NSView`. Flutter's macOS platform views work (`AppKitView`, hybrid composition), but focus traversal and accessibility tree merging remain incomplete — and focus traversal matters, because users type values into plugin fields. Floating windows sidestep this entirely and match how most DAWs behave by default. Docked inline plugin panels are the feature given up.

**D3.3 — Costs accepted:** accessibility needs explicit work rather than defaults (FR-UX-25); Dart GC introduces a jank risk at 120 Hz (R13); no serious DAW has been built in Flutter, so unknown unknowns are real (R14).

### D4 — FFI: **`dart:ffi` + `ffigen` over an `extern "C"` boundary**
The C++ core exposes a narrow, stable, hand-designed C ABI; Dart bindings are generated from those headers. *Consequence:* the boundary is a product surface, not something to grow organically. See NFR-10.

### D5 — Internal plugin model: **format-agnostic, modelled on CLAP semantics**
A single internal abstraction over CLAP, VST3 and AU, built to **CLAP's semantics** rather than the intersection of all three. CLAP is the most expressive (audio-rate non-destructive modulation, per-note expression, host/plugin thread-pool cooperation). Modelling the lowest common denominator discards those capabilities permanently. Map VST3 and AU *down* into a CLAP-shaped model, accepting that some capabilities are simply absent for those formats.

### D6 — Scripting: **WASM**
Wasmtime via its C API (Apache-2.0), or WAMR if a lighter embed is preferred. API surface defined in WIT. *Consequence:* WASM runs **off the audio thread only**. Audio-rate WASM DSP is post-1.0 research, not a v1 promise.

### D7 — Governance: **BDFL, solo maintainer**
Public repo with a clear README from day one; no active promotion until there is a demo worth showing — first impressions are spendable once.

### D8 — Name: **OneBeat**
*Action:* trademark clearance and domain/handle availability before the repo goes public.

### D9 — Signature element: **the rearrangeable workspace**
Panels dockable, splittable, tear-off-able onto other displays, savable as named layouts. Extensions contribute panels into the same system.

This is the *visible* expression of the invisible differentiator — "hackable architecture" is abstract until the user drags their piano roll onto a second monitor and saves the arrangement.

**It threatens G6 directly.** Infinitely flexible interfaces are hostile to beginners; a blank canvas is a demand, not an invitation. **Resolution: opinionated defaults, flexibility discovered later.** A strong default layout plus 3–4 named presets, rearrangement available but not advertised on first run.

### D10 — Typography
- **UI: Archivo** (SIL OFL). A grotesque with a real width axis — condensed cuts carry dense mixer and browser labels that would otherwise truncate.
- **Numeric: Martian Mono** (SIL OFL). Tabular by construction, distinctly technical. BPM, timecode, parameter values, meters.
- **Deliberately not Inter** — the default-by-omission choice, which the positioning cannot afford.

### Resulting stack

| Layer | Choice | Licence |
|---|---|---|
| Core engine, sequencer, project model | C++20 | MIT (own code) |
| Audio I/O | CoreAudio, behind an own abstraction | Apple SDK |
| CLAP hosting | `clap` headers | MIT |
| VST3 hosting | Steinberg VST3 SDK ≥3.8 | MIT |
| AU hosting | AudioToolbox via Objective-C++ | Apple SDK |
| Audio file I/O | `dr_libs` or `libnyquist` — **not libsndfile** | PD / BSD |
| Resampling | `r8brain-free-src` | MIT |
| Time-stretch | `signalsmith-stretch` | MIT |
| Lock-free queues | `readerwriterqueue` / `concurrentqueue` | BSD |
| Utilities | `choc` | ISC |
| Scripting | Wasmtime C API or WAMR + WIT | Apache-2.0 |
| UI | Flutter / Dart | BSD |
| FFI | `extern "C"` + `ffigen` | BSD |
| RT safety | RTSan, ASan, UBSan, TSan | — |

---

## 7. Domain Model

Full specification in the companion document. The essentials, because everything in §8.4 and §8.6 depends on them:

**OneBeat has two orthogonal organisational axes that meet at exactly one point.**

- **Time axis:** `Pattern` → `PatternClip` → `ArrangementLane`. Answers *what plays when*.
- **Signal axis:** `Instrument` → `MixerTrack` → Master. Answers *what it sounds like*.
- **The single join:** an `Instrument` receives note events from patterns and emits audio into mixer tracks. These two facts are independent.
- **The critical negative:** `ArrangementLane` and `MixerTrack` have **no relationship**. A lane is not a bus. Moving a clip between lanes changes nothing audible.

| Entity | FL name | Key property |
|---|---|---|
| `Instrument` | Channel | Project-global, stable ID, not owned by any pattern |
| `Pattern` | Pattern | Sparse map of `InstrumentId → NoteSequence`; a slice *across* instruments |
| `PatternClip` | Pattern clip | A **reference**, never a copy. Holds no note data |
| `ArrangementLane` | Playlist track | Purely organisational. No instrument, no effects, no routing |
| `MixerTrack` | Insert | The signal path. Many instruments may share one |

**Deviations from FL**, all serving G6: route by stable ID rather than integer index; auto-create a mixer track per instrument by default (FL's worst beginner trap is everything landing on Master); references by default plus an explicit `Make unique`; two mutes with two different names (lane mute is an *event gate*, mixer mute is an *audio gate*); pattern-scoped instrument visibility; usage counts surfaced before destructive pattern edits; audio and automation clips as first-class clip types rather than channel types.

**Resolved design questions:**

| # | Resolution |
|---|---|
| DM-Q1 | Lanes are flat in v1. Schema reserves `group_id` so grouping is additive, not a migration. |
| DM-Q2 | Clip windowing supported from v1 — clips carry source offset, length and loop mode. |
| DM-Q3 | Schema and flattener accommodate clip transforms from v0.3; UI exposes transpose in v1.0, the rest in v1.x. |
| DM-Q4 | One `NoteSequence` shared by step sequencer and piano roll. A step is a quantised note; two representations would need permanent reconciliation. |
| DM-Q5 | Multi-out ports are dynamic (reconfigurable while deactivated, per CLAP), not fixed at instantiation. |

**Non-negotiable architectural consequence:** the audio thread must never traverse `PatternClip → Pattern → Instrument`. Edits mutate the model off-thread; a flattening pass resolves all references into an immutable, time-ordered schedule; the schedule is published by atomic pointer swap; the audio thread reads only the schedule. Established in v0.1, because retrofitting it means rewriting the sequencer.

---

## 8. Functional Requirements

Priority: **M** = Must (v1.0) · **S** = Should (v1.x) · **C** = Could (post-1.0) · **W** = Won't

### 8.1 Experience, Visual Design & Onboarding

> "Beautiful" and "easy" are not requirements until they can fail. What follows converts them into things that pass or fail.

#### 8.1.1 Design system

**Palette rationale.** DAW chrome must be *chromatically quiet*, because the user fills the canvas with their own clip and track colours. Chrome that asserts a hue will clash with whatever the user picks. Equally, the surface must not be pure black — pure black makes saturated clip colours vibrate. The accent is deliberately kept away from green, amber and red, which are reserved for metering, where users read them instantly and reinvention would be actively harmful.

| Token | Value | Role |
|---|---|---|
| `surface-deep` | `#131412` | Arrangement and canvas background |
| `surface-panel` | `#1D1F1C` | Panel and browser surfaces |
| `surface-raised` | `#2A2C28` | Controls, headers, hover states |
| `line` | `#3A3D37` | Borders, grid lines, dividers |
| `text-primary` / `text-muted` | `#E8E9E4` / `#9A9D94` | Labels and values / secondary information |
| `accent` | `#7C6CF0` | Selection, focus, playhead, active state |
| *meters (semantic, fixed)* | green → amber → red | Conventional; never restyled |

| ID | Requirement | Pri |
|---|---|---|
| FR-UX-01 | Design token system defined and documented **before any UI code** | M |
| FR-UX-02 | Every colour, size and spacing value resolves to a token; no literals in widget code; CI-enforced | M |
| FR-UX-03 | The rearrangeable workspace (D9) receives disproportionate craft; everything around it stays quiet | M |
| FR-UX-04 | Dark theme default and primary; light theme supported | M |
| FR-UX-05 | Dense views render at display refresh rate including 120 Hz ProMotion, no dropped frames during playback | M |
| FR-UX-06 | Motion communicates state change or spatial relationship, never decorates; system reduce-motion respected | M |
| FR-UX-07 | Archivo for UI, Martian Mono for all numeric and time displays (D10) | M |
| FR-UX-08 | Layouts adapt from 13" laptop to large and multi-monitor setups without loss of function | M |
| FR-UX-09 | User-scalable UI zoom, independent of OS display scaling | S |

#### 8.1.2 Workspace flexibility (the signature)

| ID | Requirement | Pri |
|---|---|---|
| FR-WSP-01 | Panels dockable, splittable and resizable by drag | M |
| FR-WSP-02 | Panels tear off into separate windows, including onto other displays | M |
| FR-WSP-03 | Workspace layouts savable, nameable, switchable | M |
| FR-WSP-04 | 3–4 curated default layouts ship (e.g. Beatmaking, Mixing, Arranging) | M |
| FR-WSP-05 | Layout state persists per project and per user preference, with clear precedence | S |
| FR-WSP-06 | Reset-to-default always one action away — the user can never strand themselves | M |
| FR-WSP-07 | Extension-contributed panels participate fully in the workspace system | S |

#### 8.1.3 Interface copy

| ID | Requirement | Pri |
|---|---|---|
| FR-UX-10 | Controls named for what the user does, never for how OneBeat is built | M |
| FR-UX-11 | Consistent action vocabulary — the button that says *Export* produces a notification that says *Exported* | M |
| FR-UX-12 | Errors state what happened and what to do next, specifically. No vague failures, no apologies | M |
| FR-UX-13 | Every empty state is an invitation to act, with the action available in place | M |

#### 8.1.4 Onboarding & learnability

| ID | Requirement | Pri |
|---|---|---|
| FR-UX-14 | First launch opens a loaded demo project that plays immediately — never an empty window | M |
| FR-UX-15 | A new user produces a sound within 60 s of first launch, without documentation | M |
| FR-UX-16 | No audio configuration required before making sound | M |
| FR-UX-17 | **No functionality reachable only by right-click or undocumented shortcut.** FL Studio's greatest learnability failure; OneBeat must not inherit it | M |
| FR-UX-18 | Contextual help — hover reveals what a control does in plain language | S |
| FR-UX-19 | Starter template projects at New Project | S |
| FR-UX-20 | Progressive disclosure — workspace rearrangement, routing matrix, modulation and scripting present but not competing for attention on first use | M |
| FR-UX-21 | Undo covers every destructive action, so exploration is safe by default | M |
| FR-UX-22 | Keyboard shortcuts discoverable in-app and user-remappable | S |
| FR-UX-23 | **4 of 5 first-time users export an 8-bar loop within 15 minutes unaided**, before v1.0 | M |

#### 8.1.5 Accessibility floor

| ID | Requirement | Pri |
|---|---|---|
| FR-UX-24 | All primary actions keyboard-reachable; focus state always visible | M |
| FR-UX-25 | Screen-reader semantics on all controls. Flutter provides less of this by default than native — `Semantics` widgets required explicitly, especially on `CustomPainter` views | S |
| FR-UX-26 | Text and essential UI meets WCAG AA contrast in both themes | M |
| FR-UX-27 | No information conveyed by colour alone | M |

### 8.2 Audio Engine

| ID | Requirement | Pri |
|---|---|---|
| FR-ENG-01 | Real-time graph, sample-accurate, 44.1/48/88.2/96 kHz | M |
| FR-ENG-02 | Configurable buffer size (64–2048); user-visible round-trip latency | M |
| FR-ENG-03 | Audio-thread entry points marked `[[clang::nonblocking]]`; allocation-, lock- and exception-free, verified by RTSan in CI | M |
| FR-ENG-04 | Automatic plugin delay compensation across the full graph | M |
| FR-ENG-05 | Multicore processing of parallel branches, cooperating with CLAP's thread-pool extension | S |
| FR-ENG-06 | Offline render shares the same processing code as the real-time path | M |
| FR-ENG-07 | 32-bit float internal minimum; 64-bit option | S |
| FR-ENG-08 | Audio I/O behind an abstract interface; no CoreAudio types leak into engine code | M |
| FR-ENG-09 | Immutable flattened schedule published to the audio thread by atomic swap (§7) | M |

### 8.3 Plugin Hosting

| ID | Requirement | Pri |
|---|---|---|
| FR-PLG-01 | Host CLAP plugins including modulation and editor windows | M |
| FR-PLG-02 | Host VST3 plugins including editor windows | M |
| FR-PLG-03 | Host Audio Units (AUv2, AUv3) | M |
| FR-PLG-04 | Single format-agnostic internal model, built to CLAP semantics (D5) | M |
| FR-PLG-05 | Background scan with persistent cache; never blocks startup | M |
| FR-PLG-06 | Plugins crashing during scan are quarantined and reported | M |
| FR-PLG-07 | Out-of-process sandboxed hosting — a plugin crash never terminates OneBeat | M |
| FR-PLG-08 | Full state save/restore including opaque vendor chunks | M |
| FR-PLG-09 | Automation and MIDI/host-parameter mapping across all formats | M |
| FR-PLG-10 | Missing plugin: project opens, placeholder retains state, user informed | M |
| FR-PLG-11 | Editor windows float, with position and size persisted per project (D3.2) | M |
| FR-PLG-12 | Dynamic multi-output ports, reconfigurable while deactivated (DM-Q5) | S |
| FR-PLG-13 | Plugin browser: search, categories, favourites, hiding | S |
| FR-PLG-14 | VST2 | W |

### 8.4 Sequencing & Composition

| ID | Requirement | Pri |
|---|---|---|
| FR-SEQ-01 | Channel rack: per-instrument step sequencer, variable step count, swing | M |
| FR-SEQ-02 | Piano roll: note entry/edit, velocity, length, quantise, scale highlighting | M |
| FR-SEQ-03 | Step sequencer and piano roll operate on the same `NoteSequence` (DM-Q4) | M |
| FR-SEQ-04 | Patterns are references; `Make unique` clones and repoints on demand | M |
| FR-SEQ-05 | Pattern usage count visible; all instances highlighted on selection; warning on multi-use destructive edits | M |
| FR-SEQ-06 | Playlist: pattern clips, audio clips and automation clips placed freely on lanes | M |
| FR-SEQ-07 | Clip windowing — source offset, length and loop mode (DM-Q2) | M |
| FR-SEQ-08 | Non-destructive clip transforms: transpose in v1.0; velocity scale, nudge, probability in v1.x (DM-Q3) | M / S |
| FR-SEQ-09 | Automation clips as first-class timeline objects with editable curves | M |
| FR-SEQ-10 | Per-note properties (pan, pitch, modulation) | S |
| FR-SEQ-11 | Tempo and time-signature changes across the timeline | S |
| FR-SEQ-12 | MIDI file import/export | S |
| FR-SEQ-13 | Piano roll generators exposed through the extension API | S |

### 8.5 Audio Recording & Editing

| ID | Requirement | Pri |
|---|---|---|
| FR-AUD-01 | Multitrack recording from hardware inputs | S |
| FR-AUD-02 | Clip editing: trim, split, fade, gain, reverse | M |
| FR-AUD-03 | Time-stretch and pitch-shift | C |
| FR-AUD-04 | Non-destructive — source files never modified | M |
| FR-AUD-05 | Loop/beat detection and tempo sync | C |

### 8.6 Mixer & Routing

| ID | Requirement | Pri |
|---|---|---|
| FR-MIX-01 | Mixer tracks with gain, pan, mute, solo | M |
| FR-MIX-02 | Per-track plugin chain with reorder and bypass | M |
| FR-MIX-03 | Routing by stable ID and name, never integer index | M |
| FR-MIX-04 | A dedicated mixer track is auto-created per instrument by default; reassignment and sharing fully available; preference to disable | M |
| FR-MIX-05 | Arbitrary routing including sends and sidechain | M |
| FR-MIX-06 | Lane mute is an event gate; mixer mute is an audio gate — distinct verbs and icons | M |
| FR-MIX-07 | Full automation of mixer and plugin parameters | M |
| FR-MIX-08 | Peak, RMS and true-peak metering | S |
| FR-MIX-09 | Track grouping / busses | S |

### 8.7 Built-in Instruments & Effects

**Scope position:** the built-ins exist so OneBeat is usable on first launch with zero third-party plugins (supporting FR-UX-14/15), and so the extension API is proven by use (G4). Not competing with commercial suites.

| ID | Requirement | Pri |
|---|---|---|
| FR-BIP-01 | Sampler: multi-format loading, tuning, looping, ADSR, filter | M |
| FR-BIP-02 | Drum/slicer for one-shots and loops | S |
| FR-BIP-03 | Subtractive synth: multi-oscillator, filter, envelopes, LFOs | S |
| FR-BIP-04 | Core effects: parametric EQ, compressor, delay, reverb, limiter | M |
| FR-BIP-05 | Utilities: gain, stereo width, phase invert, tuner, spectrum analyser | S |
| FR-BIP-06 | Preset system shared by built-ins and extensions | S |
| FR-BIP-07 | Built-in plugin UIs use the same design tokens, render in Flutter, and dock into the workspace — D3.2 does not apply to them | M |

### 8.8 Content & Soundpacks

| ID | Requirement | Pri |
|---|---|---|
| FR-SND-01 | User-configurable content folders, indexed and browsable | M |
| FR-SND-02 | WAV, AIFF, FLAC, MP3, Ogg | M |
| FR-SND-03 | Browser: folder tree, name search, audition-on-click with tempo sync | M |
| FR-SND-04 | Drag-and-drop into channel rack, playlist or sampler, including from Finder | M |
| FR-SND-05 | Optional `pack.json` manifest: name, author, licence, tags, category | S |
| FR-SND-06 | Tag-based filtering where metadata exists | S |
| FR-SND-07 | Persistent index with incremental rescan, surviving restart | M |
| FR-SND-08 | Waveform thumbnails, generated and cached | S |
| FR-SND-09 | Packaged single-file soundpack format | C |
| FR-SND-10 | In-app soundpack marketplace | W |

> Folder-first with optional metadata. Requiring a pack format would make every existing sample library unusable without conversion.

### 8.9 Extensibility & Scripting

| ID | Requirement | Pri |
|---|---|---|
| FR-EXT-01 | Stable, versioned, documented public API over the project model, defined in WIT | M |
| FR-EXT-02 | Sandboxed WASM runtime with capability-scoped API access | M |
| FR-EXT-03 | Script console for interactive use | M |
| FR-EXT-04 | Extensions installable and discoverable in-app | S |
| FR-EXT-05 | Extensions bindable to UI actions, shortcuts and MIDI events | S |
| FR-EXT-06 | Extension points for generators, note transformations, file importers | S |
| FR-EXT-07 | Extension-contributed workspace panels | S |
| FR-EXT-08 | All built-in instruments and effects use only public API; CI-enforced | M |
| FR-EXT-09 | Extension failure is contained — never destabilises the host or the audio thread | M |

### 8.10 Project & File Management

| ID | Requirement | Pri |
|---|---|---|
| FR-PRJ-01 | Human-readable, diffable, text-based project format; binary sidecar for plugin state | M |
| FR-PRJ-02 | Stable IDs, never reused; lane order as a field, not array position; clips reference lanes, not vice versa | M |
| FR-PRJ-03 | Documented, versioned schema with forward-compatible loading | M |
| FR-PRJ-04 | Auto-save and crash recovery | M |
| FR-PRJ-05 | Project consolidation ("collect all assets") | S |
| FR-PRJ-06 | Export to WAV/AIFF/FLAC/MP3 with bit-depth and rate options | M |
| FR-PRJ-07 | Stem export | S |
| FR-PRJ-08 | Unlimited undo/redo across all operations | M |

---

## 9. Non-Functional Requirements

| ID | Requirement |
|---|---|
| NFR-01 | Round-trip latency <10 ms at 128 samples / 48 kHz on Apple Silicon |
| NFR-02 | Zero dropouts at 70% CPU; no crash in an 8-hour soak test |
| NFR-03 | No user data loss on crash; auto-save ≤2 min |
| NFR-04 | Cold start to usable UI <5 s with 500 plugins cached |
| NFR-05 | macOS 14+, Apple Silicon native |
| NFR-06 | UI thread never blocks on the audio thread or on FFI |
| NFR-07 | Clone → running build <15 min on a clean machine, documented in README |
| NFR-08 | **Sanitizer regime is mandatory.** RTSan on all `[[clang::nonblocking]]` paths; ASan, UBSan and TSan builds in CI on every PR. A PR failing any sanitizer does not merge |
| NFR-09 | MIT licence; CI check that no dependency introduces copyleft, LGPL included |
| NFR-10 | **FFI contract:** narrow, hand-designed, versioned C ABI. Audio-thread state reaches Dart only via lock-free snapshots sampled at frame rate. Dart never polls, allocates on, or blocks the audio thread. Documented as an ADR before UI work begins |
| NFR-11 | Platform-specific code confined to audio I/O, windowing and plugin-format layers, so v2 portability is a port rather than a rewrite |

---

## 10. Release Plan

### v0.1 — "It makes sound"
C++ engine, CoreAudio I/O, minimal graph, one built-in sampler, transport. Design tokens defined. **Flutter↔C++ FFI contract established and proven with a live meter at 120 Hz.** Flattened-schedule architecture in place. Sanitizer CI from the first commit.
**Exit:** a note plays without glitching, a meter moves smoothly, RTSan is clean.

### v0.2 — "It hosts" (CLAP)
CLAP scanning and hosting, floating editor windows, format-agnostic internal model, parameter automation, out-of-process sandbox. Signing and notarisation validated with a sandboxed helper now, not at v1.0.
**Exit:** 15 CLAP plugins load, play, and are crash-contained.

### v0.3 — "It sequences"
Full domain model implemented. Channel rack, piano roll, patterns, lanes, basic playlist, project save/load.
**Exit:** an 8-bar loop created, saved, reopened; the same pattern placed twice updates in both places.

### v0.4 — "It mixes and exports"
Mixer, ID-based routing, auto-created tracks, sends, automation clips, offline render, WAV/MP3 export.
**Exit:** a complete track produced and exported.

### v0.5 — "It hosts everything"
VST3, then AU via Objective-C++. Full compatibility pass against the reference set.
**Exit:** ≥90% of the reference set passes.

### v0.6 — "It's extensible"
Public API v1 in WIT, WASM runtime, console, extension loading. Built-ins ported onto the public API (FR-EXT-08).
**Exit:** an external developer writes a working extension from the docs alone.

### v0.7 — "It's furnished"
Browser and soundpack indexing, core effects, sampler polish, presets, waveform thumbnails.

### v0.8 — "It's beautiful and learnable"
Workspace system, full design pass against tokens, motion, empty states, copy pass, accessibility, onboarding, demo project, templates.
**Exit:** FR-UX-23 passes.

### v1.0 — "It's usable by someone else"
Audio clip editing, stability hardening, documentation, packaging, notarised distribution.
**Exit:** a producer who is not the author releases a track made in OneBeat.

### v2.0 — "It's everywhere"
Windows and Linux builds; WASAPI/ASIO and ALSA/JACK backends; platform packaging.

**Deferred to v2+:** audio recording, time-stretch, multicore graph, additional built-in instruments, lane grouping, audio-rate WASM DSP, docked plugin editors if Flutter platform views mature.

> **On v0.8:** design is a dedicated phase but must not be *only* a phase. Tokens exist from v0.1 and everything built between conforms. v0.8 turns "consistent" into "beautiful"; it cannot rescue a UI built without tokens.

---

## 11. Success Metrics

**Craft & usability**
- Novice exports an 8-bar loop unaided in <15 min: **4 of 5 test users**
- First launch to first sound: **<60 s**
- Frame drops during playback on piano roll and playlist: **zero at 120 Hz**
- Users who save a custom workspace layout: **>30%** (validates D9)

**Product**
- Plugin compatibility: **≥90%** of the reference set
- Crash-free session rate: **>99%**
- Reported data-loss incidents: **zero**
- Sanitizer failures reaching main: **zero**

**Community**
- External contributors with merged PRs: **≥3 by v1.0**
- Median time-to-first-successful-build: **<30 min**
- Third-party extensions published: **≥5 by v1.0**
- Tracks published by external users: **≥1 before declaring v1.0**

---

## 12. Risks

| ID | Risk | Impact | Mitigation |
|---|---|---|---|
| R1 | **Scope collapse under parity ambition** | Fatal | Vertical slices (§10). Parity is a direction, never a release criterion. |
| R2 | **Bus factor of 1** — a "community project" with no community | High | Contributor onboarding (NFR-07) is a v0.x requirement. Cross-platform reach (D3) widens the pool. |
| R3 | **Plugin compatibility long tail** | High | Compatibility harness and reference set before v0.5; sandbox so failures degrade rather than crash. |
| R4 | **C++ memory and RT safety with a solo dev and AI agents** | High | *The price of D2, payable in full.* NFR-08 merge-blocking. `[[clang::nonblocking]]` on every audio-thread entry point. Modern C++ only, RAII throughout. Human review of every audio-thread function and every FFI boundary function without exception. Agents used freely for UI, project model, file I/O and tests. |
| R5 | **The C ABI ossifies** — early mistakes become permanent | Medium | Design deliberately (NFR-10), version it, keep it narrow: commands in, snapshots out. |
| R6 | **FFI or GC jank breaks the 120 Hz target** | High | Proven in v0.1 with a live meter before any real UI exists. Fails cheaply if it fails. |
| R7 | **"Beautiful" is a specialist skill and there is one person** | Medium | Spend all boldness on the workspace (D9); keep everything else disciplined. **If you recruit, make the first person a designer, not a second engineer** — agent leverage exists on code, not on taste. |
| R8 | **Workspace flexibility defeats learnability** — D9 vs G6 | Medium | Opinionated defaults (D9, FR-UX-20, FR-WSP-04/06). Watch specifically in FR-UX-23 testing. |
| R9 | **Floating plugin editors feel dated** to users expecting docked panels | Low | Most DAWs float by default; persist position and size per project (FR-PLG-11). |
| R10 | **Apple platform friction** — notarisation vs out-of-process hosting | Medium | Validate the signing path with a sandboxed helper in v0.2. |
| R11 | **Extensibility becomes decorative** | Medium | FR-EXT-08 CI enforcement. If the public API isn't enough for the built-ins, it isn't enough for anyone. |
| R12 | **Flutter desktop integration gaps** — menus, Finder drag-and-drop, multi-window | Medium | Prototype FR-SND-04 and FR-WSP-02 in v0.1; both are load-bearing and both are Flutter's weaker desktop areas. |
| R13 | **Dart GC pauses at 120 Hz** | Medium | No per-frame allocation in the render path; pre-allocate and reuse painters; profile early. |
| R14 | **No prior art** — no serious DAW has been built in Flutter | Medium | v0.1 exit criteria are deliberately the three riskiest Flutter unknowns. If Flutter fails, it fails when switching costs weeks rather than years. |
| R15 | **Domain model drift** — conventional DAW assumptions creep back during v0.3 | Medium | The companion domain spec is normative. Anti-pattern table in §6 of that document is a review checklist for every sequencer PR. |
| R16 | **Name conflict** — "beat" is heavily used in audio trademarks | Low | Clear D8 before the repo is public. |

---

## 13. Decision History

| Decision | v0.1 | v0.2 | v0.3 | **v1.0** | Why it moved |
|---|---|---|---|---|---|
| Licence | Open | MIT | MIT | MIT | — |
| Core language | Open | Rust | C++20 | **C++20** | RTSan closed the safety-tooling gap; Rust's guarantee lapses at the `unsafe` plugin boundary; VST3/AU are natively C++ |
| UI | Open | SwiftUI | Flutter | **Flutter** | Canvas suits dense DAW views; hot reload; restores cross-platform; native look irrelevant for DAWs |
| Plugin order | VST3 first | CLAP first | CLAP first | **CLAP first** | Rationale shifted from ecosystem maturity to model validation |
| AU hosting | Unspecified | Swift shim | Objective-C++ | **Objective-C++** | Direct with a C++ core |
| Platforms | macOS-first | macOS permanent | macOS v1, all v2 | **macOS v1, all v2** | Reopened by the Flutter decision |
| Plugin editors | Assumed docked | Assumed embeddable | Floating | **Floating** | Flutter platform-view focus traversal incomplete |
| Signature element | — | Open | Workspace | **Workspace** | Makes the invisible differentiator visible |
| Domain model | Unspecified | Unspecified | Unspecified | **Two orthogonal axes** | The subtlest part of FL's design and the most-cloned incorrectly |

---

## 14. Requirements Traceability

| Stated requirement | Where addressed | How it changed under analysis |
|---|---|---|
| "Reference is FL Studio" | §3, §7 | Workflow reference, not parity target; the *model* is copied precisely, the ergonomics are not |
| "VST plugin support" | §8.3 | Expanded to CLAP + VST3 + AU; VST2 impossible; CLAP-first ordering |
| "Add custom soundpacks" | §8.8 | Folder-based indexing with optional metadata, not a proprietary pack format |
| "Some VST plugins built-in" | §8.7 | Minimum usable set; repurposed as the dogfooding mechanism for the extension API |
| "Full FL-parity ambition" | §5, §10 | Retained as vision, removed from release scope |
| "Open-source community project" | §11, R2, D7 | Community metrics added; governance recorded honestly as solo/BDFL |
| "Modern, hackable architecture" | §8.9, D9 | Primary differentiator; given a visible surface via the workspace |
| "Permissive licence — MIT" | D1 | Excludes JUCE *and* libsndfile; drove the dependency shortlist |
| "Beautiful UI, easy to get hands on" | §8.1, G5, G6, R7 | 31 testable requirements, two goals, four metrics, a release phase and a resourcing risk |
| "C++ instead of Rust" | D2, R4 | Accepted, with the sanitizer regime as the mandatory price |
| "Flutter frontend" | D3, R12–R14 | Accepted; forces floating plugin editors; restores cross-platform |
| "Format-agnostic internal model" | D5 | Accepted, modelled on CLAP rather than the intersection |
| "Decide the pattern/channel/mixer relationship" | §7 + companion | Two orthogonal axes; seven deviations from FL; the flattened-schedule consequence |

---

## 15. Inputs to UI Prototyping

The prototyping phase has one job beyond producing screens: **kill or confirm Flutter before v0.1 code exists.** Three of the four riskiest unknowns in this document are things a prototype can answer in days.

### 15.1 Technical questions the prototype must answer

| # | Question | Why it's load-bearing | Pass condition |
|---|---|---|---|
| P1 | Can `CustomPainter` render a scrolling piano roll with ~2,000 notes at 120 Hz? | R13, R14, FR-UX-05. If this fails, Flutter is the wrong choice and everything downstream changes | Sustained 120 fps, no GC-induced frame drops over 60 s of continuous scroll |
| P2 | Can a panel tear off into a second native window and back? | FR-WSP-02, the signature element. Multi-window is Flutter desktop's weakest area | A panel detaches, renders, receives input, and re-docks |
| P3 | Does Finder drag-and-drop deliver file paths reliably? | FR-SND-04, core to the browser workflow | Multiple audio files dropped from Finder resolve to valid paths |
| P4 | What is the FFI round-trip cost for a per-frame state snapshot? | NFR-10, R6 | A 60-value snapshot crosses the boundary in well under one frame budget |

Answer these with throwaway code, not with the real UI. If P1 fails, stop and reconsider D3 — that is a cheap reversal now and a catastrophic one at v0.4.

### 15.2 Screens to prototype, in priority order

1. **Arrangement view** — lanes, pattern clips, playhead, selection. Exercises P1 and the palette against user-coloured clips.
2. **Piano roll** — the densest view and the one users judge a DAW by.
3. **Channel rack** — step grid, per-instrument rows, the pattern/instrument relationship made visible.
4. **Mixer** — tracks, chains, meters. Exercises the semantic meter colours.
5. **Browser** — folder tree, search, waveform thumbnails, drag sources.
6. **Workspace chrome** — docking, splitting, tear-off, layout switcher. The signature; prototype it last but budget it properly.

### 15.3 Design constraints carried into prototyping

- **Tokens first** (FR-UX-01). Establish the palette in §8.1.1 and the type scale in D10 before drawing a screen.
- **Chrome stays chromatically quiet.** Test every screen with a project full of saturated user-chosen clip colours. If the chrome competes, the chrome is wrong.
- **Meters keep their conventional colours.** Green–amber–red is read instantly; restyling it costs comprehension and buys nothing.
- **Spend boldness once** (D9). The workspace is the memorable thing; everything else is disciplined and quiet.
- **Design the empty and error states in the same pass**, not afterwards (FR-UX-12/13). They are where craft is most visible and most often skipped.
- **Prototype the default layout as carefully as the flexibility.** Most users will never rearrange anything (D9, R8).

### 15.4 Still open

| # | Question | Needed by |
|---|---|---|
| OQ-1 | Trademark clearance for "OneBeat" | Before public repo |
| OQ-2 | Project file format — TOML, JSON, or custom text (FR-PRJ-01) | v0.3 |
| OQ-3 | Sandbox IPC mechanism for out-of-process hosting | v0.2 |
| OQ-4 | Plugin compatibility reference set — 50 plugins, weighted to free and obtainable, selected for what each stresses rather than popularity | v0.5 |
| OQ-5 | **Usability test participants.** FR-UX-23 needs five people who have never seen OneBeat. You are permanently disqualified from being one of them, and there is no community yet to draw from | v0.8 |