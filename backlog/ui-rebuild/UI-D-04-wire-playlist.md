# UI-D-04 — Wire playlist

| | |
|---|---|
| **Phase** | D — Wiring |
| **Type** | Feature (integration) |
| **Dependencies** | UI-C-04, UI-D-01 |
| **Reference** | existing `app/lib/src/ui/arrangement_store.dart`, old `arrangement.dart`, `clip_inspector.dart`, tickets OB-3-12, OB-3-13 |
| **Target files** | `app/lib/src/features/playlist/playlist_store.dart` + `playlist_binding.dart`; tests `app/test/features/playlist/playlist_binding_test.dart` |
| **Estimate** | M |

## Scope

1. **Store port + `PlaylistBinding`**: port the old `arrangement_store.dart` into `features/playlist/playlist_store.dart` (same commands/undo/snapshot behaviour — old file is reference only, deleted in D-09); binding maps store state → `PlaylistScreenVm` (clips with names/colours/lanes/positions, playhead from snapshots, selection); callbacks → store commands.
2. Gesture layer: place, move, resize (clip windowing per OB-3-13), duplicate, delete, select, double-click rename — port from old `arrangement.dart`; one undo entry per gesture.
3. Pattern-clip instances: the same pattern placed twice updates in both places (stage-3 exit criterion) must hold through the new UI — cover with a binding test.
4. Clip selection surfaces whatever the old `clip_inspector.dart` offered (inline or panel — match old behaviour; visual style from the design system).
5. Tests against fakes: place/move/resize round-trip, dual-instance update, rename.

## Acceptance criteria

- [ ] OB-3-12/13 behaviours reachable in the new playlist; stage-3 exit scenario passes manually against the real engine.
- [ ] Suite green; analyze + token lint clean; C-04 golden unchanged.

## Out of scope

Deleting old `arrangement.dart` (D-09); audio-clip waveforms (not in v0.3 scope).
