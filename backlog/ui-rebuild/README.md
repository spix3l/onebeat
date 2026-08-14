# UI Rebuild — presentation-first workstream

**Date:** 14 August 2026
**Mockups:** exported from the Pen design file into [`ui-files/`](../../ui-files/) — `screens/*.png` (28 full screens at 1600×1000, exported at 2×) and `components/*.png` (isolated components). These PNGs are the single source of truth for every ticket here. Do not guess at layout: open the referenced PNG and match it.

## Why this workstream exists

The previous attempt built screens and behaviour together and failed. This time the work is split into strictly separable phases:

- **Phase A — Foundations.** Design tokens synced with the Pen file; a component golden-test harness. Small, lands first, everything depends on it.
- **Phase B — Component library.** Pure presentational widgets — shared atoms in `app/lib/src/ui_kit/`, feature-specific pieces in their `app/lib/src/features/<feature>/` folder — one ticket per cluster. **No engine, FFI, or store imports.** Every widget takes plain data + callbacks. Every ticket ships golden tests.
- **Phase C — Screens.** Full-screen compositions, one per feature folder, driven by immutable view-model classes filled with fixture data that reproduces the mockup exactly. Golden test per screen at 1600×1000.
- **Phase D — Wiring.** Per-feature stores and bindings, written fresh inside each feature folder. The old stores (`rack_store`, `piano_roll_store`, `arrangement_store`, `engine_controller`, …) are **behavioural reference only** — port the logic you need, then they die.

**This is a full revamp: no file under `app/lib/src/ui/` survives.** The old tree keeps the app running until the switch-over, and its code is the source of truth for *behaviour* (gesture transactions, snapshot handling, paint-cost tricks) — read it, port from it, never import it. UI-D-09 deletes the entire directory.

Phases B and C are wide: each ticket is independent of its siblings and sized for one agent on a cheaper model. Phase D is where judgment is needed; those tickets are fewer and richer.

## Dependency graph

```
UI-A-01 (tokens+fonts) ──► UI-A-02 (harness+fixtures) ──► every UI-B-*
UI-B-01 core controls ──────► most UI-C-*
UI-B-02 top chrome ─┐
UI-B-03 rail+status ─┼──► UI-C-01 shell ──► UI-C-02..05 (embedded screens)
UI-B-04 browser ────┘
UI-B-05 rack rows + UI-B-06 inspector ──► UI-C-02 channel rack
UI-B-07 piano roll pieces ──► UI-C-03 piano roll
UI-B-08 playlist pieces ──► UI-C-04 playlist
UI-B-09 mixer strips + UI-B-10 routing panel ──► UI-C-05 mixer
UI-B-11 dialogs/overlays/windows ──► UI-C-06..12
UI-C-xx ──► UI-D-xx (one wiring ticket per surface) ──► UI-D-09 cleanup
```

Safe parallel batches:
1. UI-A-01 → UI-A-02 (serial, fast)
2. UI-B-01 … UI-B-11 — **all eleven in parallel**
3. UI-C-01 … UI-C-12 — all in parallel once their B-deps merged (C-02…05 embed inside the shell frame from C-01; they can be built against a placeholder shell and slotted in later — see the view-model rule below)
4. UI-D-01 … UI-D-08 in parallel, then UI-D-09

## Conventions (read before writing any code)

**File layout — feature-first.**

```
app/lib/src/
  design/                      # tokens (updated in A-01, kept)
  engine/                      # FFI backend (kept, out of scope for this workstream)
  ui_kit/                      # shared presentational atoms: knob, buttons, chips,
                               #   dropdown, search, dialog scaffold, empty state,
                               #   banner, floating window, popover menu
  core/                        # app-wide non-visual infrastructure, rebuilt in D-01:
                               #   engine controller, action registry, shortcuts, meters
  features/
    shell/                     # menu bar, transport bar, rail, status bar,
                               #   shell_screen.dart, shell_binding.dart
    browser/                   # browser panel
    channel_rack/              # rack_row, rack_toolbar, channel_inspector,
                               #   channel_rack_screen, rack_store, rack_binding
    piano_roll/                # key_column, note_grid, velocity_lane, pr_toolbar,
                               #   piano_roll_screen, store, binding
    playlist/                  # ruler, clip_card, canvas, playlist_screen, store, binding
    mixer/                     # mixer strips, routing panel, mixer_screen, binding
    export/                    # export flow dialogs + binding
    preferences/               # settings pages + binding
    startup/                   # first-run, first-setup, empty project, disconnected
    plugins/                   # plugin window chrome + params/builtin/failed + hosting
    console/                   # script console
    extensions/                # extension manager
    workspace/                 # layouts menu, detached windows, drag/dock
```

