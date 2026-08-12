# EPIC-8 — v0.8 "It's beautiful and learnable"

**Exit criterion (PRD §10):** FR-UX-23 passes — 4 of 5 first-time users export an 8-bar loop within 15 minutes, unaided.
**Depends on:** Stage 7 closed; OQ-5 participants recruited (started in Stage 7).
**Status:** epic. The highest design-risk stage (R7, R8) — "design is a phase but must not be only a phase": everything since v0.1 is token-conformant; this stage turns consistent into beautiful.
**Key references:** FR-WSP-01…07, FR-UX-06/08/09/13/14/15/18/19/20/22/24/25/26/27, D9, G5, G6; design screens `onebeat-ws-drag.html`, `onebeat-ws-window.html`, `onebeat-firstrun.html`, `onebeat-empty.html`, `onebeat-empty-setup.html`, `onebeat-prefs.html`, `onebeat-prefs-keys.html`, `onebeat-routing-default.html`.

## Scope

**In:** **the workspace system (D9, the signature):** dockable/splittable/resizable panels (FR-WSP-01), tear-off to separate windows incl. other displays (FR-WSP-02 — mechanism from OB-0-02), named savable layouts (FR-WSP-03), 3–4 curated presets: Beatmaking/Mixing/Arranging (FR-WSP-04), per-project + per-user persistence with precedence (FR-WSP-05), reset always one action away (FR-WSP-06); **onboarding:** first launch = loaded demo project that plays immediately (FR-UX-14), first sound <60 s (FR-UX-15), no audio config needed (FR-UX-16, holds since Stage 1), starter templates (FR-UX-19), progressive disclosure (FR-UX-20 — flexibility discovered, not advertised, per D9's resolution); **full design pass** against tokens on every screen; motion system (FR-UX-06, reduce-motion respected); empty states as invitations with in-place actions (FR-UX-13 — designed screens exist); copy pass (FR-UX-10/11/12); contextual help on hover (FR-UX-18); keyboard: all primary actions reachable, visible focus (FR-UX-24), discoverable + remappable shortcuts (FR-UX-22, on the action registry) with the designed shortcuts preference screen; accessibility: Semantics on all controls incl. CustomPainter views (FR-UX-25), AA contrast (FR-UX-26), no colour-only information (FR-UX-27); responsive 13"→multi-monitor (FR-UX-08), UI zoom (FR-UX-09); **the FR-UX-23 usability test itself**, run properly with the 5 recruited novices.

**Out:** light theme completion if it jeopardises the exit (FR-UX-04 says supported — assess); extension panels in workspace (FR-EXT-07) if time-boxed out, → v1.x.

## Risks / watch

- **R8 (flexibility vs learnability):** the usability test watches specifically for workspace-induced confusion; opinionated defaults are the mitigation — prototype the default layout as carefully as the flexibility (§15.3).
- **R7 (taste):** consider a design review/contract pass by an actual designer before the test; boldness spent on the workspace only.
- FR-UX-23 failure is a *stage* failure: schedule one remediation + retest cycle inside the stage.

## Candidate tickets (~14)

1. Workspace core: dock/split/resize model + persistence format.
2. Tear-off windows (productionise OB-0-02's mechanism).
3. Layout manager: save/name/switch; 3–4 curated presets; reset action.
4. Demo project (produced in OneBeat, licensed assets) + first-run flow per design.
5. Starter templates + New Project flow.
6. Motion pass: state-change animation per token durations; reduce-motion.
7. Empty-state pass across all panels (designed screens as spec).
8. Copy pass: vocabulary table, all strings audited (FR-UX-10/11/12).
9. Contextual hover help system (FR-UX-18).
10. Shortcut remapping UI on the action registry + discovery overlay (prefs-keys screen).
11. Accessibility: Semantics coverage incl. canvas views; contrast + colour-only audit.
12. Responsive/zoom pass (13" through multi-monitor; FR-UX-08/09).
13. Preferences screens per design (audio device, folders, D-M2 toggle, theme).
14. FR-UX-23 usability study: protocol, run, findings, remediation, retest. **Exit.**
