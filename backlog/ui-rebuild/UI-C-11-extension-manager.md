# UI-C-11 — Extension manager: list, empty, panel

| | |
|---|---|
| **Phase** | C — Screens |
| **Type** | Feature (UI, presentational) |
| **Dependencies** | UI-B-01, UI-B-11 |
| **Reference** | `ui-files/screens/ext-manager.png` (primary), `ext-empty.png`, `ext-panel.png` — open all three before writing code |
| **Target files** | `app/lib/src/features/extensions/extension_manager_screen.dart`, `extension_manager_vm.dart`; fixture `app/test/features/extensions/fixture.dart`; tests `app/test/features/extensions/extension_manager_golden_test.dart` |
| **Estimate** | S |

## Context

Per `ext-manager.png`: reduced rail (PLAYLIST, SCRIPT, EXTNS active, PACKS); left list of installed extensions; right detail panel; Tools menu open over the top. Fixture content (verbatim): Harmonizer `by @luma · v1.2.0 · bound to ⇧⌘H` (selected), Clip Roulette `built by you · v0.3.1 · from console` (enabled), Drum Fill Generator `by @grain · v0.9.2 · panel` (enabled), Groove Fetcher `by @unknown · v0.1.0` CRASHED (danger outline, toggle off); `+ Install from file…`; caption `sandboxed WASM · you grant capabilities`.

## Scope

1. **List panel**: `EXTENSIONS — 4 installed` header, extension rows (icon tile, name, dim meta, toggle / CRASHED tag), install button, caption.
2. **Detail panel** (Harmonizer): header (icon, name, meta, `Enabled` accent-outline + `Uninstall` buttons), description line, CAPABILITIES section (`WHAT IT CAN DO TO YOUR PROJECT` right mono header; rows Read the project ✓ `patterns, notes, mixer` / Modify notes ✓ `undoable, like your own edits` / Read files ✗ `has not asked` / Network ✗ `never granted` / Audio thread ✗ `impossible by design`), BINDINGS rows (Keyboard shortcut `⇧⌘H`, Menu action `Tools › Harmonize selection`, MIDI note `C#4 when recording`), danger card `GROOVE FETCHER CRASHED — CONTAINED & DISABLED` with body + `Try again once / Report crash / Uninstall` buttons.
3. **Tools menu popover** (from `ObPopoverMenu`): Script console `⌘J`, Extension manager… `⇧⌘E` (accent-highlighted), Harmonize selection `⇧⌘H`, Clip roulette `⌥R`.
4. **Empty & panel states**: transcribe `ext-empty.png` (no extensions installed) and `ext-panel.png` (an extension's own panel surface) and render each.
5. Vm + callbacks (toggles, install, uninstall, crash actions, menu). Status bar: `3 of 4 extensions enabled · 1 contained crash | All extensions sandboxed — worst case is a disabled extension, never a lost project`.
6. Goldens: `ext_manager_dark`, `ext_empty_dark`, `ext_panel_dark`, full frame, comparable 1:1.

## Acceptance criteria

- [x] Three goldens match the mockups; all copy verbatim (it is product voice, not lorem).
- [x] No store/engine imports; analyze + token lint + tests clean.

## Out of scope

Real WASM/extension model (D-08). Old `extension_manager_view.dart` untouched.
