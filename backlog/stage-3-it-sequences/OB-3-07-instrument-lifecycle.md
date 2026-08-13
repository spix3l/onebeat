# OB-3-07 — Instrument lifecycle & management

| | |
|---|---|
| **Stage** | 3 — v0.3 "It sequences" |
| **Type** | Feature (model + UI) |
| **Priority** | High |
| **Dependencies** | OB-3-02, OB-3-03, OB-2-10 (plugin list) |
| **References** | ARCHITECTURE.md §3.1, D-M2 (stub), FR-MIX-03/04 (groundwork) |
| **Estimate** | M |

## Context

Instruments are project-global with stable IDs — the single join between the time and signal axes. This ticket makes them creatable/manageable and wires the OB-2-10 plugin flow into the domain model.

## Scope

1. **Create:** from the plugin list (or the built-in sampler) → new `Instrument` with generated name/colour; **auto-create-mixer-track default (D-M2):** with mixer tracks still stubs, the instrument is assigned a dedicated `MixerTrackId` from the registry, named after it (behaviourally inert until Stage 4 but the routing data is real and correct from birth; the disable-preference arrives with the Stage 4 mixer).
2. **Manage:** rename, recolour, reorder (order field), replace plugin (state handling: keep sequences, new plugin state); duplicate (new ID, copied state).
3. **Delete with impact surfacing (§3.1):** confirmation states "removes its notes from N patterns and M clips reference those patterns" using the OB-3-02 impact report; fully undoable (OB-3-03).
4. **Preview/audition:** clicking an instrument (or pressing a key with it selected) fires a preview note through the engine — the "first sound" primitive that FR-UX-15 will lean on.
5. **UI:** instrument list presented as the channel-rack row headers (visual per design `onebeat-shell.html` left rack strip); name, colour chip, mute-preview; selection drives piano-roll/rack context.

## Acceptance criteria

- [x] Create → audition → rename/recolour → duplicate → delete round trip, all undoable.
- [x] Delete confirmation shows the correct pattern count; undo restores all sequences (test on a 5-pattern matrix).
- [x] Every new instrument carries a valid dedicated `MixerTrackId` routing entry (D-M2 data path verified even though audio behaviour waits for Stage 4).
- [x] IDs stable across save/load; no reuse after delete.

## Closeout evidence

- `model/commands.cpp` owns generated unique names, palette colours, stable
  presentation order, dedicated tracks, duplicate and replace semantics. The
  five-pattern delete/undo matrix is in `test_model_commands.cpp`.
- ABI 1.5 exposes the project instrument registry and every lifecycle command;
  `test_abi.cpp` drives the whole surface through the C boundary and freezes the
  new POD layout.
- `instrument_strip.dart` is the permanent channel-rack header strip: selection,
  inline rename, colour, mute, preview, reorder, duplicate and an impact-aware
  two-step delete. The plug-in browser exposes Add and Replace as separate
  visible actions.
- `Instrument::order` is canonical project data and is covered by the worked
  example plus byte-identical and field-by-field save/load tests. Older files
  without the field receive deterministic map order on load.
- Full local CI is green: Debug, Release, ASan/UBSan, TSan, RTSan, ABI-C,
  clang-tidy, clang-format, seam/license/token checks, Flutter analyze and
  Flutter tests. See [`docs/instrument-lifecycle.md`](../../docs/instrument-lifecycle.md).

## Out of scope

- Mixer UI/behaviour (Stage 4). Multi-out port UI (Stage 5, DM-Q5).
