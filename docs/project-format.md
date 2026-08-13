# OneBeat project format v1

Schema reference for the `.obt` project bundle. Normative: a reader or
writer that disagrees with this document is wrong. The rationale lives in
[ADR-004](adr/ADR-004-project-format.md); a complete example lives in
[`examples/demo.obt/`](examples/demo.obt/).

| | |
|---|---|
| `format` | `onebeat.project` |
| `version` | `1` |
| Status | v1 — implemented by OB-3-05 (`engine/src/model/project_io.cpp`) |
| Requirements | FR-PRJ-01, FR-PRJ-02, FR-PRJ-03 |

---

## 1. Bundle layout

```
MyTrack.obt/                directory, exported UTI, LSTypeIsPackage
├── project.json            the whole model, text, diffable
├── state/                  opaque plugin chunks, one file per instrument
│   ├── ins_01K2QF8Z00KEYS000000000000.bin
│   └── ins_01K2QF8Z01BASS000000000000.bin
└── assets/                 consolidated samples (FR-PRJ-05, not yet written)
```

`project.json` is the only file a reader must understand. Everything in
`state/` is opaque: OneBeat hands the bytes back to the plugin that produced
them and never inspects them. Everything in `assets/` is referenced by path
from `project.json`.

A bundle with no `state/` or no `assets/` is valid; the directories are created
on demand.

## 2. Units and conventions

| Concept | Representation |
|---|---|
| Musical time | Integer **ticks**, 960 per quarter note (`meta.ticks_per_quarter`). Triplet = 320, 64th = 60, quintuplet = 192 |
| Pitch | Integer MIDI key, 0–127 |
| Velocity | Integer 0–16383. MIDI-1 velocity *v* → *v* × 129; CLAP 0..1 → value / 16383 |
| Gain | Linear float, 1.0 = unity |
| Pan | Float −1.0 (left) … 1.0 (right) |
| Colour | `"#RRGGBB"`, uppercase hex |
| ID | `"<type>_<ULID>"`, see §4 |
| Absent value | `null`. A field is either present with a value or present with `null`; writers do not omit known fields |

Seconds and sample frames appear nowhere in the file. They are derived by the
time map when the model is flattened (OB-3-04).

## 3. Top-level document

```json
{
  "format": "onebeat.project",
  "version": 1,
  "clips": { … },
  "instruments": { … },
  "lanes": { … },
  "meta": { … },
  "mixer_tracks": { … },
  "patterns": { … },
  "transport": { … }
}
```

| Key | Type | Notes |
|---|---|---|
| `format` | string | Always `onebeat.project`. Written first |
| `version` | integer | Schema revision. Written second |
| `meta` | object | `name`, `created_with`, `ticks_per_quarter` |
| `transport` | object | `tempo` (float BPM), `time_signature` (`[numerator, denominator]`), `loop` (`{enabled, start, end}` in ticks) |
| `instruments` | map ID → object | §5.1 |
| `patterns` | map ID → object | §5.2 |
| `lanes` | map ID → object | §5.3 |
| `clips` | map ID → object | §5.4 |
| `mixer_tracks` | map ID → object | §5.5 |

`meta.ticks_per_quarter` is written for the benefit of external tools reading
the file. OneBeat v1 writes and requires `960`; a different value is refused
rather than honoured, because every fixture and every conversion assumes it.

## 4. Identity (FR-PRJ-02)

An ID is a type prefix, an underscore, and a 26-character Crockford base32
ULID:

```
ins_01K2QF8Z01BASS000000000000
```

| Prefix | Entity |
|---|---|
| `ins_` | instrument |
| `pat_` | pattern |
| `lan_` | lane |
| `clp_` | clip |
| `mix_` | mixer track |

Rules:

1. **IDs are never reused**, including after deletion. ULIDs make this a
   property of the identifier, so no counter or tombstone list is persisted.
2. IDs sort by creation time, so new entities cluster in a diff.
3. A reference must carry the right prefix for its target. `clip.lane_id` must
   start `lan_`; a mismatch is a load error, not a warning.
