# UI-C-10 — Script console: idle, live, save

| | |
|---|---|
| **Phase** | C — Screens |
| **Type** | Feature (UI, presentational) |
| **Dependencies** | UI-B-01, UI-B-11 |
| **Reference** | `ui-files/screens/console.png`, `console-live.png`, `console-save.png` — open all three before writing code |
| **Target files** | `app/lib/src/features/console/console_screen.dart`, `console_vm.dart`; fixture `app/test/features/console/fixture.dart`; tests `app/test/features/console/console_golden_test.dart` |
| **Estimate** | S |

## Scope

1. Open the three PNGs and transcribe them fully: layout (editor pane, output/log pane, toolbar, run controls), all visible code/log text (MartianMono), and the save-as-extension flow in `console-save.png`.
2. **`ConsoleScreenVm`** with a sealed state (idle / live-running / save-dialog) driving one `ConsoleScreen` widget inside the shell chrome (rail: SCRIPT active if the PNG shows the reduced rail — match the PNG).
3. Callbacks for every visible action (run, stop, clear, save as extension, dialog confirm/cancel, …).
4. Goldens: `console_idle_dark`, `console_live_dark`, `console_save_dark`, full frame, comparable 1:1 with the PNGs.

## Acceptance criteria

- [ ] Three goldens match the three mockups; monospace text verbatim from the PNGs.
- [ ] No store/engine imports; analyze + token lint + tests clean.

## Out of scope

Script execution, syntax highlighting beyond what the mockup shows (D-08). Old `script_console_view.dart` untouched.
