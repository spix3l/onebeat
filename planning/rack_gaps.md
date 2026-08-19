# Channel Rack / Patterns audit

## Scope

This audit compares the current OneBeat Channel Rack and pattern implementation with FL Studio's documented Channel Rack, Step Sequencer, Channel Settings, and Patterns workflows.

**Overall:** the core model is solid and already captures FL Studio's central pattern semantics: one project-global instrument rack, multiple instruments per pattern, sparse note sequences, pattern clips referencing shared patterns, live usage counts, undoable edits, step painting, velocity, and playback feedback. The current implementation is still **partial FL Studio parity**, with several user-visible gaps and a few correctness issues.

## Current strengths

- Shared pattern data across all instruments and placements.
- Pattern usage counts are derived from clips.
- Pattern creation, selection, rename, delete confirmation, and duplicate APIs exist.
- Step toggle, drag paint/erase, and velocity editing are implemented.
- 16/32/64-step pattern lengths work.
- Instrument add, drop, replace, duplicate, delete, rename, reorder, mute, gain, and pan paths exist.
- Piano-roll fallback previews exist for off-grid or multi-pitch rows.
- Playback cursor follows transport snapshot data.
- `Make unique` is available from the Playlist clip inspector.
- Project save/load and undo/redo support the model.

## Critical correctness gaps

### 1. Selecting a rack row does not select the native engine instrument

`RackBinding._onSelectRow()` updates `RackStore.selectedInstrumentId`, but does not call `EngineClient.selectInstrument()`.

Consequences:

- The inspector keyboard may audition the previously selected instrument.
- Plugin/sample preview behavior can target the wrong channel.
- The UI selection and the engine's audition channel can disagree.

Relevant code:

- `app/lib/src/features/channel_rack/rack_binding.dart`
- `app/lib/src/features/channel_rack/rack_store.dart`
- `app/lib/src/engine/engine_client.dart`

**Priority: Critical**

### 2. Routing is displayed as hardcoded text

Rack rows display `→ D1` and the inspector displays `M1 · Music`. These are not derived from the instrument's actual `routing` or mixer destination.

The model has routing data, but the rack ABI does not expose the route, and there is no route assignment callback wired from the rack.

This is a major mismatch with FL Studio, where the channel row's mixer-track destination is both visible and editable.

**Priority: Critical**

### 3. Solo is stored but does not affect audio

The rack exposes Solo and the model persists `Instrument::soloed`, but `syncChannels()` only applies gain, pan, and mute to render channels. It does not implement solo gating.

The binding comment explicitly defers real solo semantics to a future mixer stage. This creates a control that visually appears functional but does not change playback.

**Priority: Critical**

### 4. Sample-channel editor access is incomplete

FL Studio opens the channel instrument/settings from the channel button. In the current rack:

- A sample row's normal click only selects it.
- Sample rows are explicitly excluded from the double-tap plugin handler.
- The context-menu path calls the generic plugin callback rather than the dedicated sampler callback.

Therefore the built-in sampler editor is not consistently reachable from the rack.

**Priority: High**

## Major Channel Rack gaps

### 5. Per-channel grid/divisor exists in the engine but is not exposed

The native ABI supports 1/8, 1/16, and 1/32 grids. `RackStore.setGrid()` also exists, but the current screen has no per-row grid control or callback. The only active toolbar control is pattern length.

This is also a direct drift from `docs/channel-rack.md`, which claims a visible `1/8`, `1/16`, and `1/32` control.

**Priority: High**

### 6. Swing exists in the engine but has no rack UI

The engine and client support pattern swing, but `RackBinding` does not pass a swing callback and `ObRackToolbar` does not render swing controls.

FL Studio has both:

- Global/channel-rack swing.
- Per-channel Swing Mix.

The current model only has one `Pattern::swing` value. There is no per-channel swing multiplier and no “truncate swung notes” option.

**Priority: High**

### 7. Visible velocity editing is missing

