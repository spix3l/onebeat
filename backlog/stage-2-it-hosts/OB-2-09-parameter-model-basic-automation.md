# OB-2-09 — Host parameter model & basic automation

| | |
|---|---|
| **Stage** | 2 — v0.2 "It hosts" |
| **Type** | Feature (engine) |
| **Priority** | High |
| **Dependencies** | OB-2-07 |
| **References** | FR-PLG-09 (foundation), FR-MIX-07 (future consumer) |
| **Estimate** | M |

## Context

Stage 2 must prove parameters automate through the whole stack (PRD v0.2 scope: "parameter automation"). Full automation *clips* with editable curves arrive with the domain model (Stage 3/4); here we build the engine-side parameter path they will drive.

## Scope

1. **Host parameter registry:** every plugin instance's parameters addressable as `(InstanceId, ParamId)` — stable across sessions; value + modulation channels per the internal model.
2. **Automation events in the schedule:** extend OB-1-07's event types with time-stamped parameter events (value, and modulation offset where supported); the playback cursor delivers them sample-positioned within blocks; smoothing policy defined (host does not smooth by default — plugins own their smoothing; document).
3. **Test path:** schedule-built parameter ramps (the Stage 3 flattener will generate these from automation clips later) driving audible change in a hosted plugin; deterministic offline-render test with the event-capture harness.
4. **Live changes:** UI-originated parameter changes (from the generic editor, OB-2-08) travel the command queue with gesture begin/end, coexisting with schedule automation (last-writer semantics documented — full "touch" modes deferred).
5. **ABI:** parameter list/get/set surface for Dart per ADR-002 evolution policy.

## Acceptance criteria

- [x] A scheduled parameter ramp audibly sweeps a hosted plugin (e.g. filter cutoff) sample-accurately (offline render shows monotone parameter application at correct positions).
- [x] Modulation events applied non-destructively on a supporting plugin: underlying value unchanged after modulation returns to zero.
- [x] Live UI changes and scheduled automation coexist without fighting per the documented semantics.
- [x] RTSan/TSan clean across the new paths; human review completed (R4).

## Out of scope

- Automation clip UI/curves (Stage 3/4). MIDI-learn mapping (FR-PLG-09 full, Stage 4+). Mixer parameter automation (Stage 4).