4. A reference to an ID that is not present is a **dangling reference**: the
   loader reports it and the entity that holds it is dropped, except for
   `instruments`, where an unresolvable plugin becomes a missing-plugin
   placeholder instead (FR-PLG-10, as in Stage 2).

## 5. Entities

### 5.1 `instruments`

```json
"ins_01K2QF8Z01BASS000000000000": {
  "color": "#4FB286",
  "muted": false,
  "name": "Bass",
  "note_defaults": {
    "pan": 0.000000,
    "pitch_offset": 0,
    "velocity": 12900
  },
  "plugin": {
    "format": "clap",
    "id": "org.surge-synth-team.surge-xt",
    "name": "Surge XT",
    "path_hint": "/Library/Audio/Plug-Ins/CLAP/Surge XT.clap",
    "vendor": "Surge Synth Team"
  },
  "routing": [
    {
      "port": 0,
      "track_id": "mix_01K2QF8Z31BASS000000000000"
    }
  ],
  "state_ref": "state/bass.bin",
  "state_sha256": "b71c4e0a…"
}
```

| Field | Type | Notes |
|---|---|---|
| `name`, `color` | string | User-facing |
| `muted` | bool | |
| `note_defaults` | object | `velocity` (0–16383), `pan`, `pitch_offset`. Applied to notes that do not override them — stored once per instrument, which is why a note record is four integers |
| `plugin.format` | string | `clap` in v0.3; `vst3`, `au`, `wasm`, `builtin` reserved. **Absent when the writer has no name for it**: a reader that could not model the format it read leaves the file's own word in place rather than replacing it with a guess |
| `plugin.id` | string | The format's stable plugin identifier — this, not the path, is what identity means |
| `plugin.name`, `plugin.vendor` | string | Cached for the missing-plugin placeholder, which must name the plugin it cannot find |
| `plugin.path_hint` | string | Last known path, or `@bundled/<name>` for a stock plugin inside the app. A hint only: a plugin that has moved is still found by `id` |
| `routing` | array of objects | `{"port": <int>, "track_id": "mix_…"}`, one per output port. **The port is written, never implied by array position** — position *is* an index, and routing by index is what D-M1 forbids. A bare `"mix_…"` string is accepted on read, with the port taken from its position, so hand-written files stay easy to write |
| `state_ref` | string or `null` | Bundle-relative path to the opaque chunk. Written as `state/<instrument id>.bin`: two instruments may share a name, and a filename collision would have one silently loading the other's settings |
| `state_sha256` | string or `null` | Hex digest of the chunk. Mismatch is reported and the chunk is not applied |

### 5.2 `patterns`

```json
"pat_01K2QF8Z11GR00VE0000000000": {
  "color": "#4FB286",
  "length": 7680,
  "name": "Bass groove",
  "sequences": {
    "ins_01K2QF8Z01BASS000000000000": [
      [0, 720, 36, 14448],
      [960, 240, 36, 10836]
    ]
  }
}
```

| Field | Type | Notes |
|---|---|---|
| `name`, `color` | string | |
| `length` | integer ticks | The pattern's own length, independent of any clip that plays it |
| `sequences` | map instrument ID → note array | One `NoteSequence` per instrument (OB-3-08). The step sequencer and the piano roll write the same array (DM-Q4) |

**Note record.** Four integers on one line:

```
[start, length, key, velocity]
```

all in the units of §2, `start` relative to the pattern. A note may carry a
fifth element, an object of per-note properties:

```
[1920, 480, 77, 11868, {"pan": -0.250000}]
```

The reserved keys are `pan`, `pitch_offset`, and `mod`; v0.3 preserves them but
does not interpret them. The slot makes per-note expression (CLAP note
expression, MPE) an additive behaviour change. **Unknown property keys are preserved**,
attached to the note by its four values rather than by its position: a note that
has been edited is no longer the note those properties described, so they are
dropped with it rather than landing on whatever now sits at that index.

Notes sort by `start`, then `key`, then `length`. Overlaps are preserved,
including notes of the same pitch: loading a project must not rewrite an edit.
During playback, the later same-pitch note-on cuts the earlier voice as specified
by the flattener contract, so the representation remains unambiguous without
destroying note data.

