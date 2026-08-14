# UI-C-06 — Export flow: dialog, progress, done, failed

| | |
|---|---|
| **Phase** | C — Screens |
| **Type** | Feature (UI, presentational) |
| **Dependencies** | UI-B-11 |
| **Reference** | `ui-files/screens/export-audio.png`, `export-progress.png`, `export-done.png`, `export-failed.png` — open all four before writing code |
| **Target files** | `app/lib/src/features/export/export_dialogs.dart`, `export_dialogs_vm.dart`; fixture `app/test/features/export/fixture.dart`; tests `app/test/features/export/export_flow_golden_test.dart` |
| **Estimate** | M |

## Context

Four modal states over a dimmed playlist backdrop. An old `export_dialog.dart` exists — do not touch it; these are its replacements built on `ObDialogScaffold`.

## Scope

1. **`ExportDialogVm`** (settings state, per `export-audio.png`): format options (WAV/AIFF/FLAC/MP3, WAV selected), bit depth (16/24/32-float, 16 selected), sample rate (48/44.1/88.2/96, 48 selected), range (Whole project / **Loop region bars 1–8** accent-selected / Selection), stems checklist (Master ✓, Drums Bus ✓ `4 tracks`, Bass ✓, Music ✓ `2 tracks`, Vox ✓, Reverb Send ☐ dim), summary block (`6 · WAV 24-bit · 48 kHz`, `0:32 (8 bars)`, `~96 MB`, `~/Music/OneBeat/Demo Project/`), footer (`Export to ~/Music/OneBeat` + Cancel + accent Export).
2. **Progress / Done / Failed states** — transcribe each PNG exactly: layout, copy, buttons, progress bar styling, the danger banner on failed. Model as one sealed `ExportFlowVm` with four variants so a single `ExportFlow` widget renders any state.
3. Callbacks: option selects, stem toggles, `onCancel`, `onExport`, `onOpenFolder`, `onRetry`, `onClose`.
4. Goldens: four full-frame 1600×1000 goldens (`export_settings_dark`, `export_progress_dark`, `export_done_dark`, `export_failed_dark`) each rendered over the dimmed playlist fixture backdrop, comparable 1:1 with the four PNGs.

## Acceptance criteria

- [ ] Four goldens match the four mockups (copy transcribed verbatim, selection states correct).
- [ ] One widget, four vm variants; switching vm switches state (widget test).
- [ ] No store/engine imports; analyze + token lint + tests clean.

## Out of scope

Real export, file pickers, progress animation (D-06).
