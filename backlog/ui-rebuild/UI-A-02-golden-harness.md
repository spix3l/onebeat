# UI-A-02 — Component golden harness + shared fixtures

| | |
|---|---|
| **Phase** | A — Foundations |
| **Type** | Test infrastructure |
| **Dependencies** | UI-A-01 |
| **Reference** | existing `app/test/support/stage3_harness.dart`, `app/test/stage3_golden_test.dart` |
| **Target files** | `app/test/support/ui_harness.dart`, `app/test/support/ui_fixtures.dart`, `app/test/ui_kit/` (dir), `app/test/features/` (dir) |
| **Estimate** | S |

## Context

Eleven component tickets and twelve screen tickets will each write golden tests. They must all pump widgets the same way or the goldens will disagree about fonts, sizes and theme wrapping. This ticket builds that one harness so the B/C tickets contain zero boilerplate decisions.

## Scope

1. `app/test/support/ui_harness.dart`:
   - `Future<void> loadAppFonts()` — reuse/extract the font loading already done for stage-3 goldens (real Archivo + MartianMono from `third_party/fonts/`).
   - `Future<void> pumpUi(WidgetTester tester, Widget child, {Size size = const Size(1600, 1000), bool center = false})` — wraps in `OneBeatTheme` (dark tokens), `Directionality`, `MediaQuery` with `devicePixelRatio: 1.0`, disables animations, sets the surface size. `center: true` puts a component on a `surfaceSunken` background at its natural size for component goldens.
   - `Matcher uiGolden(String name)` → `matchesGoldenFile('goldens/<name>_dark.png')` — goldens live in a `goldens/` folder colocated with the calling test (`test/ui_kit/goldens/`, `test/features/<feature>/goldens/`).
2. `app/test/support/ui_fixtures.dart` — the shared demo-project fixture used across screens so every golden tells the same story as the mockups. Constants (taken from the mockups, keep verbatim):
   - Transport: BPM `124.00`, sig `4/4`, position `02:01:218`, clock `14:02`, title `ONEBEAT / v0.3 SEQUENCES`.
   - Channels (name, type, colour index c1..c8): Kick 808/Sampler/c1, Snare/Sampler/c6, Hats/Synth/c2, Sub Bass/Reese CLAP/c3, Soft Keys/EP/c5, Pluck Lead/Synth/c4, Shaker/Sampler/c7 (powered off), Open Hat/Sampler/c8.
   - Patterns: `Main Groove 4×` (contains Soft Keys piano roll, Bass Motif 3×), browser folders `Packs 12`, `Current Project`, `Drums 340`, `Synths`.
   - Playlist clips: Intro Kick 0:08, Kick Var B 0:06, Sub Bass 0:12, Lead Riff 0:06, Lead Riff B 0:08, Lead Riff C 0:05, Vocal Chop 0:09, Riser 0:04, Reverse Crash 0:05 (colours per `ui-files/screens/arrangement.png`).
   - Mixer tracks: Kick 808→Drums, Snare→Drums, Hats→Drums, Clap→Drums, Drums Bus→Master (selected, SC in), Sub Bass→Bass, Soft Keys→Music, MASTER 0.0 dB.
   These are plain records/lists — no vm classes yet (each C ticket defines its own vm and builds it from these constants).
3. A `README.md` in `app/test/ui_kit/` stating the two rules: every test starts `setUpAll(loadAppFonts)`; every golden goes through `pumpUi` + `uiGolden`.
4. Prove it: one trivial smoke golden (e.g. a `Text` in the theme) committed as `app/test/ui_kit/goldens/harness_smoke_dark.png`.

## Acceptance criteria

- [ ] `pumpUi`/`uiGolden`/`loadAppFonts` exist, documented with dartdoc.
- [ ] Fixture constants match the mockup strings above exactly.
- [ ] Smoke golden green on re-run (deterministic).
- [ ] `flutter analyze` + full `flutter test` clean.

## Out of scope

Any real component. Changing the stage-3 harness or its goldens.
