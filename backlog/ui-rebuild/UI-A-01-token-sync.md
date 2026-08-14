# UI-A-01 — Token & font sync with the Pen palette

| | |
|---|---|
| **Phase** | A — Foundations |
| **Type** | Feature (design system) |
| **Dependencies** | none |
| **Reference** | `ui-files/screens/*.png` (any), palette table below |
| **Target files** | `app/lib/src/design/tokens.dart`, `app/test/tokens_test.dart` |
| **Estimate** | S |

## Context

`tokens.dart` already defines the semantic role system (surfaces, text, accent, meters, note colours) and CI rejects literals in widget code. The Pen mockups pin the exact palette. This ticket makes the dark theme's values match the mockups and adds the roles the new UI needs, so every later ticket can build without inventing colours.

## Pen palette (authoritative values)

| Pen variable | Value | Maps to token role |
|---|---|---|
| `bg-deep` | `#131412` | `surfaceSunken` |
| `panel` | `#1b1d1a` | `surfaceDeep` / `surfacePanel` (keep both roles; panel regions in mockups use this) |
| `panel2` | `#22251f` | `surfaceRaised` |
| `raised` | `#2a2d27` | `surfaceWell` (buttons, chips at rest) |
| `raised2` | `#33372f` | new role `surfaceHover` if absent |
| `line` | `#3a3d37` | `lineStrong` |
| `line2` | `#2c2f29` | `line` |
| `text` | `#e8e9e4` | `textPrimary` |
| `muted` | `#9a9d94` | `textSecondary` |
| `dim` | `#6f726b` | `textMuted` |
| `accent` | `#7c6cf0` | `accent` |
| `accent2` | `#9a8eff` | `accentDeep`→ verify direction: `accent2` is the *lighter* hover/active shade — name it `accentBright` if `accentDeep` semantically means darker |
| `green` | `#5ccb8a` | `trafficGreen` / `meterLow` |
| `amber` | `#e6b85c` | `warning` / `trafficYellow` |
| `red` | `#e66a6a` | `danger` / `trafficRed` |
| `c1…c8` | `#F26D5B #E8B54B #9FC65C #37BE93 #2FB8C6 #E5689E #C97452 #7A8BA6` | new `channelColors` list (channel/clip/track identity colours) |
| `font` | Archivo | already bundled (`third_party/fonts/archivo`) |
| `mono` | Martian Mono | already bundled (`third_party/fonts/martian_mono`) |

Ignore the `matcha-*`, `cream*`, `coral*`, `ink*`, `Baloo 2`, `Quicksand`, `radius-*`, `gap-*` variables in the Pen file — they belong to an unrelated template that shares the document.

## Scope

1. Update the dark `OneBeatTokens` instance so every role above carries the Pen value. Where a mockup colour differs from the current token value, **the mockup wins**.
2. Add missing roles: `channelColors` (ordered list of 8), `surfaceHover`, and meter gradient stops if the current `meterLow/Mid/High` can't reproduce the green→amber→red fader meters seen in `ui-files/screens/routing-mixer.png`.
3. Confirm spacing/radius/type scales in `tokens.dart` cover what the mockups use: control height 26 (knob), 32 (transport button), radius ~6–8 on chips/buttons, ~12–16 on dialogs. Add named steps if a needed size is missing — do not add per-widget one-off constants.
4. Extend `app/test/tokens_test.dart`: assert the 8 channel colours, assert dark-theme values for the roles in the table (a change to any of them must fail a test, not pass silently).
5. Run the existing token-gallery golden if present (`app/lib/src/ui/token_gallery.dart`) and update its golden.
6. Extend `tools/token_lint.py` `SCAN_DIRS` with `app/lib/src/ui_kit`, `app/lib/src/core` and `app/lib/src/features` (keep the old `ui/` and `stock_plugins/` entries until UI-D-09 removes them with the code).

## Acceptance criteria

- [ ] All palette-table roles resolve to the listed hex values in the dark theme.
- [ ] `channelColors[0..7]` exist and are tested.
- [ ] `flutter analyze`, `flutter test`, and `python3 tools/token_lint.py` all clean (with the widened scan scope).
- [ ] No widget files touched.

## Out of scope

Light theme values (structure must stay light-ready, values can wait). Any component work.
