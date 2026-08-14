# UI-D-09 — Delete the old UI tree, migrate tests, exit review

| | |
|---|---|
| **Phase** | D — Wiring (closeout) |
| **Type** | Chore / verification |
| **Dependencies** | UI-D-01 … UI-D-08 all merged |
| **Target files** | deletion of `app/lib/src/ui/` and `app/lib/src/stock_plugins/`, test migration, `tools/token_lint.py` |
| **Estimate** | M |

## Context

This is a full revamp: **no file under `app/lib/src/ui/` survives.** By this point every behaviour has been ported into `ui_kit/`, `core/` and `features/` — this ticket removes the old tree wholesale and proves nothing was lost.

## Scope

1. Remove the `OB_NEW_UI` flag; the new shell becomes the only path.
2. `grep -rn "src/ui/\|src/stock_plugins/" app/lib app/test` — every remaining import is a porting gap: fix it in the responsible feature first (file a note against the D ticket that missed it), never by keeping the old file.
3. Delete `app/lib/src/ui/` **entirely** (widgets, stores, controllers, `token_gallery.dart` included — rebuild the gallery in `ui_kit/` if it is still wanted) and `app/lib/src/stock_plugins/` (ported to `features/plugins/stock/` in D-08).
4. Update `tools/token_lint.py`: drop the deleted `ui/` and `stock_plugins/` scan dirs; keep `ui_kit/`, `core/`, `features/`, `main.dart`.
5. Migrate or retire the old tests: stage-3 goldens re-pointed at the new surfaces (regenerate deliberately, reviewed image-by-image); `chrome_layout_test.dart`, `shell_smoke_test.dart`, `action_reachability_test.dart`, store tests re-homed under `test/features/**` against the ported stores; `test/failures/` stale artifacts deleted.
6. Sweep: `flutter analyze`, full `flutter test`, `python3 tools/token_lint.py`, then the real clang-tidy sweep and CI per repo policy (CI must be green before done).
7. Exit review: screenshot every screen from the running app next to its `ui-files/screens/*.png` mockup; record the comparison in `docs/ui-rebuild.md` (per-screen verdict + known gaps from `GAPS.md`). R4 review of this checklist is delegated — tick it and proceed.

## Acceptance criteria

- [ ] `app/lib/src/ui/` and `app/lib/src/stock_plugins/` no longer exist; zero references to them anywhere.
- [ ] App boots, every rail destination works, stage-3 exit scenario (8-bar loop, save, reopen, dual pattern instance) passes through the new UI.
- [ ] Full suite + CI green.
- [ ] `docs/ui-rebuild.md` comparison recorded for all 28 mockup screens (or the subset shipped, with the rest listed as gaps).
