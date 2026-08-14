# UI-B-11 — Dialog scaffold, empty states, banners, floating windows

| | |
|---|---|
| **Phase** | B — Component library |
| **Type** | Feature (UI, presentational) |
| **Dependencies** | UI-A-02; `ObChip` from UI-B-01 |
| **Reference** | `ui-files/screens/export-audio.png` (dialog anatomy), `export-failed.png`, `audio-disconnected.png`, `first-setup.png`, `workspace-window.png` (floating window chrome + popover menu), `plugin-float.png` (plugin window chrome) |
| **Target files** | `app/lib/src/ui_kit/` — `dialog_scaffold.dart`, `option_controls.dart`, `empty_state.dart`, `banner.dart`, `floating_window.dart`, `popover_menu.dart`; tests `app/test/ui_kit/dialogs_overlays_golden_test.dart` |
| **Estimate** | M |

## Context

Every modal/overlay screen (export flow, preferences, first-setup, failures) shares one dialog anatomy; the workspace screens add floating windows and popover menus. Building these once keeps the C-06…C-12 tickets as pure composition.

## Scope

1. **`ObDialogScaffold`** — dimmed scrim over a blurred? (no — plain scrim per mockups: background dimmed w/ `canvasScrim`) backdrop slot, centered raised panel (radius ~14, hairline border, `surfaceRaised`), header row (title semibold 21 + dim `· subtitle` + right ✕ button), content slot, footer row (left-aligned info slot + right buttons). Buttons: `ObDialogButton.primary` (accent, optional icon — `Export`), `.secondary` (raised — `Cancel`), `.danger` variant for failure screens.
2. **`option_controls.dart`**:
   - `ObSegmentedOptions`: label (`FORMAT` micro-caps) + wrap of option buttons; states rest / selected (white border + bold, per `WAV .wav` / `16-bit` / `48 kHz`) / accent-outline selected (`Loop region bars 1–8`).
   - `ObCheckRow`: accent checkbox + label + optional mono tag (`4 tracks`), unchecked-dim variant (`Reverb Send`), used for the stems list.
   - `ObSummaryBlock`: inset `surfaceSunken` block with label column (dim) and right-aligned mono values (`6 · WAV 24-bit · 48 kHz`, `0:32 (8 bars)`, `~96 MB`, path).
3. **`ObEmptyState`** — icon box (46px hairline tile), heading, dim body, action buttons row, dim footnote — anatomy per the Pen `EmptyState` component and `first-setup.png`/`audio-disconnected.png` center panels.
4. **`ObBanner`** — inline alert card for failure/warning surfaces (danger/amber icon + title + body + action), per `export-failed.png` / `audio-disconnected.png`.
5. **`ObFloatingWindow`** — draggable-window chrome: traffic-light dots, title (`Mixer` + dim `· Drums Bus selected`), right icon buttons (`+`, ✕ — and for the plugin variant: bypass chip, preset chip `Factory "Warm Keys"`, `WET ◦ 100%`, expand/minimise/close), radius ~12, border hairline, shadow; content slot. Two constructors: `.panel` (workspace-window.png) and `.plugin` (plugin-float.png header row).
6. **`ObPopoverMenu`** — anchored menu per the LAYOUTS popover: micro-caps section header, check rows (accent-filled active row `Beatmaking`), separators, action rows with icons (`Save as…`, `Rename…`, danger `Delete…`, `Reset to default`).
7. Goldens: `dialog_scaffold_dark` (scaffold + segmented + check rows + summary assembled as a mini export-like dialog), `empty_state_dark`, `banner_dark`, `floating_window_dark` (both variants, empty content), `popover_menu_dark` (the layouts menu reproduced).

## Acceptance criteria

- [ ] Each golden structurally matches its mockup region.
- [ ] All variants/states above exist and are exercised in goldens.
- [ ] analyze + token lint + tests clean.

## Out of scope

Actual modal routing (`showDialog`), window dragging behaviour, the concrete export/preferences screens (C-06…C-08).
