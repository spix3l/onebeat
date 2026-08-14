# UI-C-01 — Shell screen + view switching

| | |
|---|---|
| **Phase** | C — Screens |
| **Type** | Feature (UI, presentational) |
| **Dependencies** | UI-B-02, UI-B-03, UI-B-04 |
| **Reference** | `ui-files/components/shell.png` (empty shell), any screen for the assembled look |
| **Target files** | `app/lib/src/features/shell/shell_screen.dart`, `shell_screen_vm.dart`; tests `app/test/features/shell/shell_screen_golden_test.dart` |
| **Estimate** | M |

## Context

The frame every workspace screen lives in: menu bar + transport bar on top, side rail left, optional browser panel, workspace slot, status bar bottom. `components/shell.png` shows it with an empty workspace.

## Scope

1. **`ShellScreenVm`**: `{ObMenuBarVm menuBar, ObTransportBarVm transport, List<RailItemVm> rail, int activeRailIndex, BrowserPanelVm? browser /* null = hidden */, ObStatusBarVm status}`.
2. **`ShellScreen`** — a `StatelessWidget` composing the B components around a `Widget workspace` slot. Exact geometry from the mockups: menu 24, transport ~68, rail 80, browser 300, status 28; workspace fills the rest on `surfaceSunken` with hairline separators as in the PNG.
3. Rail/menu/status callbacks bubble out unmodified (`onRailSelect`, `onMenuTap`, …). No navigation logic inside — the parent decides what workspace to show.
4. A demo `ShellPreview` widget used only by tests: shell + empty workspace, fixture vms from `ui_fixtures.dart`.
5. Goldens: `shell_empty_dark` at 1600×1000 comparable to `components/shell.png` (MIXER rail item active, meters at the fixture levels, Ready status).

## Acceptance criteria

- [ ] Golden vs `components/shell.png`: same chrome, same geometry, empty dark workspace.
- [ ] Browser panel hides cleanly when vm is null (second golden `shell_no_browser_dark` not required if a widget test asserts the layout).
- [ ] No store/engine imports; analyze + token lint + tests clean.

## Out of scope

Real navigation state, keyboard shortcuts, menus opening.