Velocity can currently be edited through Option-drag, right-drag, and internal store methods. The current inspector does not render visible velocity `−/+` controls or a selected-step readout.

This contradicts the documented FR-UX-17 path in `docs/channel-rack.md`.

FL's Graph Editor supports much more than velocity:

- Velocity
- Pan
- Fine pitch
- Release
- Mod X
- Mod Y
- Shift
- Note repeat

The current rack only supports velocity.

**Priority: High**

### 8. No Channel Rack filtering or grouping

FL Studio provides:

- Channel filter groups.
- All/Unsorted/group views.
- Group selected.
- Rename/delete groups.
- Auto-switch display filter.
- Select unused channels.
- Sort by name, color, type, or mixer track.

The current implementation always renders every project instrument. That is a valid “All” view, but there is no way to reduce a large rack to drums, synths, unused channels, or a user-defined group.

The backlog originally specified `SHOW ALL`, but the current UI does not include it.

**Priority: High**

### 9. No multi-channel selection or bulk actions

The current rack tracks one selected instrument:

```dart
String? selectedInstrumentId;
```

FL Studio supports selecting multiple channels and applying actions such as mute/unmute, move, group, recolor, transpose, mixer assignment, swing mix, and delete. Current actions are effectively single-row operations.

**Priority: Medium**

### 10. No channel color editing

Instrument recoloring exists in the native ABI and client, but the rack provides no visible color-picker or recolor action. The color chip is display-only.

The same problem exists for pattern colors: pattern color is read from the engine but the tab does not use it visually, and there is no recolor control.

**Priority: Medium**

### 11. No independent channel loop controls

FL Studio supports channel-specific looping:

- Next step.
- Next beat.
- Next bar.
- Loop all channels.
- Loop step channels.
- Ghost steps.
- Burn looping channels to real steps.

The current model has pattern length and clip looping, but no per-channel rack loop mode or channel-specific loop length.

**Priority: Medium**

### 12. Advanced channel settings are absent

Compared with FL Studio's Channel Settings, the current rack does not expose:

- Gate.
- Shift.
- Cut/Cut-by groups.
- Cut itself.
- Maximum polyphony.
- Mono/portamento.
- Arpeggiator.
- Echo delay.
- Root key and key range.
- Fine tuning.
- Velocity/key tracking.
- Mod X/Mod Y.

Some of these belong in a channel settings/editor surface rather than the compact rack, but there is currently no obvious rack path to them.

**Priority: Medium / Advanced parity**

## Pattern-management gaps

### 13. Pattern management is split between APIs and incomplete rack UI

The native and client APIs support recolor, duplicate, and remove, but the rack only provides visible actions for create, rename, and delete.

The pattern context menu has no Duplicate or Recolor action. `ActionRegistry` declares these actions, but `RackBinding` only handles `pattern.create`.

This is a concrete discoverability and implementation gap.

**Priority: High**

### 14. The shared-pattern warning is not wired into production editors

`PatternStore` implements the D-M6 warning and `Make unique` state, but production code does not instantiate it. The rack and piano-roll stores do not call `noteEditStarted()`.

So the intended warning:

> Editing “Verse Drums” — used in 6 places

does not appear during normal rack or piano-roll editing.

`Make unique` works from the Playlist inspector, but the warning workflow is effectively dead outside tests.

**Priority: High**

### 15. Pattern delete text contradicts actual undo behavior

`DeletePatternDialog` says:

> This cannot be undone.

The native operation uses the command bus and is intended to be undoable. The dialog should explain that deleting the pattern also deletes its playlist clips, while clearly indicating that Undo can restore it.

**Priority: Medium**

### 16. Pattern length is much narrower than FL Studio

Current limits:

- UI: 16, 32, and 64 steps only.
- ABI: rejects all other lengths.
- ABI row buffer: `OB_RACK_MAX_STEPS` is 256.

FL Studio supports:

- Auto pattern length.
- 1–512 steps.
- Length in bars.
- Pattern-specific time signatures.

