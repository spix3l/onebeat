# OB-3-13 — Clip windowing, looping & transpose transform (UI)

| | |
|---|---|
| **Stage** | 3 — v0.3 "It sequences" |
| **Type** | Feature (UI + model) |
| **Priority** | Medium |
| **Dependencies** | OB-3-04 (flattener semantics), OB-3-12 |
| **References** | FR-SEQ-07, FR-SEQ-08 (transpose = M), DM-Q2, DM-Q3, D-M3 |
| **Estimate** | M |

## Context

Clips carry source offset, length and loop mode from v1 (DM-Q2), plus the first non-destructive transform — transpose (DM-Q3). The flattener already honours these (OB-3-04); this ticket gives them UI and inspector controls.

## Scope

1. **Resize semantics:** resizing a clip shorter truncates (window); longer extends per loop mode (loop = repeats with tiled visual; hold-off = silence tail); loop boundaries drawn on the clip.
2. **Source offset:** ⌥-drag inside the clip (or inspector field) shifts the window into the pattern; visual preview shifts accordingly.
3. **Clip inspector** (panel/popover per design language): start, length, offset, loop mode, mute, **transpose (±48 st)**; transposed clips badge the value on the clip face (e.g. "+3"); Martian Mono values.
4. **Interplay with Make unique (D-M3):** the inspector places *Make unique* beside the transform controls — variation without cloning is the default path, cloning the explicit one.
5. Reserved transform fields (velocity scale, nudge, probability) visible as disabled "coming later" rows? **No** — omitted entirely (no dead UI); they exist only in schema.

## Acceptance criteria

- [x] Windowing UI drives OB-3-04 correctly: truncate/loop/offset all audibly and visually correct (paired render tests).
- [x] Transpose on one of two clips sharing a pattern alters only that clip (render test), badge shown.
- [x] All operations undoable; inspector reachable without right-click.
- [x] Save/load round-trips all clip fields.

**Complete (14 August 2026).** The flattener already honoured `window_start`,
`loop` and `transpose` from OB-3-04, so this ticket was UI and ABI only. The
inspector carries start, length, offset, loop mode (`LOOP` / `HOLD-OFF`), mute
and transpose (±48, clamped), with the transpose value badged on the clip face
and loop boundaries drawn where the pattern restarts. ⌥-drag inside a clip shifts
the window; the right edge resizes.

`Make unique` sits directly beside the transform controls, which is the whole
point of D-M3's placement: varying a clip is the default path and cloning is the
explicit one, and putting them side by side is what makes that choice legible.

Per §5, the reserved transform fields (velocity scale, nudge, probability) are
**omitted entirely** — they exist in the schema and round-trip, and no dead UI
ships for them.

Round-tripping is covered by the exit script's byte-identical save → open → save
assertion, which necessarily covers every clip field the writer emits.


## Out of scope

- Velocity-scale/nudge/probability UI (v1.x per DM-Q3). Audio-clip trim/fade (Stage 9).
