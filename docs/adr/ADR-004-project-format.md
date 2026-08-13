# ADR-004 — Project file format

| | |
|---|---|
| **Status** | Accepted |
| **Date** | 13 August 2026 |
| **Ticket** | OB-3-01 (blocker for OB-3-02, OB-3-05, OB-3-06) |
| **References** | OQ-2, FR-PRJ-01/02/03, ARCHITECTURE.md §8, DM-Q1 |
| **Evidence** | [`docs/examples/demo.obt/`](../examples/demo.obt/), the diff in §5 |
| **Supersedes** | The `OBS2` scratch session written by `ob_engine_session_save` (Stage 2 interim) |

## Context

FR-PRJ-01 asks for a human-readable, diffable, text-based project with plugin
state in a binary sidecar. FR-PRJ-02 fixes three structural rules — stable
never-reused IDs, lane order as a field, clips referencing lanes. FR-PRJ-03 asks
for a documented, versioned schema that loads forward-compatibly. OQ-2 — TOML
vs JSON vs custom text — has been open since the PRD and is due now, because
OB-3-02 cannot define entities without knowing how they serialise and OB-3-05
cannot write them.

Stage 2 shipped a deliberate placeholder: a little-endian `OBS2` binary blob
holding one instance and its state chunk (`engine/src/abi/onebeat_abi.cpp`).
It was never meant to survive. This ADR is what replaces it.

The thing worth being clear-eyed about: **diffability is a property of the
writer, not of the syntax.** Any of the three candidate syntaxes diffs badly
when written carelessly and well when written canonically. So the syntax
question is smaller than it looks, and the canonical-writer rules in §4 are the
part of this decision that actually earns FR-PRJ-01.

## Decision

| Question | Decision |
|---|---|
| Syntax | **JSON** (RFC 8259), UTF-8 without BOM, LF endings, written by a canonical writer |
| Layout | **`.obt` directory bundle**: `project.json` + `state/*.bin` + `assets/` |
| Musical time | **Integer ticks, 960 per quarter note.** No floats anywhere on the time axis |
| Note record | Compact one-line array `[start, length, key, velocity]`, optional trailing object for per-note properties |
| Velocity | Integer **0–16383** (14-bit; MIDI-1 velocity *v* maps exactly as *v* × 129) |
| IDs | `<type>_<ULID>` — e.g. `pat_01K2QF8Z10CHRDS00000000000`. Globally unique, never reused, no counter and no tombstones |
| Versioning | `format` string names the language, integer `version` counts additive revisions |
| Forward compat | Unknown fields, unknown entities and unknown entity *types* are preserved verbatim on round-trip |
| Round-trip | Load → save of a canonical file is **byte-identical**; a hand-edited file is normalised on first save |
| Plugin state | Opaque chunk per instance in `state/<name>.bin`, referenced by `state_ref` with a `state_sha256` |

## Why

### 1. JSON, because the writer does the work

Judged against the criteria OB-3-01 set:

| | TOML | JSON (canonical) | JSON5 / custom |
|---|---|---|---|
| Note-heavy diff quality | Poor — an array of inline note tables wraps unpredictably, and TOML's array-of-tables form spends 3–5 lines per note | **Good** — one note per line, one changed note is one changed line | Same as JSON |
| Hand-editability | Good | Adequate — no comments, but the file is machine-written and machine-normalised | Good (comments) |
| Comments | Yes | **No** — accepted, see below | Yes |
| Parsers, MIT-compatible | Few in C++; none vendored today | Everywhere: Dart `dart:convert` in-tree, several header-only MIT C++ options | Rare in C++; custom means writing *and* maintaining one |
| 10k-note behaviour | ~1 MB, slow to parse | **~340 KB**, parses in milliseconds | ~340 KB |

The comment gap is real and is accepted. Comments in a machine-written document
are a promise you cannot keep: the writer regenerates the file on every save and
would have to reattach comments to entities it no longer recognises. Anything a
user would write in a comment belongs in a `name` field or in `meta`, where it
survives round-trips because it is data.

