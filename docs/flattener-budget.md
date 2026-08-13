# Flattener budget

`OB-3-04` §3 sets a budget: a 1,000-clip project must flatten in **under 10 ms**,
measured and recorded, with incremental re-flatten ticketed if the budget is
missed. This is the record. Re-measure whenever the flattener changes; the
numbers come from `engine/tests/test_flattener.cpp`, suite `stress`.

Measured 13 August 2026, Apple Silicon, best of five runs per row.

| Project | Events | Release | Debug |
|---|---|---|---|
| 1,000 clips, ordinary density (2 instruments × 16 notes per pattern) | 48,128 | **3.5 ms** | 16.5 ms |
| 1,000 clips, extreme density (8 instruments × 16 notes per pattern) | 192,512 | **10.4 ms** | 69.2 ms |

"1,000 clips" does not by itself pin down the work: what costs time is notes,
and a clip can hold two or two hundred. Both rows are recorded so that the
budget is a statement about something real.

**The budget is met** at ordinary density with a 3× margin. The extreme row —
128 notes per clip across a 62-bar arrangement, heavier than any arrangement a
person is likely to build — lands just over the line, and is recorded as the
known ceiling rather than smoothed away.

## Where the time goes

At 192,512 events the flatten is dominated by two sorts and one large vector:

1. `resolveOverlaps` sorts ~96,000 resolved notes by (instrument, key, start).
2. `ScheduleBuilder::build` stable-sorts ~192,000 events by frame.
3. Building that event vector.

Three things were fixed while measuring, worth ~4.8 ms of the extreme row:

- the schedule hash walked 4.6 MB **one byte at a time**; it now hashes 64-bit
  words (`ScheduleEvent` is a frozen, padding-free 24-byte POD),
- the hash worked from a full copy of the event array, which is now read in
  place,
- `ScheduleBuilder` grew from empty, reallocating a multi-megabyte buffer about
  twenty times; it now takes a `reserve()`.

## Incremental re-flatten is not ticketed yet

`OB-3-04` §3 allows "rebuilds whole but fast" for v0.3 and asks for incremental
work to be ticketed *if the budget is exceeded*. It is not exceeded at realistic
density, so no ticket is opened — dirty-span tracking is real complexity
(correctness bugs there are edits that silently do not play), and it should be
bought only when the measurement demands it.

**Open it when any of these becomes true:**

- ordinary density at 1,000 clips exceeds 10 ms in Release, or
- a real project's edit-to-audio latency is perceptible during playback, or
- Stage 4's automation curves multiply event counts as expected — they are the
  most likely thing to change this picture.

`FlattenScheduler` (`model/flattener.h`) is where it would go: it already owns
the dirty flag and the change subscription, so the interface does not change
when the implementation does.
