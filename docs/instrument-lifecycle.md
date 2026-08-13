# Instrument lifecycle

`OB-3-07` makes instruments project entities rather than the single temporary
host slot used during Stage 2.

## Model contract

- Instruments are project-global and keep a stable ULID for their lifetime.
- Presentation order is the persisted `Instrument::order` field; patterns and
  routing continue to refer to the stable ID.
- Creating an instrument derives a collision-free display name from the plug-in
  descriptor, assigns the next palette colour, and creates a dedicated mixer
  track routed to Master. The instrument and track share one undo entry.
- Duplicating creates fresh instrument and mixer-track IDs while copying the
  plug-in reference/state metadata, note defaults, colour and mute state.
- Replacing changes only `PluginRef`. Pattern sequences remain keyed by the same
  instrument ID, so no notes are moved or lost.
- Deletion reports affected pattern, note and placement counts before applying.
  Undo restores every removed sequence and automation clip with its original ID.

All mutations cross `CommandBus`; ABI 1.5 exposes the same operations to the
Flutter app, including undo and redo.

## App behaviour

The left rack strip is the permanent instrument-header surface for Stage 3.
It exposes selection, inline rename, colour cycling, mute, preview, reorder,
duplicate and deletion. Deletion uses a two-step confirmation containing the
exact pattern and placement counts. The plug-in browser exposes both **Add** and
**Replace** when an instrument is selected.

Selection activates that instrument's hosted plug-in before preview notes are
sent. Stage 3 editors consume the same selection; `OB-3-09` adds step cells to
the right of these headers and `OB-3-10` uses it as piano-roll context.

## Verification

- `test_model_commands.cpp` covers generated names/colours, routing, rename,
  recolour, duplicate, replacement, reorder, five-pattern deletion and exact
  undo restoration.
- `test_abi.cpp` freezes ABI 1.5 and drives create, mute, replace, rename,
  duplicate, reorder, undo/redo and delete through the public C surface.
- `test_project_io.cpp` checks `order` across field-by-field and byte-identical
  save/load, including the worked project fixture.