A custom text syntax was rejected on maintenance grounds alone. It buys
comments and slightly denser notes in exchange for a parser, a writer, an error
reporter with line/column diagnostics, and a fuzz corpus — all of which JSON
gets for free, and none of which are the interesting part of a DAW.

### 2. The bundle, because plugin state is binary and large

A single file would have to base64 plugin chunks into the text — which destroys
the diff, since Vital's state is measured in hundreds of kilobytes and changes
every time a knob moves. A bundle keeps `project.json` small and textual and
puts every byte that is not human-readable behind a filename.

`.obt` is registered as an exported UTI with `LSTypeIsPackage`, so Finder
presents it as one document (double-click opens, drag moves it whole, Show
Package Contents still works). Git sees an ordinary directory, which is the
point: `git diff` on a project shows the changed patterns and one line per
touched sidecar, not one enormous blob.

The trade-off against a flat directory is real — a bundle is slightly harder to
poke at from Finder, and some sync tools handle package directories badly. It
went to the bundle because the alternative asks every user to keep a project
directory and its sidecars together by hand, and one day they will not.

### 3. Ticks, because floats do not belong on the time axis

960 ticks per quarter divides cleanly by 2, 3, 4, 5, 6, 8, 12, 16, 32 and 64:
triplets are 320, 64th notes are 60, quintuplets are 192, all exact. Integer
time means a pattern that round-trips is bit-identical, an edit is comparable
with `==`, and no accumulated rounding drifts a note off the grid over a long
arrangement. Seconds are derived by the time map at flatten time (OB-3-04),
never stored.

Velocity is an integer for the same reason. 14-bit is chosen because MIDI-1's
0–127 maps onto it exactly (× 129), so hardware input is lossless, and because
CLAP's 0..1 double is recovered as *v* / 16383 without a formatting rule. The
alternative — a 6-decimal float per note — cost one line of writer spec and
gave back nothing but noisier diffs.

### 4. ULIDs, because uniqueness should be structural

FR-PRJ-02 says IDs are never reused. There are two ways to keep that promise: a
persisted per-project counter with deletion tombstones, or identifiers that are
unique by construction. The counter is shorter to read and deterministic in
tests, but it makes never-reuse a bookkeeping obligation that every code path
must honour — and it breaks the moment two projects meet, which they will as
soon as copy-paste between projects (Stage 7) or a preset browser exists.

ULIDs are 26 Crockford-base32 characters, monotonic within a millisecond, and
sort by creation time — so a diff of a project with new entities groups them
together. The type prefix (`ins_`, `pat_`, `lan_`, `clp_`, `mix_`) means a
dangling reference is diagnosable by eye and a mis-typed reference is caught by
the loader rather than by a confusing runtime failure. The cost is 30-character
identifiers in the text; they appear once per entity and once per reference,
never per note.

Tests fix the clock and the random source, so fixtures stay byte-stable.

### 5. The diff FR-PRJ-01 is asking for

[`docs/examples/demo.obt/`](../examples/demo.obt/) is a realistic
project written to these rules: 4 instruments, 3 patterns, 16 clips across 4
lanes, 5 mixer tracks, 565 lines. Moving one clip two bars later and editing one
pattern (one note added, one velocity raised) produces this, verbatim from
`git diff`:

```diff
--- a/demo.obt/project.json
+++ b/demo.obt/project.json
@@ -187,13 +187,13 @@
       "length": 15360,
       "muted": false,
       "source": {
         "pattern_id": "pat_01K2QF8Z12H00K000000000000",
         "type": "pattern"
       },
-      "start": 15360,
+      "start": 23040,
       "transforms": {
         "loop": true,
@@ -541,13 +541,14 @@
       "name": "Lead hook",
       "sequences": {
         "ins_01K2QF8Z02SYNTH00000000000": [
           [0, 480, 72, 12900],
           [480, 240, 76, 11868],
           [960, 960, 79, 13932],
-          [2400, 480, 76, 12384],
+          [1920, 480, 77, 11868],
+          [2400, 480, 76, 14448],
           [3840, 480, 77, 12900],
           [4320, 240, 81, 11868],
```

