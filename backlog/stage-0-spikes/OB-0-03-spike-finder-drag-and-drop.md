# OB-0-03 — Spike P3: Finder drag-and-drop file paths

| | |
|---|---|
| **Stage** | 0 — Risk spikes |
| **Type** | Spike (throwaway code) |
| **Priority** | High |
| **Dependencies** | None (parallel with OB-0-01/02) |
| **References** | PRD §15.1 P3, FR-SND-04, R12 |
| **Estimate** | S |

## Context

Dragging samples from Finder into the channel rack, playlist or sampler is core to the browser workflow (FR-SND-04, Must). Desktop drag-and-drop is one of Flutter's flagged weak areas (R12).

## Scope

Minimal Flutter macOS app with a drop target that:

- Accepts drags from Finder of single and multiple files.
- Resolves each drop to an absolute file path and displays it.
- Distinguishes drop position (which of two targets received the drop) — needed later for "drop on rack vs playlist".
- Tests: multiple files at once; files with spaces/unicode in names; files from an external volume; a folder (should be identifiable as a directory).
- Also test drag **within** the app (a widget dragged between two panes) since internal DnD underpins the workspace and playlist.

Use `super_drag_and_drop` (or `desktop_drop` as fallback); record which was used and any macOS sandbox/entitlement implications (security-scoped bookmarks if the app is sandboxed).

## Technical notes

- Decide and record: will the shipped app use the macOS App Sandbox? If yes, dropped paths need security-scoped bookmark persistence for the content index (FR-SND-07) — flag this consequence in ADR-001 even though implementation is Stage 7.
- Keep code in `spikes/p3_dnd/`.

## Acceptance criteria

- [ ] **Pass condition (PRD §15.1): multiple audio files dropped from Finder resolve to valid paths.**
- [ ] Unicode/space filenames and external-volume files resolve correctly.
- [ ] Multi-target drop position discrimination works.
- [ ] Internal widget-to-widget drag works.
- [ ] Package choice, entitlement requirements, and sandbox implications recorded in ADR-001.

## Out of scope

- Audition-on-drop, waveform preview, actual file loading.
