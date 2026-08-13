# Spike P2 — panel tear-off into a second native window

**Ticket:** OB-0-02 · **Date:** 13 August 2026 · **Status:** pass condition met, with a blocking caveat

## Headline

Flutter **can** tear a panel off into a real native macOS window, and it is far
better than the "second engine, serialize your state across an IPC boundary"
architecture the ticket feared. **But it cannot be used by OneBeat today**: the
API is `@internal`, experimental, and gated behind a feature flag the Flutter
tool refuses to enable outside the master channel.

## What was run

Two SDKs, pinned per directory by fvm so the main app is untouched:

| Directory | SDK | Windowing |
|---|---|---|
| `app/` (ships) | stable 3.44.4 | unavailable |
| `spikes/p2_multiwindow/` | master 3.48.0-1.0.pre-176 | enabled |

```
cd spikes/p2_multiwindow
fvm flutter config --enable-windowing
fvm flutter run -d macos --dart-define=AUTO_TEAROFF=true
```

## Results

### Confirmed by instrumentation

The spike prints the engine's root-view count rather than relying on a
screenshot. Tear-off and re-dock:

```
P2[startup]         views=2 ids=[0, 1] isolate=main rss=196.0MB
P2[after tear-off]  views=3 ids=[0, 1, 2] isolate=main rss=224.6MB
P2[after re-dock]   views=2 ids=[0, 1] isolate=main rss=217.3MB
```

| Question the ticket asks | Answer |
|---|---|
| Same engine, or a second isolate? | **Same engine, same isolate.** `isolate=main` throughout; the second window is another `FlutterView` on the one engine. |
| Must panels serialize state on detach? | **No.** The detached window's builder closes over the *same* `PanelModel` instance and re-renders from it live. This is the finding that matters most for the Stage 8 workspace. |
| Memory overhead per window? | **~28 MB** on creation (196 → 225 MB). Re-docking returned ~7 MB, so teardown is not a clean reversal — either lazy GC or a leak. Worth re-measuring before building a workspace that opens many panels. |

### Confirmed visually

Two genuine native `NSWindow`s with their own title bars and traffic lights, the
detached one rendering a live meter animating from the ticker that lives in the
main window's `State`. Screenshots in the ticket.

### Confirmed by scripted input

Keyboard: `abc` typed via System Events landed in the detached window's field
and updated the shared model.

### NOT confirmed — needs a human and hardware

- **Mouse clicks.** Synthetic `System Events` clicks did not increment the
  counter, while keystrokes did. This is most likely an artefact of synthetic
  click delivery rather than a Flutter defect, but it is **not proven either
  way**. A 20-second manual check settles it: run the spike, click the
  `clicked 0x` button in the detached window.
- **Second display.** This machine has one display (MacBook Air M3). The
  ticket's "works when dragged to a second display" criterion is unverified.

## The blocking caveat

OneBeat ships on **stable**. On stable 3.44.4:

- `flutter config --enable-windowing` accepts the value and reports it back as
  `(Unavailable)`.
- No `FLUTTER_ENABLED_FEATURE_FLAGS` define reaches the compiler, so
  `isWindowingEnabled` is `false` and every windowing constructor throws
  `UnsupportedError`.
- `--dart-define=FLUTTER_ENABLED_FEATURE_FLAGS=windowing` is explicitly
  rejected by the tool.

Notably the *engine* is ready: the stable prebuilt `FlutterMacOS.framework`
exports all 22 `InternalFlutter_Window_*` symbols. The block is framework and
tooling policy, not capability.

**The API is also moving fast.** Between stable 3.44 (24 June) and master
(13 August) — seven weeks:

| 3.44 stable | master |
|---|---|
| `RegularWindowController` | `WindowController` |
| `RegularWindow` | `Window` |
| `WindowManager(child:)` | `WindowManager(initialWindows:)` |
| `preferredSize:` | `size:` |

The framework header says this outright: *"Flutter will make breaking changes to
this file, even in patch versions."*

## Native runner change required

The default macOS runner template creates a `FlutterViewController` at launch,
which crashes a windowing app:

```
NSInternalInconsistencyException: 'Multiview can only be enabled before adding any view controllers.'
```

The fix, taken from `examples/multiple_windows`: delete
`MainFlutterWindow.swift` (and its `project.pbxproj` references) and reduce
`AppDelegate` to running a headless `FlutterEngine`. Dart then owns every
window, including the main one. This is a real migration cost for OneBeat, not
just spike scaffolding.

## Recommendation

See `docs/adr/ADR-001-ui-toolkit.md`. In short: P2 is answered **yes on
capability, no on availability**. `OB-2-08`'s generic parameter editor cannot
depend on this landing in stable by Stage 2, and needs a fallback design.