Three changed lines for two edits, and each one says what it means. That is the
bar FR-PRJ-01 sets, and it is met by the canonical writer — not by JSON.

Note what the structural rules bought here. The clip move touched **one line**
because clips reference lanes and carry their own start; had lanes listed their
clips, the move would have rewritten two lane records. Nothing renumbered,
because order is a field.

## Canonical writer rules (normative)

Two saves of the same model must be byte-identical, on any machine, in any
locale. The full rules are in [`docs/project-format.md`](../project-format.md)
§6; the load-bearing ones:

1. UTF-8, no BOM, LF endings, two-space indent, one trailing newline.
2. `format` and `version` come first, in that order; every other key in every
   object is sorted by Unicode code point. (The header exception exists so a
   human or a sniffing tool reads the version first; everything else sorts.)
3. Entity maps are keyed by ID and therefore sort by ID, which is creation
   order.
4. Arrays whose elements are all numbers are written on one line
   (`[4, 4]`, and every note). All other arrays are one element per line.
5. Notes within a sequence sort by `start`, then `key`, then `length`.
6. Integers are written bare. Non-integers are written with exactly six decimal
   places, never in exponent form; `-0` is written `0.000000`; NaN and infinity
   are invalid and rejected at write time.
7. Only `"`, `\`, and control characters are escaped. Non-ASCII text stays
   literal UTF-8 so names in any language remain readable and diffable.

## Forward-compatible loading (normative)

- `format` must be `onebeat.project`. Anything else is refused with "this is not
  a OneBeat project".
- `version` greater than the reader's is **refused**, with the message naming
  the version that wrote it. OneBeat will not partially load a newer project and
  will never overwrite one.
- `version` less than or equal to the reader's loads. Revisions are additive by
  rule; a change that cannot be additive gets a new `format` string, not a
  version bump.
- **Unknown fields on a known entity** are retained on the entity and written
  back in sorted position.
- **Unknown entities** in a known map, and **unknown top-level maps**, are
  retained verbatim and reported once in the log as "kept, not understood". They
  are never silently dropped — a round-trip through an older OneBeat must not
  cost a user work done in a newer one.
- Unknown keys in a note's trailing property object are retained with the note.
- `group_id` is present and `null` on every lane. It is **reserved** for DM-Q1
  (folder lanes) so that adding grouping later is a value change, not a schema
  change. Readers must accept and preserve a non-null value they do not
  understand.

## Consequences

- OB-3-05 implements exactly the rules above and gains a `--check-canonical`
  test: load, save, compare bytes, over the example project and every fixture.
- OB-3-06's auto-save writes the same bundle to a recovery location; because the
  writer is canonical, "did anything change?" is a byte comparison.
- The Stage 2 `OBS2` scratch session is superseded. It stays until OB-3-05
  lands, then is deleted, not migrated: no user has a project in it.
- Merge conflicts in `project.json` are resolvable by hand for structure and
  patterns, and are not resolvable for sidecars. That is the honest limit of
  FR-PRJ-01 and is documented as such rather than papered over.
- Sidecars carry a `state_sha256` so a corrupted or hand-swapped chunk is
  detected at load and reported, instead of being handed to a plugin.

## Alternatives rejected

- **TOML.** Pleasant for the entity records, poor for the note-heavy parts, and
  the note-heavy parts are the ones that get edited every minute.
- **SQLite.** Excellent for auto-save and crash recovery, disqualified by
  FR-PRJ-01's "text-based, diffable" — it is a binary file with a hidden schema.
- **One flat file with base64 state.** Kills the diff for exactly the projects
  people care about, and makes every knob turn a multi-hundred-kilobyte change.
- **Per-project counter IDs with tombstones.** Shorter IDs, but never-reuse
  becomes a rule people must remember instead of a property of the identifier.

## What would change this decision

Two saves that are not byte-identical, a 10k-note project that takes longer than
about 50 ms to load, or real use showing that users routinely need comments in
the file. The first two are testable and will be tested in OB-3-05; the third is
a v0.8 usability observation, and the answer to it would be `meta` fields, not a
new syntax.
