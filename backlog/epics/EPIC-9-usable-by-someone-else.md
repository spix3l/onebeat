# EPIC-9 — v1.0 "It's usable by someone else"

**Exit criterion (PRD §10):** a producer who is not the author releases a track made in OneBeat.
**Depends on:** Stage 8 closed.
**Status:** epic.
**Key references:** FR-AUD-02/04, FR-SEQ-08 (transpose UI shipped — verify), NFR-02/03/04, G1–G7 final audit, PRD §11 success metrics; community goals (≥3 external contributors, ≥5 extensions — trailing indicators to check, not tickets).

## Scope

**In:** **audio clip editing** (FR-AUD-02: trim, split, fade, gain, reverse; non-destructive, sources never modified, FR-AUD-04) completing the AudioClip type from OB-3-02; **stability hardening:** 8-hour soak (NFR-02), zero-dropout-at-70%-CPU verification, crash-free-session instrumentation (opt-in local metrics), long-session memory audit; bug-fix burn-down from all prior closeout debt; **documentation:** user guide (first track walkthrough), extension developer docs finalised, contributor docs (median build-time <30 min re-verified); **packaging & distribution:** notarised DMG, update mechanism (Sparkle is MIT — verify licence chain), version/release process, project-format schema doc published (FR-PRJ-03); **the release-by-someone-else programme:** recruit 2–3 external producers, support them through making and releasing a track — their friction list is the final backlog.

**Out:** everything in PRD §5's non-goals and §10's "deferred to v2+" (recording, stretch, multicore, folder lanes, Windows/Linux).

## Risks / watch

- The exit criterion has a long external lead time — recruit producers at stage start, not end.
- Scope discipline (R1): the producers' friction lists will tempt parity creep; only track-blocking issues gate v1.0.
- OQ-1 (trademark) must be long closed; if not, naming is now a launch blocker.

## Candidate tickets (~10)

1. Audio clip editing: trim/split/fade/gain/reverse (engine + arrangement UI).
2. Audio clip routing + waveform rendering in clips.
3. Transpose-UI & FR gap audit: every v1.0 "M" requirement verified shipped (traceability sweep of PRD §8).
4. 8-hour soak + 70%-CPU dropout test harness; fixes (NFR-02).
5. Memory/leak audit across long sessions.
6. User documentation site + in-app help links.
7. Update mechanism + release pipeline finalisation.
8. External producer programme: recruit, support, collect friction, fix blockers.
9. Public repo launch checklist (OQ-1 confirmed, README/demo per D7, contribution flow).
10. v1.0 exit: external track released; §11 metrics reviewed and recorded.
