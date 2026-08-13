# OB-2-06 — Code-signing & notarization validation (Gate G-B)

| | |
|---|---|
| **Stage** | 2 — v0.2 "It hosts" |
| **Type** | Infra / risk validation |
| **Priority** | Blocker — PLAN.md gate G-B; PRD: "validated now, not at v1.0" |
| **Dependencies** | OB-2-05 (a real helper to sign) |
| **References** | R10, PRD §10 v0.2 |
| **Estimate** | M |

## Context

R10: Apple platform friction between notarization and out-of-process hosting is a known risk. If Apple's rules reject the architecture, we must find out while the sandbox design is still cheap to change — that is exactly this stage.

## Scope

1. **Signing pipeline:** Developer ID signing of the app bundle including the embedded helper executable; hardened runtime on both; entitlement sets per ADR-003 (notably `com.apple.security.cs.disable-library-validation` on the helper — required to load arbitrary third-party plugin binaries — plus JIT/unsigned-memory entitlements if the helper needs them).
2. **Notarization:** submit via `notarytool`, staple, verify Gatekeeper acceptance on a clean machine (first-download quarantine bit set).
3. **Runtime verification post-notarization:** helpers launch, load third-party CLAP binaries, IPC works, crash containment works — under Gatekeeper, not just in dev builds.
4. **CI integration:** a release-lane workflow producing a signed, notarized DMG/zip on demand (secrets in CI); documented in `docs/release.md`.
5. **Fallback investigation (only if rejected/blocked):** alternative entitlement combinations, XPC service packaging vs bare executable, or in-process fallback flag — findings appended to ADR-003.

## Inherited decision to confirm (OB-2-02, 13 August 2026)

**The App Sandbox is off**, in both `Release.entitlements` and
`DebugProfile.entitlements`. It was on — Flutter's macOS template enables it —
and under it the plug-in scan finds zero plug-ins in a shipped build: there is
no entitlement for `/Library/Audio/Plug-Ins`, and `$HOME` is redirected into a
container that plug-in installers know nothing about. The argument is written
into both entitlements files. This ticket owns confirming it survives
notarization and Gatekeeper, since it is the assumption everything in §1–§3
below rests on. Note also that scope item 1's `disable-library-validation`
belongs to the **helper only**; the main app keeps library validation on.

## Acceptance criteria

- [ ] A notarized build passes Gatekeeper on a clean macOS 14+ machine and hosts a sandboxed third-party CLAP plugin end-to-end, including crash-restart.
- [ ] Entitlement set documented with rationale per entitlement.
- [ ] Release workflow reproducible from `docs/release.md`.
- [ ] **Gate G-B recorded as passed** (or the fallback decision escalated before further hosting work).

## Out of scope

- App Store distribution (not planned). Auto-update (Stage 9).
