# UI-C-02 — Channel rack screen

| | |
|---|---|
| **Phase** | C — Screens |
| **Type** | Feature (UI, presentational) |
| **Dependencies** | UI-B-01, UI-B-05, UI-B-06 (UI-C-01 for the full-frame golden; build the workspace first, wrap last) |
| **Reference** | `ui-files/screens/channel-rack.png` — open it before writing code |
| **Target files** | `app/lib/src/features/channel_rack/channel_rack_screen.dart`, `channel_rack_screen_vm.dart`; fixture `app/test/features/channel_rack/fixture.dart`; tests `app/test/features/channel_rack/channel_rack_screen_golden_test.dart` |
| **Estimate** | M |

## Scope

1. **`ChannelRackScreenVm`**: header (title `CHANNEL RACK`, pattern tabs `Main Groove 4` selected / `All 8`, right hint `double-click a channel to open its piano roll`, `+ Add channel` accent button, round search button), `ObRackToolbar` vm, `List<RackRowVm>` (the 8 fixture channels with their exact step patterns — transcribe on/off/playing cells from the PNG), `int? playingStep` (col 9 in the mockup), footer vm, `ChannelInspectorVm?` (Soft Keys, per UI-B-06).
2. **`ChannelRackScreen`** — workspace-only widget assembling: header row → toolbar → `ObRackHeader` → row list (plain `ListView`) → spacer → `ObRackFooter` → `ObChannelInspector` pinned at bottom.
3. Callbacks bubble: `onStepTap(channel, step)`, `onRowSelect`, `onAddChannel`, toolbar/dropdown/inspector callbacks.
4. Fixture reproduces the mockup fully (channel names/types/colours from `ui_fixtures.dart`; Shaker powered off; Soft Keys selected).
5. Goldens: `channel_rack_screen_dark` (workspace only, 1520×880) and — if UI-C-01 is merged — `channel_rack_full_dark` (wrapped in `ShellScreen`, 1600×1000, CHANNELS rail active) which must sit side-by-side with the mockup.

## Acceptance criteria

- [ ] Full-frame golden comparable 1:1 with `screens/channel-rack.png` (a reviewer diffing by eye finds the same rows, steps, inspector, chrome).
- [ ] Step/row callbacks proven with a widget test.
- [ ] No store/engine imports; analyze + token lint + tests clean.

## Out of scope

Wiring (D-02), scroll virtualisation, drag interactions.
