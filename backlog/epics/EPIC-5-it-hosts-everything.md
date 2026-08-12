# EPIC-5 — v0.5 "It hosts everything"

**Exit criterion (PRD §10):** ≥90% of the reference set passes.
**Depends on:** Stage 4 closed. Consumes: internal model (OB-2-01), helper (OB-2-05), editor windows (OB-2-08).
**Status:** epic.
**Key references:** FR-PLG-02/03/04/12, D5, OQ-4, DM-Q5, R3.

## Scope

**In:** **VST3 hosting** (Steinberg SDK ≥3.8, MIT) mapped *down* into the CLAP-shaped model — editor windows, params, state, latency; **AU hosting** (AUv2 + AUv3) via Objective-C++ in the helper; dynamic multi-out ports surfaced (DM-Q5) with UI for port→mixer-track assignment; the **compatibility reference set** (OQ-4): 50 plugins, weighted to free/obtainable, selected for what each stresses (GUI toolkits, threading, state size, latency, multi-out, sample-rate handling) — plus a **compatibility harness** that runs the OB-2-11-style checklist across the set automatically where possible; per-format down-mapping documented (what VST3/AU lose vs CLAP, D5).

**Out:** VST2 (W, impossible); AAX (W); format-specific extras beyond the internal model.

## Risks / watch

- R3 (long tail) is the epic's whole nature: budget for per-plugin quirk fixes; quarantine + sandbox mean failures degrade, not crash.
- AUv3 out-of-process model may interact oddly with our own helper architecture (AUv3 is *already* out-of-process) — investigate early; possibly host AUv3 in-process-of-helper vs direct.
- VST3 COM lifetime bugs are the classic crash source — the sandbox earns its keep here; keep ASan runs on the adapter suite.

## Candidate tickets (~10)

1. OQ-4: select + document the 50-plugin reference set (stress rationale per entry).
2. Compatibility harness: scripted per-plugin checklist runs, results matrix artifact.
3. VST3 adapter: lifecycle/processing (module load, component/controller, buses).
4. VST3 params/state/editor mapping (incl. down-mapping doc).
5. AUv2 adapter via Objective-C++ (AudioToolbox, view hosting).
6. AUv3 adapter + out-of-process interaction decision.
7. Multi-out ports: dynamic reconfiguration + port routing UI (DM-Q5).
8. Format badges/dedup in scanner & list (same plugin in 3 formats).
9. Per-format quirks database (known workarounds, keyed by plugin id/version).
10. v0.5 exit verification: full reference-set pass ≥90%, failures dispositioned.
