# Stage 3 closeout — v0.3 "It sequences"

Status: **built and automated-verified, awaiting owner sign-off.** Every ticket
from OB-3-01 to OB-3-15 has landed. Two acceptance criteria across the stage are
hardware gates rather than missing code, and are called out honestly below rather
than ticked.

Exit criterion, PRD §10, verbatim:

> an 8-bar loop created, saved, reopened; the same pattern placed twice updates
> in both places.

**Both behaviours are demonstrated automatically**, against the real engine
dylib through the real FFI client, in `app/test/stage3_exit_test.dart`. That test
is the automated equivalent of the manual demo and is kept green permanently
(OB-3-14 §2, OB-3-15 §2).

## What the exit script does

From an empty project, in one test:

1. Adds an instrument from a real CLAP bundle (the stock `OneBeat Piano`, so the
   script is hermetic in any built checkout).
2. Renames the pattern, sets it to 16 steps, programs a four-step kick pattern in
   the rack inside one gesture.
3. Opens the same sequence in the piano roll and asserts the four steps are
   **there as notes** — not converted into notes. One `NoteSequence`, two views
   (DM-Q4). Adds a melody note; the pattern's note count moves in step.
4. Places the pattern a second time and resizes both clips to four bars, so the
   arrangement spans 8 bars and each clip loops the 1-bar pattern four times.
5. Edits the pattern once more and asserts **every** placement's note count
   changed — the criterion's second half.
6. Saves, reopens into the same engine, saves again, and asserts the two
   `project.json` files are byte-identical.

Two further scripts in the same file cover `Make unique` (one placement
diverges, the other keeps the original, undo restores the share) and the lane
critical negative (moving a clip between lanes changes the lane and nothing
else).

## R15 — the seven anti-patterns, audited item by item

ARCHITECTURE.md §6, walked against the shipped code. Each row names what enforces
it, because "we didn't do that" is worth nothing without a pointer.

| # | Anti-pattern | Absent? | Enforced by |
|---|---|---|---|
| 1 | Pattern belongs to a lane | Yes | `Pattern` has no lane field (`model/entities.h`). Its `sequences` map is keyed by `InstrumentId` and is a horizontal slice across instruments. A lane is reached only from a `Clip`. |
| 2 | Lane is a signal path | Yes | `ArrangementLane` holds name, colour, height, order, three flags and a reserved `group_id` — no instrument, no routing, no gain. `ob_lane_info` mirrors exactly that, and there is no ABI call that could add one. The lane header UI is the same list (`ui/arrangement.dart`). `stage3_exit_test.dart` asserts a lane change leaves every other clip field untouched. |
| 3 | Clip copies pattern data | Yes | `PatternSource` holds a `PatternId` and nothing else; there is no path from a clip to mutable note data. Proven end to end by the exit script's step 5 and by `stage3_store_test.dart`'s Make-unique group. |
| 4 | Instrument ↔ mixer track hardwired 1:1 | Yes | `Instrument.routing` is a `vector<OutputRoute>` of `{PortId, MixerTrackId}` — many ports, any track. D-M2's auto-created track is a *preference* (`Preferences::auto_create_mixer_track`), not a structural rule. |
| 5 | Instruments scoped per pattern | Yes | `Project::instruments_` is project-global. `ob_engine_instrument_*` takes no pattern argument. The rack's pattern-scoped row list (D-M5) is a *view* over the sparse sequence map, computed in `RackStore.isVisible` — presentation only. |
| 6 | Note data stored inside clips in the project file | Yes | `docs/project-format.md` §5.2: notes live under `patterns[].sequences`. A clip serialises a `pattern_id` plus its transforms. Confirmed by the byte-identical save→open→save round-trip in the exit script. |
| 7 | Audio thread traverses the reference graph | Yes | The flattener (`model/flattener.cpp`) resolves Pattern → Clip → Lane off-thread into an immutable schedule, published by atomic pointer swap. The audio thread reads only `core::Schedule`. Nothing added in Stage 3 touches that boundary: every new ABI call mutates the model and calls `publishModel`, which re-flattens. |

**Conclusion: all seven absent.** The two that Stage 3 could most plausibly have
broken are #2 and #3, because the arrangement view is exactly where a lane grows
a fader and a clip grows a note cache. Both now have tests that fail if it
happens, not just prose.