### 5.3 `lanes`

```json
"lan_01K2QF8Z21BASS000000000000": {
  "collapsed": false,
  "color": "#4FB286",
  "group_id": null,
  "height": 88,
  "muted": false,
  "name": "Bass",
  "order": 1,
  "soloed": false
}
```

| Field | Type | Notes |
|---|---|---|
| `order` | integer | **Display order is this field, never array position** (FR-PRJ-02). Reordering four lanes rewrites four integers and touches no clip. Two lanes claiming one position is repaired at load, in the order the file listed them |
| `height` | integer | Lane height in logical pixels |
| `collapsed` | bool | Display state, saved so a project opens as it was left |
| `muted`, `soloed` | bool | An **event** gate: the clips on this lane are not scheduled at all. Not the mixer's audio gate (D-M4) |
| `group_id` | `lan_` ID or `null` | **Reserved for DM-Q1** (folder lanes). v1 always writes `null`; a reader that does not understand a non-null value preserves it |

Lanes do not list their clips. See §5.4.

### 5.4 `clips`

```json
"clp_01K2QF8Z420000000000000110": {
  "lane_id": "lan_01K2QF8Z22SYNTH00000000000",
  "length": 15360,
  "muted": false,
  "source": {
    "pattern_id": "pat_01K2QF8Z12H00K000000000000",
    "type": "pattern"
  },
  "start": 23040,
  "transforms": {
    "loop": true,
    "probability": 1.000000,
    "time_nudge": 0,
    "transpose": 0,
    "velocity_scale": 1.000000,
    "window_start": 0
  }
}
```

| Field | Type | Notes |
|---|---|---|
| `lane_id` | `lan_` ID | **Clips reference lanes; lanes do not list clips** (FR-PRJ-02). Moving a clip between lanes rewrites one line |
| `start`, `length` | integer ticks | Position and extent on the timeline. A clip with no length is dropped at load |
| `muted` | bool | This placement is silent; the pattern and its other placements are unaffected |
| `source.type` | string | `pattern`, `audio` or `automation` (below). A type this version cannot model does not fail the load: the clip stays in the file untouched and out of the session, and the next save writes it back as it was |
| `transforms.window_start` | integer ticks | Offset into the source at which playback begins (DM-Q2) |
| `transforms.loop` | bool | Whether the source repeats to fill `length` or plays once and stops |
| `transforms.transpose` | integer semitones | Non-destructive (DM-Q3) |
| `transforms.velocity_scale`, `time_nudge`, `probability` | float, ticks, float | **Stored and round-tripped, not yet honoured**: OB-3-13 gives them semantics. Writing them from the start means turning them on is a behaviour change and not a schema change |

`transforms` semantics are pinned down by OB-3-13; this document defines only
their storage.

**Source shapes.** One key of `source` is `type`; the rest depend on it.