The current project has a transport time signature, but no per-pattern time signature and no automatic pattern-length mode.

**Priority: High**

### 17. Pattern ordering and selector workflow are limited

FL Studio supports:

- Find first/next empty pattern.
- Move pattern up/down.
- Pattern groups.
- Pattern filters.
- Select pattern instances in the Playlist.
- Split by channel.
- Render pattern to audio.
- Render and replace.

The current rack uses creation-order tabs. There is no pattern list/dropdown, reordering, grouping, empty-pattern navigation, split-by-channel, or pattern render workflow.

**Priority: Medium**

### 18. Automation is modeled outside patterns

FL Studio patterns contain note, step, and automation data for the channels. OneBeat currently models automation as a separate `AutomationSource` clip type, while `Pattern` contains only instrument note sequences.

That is an intentional architectural choice, but it is still a parity difference. Automation authored alongside a pattern cannot currently behave as pattern-local automation in the FL sense.

**Priority: Medium / Architectural**

## Documentation and test drift

`docs/channel-rack.md` currently claims functionality that the active UI does not provide:

- Visible per-row grid controls.
- Visible swing controls.
- Visible velocity controls.
- `SHOW ALL`.
- `+ ADD INSTRUMENT`.
- `− PAT`.
- Footer wiring.
- Some undo paths.

The current screen mainly wires pattern tabs, pattern length, step editing, velocity drag, and instrument row actions.

The test suite has good store/widget coverage, but it does not currently protect the most important gaps:

- Native instrument selection before audition.
- Actual route assignment and display.
- Solo affecting rendered audio.
- Pattern duplicate/recolor from the rack.
- Shared-pattern warning appearing in the rack/piano roll.
- Pattern delete followed by undo.
- 512-step/auto-length behavior.
- Per-row grid control in the current UI.

## Recommended implementation order

### Phase 1 — Correctness

1. Wire rack row selection to `client.selectInstrument`.
2. Expose actual route/mixer-track data and assignment.
3. Implement real solo semantics or hide/disable the control until supported.
4. Fix sampler opening from single-click/double-click/context menu.
5. Correct the delete dialog's undo language.

### Phase 2 — Restore the documented rack contract

1. Add visible per-row grid/divisor controls.
2. Add visible pattern swing controls.
3. Add selected-step velocity controls/readout.
4. Add `SHOW ALL` / used-only filtering.
5. Add remove-sequence (`− PAT`) as a clearly distinct action from deleting the channel.

### Phase 3 — Pattern parity

1. Add pattern duplicate and recolor to the rack selector.
2. Wire the shared-pattern warning into actual note-edit entry points.
3. Expand pattern length to Auto and 1–512 steps.
4. Add per-pattern time signature.
5. Add pattern ordering, grouping, and empty-pattern navigation.

### Phase 4 — Advanced FL parity

1. Channel filter groups and multi-selection.
2. Graph Editor properties beyond velocity.
3. Per-channel swing mix and loop modes.
4. Channel Settings surface.
5. Pattern-local automation or an explicitly documented divergence.
6. Split-by-channel and pattern-to-audio workflows.

## Audit result

The project has a good shared-pattern foundation, but the active Channel Rack is currently closer to a compact step editor than an FL Studio-equivalent Channel Rack. The most urgent issues are incorrect native selection, fake routing/solo presentation, missing documented controls, and the unwired shared-pattern warning.

## Comparison sources

- [FL Studio Channel Rack & Step Sequencer](https://www.image-line.com/fl-studio-learning/fl-studio-online-manual/html/channelrack.htm)
- [FL Studio Patterns Menu](https://www.image-line.com/fl-studio-learning/fl-studio-online-manual/html/menu_patterns.htm)
- [FL Studio Channel Settings](https://www.image-line.com/fl-studio-learning/fl-studio-online-manual/html/chansettings.htm)
- [FL Studio Miscellaneous Channel Settings](https://www.image-line.com/fl-studio-learning/fl-studio-online-manual/html/chansettings_misc.htm)
