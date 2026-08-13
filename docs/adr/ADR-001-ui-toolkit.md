# ADR-001 — UI toolkit: Flutter go/no-go

| | |
|---|---|
| **Status** | Accepted, with a conditional on FR-WSP-02 |
| **Date** | 13 August 2026 |
| **Ticket** | OB-0-05 (gate G-A), answered by OB-0-01…04 |
| **References** | PRD §15.1 P1–P4, D3, D9, R12, R13, R14, FR-WSP-02, FR-UX-05 |
| **Supersedes** | — |

## Context

D3 chose Flutter for the UI. PLAN.md gate **G-A** requires that choice be
confirmed or killed by four spikes before the UI is built on it, on the grounds
that reversing it at v0.4 is catastrophic while reversing it at v0.1 is cheap.

**This ADR is late.** Stage 1 shipped a working Flutter app before G-A ran, so
the gate is being closed against evidence gathered from the real implementation
plus one dedicated spike, rather than from four throwaway prototypes as PRD
§15.1 intended. That deviation is recorded honestly here rather than papered
over: the risk it created was real, and P2 in particular turned out to have an
answer that would have changed Stage 2's plan had it been asked first.

## Decision

**Flutter is confirmed for OneBeat's UI.** No spike produced a result that
justifies reversing D3.

**FR-WSP-02 (tear-off panels) is accepted as conditional**, not confirmed. It
works, but only on an API OneBeat cannot currently ship. See P2 below.

## The evidence

### P1 — CustomPainter at 120 Hz · **partially answered**

Pass condition: *sustained 120 fps, no GC-induced frame drops over 60 s.*

What exists: 60 s of continuous playback with two `CustomPainter` views (meter,
clock) at **zero dropped frames**, and a CI benchmark bounding the meter
painter's per-frame CPU cost at **0.0050 ms — 0.06 % of a 120 Hz frame**
(`app/test/paint_cost_test.dart`).

What is missing, and it is not a detail:

1. **The display is 60 Hz.** The dev machine is a MacBook Air M3; the frame
   budget comes from the display, so nothing here was measured at 8.33 ms.
2. **The load is not comparable.** P1 asks about ~2,000 rounded, bordered,
   individually-coloured note rectangles. The meter is a handful of
   `drawRect` calls and is not a proxy for it.

Carried as debt D1a (hardware) and D1b (the piano roll, Stage 3). **This is the
one spike whose failure would still kill Flutter**, and it remains genuinely
open. It is accepted for now because Stage 2 is hosting work, which does not
depend on it — but it must be closed in Stage 3, before the piano roll's
architecture is settled.

### P2 — Panel tear-off into a second window · **yes on capability, no on availability**

Pass condition: *a panel detaches, renders, receives input, and re-docks.*

Answered by `spikes/p2_multiwindow/` (full write-up in its `FINDINGS.md`):

- Detach, render, and re-dock are **confirmed** — root views go 2 → 3 → 2, and
  the detached window renders a live meter driven from the main window's ticker.
- Keyboard input into the detached window is **confirmed**. Mouse clicks were
  not confirmed by scripted input, which is inconclusive rather than negative;
  second-display behaviour is untested for lack of a second display.
- The architecture is much better than feared: **one engine, one isolate, many
  `FlutterView`s**. The detached window closes over the *same* model object, so
  panels do **not** serialize state on detach. R12's premise — that multi-window
  is Flutter desktop's weakest area — is now outdated on capability.

The blocker is availability, not capability:

- The windowing API is `@internal` and experimental, gated by a feature flag the
  tool **refuses to enable outside the master channel**. On stable 3.44.4 every
  windowing constructor throws `UnsupportedError`.
- The API broke in four visible ways in the seven weeks between 3.44 and master.
  Its own header promises breaking changes *in patch versions*.
- Adopting it also requires deleting the standard macOS runner's
  `MainFlutterWindow` and running a headless engine — a real migration, since
  Dart then owns the main window too.

The stable engine already exports all 22 `InternalFlutter_Window_*` symbols, so
this is policy and framework churn, not missing capability. It is reasonable to
expect it in stable eventually; it is **not** reasonable to plan Stage 2 around
that happening on a particular date.

### P3 — Finder drag-and-drop · **not answered**

Never attempted. First needed by the browser in Stage 7. Risk carried; the
mechanism (`NSPasteboard` via a platform channel or an existing package) is
well-trodden and not judged a threat to D3.

### P4 — FFI snapshot round-trip cost · **answered, pass**

Pass condition: *a 60-value snapshot crosses the boundary in well under one
frame budget.* Answered by the shipped implementation: a seqlock read through
one C call per frame into a struct allocated once. Measured across 3797 frames
with a 2.20 ms average build time including the read, and no measurable
per-frame attribution. This is the clearest pass of the four.

## Consequences

1. **D3 stands.** Flutter remains the UI toolkit. No further gate on it before
   Stage 3.
2. **`OB-2-08` must not assume multi-window.** Its scope item 5 — a Flutter
   generic parameter editor for plugins without a GUI — is the first thing in
   the project that needs a Flutter surface in a second window, and it cannot
   depend on the windowing API reaching stable in time. It needs a fallback:
   render the generic editor **inside the main window** (a panel or sheet),
   and treat a floating version as an enhancement that lands when the API does.
   Third-party plugin GUIs are unaffected — those are native `NSView`s in the
   helper process, not Flutter surfaces.
3. **FR-WSP-02 is conditional and must be re-tested before Stage 8.** The
   workspace's signature tear-off depends entirely on this API stabilising. If
   it has not reached stable by then, the choice is to ship the windowing
   feature flag on a pinned SDK, or to redesign FR-WSP-02 around virtual
   workspaces in one window. That is a product decision, not a technical one,
   and it should be made deliberately rather than discovered.
4. **P1 must be closed in Stage 3**, on ProMotion hardware, with the real piano
   roll. It is the only spike that can still invalidate D3.
5. **Track the windowing API's path to stable** as a standing item — it changes
   what FR-WSP-02 and `OB-2-08` can promise.

## What this ADR does not claim

That the four spikes were run as PRD §15.1 specified. Three of the four answers
come from production code and one from a dedicated spike. P1 and P3 are
partially and wholly unanswered respectively. Gate G-A is closed on the basis
that no *available* evidence contradicts D3 — not on the basis that every
question was asked.
