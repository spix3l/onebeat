# The Stage 3 editors — piano roll, patterns, arrangement, clips

Covers OB-3-10 (piano roll), OB-3-11 (pattern management), OB-3-12 (arrangement)
and OB-3-13 (clip windowing and transforms). The channel rack has its own note in
[`channel-rack.md`](channel-rack.md); this picks up where it leaves off.

Read [ARCHITECTURE.md §2–§4](../ARCHITECTURE.md) first if you have not. Everything
below is downstream of one sentence: **time is Pattern → Clip → ArrangementLane,
signal is Instrument → MixerTrack → Master, and `Instrument` is the only join.**

## Where the code is

| Concern | File |
|---|---|
| C ABI (notes, patterns, lanes, clips, project I/O) | `engine/src/abi/onebeat_abi.h` §ABI 1.7 |
| Dart seams | `app/lib/src/engine/engine_client.dart` — `NoteClient`, `PatternClient`, `ArrangementClient`, `EditGestureClient` |
| Piano roll | `app/lib/src/ui/piano_roll.dart`, `piano_roll_store.dart` |
| Pattern selector + D-M6 notice | `app/lib/src/ui/pattern_selector.dart`, `pattern_store.dart` |
| Arrangement | `app/lib/src/ui/arrangement.dart`, `arrangement_store.dart` |
| Clip inspector | `app/lib/src/ui/clip_inspector.dart` |
| Action registry (FR-UX-17) | `app/lib/src/ui/action_registry.dart` |

## The three rules that shaped all of it

### 1. A clip holds a `PatternId` and no note data

There is no field on `Clip` that could hold a note, so "editing a pattern updates
every placement" is true by construction rather than by discipline. The exit test
asserts it against the real engine (`app/test/stage3_exit_test.dart`), and the
`Make unique` escape hatch (D-M3) is the *only* way to break the link.

`Duplicate pattern` and `Make unique` are deliberately two different actions with
two different names (FR-UX-11):

- **Duplicate pattern** — an unreferenced clone. No clip points at it yet.
- **Make unique** — clone, then repoint *exactly the selected clips*, as one undo
  entry. Undo restores the shared reference.

### 2. Notes are addressed by value, never by index

`ob_engine_notes_*` takes an array of `ob_note` rather than indices. An index
into a sorted sequence goes stale the instant another edit re-sorts it, and the
piano roll's selection outlives many edits. So the editor holds the note *values*
it selected and hands the same values back; `PianoRollStore._reselect` drops
whatever no longer exists, which is what makes deleting a selection leave nothing
selected.

### 3. A lane carries no signal

`ob_lane_info` has a name, a colour, an order, a height and three flags. There is
no gain, no meter, no instrument, no plugin — and no ABI call that could add one.
Moving a clip between lanes changes nothing audible; the exit test asserts every
other clip field is untouched by a lane change.

The lane's mute is an **event gate** (D-M4): clips on a muted lane are not
scheduled at all. The UI labels it `GATE`, never `M`, because confusing it with
the mixer's audio mute is the exact mistake the naming exists to prevent.

## D-M6: telling the user before they are surprised

Reference semantics are absolute, so the UI has to surface reference impact
*before* the user is caught out. Three mechanisms, all in
`pattern_store.dart` and `pattern_selector.dart`:

1. **Usage badge.** Every pattern row shows `N×`. Shown for patterns used once
   too — a badge that appears only when it is interesting teaches nothing about
   what it means.
2. **Instance highlighting.** Selecting a pattern outlines all of its clips in
   the arrangement (`ArrangementStore.isHighlighted`).
3. **The notice.** The first note-edit of a session on a pattern used by more
   than one clip raises a non-blocking bar: *"Editing 'Verse Drums' — used in 2
   places."* It never blocks, never asks permission, and appears **once per
   pattern per session**.

One interaction worth knowing: the once-per-session set is keyed by pattern
alone. If you edit a shared pattern from the rack (no clip context) and *then*
reach the same pattern by double-clicking one of its clips, the notice does not
reappear, so the inline `Make unique for this clip` action is not offered that
time. That is the specified behaviour — the rule is "once per pattern", and
making it "once per pattern per entry route" would nag. `Make unique` remains
permanently available in the clip inspector, which is where D-M3 says it belongs
anyway: beside the transform controls, so that varying a clip reads as the
default path and cloning as the explicit one.

## Gestures and undo

All three editors share one native transaction (`ob_engine_rack_gesture_*`,
exposed in Dart as `EditGestureClient`). A drag brackets it on mouse-down and
commits on mouse-up, so a note drag across twenty positions is **one** history
entry. Escape aborts, reverting every intermediate edit — which is what makes an
accidental drag across a dense pattern recoverable without reaching for undo.

The store tests assert the counts directly: one begin, one commit, zero aborts
for a completed drag; one begin, one abort, zero commits for a cancelled one.

## FR-UX-17, as a test rather than a walkthrough

`action_registry.dart` declares every user action once: id, label, area,
shortcut. Every visible control carries `key: actionKey(id)`.
`app/test/action_reachability_test.dart` renders each editor and asserts that
every declared action for that area has at least one visible control.

**A context-menu-only action fails the build.** The test also contains a
permanent negative case — a fake registry entry with no control, asserted to make
the check fail — so the guard cannot silently stop guarding.

Right-click still exists as an accelerator (right-click a note deletes it). What
FR-UX-17 forbids is right-click-*only*, and the registry is what makes the
difference checkable.

## Performance

Layered `CustomPainter`s per ADR-001: grid, notes and playhead are three stacked
`CustomPaint`s with their own repaint boundaries, so a moving playhead does not
repaint 2,000 notes. Every `Paint` is a painter field built in the constructor;
`paint()` allocates nothing.

Measured by `app/test/stage3_paint_cost_test.dart` on a MacBook Air M3, against
the 8.33 ms 120 Hz frame:

| Surface | Fixture | Cost |
|---|---|---|
| Piano roll notes layer | 2,000 notes, 32 bars, 4 octaves | **0.22–0.25 ms** |
| Arrangement clips layer | 200 clips over 20 lanes | **1.05–1.35 ms** |

The arrangement figure started at 2.6 ms. Two things fixed it, both worth keeping
in mind when extending the painter:

- clips were bucketed by lane once per paint instead of asking the store per
  lane, which was an O(lanes × clips) scan;
- the note-density preview is capped by the clip's *pixel width* as well as its
  note count. A 20-pixel clip cannot show 64 distinct ticks — they land on top of
  each other — so drawing them was pure cost.

**What these numbers do not prove.** They measure painter CPU, not end-to-end
120 Hz: rasterization is on the GPU, and vsync scheduling is not exercised. This
machine reports a 60 Hz panel, so the sustained-120 Hz criterion in OB-3-10 and
OB-3-12 still needs ProMotion hardware (debt D1a). What they do prove is that if
a frame is ever missed it is not because the painter got expensive, and that CI
fails the day someone makes it expensive.

## Project files

ABI 1.7 exposes `ob_engine_project_save` / `ob_engine_project_open` /
`ob_engine_project_json`. These are the real project bundle (ADR-004), distinct
from `ob_engine_session_save`, which is the v0.2 scratch file holding one hosted
plug-in's opaque chunk and is now clearly the narrower thing.

Opening clears the undo history: the history belongs to the session that made it,
and keeping the old stack would let undo reach back into a project that is no
longer loaded. A failed open leaves the current project exactly as it was.

The round-trip property the exit test asserts is **save → open → save is
byte-identical**. That is stronger than comparing against the pre-save model,
because saving legitimately stamps `meta.created_with`.