Each feature folder owns everything about the feature: its widgets, `<feature>_screen.dart`, `<feature>_vm.dart`, and in Phase D its `<feature>_store.dart` + `<feature>_binding.dart`. Cross-feature imports: `ui_kit/`, `design/`, and (from bindings only) `core/` + `engine/`. A feature never imports another feature's internals — if two features need a widget, it moves to `ui_kit/`.

Tests mirror the tree: `app/test/ui_kit/` and `app/test/features/<feature>/`, goldens colocated in a `goldens/` folder next to the test, fixtures in `app/test/features/<feature>/fixture.dart` (shared demo-project constants stay in `app/test/support/ui_fixtures.dart`).

- **Do not modify existing files** under `lib/src/ui/` (the old shell keeps running until D-09) except where a ticket explicitly says so. New code only adds files.

**Tokens.** Widget code contains **zero literal colours or dimensions** — `tools/token_lint.py` fails CI on `Color(0x…)`, hex, raw `EdgeInsets`/`SizedBox`/`fontSize` in widget code. UI-A-01 extends its scan scope to `lib/src/ui_kit/`, `lib/src/core/` and `lib/src/features/`. Read tokens via `OneBeatTheme.of(context)` (`app/lib/src/design/tokens.dart`). If a token you need does not exist, add it in UI-A-01 style (semantic name, light-ready) — never inline the value.

**View-model rule (what makes phases separable).** A screen widget's constructor takes exactly `(vm, callbacks)`:

```dart
class MixerScreenVm {
  const MixerScreenVm({required this.strips, required this.routing});
  final List<MixerStripVm> strips;   // plain immutable data, no engine types
  final RoutingPanelVm? routing;
}

class MixerScreen extends StatelessWidget {
  const MixerScreen({required this.vm, required this.onSelectStrip, ...});
}
```

No screen or component may import `engine/`, `*_store.dart`, or `engine_controller.dart`. Callbacks are plain `ValueChanged`/`VoidCallback` typedefs that Phase D will connect. If you feel a need for state beyond local ephemeral UI state (hover, drag-in-progress), it belongs in the vm — stop and put it there.

**Golden tests.** Use the harness from UI-A-02: `loadAppFonts` in `setUpAll` (real Archivo/MartianMono — block glyphs measure differently), fixed `Size`, `uiGolden('<name>')` resolving to a `goldens/` folder colocated with the test. Fixture data must reproduce the mockup's content (same names, same step patterns, same numbers) so a human can diff golden vs mockup side by side. Deterministic only: playhead stationary, no animations mid-flight, no `DateTime.now()` (the 14:02 clock in the mockups is a fixture value).

**Fidelity bar.** Match the mockup's layout, spacing rhythm, colours and type. You are *not* pixel-diffing against the PNG — the golden records what *you* built; the acceptance bar is that a reviewer putting your golden next to the mockup sees the same design. When a measurement is unclear, derive it from neighbouring elements in the PNG (export scale is 2×: measure px, divide by 2).

**Definition of done for every ticket.**
- `cd app && flutter analyze` clean.
- `python3 ../tools/token_lint.py` (from `app/`) clean, or `python3 tools/token_lint.py` from repo root.
- `flutter test test/ui_kit test/features` green, new goldens committed.
- Old tests still green: `flutter test`.
- Branch `ui-rebuild/<ticket-id>`, push, hand over the PR URL (do not open the PR with `gh` — wrong identity on this machine).

**Interaction scope in B/C.** Build the *states* the mockups show (hover/active/selected/disabled variants where visible), with callbacks fired on tap. Do not build drag-and-drop, keyboard shortcuts, or focus routing in B/C unless the ticket says so — that is Phase D territory.

## Ticket index

