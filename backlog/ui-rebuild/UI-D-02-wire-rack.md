# UI-D-02 — Wire channel rack

| | |
|---|---|
| **Phase** | D — Wiring |
| **Type** | Feature (integration) |
| **Dependencies** | UI-C-02, UI-D-01 |
| **Reference** | existing `app/lib/src/ui/rack_store.dart`, `pattern_store.dart`, old `channel_rack.dart` (behaviour source of truth), `docs/channel-rack.md`, ticket OB-3-09 |
| **Target files** | `app/lib/src/features/channel_rack/rack_store.dart` + `rack_binding.dart`; tests `app/test/features/channel_rack/rack_binding_test.dart` |
| **Estimate** | L |

## Context

The old rack is fully functional against ABI 1.6 (steps, velocity, swing, divisors, pattern scoping — see OB-3-09). This ticket re-homes that behaviour without re-deriving it: **port** `rack_store.dart` (and the rack-relevant parts of `pattern_store.dart`) into `features/channel_rack/rack_store.dart` — same commands, transactions and snapshot handling, adapted to the feature layout — then the binding translates store state ⇄ `ChannelRackScreenVm`. The old files are reference only and die in D-09.

## Scope

1. **`RackBinding`**: store → vm (rows from pattern-scoped instruments, steps/velocity, playing step from snapshots, selection, pattern tabs from `pattern_store.dart`); callbacks → store commands (step toggle, velocity, row select, add channel, add instrument, show-all toggle, swing, snap/divisor, remove-from-pattern vs delete).
2. Restore the gesture layer the old rack had, as wrappers/controllers around the presentational widgets (inside `features/channel_rack/`, or as opt-in gesture parameters on the components): drag-paint/erase with one undo entry per gesture; velocity drag; FR-UX-17 — every right-click action also reachable via visible UI.
3. Playback feedback: playing column driven by snapshot data with no per-frame allocation (reuse the old approach; keep the stage-3 paint-cost test philosophy — add a paint-cost test for the new row painter if steps became a painter).
4. Inspector wiring: selection → `ChannelInspectorVm` (vol/pan/M/S/FX chips/route from the store; keyboard taps audition via the existing preview path if one exists, else stub with TODO).
5. Tests against `fake_rack_client.dart`: step toggle round-trip, drag-paint transaction, velocity edit, pattern switch re-scopes rows.

## Acceptance criteria

- [ ] OB-3-09's checked acceptance criteria still hold on the new rack (program 4-instrument pattern, swing, D-M5 behaviours, velocity, no right-click-only actions).
- [ ] Old rack tests migrated or superseded; suite green; analyze + token lint clean.
- [ ] Rack golden(s) from C-02 unchanged (wiring must not alter rendering).

## Out of scope

Deleting old `channel_rack.dart` (D-09).
