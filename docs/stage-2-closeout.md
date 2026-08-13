# Stage 2 closeout — v0.2 “It hosts”

Status: implementation complete for the deterministic CLAP fixture and local
containment path; release gates requiring credentials, third-party downloads,
hours of wall-clock validation, and owner sign-off remain open.

## Built and locally verified

- Real CLAP factory enumeration, instantiate/activate/process lifecycle, audio
  and note ports, params, value and modulation events, opaque state, latency,
  thread checks, and Cocoa GUI parenting.
- Helper-owned shared-memory audio transport with Mach semaphores, a bounded
  60%-of-block deadline, silence on the first miss, dead after the second miss,
  crash/hang containment, and checkpoint restart.
- ABI 1.3 loaded-instance and parameter surface, live gesture commands,
  sample-positioned schedule parameter events, scratch-session state chunks,
  and a silent state-preserving missing-instrument placeholder.
- Pen-reference plug-in manager problem/missing states and the in-main generic
  parameter editor. Native plug-in views open in a helper-owned Cocoa window.
- Local Developer ID/notarytool validation script with the library-validation
  exception scoped to the helper. CI publishing is intentionally deferred;
  OneBeat is not being published yet.

## Reference plug-in matrix

The rows below must be completed on the notarized build. A blank result is not a
pass and is intentionally not presented as one.

| Plug-in | Version | Scan | Audio/notes | Params | State | GUI | Kill/restart | Result |
|---|---|---|---|---|---|---|---|---|
| Surge XT | — | — | — | — | — | — | — | pending |
| Vital | — | — | — | — | — | — | — | pending |
| Odin 2 | — | — | — | — | — | — | — | pending |
| Airwindows CLAP 1 | — | — | — | — | — | — | — | pending |
| Airwindows CLAP 2 | — | — | — | — | — | — | — | pending |
| u-he demo 1 | — | — | — | — | — | — | — | pending |
| u-he demo 2 | — | — | — | — | — | — | — | pending |
| Reference 08 | — | — | — | — | — | — | — | pending |
| Reference 09 | — | — | — | — | — | — | — | pending |
| Reference 10 | — | — | — | — | — | — | — | pending |
| Reference 11 | — | — | — | — | — | — | — | pending |
| Reference 12 | — | — | — | — | — | — | — | pending |
| Reference 13 | — | — | — | — | — | — | — | pending |
| Reference 14 | — | — | — | — | — | — | — | pending |
| GUI-less reference | — | — | — | — | — | n/a | — | pending |

## Required release-gate run

1. Run `tools/release_macos.sh` with Developer ID and App Store Connect
   credentials.
2. On a clean macOS 14+ machine, download the artifact so quarantine is set,
   verify Gatekeeper launch, and complete every matrix row.
3. Run 10 simultaneous instances at 128 frames for 30 minutes, then the OB-2-05
   8-hour soak. Record xruns and resident-memory start/end.
4. Force-kill every helper and the app; confirm state restart and zero orphans.
5. Record geometry/multi-display/focus observations. Current native window
   creation is implemented, but geometry persistence and forwarding transport
   shortcuts from a non-text plug-in field need final field validation.
6. Obtain R4 reviews for RT/IPC and ABI code and owner sign-off.

Until those steps contain evidence, Gate G-B, Gate G-C, OB-2-05, OB-2-06,
OB-2-07, OB-2-08, and OB-2-11 remain open. This is deliberate: CI cannot
truthfully manufacture notarization or third-party compatibility evidence.