| ID | Title | Deps | Size |
|---|---|---|---|
| [UI-A-01](UI-A-01-token-sync.md) | Token & font sync with the Pen palette | — | S |
| [UI-A-02](UI-A-02-golden-harness.md) | Component golden harness + shared fixtures | A-01 | S |
| [UI-B-01](UI-B-01-core-controls.md) | Core controls: knob, buttons, dropdown, chips, search | A-02 | M |
| [UI-B-02](UI-B-02-top-chrome.md) | Top chrome: menu bar, transport, readouts, export | A-02 | M |
| [UI-B-03](UI-B-03-rail-statusbar.md) | Left rail + status bar | A-02 | S |
| [UI-B-04](UI-B-04-browser-panel.md) | Browser panel | A-02 | M |
| [UI-B-05](UI-B-05-rack-row.md) | Channel rack row + step grid + rack toolbar | A-02 | M |
| [UI-B-06](UI-B-06-channel-inspector.md) | Channel inspector strip | A-02 | M |
| [UI-B-07](UI-B-07-piano-roll-pieces.md) | Piano-roll pieces: keys, grid, velocity, toolbar | A-02 | L |
| [UI-B-08](UI-B-08-playlist-pieces.md) | Playlist pieces: ruler, clip cards, playhead | A-02 | M |
| [UI-B-09](UI-B-09-mixer-strips.md) | Mixer strips: mini, fader, master | A-02 | M |
| [UI-B-10](UI-B-10-routing-panel.md) | Routing panel pieces | A-02 | M |
| [UI-B-11](UI-B-11-dialogs-overlays.md) | Dialog scaffold, empty states, banners, floating windows | A-02 | M |
| [UI-C-01](UI-C-01-shell-screen.md) | Shell screen + view switching | B-02,03,04 | M |
| [UI-C-02](UI-C-02-channel-rack-screen.md) | Channel rack screen | B-01,05,06 | M |
| [UI-C-03](UI-C-03-piano-roll-screen.md) | Piano roll screen | B-01,07 | M |
| [UI-C-04](UI-C-04-playlist-screen.md) | Playlist screen | B-01,08 | S |
| [UI-C-05](UI-C-05-mixer-screen.md) | Mixer + routing screen | B-01,09,10 | M |
| [UI-C-06](UI-C-06-export-flow.md) | Export flow: dialog, progress, done, failed | B-11 | M |
| [UI-C-07](UI-C-07-startup-states.md) | First-run, first-setup, empty project, audio disconnected | B-11 | M |
| [UI-C-08](UI-C-08-preferences.md) | Preferences: audio, keys | B-11 | S |
| [UI-C-09](UI-C-09-plugin-windows.md) | Plugin windows: float wrapper, params, builtin, failed | B-11 | M |
| [UI-C-10](UI-C-10-console.md) | Script console: idle, live, save | B-11 | S |
| [UI-C-11](UI-C-11-extension-manager.md) | Extension manager: list, empty, panel | B-11 | S |
| [UI-C-12](UI-C-12-workspace-layouts.md) | Workspace layouts menu + detached panel window | B-11 | S |
| [UI-D-01](UI-D-01-wire-shell.md) | Wire shell, transport, status bar | C-01 | M |
| [UI-D-02](UI-D-02-wire-rack.md) | Wire channel rack | C-02, D-01 | L |
| [UI-D-03](UI-D-03-wire-piano-roll.md) | Wire piano roll | C-03, D-01 | L |
| [UI-D-04](UI-D-04-wire-playlist.md) | Wire playlist | C-04, D-01 | M |
| [UI-D-05](UI-D-05-wire-mixer.md) | Wire mixer + routing | C-05, D-01 | M |
| [UI-D-06](UI-D-06-wire-export.md) | Wire export flow | C-06, D-01 | M |
| [UI-D-07](UI-D-07-wire-prefs-startup.md) | Wire preferences + startup states | C-07, C-08, D-01 | M |
| [UI-D-08](UI-D-08-wire-plugin-ext-console.md) | Wire plugin windows, extensions, console | C-09..11, D-01 | L |
| [UI-D-09](UI-D-09-cleanup-exit.md) | Delete superseded UI, migrate tests, exit review | all D | M |
