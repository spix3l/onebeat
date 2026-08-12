# OB-3-06 — Auto-save & crash recovery

| | |
|---|---|
| **Stage** | 3 — v0.3 "It sequences" |
| **Type** | Feature |
| **Priority** | High |
| **Dependencies** | OB-3-05, OB-1-12 (crash marker) |
| **References** | FR-PRJ-04, NFR-03, G3 |
| **Estimate** | M |

## Context

NFR-03: no user data loss on crash; auto-save ≤2 min. Combined with plugin sandboxing (G3), this is the "your work is safe" pillar.

## Scope

1. **Auto-save:** every ≤2 min *and* on significant events (before plugin load, before destructive multi-entity commands), to a shadow location (`~/Library/Application Support/OneBeat/autosave/<project-id>/`), never overwriting the user's file; skipped when the model is unchanged; save runs on a worker thread — **playback and UI never hitch** (measured).
2. **Recovery flow:** on launch after a crash marker (OB-1-12), or on opening a project newer in autosave than on disk: offer *Restore auto-saved version* / *Open last saved* with timestamps, per FR-UX-12 copy standards; restoring never silently overwrites the on-disk file.
3. **Unsaved-new-project coverage:** an unsaved project auto-saves too (recoverable "Untitled").
4. **Retention:** N rotating autosaves per project (default 5), pruned.
5. **Fault-injection test suite:** scripted `kill -9` at randomized points during editing scripts (via the command bus test driver); on relaunch, recovered project must contain all commands committed >2 s before the kill (bounded loss window documented).

## Acceptance criteria

- [ ] Fault-injection suite: 50 randomized kill runs, zero corrupt/unloadable recoveries, loss window within bounds.
- [ ] Auto-save during 120 Hz playback causes zero dropped frames and zero xruns (measured).
- [ ] Recovery dialog matches FR-UX-12 (specific, actionable, no apologies); both paths work; nothing silently overwritten.
- [ ] Retention/pruning verified.

## Out of scope

- Versioned project history / time machine. Cloud backup.
