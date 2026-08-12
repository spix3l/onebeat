# OB-3-11 — Pattern management: selector, usage, Make unique

| | |
|---|---|
| **Stage** | 3 — v0.3 "It sequences" |
| **Type** | Feature (model + UI) |
| **Priority** | High |
| **Dependencies** | OB-3-02, OB-3-03, OB-3-09 |
| **References** | FR-SEQ-04/05, D-M3, D-M6 |
| **Estimate** | M |

## Context

Reference semantics are absolute (ARCHITECTURE.md §3.3) — and therefore the UI must surface reference impact before the user is surprised by it (D-M6). `Make unique` is the explicit escape hatch (D-M3).

## Scope

1. **Pattern selector** (per design, shell top-left region): list/dropdown of patterns with name, colour, **usage count badge** (number of clips referencing it); create/rename/recolour/duplicate/delete (delete warns with clip count; undoable); the selected pattern is what the rack and piano roll edit.
2. **Instance highlighting (D-M6):** selecting a pattern highlights all its clips in the arrangement (accent outline per tokens).
3. **Destructive-edit warning (D-M6):** first note-edit of a session on a pattern referenced by >1 clip surfaces a non-blocking notice ("Editing 'Verse Drums' — used in 6 places"), with *Make unique for this clip* as an inline action when the edit context came from a clip; never nags repeatedly (once per pattern per session); never blocks the edit.
4. **Make unique (FR-SEQ-04):** on a selected clip: clone the pattern (new ID, copied sequences, derived name "Verse Drums 2"), repoint that clip only; undoable as one entry; also exposed on multi-selected clips (one clone, all selected repointed).
5. **Duplicate pattern** (unreferenced clone) distinct from Make unique — both available, clearly named per the consistent action vocabulary (FR-UX-11).

## Acceptance criteria

- [ ] Usage counts correct and live (derived, tested against a fixture arrangement).
- [ ] Selecting a pattern highlights exactly its instances.
- [ ] Make unique: edited clone diverges; other clips unaffected; undo restores the shared reference (offline-render verified).
- [ ] The multi-use warning appears per spec, once per pattern/session, never blocks.
- [ ] All actions discoverable without right-click (FR-UX-17) and undoable.

## Out of scope

- Non-destructive transform UI beyond what OB-3-13 covers. Pattern folders/tags (post-v1).
