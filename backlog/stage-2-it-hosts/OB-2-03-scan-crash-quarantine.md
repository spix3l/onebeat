# OB-2-03 — Scan crash quarantine & reporting

| | |
|---|---|
| **Stage** | 2 — v0.2 "It hosts" |
| **Type** | Feature |
| **Priority** | High |
| **Dependencies** | OB-2-02, OB-2-05 |
| **References** | FR-PLG-06, G3; design screen `onebeat-fail-plugin.html` |
| **Estimate** | S |

## Context

Plugins crash during scan; the scan must survive, mark the offender, and tell the user plainly (FR-PLG-06). The failure state is already designed (`onebeat-fail-plugin.html`).

## Scope

1. **Detection:** helper-process death during a scan of plugin X → X is recorded as quarantined with the failure phase (load/enumerate/instantiate) and signal; scan continues with the next plugin. A watchdog timeout (hang ≠ crash) also quarantines.
2. **Persistence:** quarantine status + reason in the scan cache; quarantined plugins skipped on future scans unless the user retries or the bundle version changes (auto-retry once on version change).
3. **UI:** per the designed failure screen — plugin name, what happened in plain language, actions: *Retry scan*, *Keep quarantined*; a quarantined section in the plugin list; error copy follows FR-UX-12 (what happened + what to do next, no apologies).
4. **Reporting:** helper writes a crash-context file (plugin path, phase, stack if available) into the session log directory (OB-1-12).

## Acceptance criteria

- [ ] A deliberately-crashing test plugin (built in-repo: crashes on entry) is quarantined; the scan completes for remaining plugins; the app never dies.
- [ ] A hanging test plugin trips the watchdog and is quarantined.
- [ ] Quarantine persists across restarts; *Retry* re-scans exactly that plugin; version bump triggers one auto-retry.
- [ ] UI matches the designed failure state; copy reviewed against FR-UX-12.

## Out of scope

- Crashes during *processing* (OB-2-05's runtime containment).
