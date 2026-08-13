# OB-0-01 — Spike P1: CustomPainter piano roll at 120 Hz

> **Closed by decision, 13 August 2026 — the spike will not be built.**
> The maintainer's call: Flutter can render this, the question is not open
> enough to be worth throwaway code, and D3 stands without it. What that
> changes, and what it deliberately does not, is in **Resolution** at the
> bottom of this file. The acceptance criteria below are left unticked on
> purpose: they were waived, not met, and a ticked box would say otherwise.

| | |
|---|---|
| **Stage** | 0 — Risk spikes |
| **Type** | Spike (throwaway code) |
| **Priority** | Blocker — the single most load-bearing question in the project |
| **Dependencies** | None |
| **References** | PRD §15.1 P1, FR-UX-05, R13, R14, D3 |
| **Estimate** | M |

## Context

**Partial-answer note (added at Stage 1 closeout).** Stage 1 shipped two
`CustomPainter` views (meter, clock) with zero dropped frames over 60 s, and
`app/test/paint_cost_test.dart` bounds the meter painter at 0.0050 ms/frame —
0.06 % of a 120 Hz budget. **Neither result answers this ticket.** Two gaps
remain, and both matter:

1. **The load is not comparable.** The meter is a handful of `drawRect` calls.
   This spike asks for ~2,000 rounded, bordered, individually-coloured
   rectangles plus grid and playhead. That is the question.
2. **The hardware is not available.** The development machine is a MacBook Air
   M3 (`Mac15,12`) with a 60 Hz built-in panel. This spike requires a
   120 Hz ProMotion display, and no software workaround substitutes for it: the
   frame budget comes from the display, and rasterization and vsync scheduling
   are exactly what a CPU-side benchmark cannot measure.

To run it: either a ProMotion Mac, or an external high-refresh display — check
this Air's external-display refresh support against Apple's spec sheet before
buying anything, as it is not assumed here.

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

## Resolution — closed by decision, 13 August 2026

The maintainer waived this spike: Flutter can render a piano roll, the question
does not warrant throwaway code, and D3 is settled. That is a decision about
risk appetite and it is the maintainer's to make, so it is taken as made.

**What was actually established** (unchanged by the decision, and the reason it
is a defensible one): two `CustomPainter` views ran 60 s of continuous playback
with **zero dropped frames**, and `app/test/paint_cost_test.dart` bounds the
meter painter at **0.0050 ms/frame — 0.06 % of a 120 Hz budget**, in CI, on
every commit. The published evidence for Flutter desktop rendering thousands of
primitives per frame is also not thin.

**What the decision does not establish**, and what therefore moves rather than
disappears: nobody has drawn 2,000 rounded, bordered, individually-coloured
rectangles at 8.33 ms on this project, because nobody has had a 120 Hz panel to
draw them on (debt D1a). Two consequences:

1. **The measurement moves to `OB-3-10` (piano roll UI)**, which now carries it
   as an acceptance criterion. That is the first commit where the real load
   exists, and it is still inside the "cheap reversal" window §15.1 is about —
   Stage 3, not v0.4.
2. **The paint-path discipline in *Technical notes* above is binding anyway.**
   No per-frame allocation, pre-allocated `Paint`s, no closures in hot loops. It
   was written as a spike constraint; it survives as a rule, because it is what
   makes the Stage 3 measurement likely to pass rather than a coin toss.

Debt **D1b** (close P1 with the real piano roll) is therefore *not* cancelled —
it is what `OB-3-10` now owns. **D1a** (ProMotion hardware) still has to be
resolved to satisfy it, and no software substitute exists for a display.

Recorded in [ADR-001](../../docs/adr/ADR-001-ui-toolkit.md) §Amendment.
