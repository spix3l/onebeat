# OB-0-01 — Spike P1: CustomPainter piano roll at 120 Hz

| | |
|---|---|
| **Stage** | 0 — Risk spikes |
| **Type** | Spike (throwaway code) |
| **Priority** | Blocker — the single most load-bearing question in the project |
| **Dependencies** | None |
| **References** | PRD §15.1 P1, FR-UX-05, R13, R14, D3 |
| **Estimate** | M |

## Context

The entire UI stack decision (D3, Flutter) rests on whether `CustomPainter` can render the densest DAW view at ProMotion refresh rates. If this fails, Flutter is the wrong choice and everything downstream changes. PRD §15.1: answer with throwaway code, not the real UI. This is deliberately the first ticket in the project.

## Scope

Build a minimal Flutter macOS app containing a single `CustomPainter` view that renders a fake piano roll:

- ~2,000 note rectangles with rounded corners, per-note colour, and a 1px border (approximating real note rendering cost).
- Horizontal grid lines (pitch rows) and vertical beat/bar lines.
- A moving playhead line animating left-to-right.
- Continuous horizontal auto-scroll plus interactive scroll/zoom via trackpad.
- Notes generated procedurally (seeded random) — no real data model.

Instrument it:

- Frame timing captured via `SchedulerBinding.addTimingsCallback`; report build+raster times.
- Run on an Apple Silicon Mac with a 120 Hz ProMotion display.
- Record a 60-second continuous-scroll session and export the frame-time histogram (a simple CSV dump + summary print is fine).

Test at least two rendering strategies if the naive one fails:
1. Naive: single painter, full repaint per frame.
2. Layered: static grid on a cached layer (`RepaintBoundary`/`Picture` caching), notes and playhead on separate layers.

## Technical notes

- No per-frame allocation in the paint path: pre-allocate `Paint` objects, reuse `Path`s, avoid closures in hot loops (R13 mitigation — this spike also validates that discipline is sufficient).
- Use `flutter run --profile` for measurements; debug-mode numbers are meaningless.
- Keep the code in `spikes/p1_piano_roll/` — clearly marked throwaway, excluded from any future CI.

## Acceptance criteria

- [ ] The spike app renders ~2,000 notes with grid, playhead, scroll and zoom.
- [ ] A 60 s continuous-scroll session at 120 Hz is measured in profile mode on Apple Silicon + ProMotion.
- [ ] **Pass condition (PRD §15.1): sustained 120 fps with no GC-induced frame drops over the 60 s window.** Result recorded as pass/fail with the frame-time histogram attached.
- [ ] If the naive strategy fails but a layered strategy passes, the passing strategy is documented as a constraint for all future canvas work.
- [ ] Findings written into ADR-001 (OB-0-05), including raster-thread headroom (how far under budget we are — headroom predicts whether real note editing UI will still fit).

## Out of scope

- Any real note editing, selection, or data model.
- Reusable code — this is explicitly throwaway (PRD §15.1).

## Failure escalation

If no strategy sustains 120 fps: **stop the project sequence.** OB-0-05 becomes a re-evaluation of D3 (PRD §15.1: "a cheap reversal now and a catastrophic one at v0.4").
