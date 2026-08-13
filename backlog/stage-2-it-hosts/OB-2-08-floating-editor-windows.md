# OB-2-08 — Floating native plugin editor windows

| | |
|---|---|
| **Stage** | 2 — v0.2 "It hosts" |
| **Type** | Feature (UI/platform) |
| **Priority** | High |
| **Dependencies** | OB-2-07, **OB-0-02** (scope item 5 is a Flutter surface in a second window — that is spike P2) |
| **References** | D3.2, FR-PLG-11; design screens `onebeat-plugin-float.html`, `onebeat-plugin-params.html` |
| **Estimate** | L |

## Context

Third-party editors are floating native windows (D3.2) — deliberately not embedded in Flutter. The plugin's `NSView` lives in an `NSWindow` we own, with a thin native title/header bar per the design (`onebeat-plugin-float.html`). Position and size persist per project (FR-PLG-11).

## Complication to solve

The plugin `NSView` must be created in the process where the plugin lives — the **helper**. Approach: the helper creates the `NSWindow` + hosts the `clap_plugin_gui` surface in its own process (helpers are background apps with windowing capability), while the main app orchestrates show/hide/position via the control channel. Alternative (if UX problems arise: z-order, focus, Dock behaviour): `NSView` bridging via `NSRemoteView`-style APIs is private — not available; document the chosen model and its trade-offs in the ticket close-out.

## Scope

1. **Window chrome:** native window with OneBeat-styled header strip per design: plugin name, preset field placeholder, bypass toggle, close; content = plugin GUI view; resizable when the plugin supports it (`clap_plugin_gui` resize negotiation).
2. **Lifecycle:** open/close from the plugin list UI; reopen restores geometry; window survives plugin crash-restart (reopens after restart); closes cleanly on instance removal.
3. **Persistence:** per-project record of open state, position, size, display (multi-monitor: falls back gracefully when the display is gone).
4. **Focus & keyboard:** typing in plugin text fields works (the reason for D3.2); spacebar-for-transport does not fire while a plugin field has focus, but transport shortcuts work when the editor window merely has focus without an active text field (define and test the rule).
5. **Fallback:** plugins without a GUI get a **generic parameter editor** window (Flutter, tokens, per design `onebeat-plugin-params.html`): parameter list with sliders/steppers, search, Martian Mono values.

## Acceptance criteria

- [ ] Editors for ≥5 reference plugins open floating, render, receive mouse + keyboard, resize per plugin rules.
- [ ] Geometry persists per project across app restarts; disconnected-display fallback verified.
- [ ] Focus rule implemented and tested (text entry in a plugin never triggers transport).
- [ ] Generic parameter editor works for a GUI-less plugin, styled per design.
- [ ] Crash-restart of a plugin with an open editor: window reappears with the restarted instance.

## Out of scope

- Docked built-in plugin UIs (FR-BIP-07 — built-ins are Flutter panels, Stage 7). Preset browser (Stage 7).
