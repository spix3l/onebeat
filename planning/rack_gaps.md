# Channel Rack / Patterns audit

## Status

The original Phase 1 correctness gaps are implemented and verified:

- Rack row selection calls the native `selectInstrument` path before updating the inspector.
- Rack routing displays the instrument's real destination and assigns it through the mixer-track selector.
- Mixer strip routing, gain, mute, solo, master gain, and master state are read from the model where the native seam exposes them. Unsupported sends and sidechains are no longer shown as synthetic data.
- Solo state is engine-backed and exclusive in the rack/mixer; native channel synchronization applies the solo gate during rendering.
- Sample channels open the built-in sampler from the inspector, double-click, and context-menu paths.
- Pattern length supports Auto and 1–512 steps through the ABI-compatible rack contract.
- Per-pattern time signatures, pattern groups, ordering, duplicate, recolor, and delete flows are wired.
- Pattern colors are visible in the rack selector and channel/pattern views; the context menu still cycles the existing palette rather than exposing a free-form color editor.
- Shared-pattern notices are wired into rack note editing. The rack action isolates the edit by repointing a known playlist clip or cloning/selecting the current pattern when no clip context exists. Playlist clip inspection still supports clip-specific Make Unique.
- A dedicated Channel Settings editor persists the available gate, shift, cut-group, polyphony, mono/portamento, tuning/range, modulation, arpeggiator, and echo fields through the ABI seam.
- Pattern-owned automation is persisted and scheduled by the flattener; editor authoring still uses the existing automation-clip workflow.
- Split-by-channel and audio render/replace workflows exist in the Playlist/audio editor paths.

## Verification

Recent focused verification:

- Flutter analyzer for rack, mixer, core, and rack regression tests: clean.
- Rack and mixer widget tests: all passing, including route assignment, native selection, solo exclusivity, model-read memoization, shared-pattern isolation, and narrow-layout coverage.
- Native CTest suite: 5/5 passing in the existing build.

## Remaining parity work

These are genuine feature gaps rather than the old Phase 1 defects:

### Channel Rack

- Per-channel swing mix and swing truncation.
- Direct per-row grid controls remain primarily in the inspector/context menu rather than on-row.
- Custom channel groups and group management; filtering is currently All/Used.
- Auto-switch and unused-channel filtering beyond the current All/Used choices.
- Rich multi-channel bulk operations beyond current shift selection, mute/delete, and grouping hooks.
- Channel-specific loop modes: next step/beat/bar, ghost steps, and burn-to-steps.
- A real channel color picker; current recolor uses the fixed palette.
- Advanced Channel Settings runtime behavior for cut groups, polyphony, mono/portamento, arpeggiator, echo, tuning, modulation, and related voice semantics remains partial even though values persist.

### Pattern and editor workflows

- Automatic pattern length based on content, length-in-bars controls, and pattern-specific meter behavior beyond the current Auto/step-count/time-signature seams.
- A free-form pattern/color editor and richer selector filtering/instance-selection workflows.
- Pattern-local automation authoring in the rack/piano-roll editors; native persistence and flattening are present.
- Graph Editor lanes beyond velocity: pan, fine pitch, release, Mod X/Y, shift, and note repeat.
- Native integration coverage proving solo changes rendered audio, plus broader route graph integration coverage and multi-output instrument routing. Current assignment targets output port 0.
- Dedicated pattern deletion-followed-by-undo and automatic-length regression coverage should be expanded alongside the remaining engine work.

## Recommended next order

1. Add native integration tests for solo gating, route graph display/assignment, delete/undo, and Auto length.
2. Add channel groups, richer filters, channel loop modes, and per-channel swing data/UI.
3. Complete the dedicated settings runtime semantics and Graph Editor property lanes.
4. Add pattern-local automation editing and a real color editor.
5. Extend routing to multi-output instruments and expose sends/sidechains only after native model support exists.

## Sources

- [FL Studio Channel Rack & Step Sequencer](https://www.image-line.com/fl-studio-learning/fl-studio-online-manual/html/channelrack.htm)
- [FL Studio Patterns Menu](https://www.image-line.com/fl-studio-learning/fl-studio-online-manual/html/menu_patterns.htm)
- [FL Studio Channel Settings](https://www.image-line.com/fl-studio-learning/fl-studio-online-manual/html/chansettings.htm)
- [FL Studio Miscellaneous Channel Settings](https://www.image-line.com/fl-studio-learning/fl-studio-online-manual/html/chansettings_misc.htm)
