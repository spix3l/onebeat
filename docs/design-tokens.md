# Design tokens

The token system exists before the UI does (FR-UX-01). Every colour, size,
spacing, radius, duration and type style in the app resolves to a token defined
in `app/lib/src/design/tokens.dart`, and CI fails the build on a literal
(`tools/token_lint.py`, FR-UX-02).

**The living specimen sheet is in the app: press F9.** It renders the tokens the
app is actually using, so it cannot go stale. This document is the rationale.

## Structure

Tokens are **semantic roles resolved through a theme object**, not global
constants:

```dart
final OneBeatTokens tokens = OneBeatTheme.of(context);
Container(color: tokens.color.surfacePanel, padding: EdgeInsets.all(tokens.spacing.md));
```

Roles are named for their job (`surfacePanel`, `textMuted`, `meterHigh`), never
for their value (`grey900`, `red500`). That is what lets a light theme
(FR-UX-04) be a second `OneBeatTokens` instance and nothing else — no widget
changes, no renaming, no conditionals at call sites. `tokens_test.dart` builds a
light theme to prove the path is real, even though only dark ships in v0.1.

Material is not used at all. The app is built on `WidgetsApp`, so no Material
default can smuggle in a colour that is not a token.

## Colour (PRD §8.1.1)

| Role | Value | Job |
|---|---|---|
| `surfaceDeep` | `#131412` | the window |
| `surfacePanel` | `#1D1F1C` | panels on the window |
| `surfaceRaised` | `#2A2C28` | controls and cards on a panel |
| `line` | `#3A3D37` | hairlines and separators |
| `textPrimary` | `#E8E9E4` | body and values |
| `textMuted` | `#9A9D94` | labels and secondary values |
| `accent` | `#7C6CF0` | the single accent |
| `accentMuted` | `#4A417F` | selection fills, focus washes |

The chrome is chromatically quiet on purpose: user clip colours are the only
saturated thing on screen, and every screen is tested against saturated clip
colours (PRD §15.3).

### Meters are special

`meterLow` / `meterMid` / `meterHigh` are green, amber and red, and they are
**never restyled**. A meter is an instrument, and its colours carry meaning by
convention: green below −12 dB, amber approaching 0, red at clipping. Taste does
not get a vote here.

### Contrast (FR-UX-26)

Checked as a test, not as a claim — `app/test/tokens_test.dart` computes WCAG
relative luminance and fails the build below AA (4.5:1) for both text roles on
all three surfaces. Measured ratios:

| | `surfaceDeep` | `surfacePanel` | `surfaceRaised` |
|---|---|---|---|
| `textPrimary` | 14.7:1 | 13.4:1 | 10.9:1 |
| `textMuted` | 7.0:1 | 6.4:1 | 5.2:1 |

## Type (D10)

- **Archivo** for words. Its condensed width axis (`labelDense`) is what makes
  dense chrome labels fit without shrinking the type below a readable size.
- **Martian Mono** for every number and time display, with **tabular figures**,
  so a running clock or a level readout does not jitter as digits change.

Both are variable fonts, bundled with their SIL OFL licences in
`third_party/fonts/`.

Scale: `title` (14/600), `body` (13/400), `label` (11/500, muted), `labelDense`,
`numeric` (13/500 tabular), `numericLarge` (19), `numericSmall` (11, muted).

## Spacing, radius, size, motion

Spacing is a 7-step scale (`xxs` 2 → `xxl` 32). Radius is 3/5/8. Sizes cover the
chrome geometry — bar heights, control heights, meter dimensions — so a layout
change is a token change.

Motion durations are short by design (80/140/240 ms): a DAW is a tool, and an
animation must never sit between an intent and its result. The motion group also
carries **meter ballistics** (attack and decay in dB per second, peak-hold
seconds), because those are design decisions rather than engine constants — and
they are applied against wall-clock time, so a dropped frame cannot change how
fast the meter falls.

## Adding a token

1. Add the role to the right group in `tokens.dart`, named for its job.
2. Use it. The specimen sheet (F9) picks it up automatically if it belongs to a
   rendered group; add it there if it is a new kind of thing.
3. If it is a colour meant to carry text, add it to the contrast test.
