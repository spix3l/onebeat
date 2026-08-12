# OB-2-05 — Out-of-process sandboxed host helper

| | |
|---|---|
| **Stage** | 2 — v0.2 "It hosts" |
| **Type** | Feature — architecture-critical |
| **Priority** | Blocker |
| **Dependencies** | OB-2-04 (ADR-003), OB-2-01 |
| **References** | FR-PLG-07, G3, FR-PLG-06 |
| **Estimate** | L |

## Context

G3: a plugin crash never destroys user work. The helper process is the containment vessel: plugins execute there; the engine talks to a proxy `PluginInstance` that speaks ADR-003's IPC.

## Scope

1. **Helper executable** (`onebeat-plugin-host`): loads one plugin (per ADR-003 topology), implements the host side of the plugin API against the IPC transport; RT processing loop on a promoted (real-time scheduling) thread reading/writing the shared-memory rings.
2. **Proxy `PluginInstance`** in the engine: indistinguishable from in-process instances to the rest of the engine; marshals lifecycle, events, audio, parameters, state through IPC per ADR-003's latency model.
3. **Crash containment:** helper death → proxy outputs silence, engine keeps its deadline, UI notified with the designed error state (plugin name + *Restart plugin* action); restart re-instantiates and restores the last good state chunk (state checkpointed on save and periodically).
4. **Watchdog:** helper misses N consecutive deadlines → treated as hung: killed, reported, restartable.
5. **Supervision:** helper lifecycle owned by a non-RT supervisor thread/service in the app process; clean shutdown on app exit; orphan reaping (no zombie helpers after a hard app kill).
6. Scan mode: the same helper binary runs OB-2-02's enumeration (`--scan` mode).

## Acceptance criteria

- [ ] A test plugin that crashes during `process()`: audio continues (silence from that plugin only), no xrun, no app crash, notification shown, *Restart* recovers it with state intact (G3 demonstrated end-to-end).
- [ ] A test plugin that hangs in `process()`: watchdog fires, same recovery path.
- [ ] 8-hour soak with 10 sandboxed instances at 128 frames: zero xruns attributable to IPC (NFR-02 partial evidence), no helper/app memory growth.
- [ ] `kill -9` of the app leaves no orphan helpers after relaunch.
- [ ] Human review completed (R4 — RT + IPC code, no exceptions).

## Out of scope

- CLAP specifics (OB-2-07 plugs the CLAP adapter into the helper). Editor windows (OB-2-08).
