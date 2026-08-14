# UI-D-01 — Wire shell, transport, status bar

| | |
|---|---|
| **Phase** | D — Wiring |
| **Type** | Feature (integration) |
| **Dependencies** | UI-C-01 (and ideally C-02…05 merged so there is something to switch between) |
| **Reference** | existing `app/lib/src/ui/shell.dart`, `engine_controller.dart`, `transport_readout.dart`, `action_registry.dart`, `app_menu_bar.dart`, `meter_state.dart` |
| **Target files** | `app/lib/src/core/` (rebuilt infrastructure), `app/lib/src/features/shell/shell_binding.dart`, edits to `app/lib/main.dart`; tests `app/test/features/shell/shell_binding_test.dart` |
| **Estimate** | M |

## Context

First integration ticket: make the app boot into the new `ShellScreen` while the old shell remains available behind a flag until D-09. This ticket also establishes `app/lib/src/core/` — the old `engine_controller.dart`, `action_registry.dart`, `shortcuts.dart`, `meter_state.dart` and `frame_stats.dart` are **ported** there (read, rewrite, adapt — never imported from `lib/src/ui/`), because nothing under the old tree survives D-09. Port faithfully: the transport/meter snapshot handling and action model are proven code; this is a move-and-adapt, not a redesign.

## Scope

0. **`core/` port**: bring engine controller, action registry, shortcuts and meter state into `app/lib/src/core/` with their existing tests adapted alongside. The old copies stay in place, untouched, still driving the old shell until D-09.
1. **`ShellBinding`** — a widget owning the mapping: listens to the core engine controller (transport state, bpm, sig, position, meter levels), builds `ShellScreenVm` each frame-change, passes callbacks down: play/stop/loop/undo/redo → core actions; rail select → workspace switching; menu taps → menus rebuilt in `features/shell/` from the old `app_menu_bar.dart` action list; Export → opens the (new, if D-06 landed; else old) export dialog.
2. Position/BPM readouts formatted exactly as the vm expects (`124.00`, `02:01:218`); clock = real time (goldens keep using fixtures — bindings are tested with fakes, not goldens).
3. Workspace switching: rail index → the new screens where merged (rack, piano, playlist, mixer), old widgets where not — temporary shims allowed and marked `// TODO(UI-D-09)`.
4. Boot flag: `--dart-define=OB_NEW_UI=true|false` (default **true**); old shell path kept compiling.
5. Tests with the existing fake clients (`test/support/fake_*`): transport state round-trips into the vm; play button callback reaches the engine fake; rail switching swaps workspaces.

## Acceptance criteria

- [ ] `tools/dev.sh` (or `flutter run`) boots into the new shell against the real engine; transport plays/stops audibly.
- [ ] Old test suite still green; new binding tests green.
- [ ] No presentational file gained an engine import (engine access only from `core/` and `*_binding.dart` files).
- [ ] analyze + token lint clean.

## Out of scope

Deleting the old shell (D-09), per-surface interactions (D-02…D-08).
