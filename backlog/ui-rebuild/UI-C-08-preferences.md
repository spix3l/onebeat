# UI-C-08 — Preferences: audio, keys

| | |
|---|---|
| **Phase** | C — Screens |
| **Type** | Feature (UI, presentational) |
| **Dependencies** | UI-B-01, UI-B-11 |
| **Reference** | `ui-files/screens/preferences-audio.png`, `preferences-keys.png` — open both before writing code |
| **Target files** | `app/lib/src/features/preferences/preferences_screen.dart`, `preferences_vm.dart`; fixture `app/test/features/preferences/fixture.dart`; tests `app/test/features/preferences/preferences_golden_test.dart` |
| **Estimate** | S |

## Scope

1. **Settings frame**: replaces the browser panel with a `SETTINGS` nav panel — items Audio (accent-selected), Sound & Plugins, Keys & Shortcuts, Appearance, Extensions, About — inside the normal shell chrome.
2. **Audio page** (per `preferences-audio.png`): title `Audio · changes apply instantly, no restart`; DEVICE section (`Output device` label + dim caption, `Scarlett 2i2 USB ▾` dropdown, `Test output` button); LATENCY (`Buffer size` + segmented 64…2048 with 128 selected, big mono `5.3 ms round-trip`, green `✓ zero dropouts`, dim mono caption line); SAMPLE RATE (segmented 44.1/48/88.2/96, 48 selected, dim note); SOUND FOLDERS (mono path rows with count + ✕: `~/Music/OneBeat/Samples 1240`, `~/Music/Splice 8412`, `+ Add sound folder…`); PLUGIN FOLDERS (same anatomy, `Last scan today 13:40` right, CLAP 14 / VST3 22 rows, `+ Add plugin folder…`); bottom reassurance card ("Nothing on this page is required to make sound…").
3. **Keys page**: transcribe `preferences-keys.png` fully (shortcut list rows, likely search + binding tags).
4. Vm per page + callbacks for every control; a `PreferencesScreen(page: …)` switcher.
5. Goldens: `preferences_audio_dark` and `preferences_keys_dark`, full frame 1600×1000, comparable 1:1 with the PNGs (status bar `Ready · changes below apply live`, right `⌘, settings · ⌘K actions`).

## Acceptance criteria

- [ ] Both goldens match the mockups, copy verbatim, selection states correct.
- [ ] No store/engine imports; analyze + token lint + tests clean.

## Out of scope

Persisting settings, folder pickers, actual key rebinding (D-07). The old `preferences_dialog.dart` stays untouched.
