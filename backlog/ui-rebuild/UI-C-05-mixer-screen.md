# UI-C-05 — Mixer + routing screen

| | |
|---|---|
| **Phase** | C — Screens |
| **Type** | Feature (UI, presentational) |
| **Dependencies** | UI-B-01, UI-B-09, UI-B-10 (UI-C-01 for full-frame golden) |
| **Reference** | `ui-files/screens/routing-mixer.png` (primary), `routing-overview.png`, `routing-default.png` (secondary states — open all three) |
| **Target files** | `app/lib/src/features/mixer/mixer_screen.dart`, `mixer_screen_vm.dart`; fixture `app/test/features/mixer/fixture.dart`; tests `app/test/features/mixer/mixer_screen_golden_test.dart` |
| **Estimate** | M |

## Scope

1. **`MixerScreenVm`**: left panel (`MIXER` header + dim `route by name · never by number` + `List<MixerStripVm>` meter strips), right panel — one of: `RoutingPanelVm` (track selected), the **overview** state (`routing-overview.png` — transcribe it: it shows the routing graph/overview layout), or the **default/empty** state (`routing-default.png`). Model as a sealed `RoutingRightPanelVm`.
2. **`MixerScreen`** — workspace-only: mixer strip panel (~530px, per mockup) + routing panel filling the rest, hairline split.
3. Fixture: the exact Drums Bus scenario from `ui_fixtures.dart` (8 strips, Drums Bus selected + SC in, routing panel content per UI-B-10).
4. Callbacks bubble: strip taps, mute/solo, send/sidechain changes, `onShowOverview`.
5. Goldens: `mixer_screen_full_dark` (in `ShellScreen`, MIXER rail active, **no browser panel** — the mockup docks the mixer against the rail) vs `screens/routing-mixer.png`; plus `mixer_overview_dark` and `mixer_default_dark` workspace goldens vs the other two PNGs.

## Acceptance criteria

- [ ] Three goldens comparable 1:1 with the three mockups (status bar `Inspecting Drums Bus · 4 feeds · 2 sends · 1 sidechain` and right hint `⌘R routing · ⇧⌘R overview` on the primary).
- [ ] Right panel switches by vm type only (widget test).
- [ ] No store/engine imports; analyze + token lint + tests clean.

## Out of scope

Meter animation, routing edits (D-05), the detached-window mixer (C-12).
