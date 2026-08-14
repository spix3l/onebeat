# UI-C-12 — Workspace layouts menu + detached panel window

| | |
|---|---|
| **Phase** | C — Screens |
| **Type** | Feature (UI, presentational) |
| **Dependencies** | UI-B-09, UI-B-11; UI-C-01, UI-C-04 helpful for backdrops |
| **Reference** | `ui-files/screens/workspace-window.png` (layouts popover + detached mixer window), `workspace-drag.png` (panel drag/dock state) — open both before writing code |
| **Target files** | `app/lib/src/features/workspace/workspace_overlays.dart`, vms alongside; tests `app/test/features/workspace/workspace_layouts_golden_test.dart` |
| **Estimate** | S |

## Scope

1. **Layouts control**: the browser-header `Layouts Beatmaking` pill button (accent outline) that opens the `ObPopoverMenu` with LAYOUTS section (Beatmaking ✓ accent, Arranging, Mixing), separator, `+ Save as…`, `✎ Rename…`, danger `Delete…`, `↺ Reset to default`.
2. **Detached panel**: `ObFloatingWindow.panel` titled `Mixer · Drums Bus selected` containing the fader-strip board from UI-B-09, positioned over the playlist per the mockup; status bar `Mixer detached to its own window · Layout Beatmaking · saved`, right hint `Reset to default is one click away, always`.
3. **Drag/dock state**: transcribe `workspace-drag.png` — the mid-drag visual (dock highlight targets, dragged panel ghost) as a static presentational state driven by vm (`WorkspaceDragVm{...}`).
4. Vm + callbacks (`onLayoutSelect`, `onSaveAs`, `onRename`, `onDelete`, `onReset`, `onDetach`, `onCloseWindow`).
5. Goldens: `workspace_window_dark` and `workspace_drag_dark`, full frame, comparable 1:1 with the two PNGs.

## Acceptance criteria

- [ ] Both goldens match the mockups (popover open state included in `workspace_window_dark` exactly as the PNG shows both at once).
- [ ] No store/engine imports; analyze + token lint + tests clean.

## Out of scope

Real OS windowing, drag gestures, layout persistence (D-01/D-05 decide the windowing mechanism).
