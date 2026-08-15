# UI-D-06 — Wire export flow

| | |
|---|---|
| **Phase** | D — Wiring |
| **Type** | Feature (integration) |
| **Dependencies** | UI-C-06, UI-D-01 |
| **Reference** | existing `app/lib/src/ui/export_dialog.dart` (uncommitted changes on this branch — read them first) and whatever export path it calls |
| **Target files** | `app/lib/src/features/export/export_binding.dart`; tests `app/test/features/export/export_binding_test.dart` |
| **Estimate** | M |

## Scope

1. **The engine had no export at all.** The dialog's progress bar was a timer and
   its "done" screen named a file nobody had written. So the ticket grew an
   engine half: `core/audio_export.{h,cpp}` (24-bit WAV/AIFF writer, windowed-sinc
   resampler, `exportSong` driving `Engine::process` faster than real time) and
   `ob_engine_export_start` / `_status` / `_cancel` (ABI 1.17).
2. **`ExportBinding`**: drives the sealed `ExportFlowVm` — settings → progress
   (polled from the render thread) → done/failed, and cancel back to settings.
3. **The dialog was cut down to what the engine renders**: format and sample
   rate, plus the destination folder (`NSOpenPanel` via the existing panels
   bridge). Bit depth, range and stems are gone rather than disabled — see
   `GAPS.md` §2.
4. Transport-bar `Export` and ⌘E open the flow (already wired in UI-D-01).
5. Tests: engine-level render-to-file and resampler tests, an ABI test that
   exports a real project to a temp folder, and widget tests over a fake client.

## Acceptance criteria

- [x] A real project exports through the new dialog end-to-end (WAV at least), file plays.
- [x] Cancel mid-progress works and cleans up (the partial file is deleted).
- [x] Suite green; analyze + token lint clean; C-06 goldens unchanged.
- [x] Human review (R4, delegated).

## Out of scope

Stem rendering, compressed formats, an export range and a bit-depth choice —
all recorded in `GAPS.md` §2.
