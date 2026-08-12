# EPIC-4 — v0.4 "It mixes and exports"

**Exit criterion (PRD §10):** a complete track produced and exported.
**Depends on:** Stage 3 closed (OB-3-15). Consumes: mixer-track stubs (OB-3-02/07), parameter path (OB-2-09), offline driver (OB-1-13).
**Status:** epic — break into tickets when Stage 3 closes.
**Key references:** FR-MIX-01…09, FR-SEQ-09, FR-ENG-04/06, FR-PRJ-06, D-M2, D-M4; design screens `onebeat-routing.html`, `onebeat-routing-overview.html`, `onebeat-routing-default.html`, `onebeat-export.html`, `onebeat-export-progress.html`, `onebeat-export-done.html`, `onebeat-export-fail.html`.

## Scope

**In:** real `MixerTrack` behaviour (gain/pan/mute/solo, ordered effect chains with reorder+bypass); ID-based arbitrary routing incl. sends and sidechain (FR-MIX-03/05); auto-created track behaviour completed + disable preference (D-M2); audio-gate mute vs lane mute distinction shipped in UI (D-M4); mixer panel UI per design; routing overview UI (3 designed screens); automation clips end-to-end (first-class timeline objects, editable curves → flattener → parameter events, FR-SEQ-09, FR-MIX-07); plugin delay compensation across the graph (FR-ENG-04); offline render sharing the RT path (FR-ENG-06 via OB-1-13's driver) with the 4-screen export flow: WAV/AIFF/FLAC/MP3, bit depth/rate options (FR-PRJ-06); basic master/track peak metering in the mixer (RMS/true-peak → v1.x, FR-MIX-08).

**Out:** track grouping/busses UI beyond routing (FR-MIX-09, v1.x); stem export (v1.x); MP3 *import* (Stage 7's concern); mastering-grade metering.

## Risks / watch

- Graph cycles: routing UI must prevent feedback loops (validation at edit time, not audible discovery).
- PDC interacts with the sandbox latency model — ADR-003's choice lands here; verify compensated null test (phase-cancellation test through a latency plugin).
- MP3 encode under MIT: LAME is LGPL — **not usable**; evaluate Shine (MIT?) / minimp3-adjacent encoders or drop MP3 export to v1.x with owner sign-off (licence audit gates this).

## Candidate tickets (~12)

1. Mixer track engine: gain/pan/mute/solo + chain processing.
2. Routing graph: sends, sidechain taps, cycle prevention, topological order.
3. PDC across the full graph (null test as AC).
4. Mixer panel UI per design (strips, chain list, drag reorder, bypass).
5. Routing overview UI (3 screens: matrix/default/detail).
6. D-M2 completion: auto-create behaviour, naming, disable preference.
7. Automation clip model + curve editor UI.
8. Automation flattening → parameter events (extends OB-3-04).
9. Mixer/plugin parameter automation binding UX (arm/target picking).
10. Offline render engine mode (bounce; consumes OB-1-13 driver; progress/cancel).
11. Export UI flow (4 designed screens) + encoders (WAV/AIFF/FLAC; MP3 pending licence).
12. v0.4 exit verification: produce and export a complete track; A/B offline vs realtime render null test.
