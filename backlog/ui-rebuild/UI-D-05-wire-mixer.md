# UI-D-05 — Wire mixer + routing

| | |
|---|---|
| **Phase** | D — Wiring |
| **Type** | Feature (integration) |
| **Dependencies** | UI-C-05, UI-D-01 |
| **Reference** | existing `app/lib/src/ui/mixer_view.dart` (uncommitted changes exist on this branch — read `git status` first), `meter_state.dart`, `engine_controller.dart` |
| **Target files** | `app/lib/src/features/mixer/mixer_binding.dart`; tests `app/test/features/mixer/mixer_binding_test.dart` |
| **Estimate** | M |

## Context

Mixing/routing backend surface is partly v0.4 (EPIC-4) territory. Wire what the current ABI exposes; where the engine has no facility yet (sends, sidechain), the binding surfaces the vm with disabled/stub affordances and files the gap in a `GAPS.md` note in this folder — do not fake working behaviour.

## Scope

1. **`MixerBinding`**: engine mixer/track state → `MixerScreenVm`; meter levels via `meter_state.dart` (real-time, allocation-free per existing meter approach); selection → routing panel vm.
2. Callbacks: strip select, mute/solo, fader (if ABI supports), route changes, sends/sidechain where supported.
3. The detached mixer window (C-12) shares this binding — same vm, fader variant.
4. Tests with fakes: selection round-trip, mute/solo commands, meter vm update on snapshot.

## Acceptance criteria

- [ ] Live meters move on playback in the new mixer against the real engine.
- [ ] Every non-functional affordance is visibly disabled and listed in `GAPS.md` with the ABI capability it waits on.
- [ ] Suite green; analyze + token lint clean; C-05 goldens unchanged.

## Out of scope

New engine/ABI work (that is EPIC-4; audio-thread and FFI changes need human review — R4).
