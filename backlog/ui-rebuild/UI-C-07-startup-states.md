# UI-C-07 — First-run, first-setup, empty project, audio disconnected

| | |
|---|---|
| **Phase** | C — Screens |
| **Type** | Feature (UI, presentational) |
| **Dependencies** | UI-B-11 |
| **Reference** | `ui-files/screens/first-run.png`, `first-setup.png`, `empty-project.png`, `audio-disconnected.png` — open all four before writing code |
| **Target files** | `app/lib/src/features/startup/startup_screens.dart`, vms alongside; fixture `app/test/features/startup/fixture.dart`; tests `app/test/features/startup/startup_states_golden_test.dart` |
| **Estimate** | M |

## Scope

1. Open each PNG and transcribe it fully — copy, buttons, icons, layout. Expected anatomy (verify against the PNGs, the PNG wins):
   - **first-run**: the very first launch experience.
   - **first-setup**: guided device/folder setup (`ObEmptyState`/dialog composition).
   - **empty-project**: shell with an empty-workspace `ObEmptyState` prompting the first action.
   - **audio-disconnected**: shell with a danger/amber `ObBanner` state — note the transport/status treatment in the PNG.
2. One widget per state (`FirstRunScreen`, `FirstSetupScreen`, `EmptyProjectScreen`, `AudioDisconnectedOverlay`), each vm+callbacks, composed from B-11 pieces and (where the PNG shows the shell) `ShellScreen` from C-01 with fixture chrome.
3. Goldens: one 1600×1000 full-frame golden per state, comparable 1:1 with its PNG.

## Acceptance criteria

- [ ] Four goldens match the four mockups; all copy transcribed verbatim.
- [ ] Action callbacks exist for every visible button.
- [ ] No store/engine imports; analyze + token lint + tests clean.

## Out of scope

Real device detection, onboarding logic (D-07).
