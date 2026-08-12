# OB-1-03 — Design token system, typography, token lint

| | |
|---|---|
| **Stage** | 1 — v0.1 "It makes sound" |
| **Type** | Design/Infra |
| **Priority** | Blocker for all UI tickets — "tokens before any UI code" |
| **Dependencies** | OB-1-01 |
| **References** | FR-UX-01, FR-UX-02, FR-UX-04, FR-UX-07, FR-UX-26, D10, §8.1.1, G5 |
| **Estimate** | M |

## Context

FR-UX-01: token system defined and documented **before any UI code**. FR-UX-02: every colour/size/spacing resolves to a token, CI-enforced. The palette and rationale are locked in PRD §8.1.1; typography in D10. The Pencil design file is the visual reference.

## Scope

1. **Token definitions** (`app/lib/src/design/tokens.dart` + generated docs page):
   - Colour: `surface-deep #131412`, `surface-panel #1D1F1C`, `surface-raised #2A2C28`, `line #3A3D37`, `text-primary #E8E9E4`, `text-muted #9A9D94`, `accent #7C6CF0`, semantic meter colours (green/amber/red, fixed, never restyled).
   - Spacing scale, radius scale, border widths, elevation/overlay values, animation durations + curves (FR-UX-06 groundwork).
   - Type scale: **Archivo** (UI, incl. condensed cuts for dense labels) and **Martian Mono** (all numeric/time displays), bundled as assets with their SIL OFL licences in `third_party/fonts/`.
   - Structure supports a future light theme (FR-UX-04): tokens are semantic roles resolved through a theme object, not global constants — even though only dark ships in v0.1.
2. **ThemeData integration:** a `OneBeatTheme` InheritedWidget/extension exposing tokens to widgets; Material defaults suppressed.
3. **Token lint (CI, merge-blocking):** a custom lint or analyzer script failing on `Color(0x...)`, hex literals, and raw numeric `EdgeInsets`/`SizedBox`/`fontSize` in `app/lib/src/ui/**` (allowlist: `tokens.dart` itself and generated code). Wire into OB-1-02's pipeline.
4. **Contrast check:** documented verification that `text-primary`/`text-muted` on all three surfaces meet WCAG AA (FR-UX-26).

## Acceptance criteria

- [ ] All §8.1.1 values present as named tokens; docs page renders swatches and type specimens.
- [ ] Fonts load and render in a sample screen; numerics use Martian Mono tabular figures.
- [ ] Token lint demonstrated: a PR with a literal colour in a widget fails CI (then reverted).
- [ ] AA contrast documented for text tokens on all surface tokens.
- [ ] Light-theme resolution path exists structurally (a second theme object can be added without touching widget code).

## Out of scope

- Light theme values (v1.x). Motion system beyond duration/curve tokens. Any real screens.