## Automated coverage added this stage

| Layer | File | What it holds |
|---|---|---|
| Native ABI | `engine/tests/test_abi.cpp` | ABI 1.7 layout freeze; notes/patterns/lanes/clips behaviour; Make unique + undo restoring the share; argument validation. |
| Stores | `app/test/stage3_store_test.dart` | 21 cases: gesture-per-drag, selection survival, quantise, marquee, viewport persistence, D-M6 once-per-session, usage counts, Make unique, clip transforms, lane reorder, event gate. |
| FR-UX-17 | `app/test/action_reachability_test.dart` | Every registered action has a visible control, per editor, plus a permanent deliberate-violation case. |
| Goldens | `app/test/stage3_golden_test.dart` | Piano roll and arrangement dark-theme surfaces. |
| Perf | `app/test/stage3_paint_cost_test.dart` | 2,000-note roll and 200-clip arrangement inside the 120 Hz paint budget; painters allocate outside `paint()`. |
| Integration | `app/test/stage3_exit_test.dart` | The v0.3 exit script against the real engine. |

Full app suite: **56 tests green.** Engine suite green. `clang-format`,
`clang-tidy` (Homebrew LLVM, now including `engine/src/abi`), `seam_check.sh`,
`token_lint.py` and `flutter analyze` all clean.

## Two bugs the new tests caught

Worth recording because both were invisible without the artefact that found them:

- **The piano roll grid never filled its background.** Row shading is applied to
  *some* rows, so natural notes outside the selected scale rendered transparent.
  Caught by the first golden, one line to fix.
- **The arrangement clips painter cost 2.6 ms per frame** at the 200-clip figure
  — inside the 4.16 ms guard but two and a half times what it should be. Caught
  by the paint-cost test. Two causes: an O(lanes × clips) scan, and a density
  preview drawing 64 ticks onto clips 20 pixels wide. Now 1.05–1.35 ms.

## Debt and what is *not* ticked

### D1a — no ProMotion hardware (carried forward, unchanged)

OB-3-10's "2,000-note pattern sustains 120 Hz during scroll + playback on a
120 Hz display" and OB-3-12's "200-clip arrangement, zero dropped frames" are
**not ticked.** This machine reports a 60 Hz panel. Measuring at 60 Hz and
calling it done is exactly what OB-3-10's own text forbids.

What has been done instead is the part that does not need the hardware: painter
CPU cost is measured against the 8.33 ms budget and guarded in CI (see
`docs/stage-3-editors.md` for figures). If the criterion later fails on real
ProMotion hardware, ADR-001 §Amendment's D3 reversal is the response — this is a
strategy question, not a UI defect.

### The palette diverges from the design screens

The design screens (`onebeat-shell.html`, `onebeat-piano.html`) render a cool
neutral black; the shipped tokens are PRD §8.1.1's warm neutral
(`surfaceDeep #131412`). Stage 3 aligned **layout, structure and interaction**
with the screens — view switcher, pattern selector with usage badges, keyboard
sidebar, scale highlighting, velocity strip, lane headers, ruler, clip inspector
— and left the base palette alone, because §8.1.1 is normative and retinting the
whole app is an owner decision rather than a side effect of building the piano
roll. New canvas tokens were added inside the existing family.

**Owner decision needed:** adopt the design screens' cooler palette (a change to
PRD §8.1.1 and one token block), or keep §8.1.1 and update the design screens.

### Smaller follow-ups

- Audio and automation clips exist structurally (D-M7) and are reported by
  `ob_engine_clip_at` with an empty `pattern_id`, but are not drawn. Stages 4
  and 9 own them.
- Lane drag-reorder renumbers densely through individual `reorderLane` calls; a
  single batched command would make it one history entry rather than one per
  moved lane.
- The perf lane produces figures per run but does not yet write trend data to a
  file on `main` (OB-3-14 §4's "trend data" half).

## Sign-off

- [ ] Owner runs the manual screen-captured demo (OB-3-15 §1).
- [ ] Owner confirms the 120 Hz criteria on ProMotion hardware, or accepts D1a
      carrying into Stage 4.
- [ ] Owner rules on the palette question above.
- [ ] Stage 4 (EPIC-4) breakdown scheduled.
