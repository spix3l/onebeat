# Stage 2 closeout — v0.2 “It hosts”

Status: Stage 2 exit verification was tested and owner-approved on 13 August
2026. Notarization/Gate G-B is explicitly deferred until OneBeat has a
distribution plan. OB-2-05, OB-2-07, and OB-2-08 retain follow-up validation
and compatibility work without blocking local development.

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

The owner confirmed that the Stage 2 exit run had already been completed and
approved. Its detailed per-plugin rows and versions were not retained in the
repository, so the table below remains an honest template for the next recorded
compatibility pass rather than reconstructed data.

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

## Deferred distribution gate and remaining follow-up

1. When distribution work begins, run `tools/release_macos.sh` with Developer
   ID and App Store Connect credentials, then validate on a clean Mac.
2. Preserve named/versioned rows during the next compatibility pass.
3. Run 10 simultaneous instances at 128 frames for 30 minutes, then the OB-2-05
   8-hour soak. Record xruns and resident-memory start/end.
4. Force-kill every helper and the app; confirm state restart and zero orphans.
5. Record real-plugin geometry/multi-display/focus observations. Geometry
   persistence, missing-display fallback, and crash-reopen are implemented and
   fixture-tested; transport shortcut behavior still needs a real editor.
6. Obtain R4 reviews for RT/IPC and ABI code.

Gate G-B/OB-2-06 is deferred, not required for local work. OB-2-11 is closed by
the owner's test and approval. The remaining OB-2-05/07/08 follow-ups stay
visible because CI cannot manufacture real-editor interaction or human review.