| `type` | Fields |
|---|---|
| `pattern` | `pattern_id` — a `pat_` ID, and nothing else. A clip holds no note data (D-M3) |
| `audio` | `path` (bundle-relative once consolidated), `source_offset` ticks, `gain`, `reversed`, `destination_id` — a `mix_` ID, because an audio clip routes to a track directly and has no instrument (D-M7). Stage 9 owns the behaviour; v0.3 stores it and plays nothing |
| `automation` | `target_kind` (`instrument` or `mixer_track`), `target_id`, `parameter` (the format's parameter id), and `points`: an array of `[position, value]`, position in ticks and value 0–1. Stage 4 owns curve shape; v0.3 flattens each point to one parameter event |

### 5.5 `mixer_tracks`

```json
"mix_01K2QF8Z31BASS000000000000": {
  "chain": [],
  "gain": 0.891251,
  "muted": false,
  "name": "Bass",
  "output_id": "mix_01K2QF8Z34MASTER0000000000",
  "pan": 0.000000,
  "sends": [],
  "soloed": false
}
```

| Field | Type | Notes |
|---|---|---|
| `gain`, `pan` | float | Linear gain, pan −1…1 |
| `muted`, `soloed` | bool | An **audio** gate, unlike a lane's event gate (D-M4) |
| `chain` | array | Effect instances, in order. Empty until Stage 4 |
| `sends` | array | Send descriptors. Empty until Stage 4 |
| `output_id` | `mix_` ID or `null` | `null` marks the master track. **Exactly one track has it**, and a file with none, with several, or with a routing loop is repaired at load and reported — an unroutable mixer is silence at best and a stack overflow at worst |

## 6. Canonical writer rules (normative)

Two saves of the same model are byte-identical, on any machine, in any locale.

1. UTF-8, no BOM. LF line endings. Two-space indent. Exactly one trailing
   newline. No trailing whitespace.
2. `format` first, `version` second. Every other key of every object — including
   the top level — is sorted ascending by Unicode code point.
3. Entity maps are keyed by ID, so they sort by ID, so they read in creation
   order.
4. An array of numbers — optionally with a single object as its last element —
   is written on one line, elements separated by `", "`, the object inline with
   its own keys sorted. Every other non-empty array is one element per line. An
   empty array is `[]`; an empty object is `{}`.

   This is the note record and nothing else: four integers, plus the properties
   of §5.2 when there are any. It is what makes "three notes added" three added
   lines. The leading number is required so that an array *of* objects never
   collapses — one entry inline and two entries expanded would change the shape
   of the file as it grows, which is the opposite of the point.
5. Notes sort as §5.2.
6. Integers are written bare, no `+`, no leading zeros. Non-integers are written
   with exactly six decimal places, never in exponent notation. `-0` is written
   `0.000000`. NaN and ±infinity are invalid: the writer rejects them rather
   than emitting `null`.
7. Strings escape only `"`, `\`, and characters below U+0020 (as `\uXXXX`).
   Non-ASCII characters are written literally, so names in any script stay
   readable and diffable.
8. No comments, because JSON has none, and because a machine-regenerated file
   cannot honestly keep them. Use `meta` or a `name`.

## 7. Versioning and forward compatibility (FR-PRJ-03)

- A file whose `format` is not `onebeat.project` is refused: it is not a OneBeat
  project.
- A file whose `version` exceeds the reader's is **refused**, naming the writing
  version. OneBeat never partially loads, and never overwrites, a project from
  a newer build.
- Revisions within `version` are additive by rule: new optional fields, new
  entity types, new enum values. A change that cannot be expressed additively
  takes a new `format` string.
- **Preservation, in all cases:** unknown fields on a known entity, unknown
  entities in a known map, unknown top-level maps, and unknown per-note property
  keys are retained and written back in canonical position. Unknown top-level
  maps and unknown entity types are logged once as "kept, not understood".
- Enum values a reader does not recognise (`plugin.format`, `source.type`) do
  not fail the load. The owning entity is preserved and marked unplayable, and
  the UI says so.

**Round-trip guarantee.** Loading a canonical file and saving it without edits
reproduces it byte for byte, including everything the reader did not understand.
A hand-edited or third-party file that is valid but not canonical loads fine and
is normalised on the first save; that normalisation is the only diff a user
should ever see from an untouched project.

## 8. Errors

| Condition | Behaviour |
|---|---|
| Malformed JSON | Load fails, reported with line and column |
| Wrong `format`, or `version` too new | Load fails with a specific message; the file is not touched |
| Dangling reference | Reported; the holding entity is dropped (instruments become placeholders) |
| Missing sidecar | Instrument loads without state; reported |
| `state_sha256` mismatch | Chunk not applied; instrument loads at defaults; reported loudly |
| Unknown field, entity or type | Preserved, logged once, not an error |

Message wording follows [`docs/errors.md`](errors.md).

## 9. Not in v1

Automation clips and curves (Stage 4), audio clips and `assets/` consolidation
(FR-PRJ-05), effect chains and sends beyond their empty arrays (Stage 4),
folder lanes (DM-Q1, field reserved), per-note property keys (slot reserved),
and encryption or compression of the bundle (no plans).
