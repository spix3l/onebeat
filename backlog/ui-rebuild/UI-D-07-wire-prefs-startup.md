# UI-D-07 — Wire preferences + startup states

| | |
|---|---|
| **Phase** | D — Wiring |
| **Type** | Feature (integration) |
| **Dependencies** | UI-C-07, UI-C-08, UI-D-01 |
| **Reference** | existing `app/lib/src/ui/preferences_dialog.dart`, `plugin_library_store.dart` (folder scanning), engine device APIs via `engine_controller.dart` |
| **Target files** | `app/lib/src/features/preferences/preferences_binding.dart`, `app/lib/src/features/startup/startup_binding.dart`; tests alongside |
| **Estimate** | M |

## Scope

1. **`PreferencesBinding`**: audio page ↔ real device list/buffer/sample-rate (instant apply, live latency readout — the mockup promises `changes apply instantly, no restart`); sound/plugin folders ↔ real persisted settings + rescan; keys page ↔ existing shortcut map (`shortcuts.dart`).
2. **`StartupBinding`**: app boot decides between first-run / first-setup / empty-project / normal; audio-device-lost events raise the disconnected overlay and clear it on reconnect.
3. Folder pickers via real platform dialogs; counts from actual scans.
4. Tests with fakes: buffer change round-trip updates latency text; device-lost event flips the overlay vm; first-run flag routing.

## Acceptance criteria

- [ ] Changing buffer size in the new prefs audibly applies without restart; dropout tick reflects reality.
- [ ] Pulling the audio device (or simulating it) shows the disconnected state; reconnect recovers.
- [ ] Suite green; analyze + token lint clean; goldens unchanged.

## Out of scope

Appearance/About page content beyond what exists; key *rebinding* UI if the mockup's keys page is display-only (match the mockup).
