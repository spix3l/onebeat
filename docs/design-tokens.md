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

Values are **sampled from the design screens**, not transcribed by eye. The
screens are raster exports, so `tools/` has no automated check for this; the
sampling was done once with PIL against `onebeat-shell.html` and
`onebeat-piano.html` and the results are recorded here.

| Role | Value | Job |
|---|---|---|
| `surfaceSunken` | `#101210` | the top bar, the status bar, input wells |
| `surfaceDeep` | `#161814` | the canvas |
| `surfacePanel` | `#1B1D1A` | panels and lane headers |
| `surfaceRaised` | `#20231F` | the left rail, controls at rest |
| `surfaceOverlay` | `#2A2D27` | hover, selected rows, popup menus |
| `line` | `#3A3D37` | hairlines and separators |
| `textPrimary` | `#E8E9E4` | body and values |
| `textMuted` | `#9A9D94` | labels and secondary values |
| `accent` | `#7264E8` | the single accent |
| `accentMuted` | `#4A417F` | selection fills, focus washes |

**Five levels, not three.** The app shipped with three and the design uses five.
The two additions matter for different reasons:

- `surfaceSunken` is *darker* than the canvas. The design puts the chrome below
  the work in depth rather than above it, which is why the top bar reads as a
  frame rather than as a floating toolbar.
- `surfaceOverlay` separates hover from rest. With three levels, hover had to
  borrow the selected colour, so hovering a pattern row looked like selecting
  it.

The chrome is chromatically quiet on purpose: user clip colours are the only
saturated thing on screen, and every screen is tested against saturated clip
colours (PRD §15.3).

### Canvas roles (OB-3-10, OB-3-12)

The piano roll and the arrangement need roles the chrome does not.

**The roll's canvas is deliberately cooler than the chrome.** This was initially
read as the whole app being cool-toned and the tokens being wrong; sampling the
screens showed the opposite. The chrome is the warm neutral §8.1.1 always
specified — `#3A3D37` in the design is *exactly* the shipped `line` value — and
it is the roll's canvas alone that shifts cool. That separation is the point: it
distinguishes the thing you are editing from the tool you are editing it with,
on the one surface users stare at longest.

| Role | Value | Job |
|---|---|---|
| `rollCanvas` | `#1B1C20` | the piano roll's grid, cool by design |
| `rowShade` | `#16181C` | accidental rows — *below* the canvas |
| `rowShadeInScale` | `#232426` | in-scale rows — *above* it, so scale reads as a lift |
| `gridLine` | `#24262A` | beat lines, row separators |
| `gridLineStrong` | `#383B44` | bar lines |
| `noteFill` | `#48BCD2` | a note |
| `noteSelected` | `#E7ECF7` | a selected note |
| `noteGhost` | `#2F3138` | other instruments' notes, for context |
| `playhead` | `#9A8EFF` | the transport cursor |
| `canvasScrim` | `#101210` @ 55% | past the end of the pattern or arrangement |
| `marqueeFill` | `#7264E8` @ 14% | lasso selection |
| `clipSelectedOutline` | `#B9AEFF` | instance highlighting (D-M6) |

Two of these are derived rather than picked, and both live in `ColorTokens` so
that no widget derives its own opacity:

- `canvasScrim` and `marqueeFill` are pre-multiplied constants, not
  `.withValues()` calls at the call site — `tools/token_lint.py` rejects those.
- `ColorTokens.noteAtVelocity(unit)` ramps `noteFill`'s alpha from 0.45 to 1.0
  across the velocity range. "How loud looks how solid" is a design decision, so
  it belongs here and not in a painter.

### Meters are special

`meterLow` / `meterMid` / `meterHigh` are green, amber and red, and they are
**never restyled**. A meter is an instrument, and its colours carry meaning by
convention: green below −12 dB, amber approaching 0, red at clipping. Taste does
not get a vote here.

### Contrast (FR-UX-26)

Checked as a test, not as a claim — `app/test/tokens_test.dart` computes WCAG
relative luminance and fails the build below AA (4.5:1) for both text roles on
**all five** surfaces — text sits on every one of them, so every one is held to
the same bar.

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
