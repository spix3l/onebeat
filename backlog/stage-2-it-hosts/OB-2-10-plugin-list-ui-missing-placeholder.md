# OB-2-10 — Plugin list UI & missing-plugin placeholder

| | |
|---|---|
| **Stage** | 2 — v0.2 "It hosts" |
| **Type** | Feature (UI + engine) |
| **Priority** | Medium |
| **Dependencies** | OB-2-02, OB-2-07, OB-2-08 |
| **References** | FR-PLG-10, FR-PLG-13 (minimal), FR-UX-12/13; design screens `onebeat-fail-plugin.html` |
| **Estimate** | M |

## Context

A working (if minimal) way to see scanned plugins, add an instance, and open its editor — plus the load-path resilience of FR-PLG-10: a project referencing an absent plugin still opens, with state preserved.

## Scope

1. **Plugin list panel (Flutter, tokens):** scanned plugins with name/vendor/format badge/category; text filter; quarantined section (OB-2-03); *Add* creates an instance (v0.2: a flat "loaded instances" list — mixer placement comes in Stage 4); empty state designed per FR-UX-13 ("No plugins found — add a folder" with the action in place).
2. **Instance list:** loaded instances with open-editor, bypass, remove; state saved into the session (Stage 2 interim persistence: instances + state chunks in a scratch session file — the real project format replaces this in Stage 3, and the placeholder mechanism carries over).
3. **Missing-plugin placeholder (FR-PLG-10):** loading a session referencing an uninstalled plugin creates a placeholder instance that (a) preserves the state chunk byte-exactly, (b) shows name/vendor/format and "what to do next" copy per FR-UX-12, (c) passes audio through (effects) or renders silence (instruments), (d) upgrades in place to a real instance when the plugin appears in a later scan — state restored, no project edit required.

## Acceptance criteria

- [ ] Scan → list → add instance → hear it → open editor → remove: full flow works.
- [ ] Save session with plugin X; uninstall X; reopen — session loads, placeholder present with state; reinstall X; rescan — placeholder upgrades and sounds identical (chunk hash verified).
- [ ] Quarantined and missing states use the designed error/empty patterns; copy reviewed against FR-UX-12/13.
- [ ] Token lint clean.

## Out of scope

- Favourites/hiding/categories browsing (FR-PLG-13 full, Stage 7). Channel-rack/mixer integration (Stages 3–4).
