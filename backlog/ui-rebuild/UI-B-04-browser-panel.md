# UI-B-04 — Browser panel

| | |
|---|---|
| **Phase** | B — Component library |
| **Type** | Feature (UI, presentational) |
| **Dependencies** | UI-A-02; `ObSearchField` from UI-B-01 |
| **Reference** | left panel (x≈90..390) of `ui-files/screens/channel-rack.png` (folder tree + pattern tree) and `ui-files/screens/arrangement.png` (sample list variant) |
| **Target files** | `app/lib/src/features/browser/browser_panel.dart`; tests `app/test/features/browser/browser_panel_golden_test.dart` |
| **Estimate** | M |

## Context

The browser is the 300px docked panel between rail and workspace. It has two content variants in the mockups: a **tree** (rack/piano-roll screens) and a **flat sample list** (arrangement screen).

## Scope

1. **`ObBrowserPanel`** — panel frame on `surfacePanel` with right hairline: header row (`BROWSER` micro-caps + round search icon button), `ObSearchField`, scrollable content slot.
2. Row widgets, all 26–30px tall, vm-driven:
   - `BrowserFolderRow` — folder icon, name, dim mono count right (`Packs 12`, `Drums 340`), disclosure state.
   - `BrowserPatternRow` — pattern glyph, colour tick bar, name, right badge: dim mono count (`4×`, `3×`) or mono tag `piano roll`; selected state = accent fill row (see `Main Groove` selected in channel-rack, `Soft Keys` selected in piano-roll — both must render).
   - `BrowserSampleRow` — 8px colour dot, name, right waveform glyph; hover/selected shade (`Sub Bass` highlighted in arrangement.png).
   - Indentation: children indent ~22px per level.
3. Vm: a small sealed tree `BrowserNodeVm` (folder/pattern/sample) with `children`, plus `selectedId`, `onTap(id)`, `onToggle(id)`.
4. Goldens: `browser_tree_dark` reproducing the channel-rack browser exactly (Packs 12 / Current Project / Main Groove 4× selected / Soft Keys piano roll / Bass Motif 3× / Drums 340 / Synths) and `browser_samples_dark` reproducing the arrangement list (9 samples with their dot colours from `channelColors`).

## Acceptance criteria

- [ ] Both goldens side-by-side comparable with their mockup regions.
- [ ] Selection states: accent row (pattern) and shaded row (sample) both correct.
- [ ] Pure vm + callbacks; no store imports.
- [ ] analyze + token lint + tests clean.

## Out of scope

Drag-out of samples, real filesystem browsing, search filtering behaviour.
