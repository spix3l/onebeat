# OB-0-05 — Decision gate: ADR-001, Flutter go/no-go

| | |
|---|---|
| **Stage** | 0 — Risk spikes |
| **Type** | Decision / documentation |
| **Priority** | Blocker — gates Stage 1 |
| **Dependencies** | OB-0-01, OB-0-02, OB-0-03, OB-0-04 |
| **References** | PRD §15.1, D3, R6, R12, R13, R14; PLAN.md gate G-A |
| **Estimate** | S |

## Context

Stage 0's job (PRD §15): kill or confirm Flutter before v0.1 code exists. This ticket consolidates the four spike results into ADR-001 and makes the call.

## Scope

Write `docs/adr/ADR-001-flutter-go-no-go.md` containing:

- Result table for P1–P4: pass/fail against the PRD §15.1 pass conditions, with measurements.
- **Decision:** Flutter confirmed / Flutter rejected / Flutter confirmed with descopes (list them).
- Binding constraints discovered (e.g. required canvas layering strategy from P1, multi-window state-transfer model from P2, sandbox/entitlement stance from P3, snapshot mechanism from P4).
- Consequences for specific requirements: FR-UX-05, FR-WSP-02, FR-SND-04, NFR-10.
- If rejected: a stop-and-replan note — Stages 1+ tickets are void until D3 is re-decided.

Also: delete or archive `spikes/` from the main build path (keep in history; they must not become load-bearing).

## Acceptance criteria

- [ ] ADR-001 exists with all four spike results, measurements attached, and an explicit decision.
- [ ] Each spike's binding constraints are listed and referenced from the relevant Stage 1–3 tickets (a one-line "see ADR-001" suffices).
- [ ] If any pass condition failed, the descope/replan is agreed with the project owner before Stage 1 starts.

## Out of scope

- ADR-002 (C ABI design) — Stage 1, but it consumes P4's findings.
