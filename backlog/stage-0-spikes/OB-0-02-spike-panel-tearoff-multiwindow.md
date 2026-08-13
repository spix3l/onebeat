# OB-0-02 — Spike P2: panel tear-off into a second native window

| | |
|---|---|
| **Stage** | 0 — Risk spikes |
| **Type** | Spike (throwaway code) |
| **Priority** | Blocker |
| **Dependencies** | None (parallel with OB-0-01) |
| **References** | PRD §15.1 P2, FR-WSP-02, D9, R12 |
| **Estimate** | M |
| **Blocks** | `OB-2-01` — run this before Stage 2 feature work begins |

## Context

**Scheduling note (added at Stage 1 closeout).** This spike was originally read
as a Stage 8 risk, on the grounds that the workspace is the first thing to tear
a panel off. That is wrong: `OB-2-08` scope item 5 requires a **Flutter**
generic parameter editor in a floating window for plugins without a GUI, which
is the same question, two tickets after CLAP hosting lands. Answer it before
`OB-2-01` so that a failure is a re-plan rather than a rewrite.

The rearrangeable workspace is the signature element (D9); tearing a panel off into a separate window — including onto another display — is FR-WSP-02, a Must. Multi-window is Flutter desktop's weakest area (R12). The design file shows this flow (`onebeat-ws-drag.html`, `onebeat-ws-window.html`).

## Scope

Build a minimal Flutter macOS app with two dummy panels (each containing live-updating content, e.g. an animating meter, so rendering in the second window is actually exercised):

- A "tear off" action detaches a panel into a **separate native macOS window**.
- The detached window renders its panel, receives mouse and keyboard input, and can be moved to a second display.
- A "re-dock" action returns the panel to the main window.
- Investigate and record the state of the art: Flutter's official multi-window support status on the current stable channel, `desktop_multi_window` package, or a custom `NSWindow` + engine approach. Pick the most viable and prototype it.

## Technical notes

- Key questions to answer beyond mere "it opens": does the second window run on the same engine or a second isolate? Can widget state transfer across, or must panels serialize state on detach? What is the memory overhead per window? These answers shape the Stage 8 workspace architecture.
- Keep code in `spikes/p2_multiwindow/`.

## Acceptance criteria

- [ ] **Pass condition (PRD §15.1): a panel detaches, renders, receives input, and re-docks.**
- [ ] Detached window works when dragged to a second display.
- [ ] The mechanism (engine/isolate model, state-transfer approach, memory overhead per window) is documented in ADR-001.
- [ ] Known limitations (menu bar behaviour, focus quirks, close-button handling) are listed.

## Out of scope

- Docking/splitting/layout persistence (Stage 8).
- Polished drag-and-drop visuals — a button-triggered detach is acceptable for the spike.

## Failure escalation

If no approach yields a working second window: FR-WSP-02 is descoped or redesigned (e.g. single-window with virtual workspaces) — a product decision to raise before Stage 1, recorded in ADR-001. This does not kill Flutter on its own, but weakens D9 and must be an explicit trade-off.
