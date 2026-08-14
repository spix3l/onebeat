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

1. **`ExportBinding`**: drives the sealed `ExportFlowVm` state machine — settings → progress (real progress callbacks) → done/failed; maps options (format/depth/rate/range/stems) onto the existing export call surface.
2. Options the backend doesn't support yet: visibly disabled + `GAPS.md` entry (likely candidates: stems, some formats — verify against the current export code before assuming).
3. Summary block computed live (file count, duration from range, estimated size).
4. Wire the transport-bar `Export` button and `⌘E` (via `action_registry.dart`) to open the flow.
5. Tests with a fake exporter: happy path reaches done with a real file in a temp dir; failure path shows the failed vm with the error message.

## Acceptance criteria

- [ ] A real project exports through the new dialog end-to-end (WAV at least), file plays.
- [ ] Cancel mid-progress works and cleans up.
- [ ] Suite green; analyze + token lint clean; C-06 goldens unchanged.

## Out of scope

New export capabilities (stem rendering etc. if absent — EPIC-4).
