# OB-3-09 — Channel rack UI (step sequencer)

| | |
|---|---|
| **Stage** | 3 — v0.3 "It sequences" |
| **Type** | Feature (UI) |
| **Priority** | High |
| **Dependencies** | OB-3-07, OB-3-08 |
| **References** | FR-SEQ-01, D-M5, FR-UX-17; design screen `onebeat-shell.html` (rack region) |
| **Estimate** | L |

## Context

The FL-workflow heart: per-instrument step rows inside the current pattern. Pattern-scoped visibility (D-M5) keeps it navigable: show only instruments the pattern uses, with an explicit add action — presentation only; the sparse matrix is untouched.

## Scope

1. **Layout per design:** instrument rows (OB-3-07 headers) + step grid; steps per row from pattern length and grid resolution; **variable step count** per pattern (e.g. 16/32/64 via pattern length) and per-row grid divisor; bar grouping visuals every 4 steps.
2. **Interaction:** click toggles; drag paints/erases (one undo entry per gesture); right-drag or modifier for velocity per step (with velocity visualised on the step) — **and** every right-click/modifier action also reachable via visible UI (FR-UX-17: nothing right-click-only).
3. **Pattern-scoped visibility (D-M5):** rows = instruments with sequences in the current pattern; **“＋ Add instrument”** row action (from existing instruments or new plugin); *Show all instruments* toggle; removing an instrument's sequence from the pattern ≠ deleting the instrument (distinct, labelled actions).
4. **Swing:** per-pattern swing control applying at flatten time (pairs of grid positions offset; parameter in the model, flattener support coordinated with OB-3-04).
5. **Playback feedback:** step cursor sweeps in time via snapshot data (no per-frame allocation; ADR-001 canvas constraints apply).
6. **Off-grid indicator** per OB-3-08's rule.

## Acceptance criteria

- [ ] Program a 16-step drum pattern across 4 instruments in <30 s of clicks (self-timed sanity check of interaction cost); it plays with the step cursor tracking.
- [x] Swing audibly and deterministically offsets off-beat steps (golden render test).
- [x] D-M5 behaviours all present: scoped rows, add-instrument action, show-all toggle, remove-from-pattern vs delete distinction.
- [x] Velocity paintable and visible; every action discoverable without right-click (FR-UX-17 walkthrough recorded).
- [ ] 120 Hz playback with the rack visible: zero dropped frames (profile run).
- [x] Token lint clean; matches the design's rack region.

**In review (13 August 2026).** The implementation and automated evidence are
complete; the two unchecked items are field gates, not missing code. ABI 1.6
provides the current pattern, ordered rows, variable per-row divisors, step and
velocity edits, sequence removal, swing and gesture transactions. The shell is
now the real model-backed rack, and [`docs/channel-rack.md`](../../docs/channel-rack.md)
records the Pen comparison, FR-UX-17 walkthrough and exact behavior.

Native ABI coverage programs steps, changes velocity and swing, removes and
undoes a sequence, changes the divisor and grows the pattern. The swing golden
fixes 50% swing at `0, 300, 315, 480, 780` ticks, including an unchanged
off-grid onset. Flutter has a fake-client store test and the first Stage 3 dark
golden. The dense 8 × 64-cell painter measures 0.27–0.31 ms locally against an
8.33 ms 120 Hz frame and allocates its paints outside `paint()`.

The app was built and launched with the bundled ABI 1.6 engine, reaching its
first usable frame in 274 ms. A real four-instrument under-30-second walkthrough
and a zero-drop profile on a 120 Hz panel remain owner/hardware evidence; this
MacBook Air reports a 60 Hz panel, so the ticket is review rather than falsely
closed.

## Out of scope

- Piano roll (OB-3-10). Per-step probability/alternate step modes (post-v1).
