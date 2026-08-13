# CLAP 1.2 coverage audit

**Ticket:** OB-2-01 (AC 4) · **Decision:** D5 · **Date:** 13 August 2026

D5 says OneBeat's internal plugin model is built to **CLAP's semantics**, not to
the intersection of CLAP, VST3 and AU — because modelling the lowest common
denominator discards CLAP's real capabilities permanently, and permanently is a
long time. This document is the check on that claim: every core CLAP 1.2 concept
either has a seat in `engine/src/plugin/` or an exclusion recorded here with a
reason and a landing stage.

An exclusion is not a bug. An *undocumented* exclusion is, because it becomes
invisible and then becomes permanent.

## Core plugin interface

| CLAP concept | Seat in the model | Notes |
|---|---|---|
| `init` / `destroy` | Constructor / destructor | C++ has these; a separate `init` would add a fourth state for nothing. |
| `activate` / `deactivate` | `PluginInstance::activate()` / `deactivate()` | Plus an explicit `State` enum, so DM-Q5's "reconfigure only while deactivated" is checkable rather than remembered. |
| `start_processing` / `stop_processing` | `startProcessing()` / `stopProcessing()` | `[audio-thread]`, as in CLAP. |
| `reset` | `reset()` | |
| `process` | `process(ProcessBlock&)` | |
| `on_main_thread` | `onMainThread()` | |
| `get_extension` | ✗ **Excluded** | CLAP discovers optional interfaces at runtime by string. Internally we have a C++ interface with virtual defaults, which gives the same optionality with compile-time checking. The CLAP *adapter* (OB-2-07) queries extensions and fills in these methods. |

## Events

| CLAP event | Seat | Notes |
|---|---|---|
| `NOTE_ON`, `NOTE_OFF` | `EventType::NoteOn`, `NoteOff` | |
| `NOTE_CHOKE` | `EventType::NoteChoke` | Modelled. The **built-in sampler** degrades it to its fastest release, because the v0.1 voice allocator has no per-voice hard cut — recorded in `sampler_plugin.cpp` at the point of loss. Hosted plugins get the real event. |
| `NOTE_END` | `EventType::NoteEnd` | Output direction only. A host that ignores it leaks per-note automation state. |
| `NOTE_EXPRESSION` | `EventType::NoteExpression` + `NoteExpressionId` | All seven CLAP expressions with CLAP's ranges. |
| `PARAM_VALUE` | `EventType::ParamValue` | Note-addressable via `paramValueForNote`. |
| `PARAM_MOD` | `EventType::ParamModulation` | **The capability D5 exists for.** Kept structurally distinct from value: `ModulatedValue` has separate `base` and `modulation` fields, and only `base` is ever saved. |
| `PARAM_GESTURE_BEGIN/END` | `EventType::ParamGestureBegin`/`End` | |
| `TRANSPORT` | `ProcessBlock::transport` + `EventType::TransportDiscontinuity` | Deliberately different: transport is a *state*, so it travels in the block (as `clap_process.transport` does), and only the discontinuity is an occurrence. |
| `MIDI` | `EventType::Midi1` | 3 bytes, kept opaque. |
| `MIDI2` | `EventType::Midi2` | One UMP packet. The reason `PluginEvent` is 40 bytes rather than 32. |
| `MIDI_SYSEX` | `EventType::MidiSysex` | Pointer + length, borrowed for the call. A 64 KB dump has no business inside a fixed-size event. |
| Event header `space_id` | ✗ **Excluded** | CLAP's namespace field for third-party event vocabularies. Nothing in OneBeat produces or consumes one, and adding it later is a field, not a redesign. Revisit if an extension ecosystem needs it (Stage 6). |
| Variable-size events | ✗ **Deliberately different** | Every event is 40 bytes, so a list is a contiguous array walked linearly — the same choice `ScheduleEvent` makes. Costs the ability to carry an arbitrary payload inline; buys a cache-friendly scan and trivial copyability across the Stage 2 IPC boundary. |

## Parameters (`clap.params`)

| CLAP concept | Seat |
|---|---|
| Stable `id`, `name`, `module` path | `ParamInfo::id` / `name` / `module` |
| Native `min`/`max`/`default` | `ParamInfo::min_value` / `max_value` / `default_value` |
| `cookie` | `ParamInfo::cookie` — opaque, never persisted |
| `IS_STEPPED`, `IS_PERIODIC`, `IS_HIDDEN`, `IS_READONLY`, `IS_BYPASS`, `IS_ENUM` | `ParamFlagIs*` |
| `IS_AUTOMATABLE` + per note-id / key / channel / port | `ParamFlagIsAutomatable*` (all five) |
| `IS_MODULATABLE` + per note-id / key / channel / port | `ParamFlagIsModulatable*` (all five) |
| `REQUIRES_PROCESS` | `ParamFlagRequiresProcess` |
| `value_to_text` / `text_to_value` | `paramValueToText` / `paramTextToValue` |
| `flush` | `paramsFlush` |
| `clap_host_params.rescan` / `clear` | `PluginHost::paramsRescan` / `paramsClear` with the same flag granularity |

Nothing excluded.

## Ports

| CLAP concept | Seat | Notes |
|---|---|---|
| `clap.audio-ports` — dynamic lists, stable IDs, main flag | `audioPortCount` / `audioPortInfo`, `AudioPortInfo` | Lists are dynamic and reconfigurable while deactivated (FR-PLG-12, DM-Q5). |
| In-place pairing | `supports_in_place`, `in_place_pair` | |
| `clap.note-ports` with dialects | `notePortCount` / `notePortInfo`, `NoteDialect` bitmask | CLAP / MIDI / MPE / MIDI2, with a preferred dialect. |
| `clap_host_audio_ports.rescan` with flags | `PluginHost::audioPortsRescan(PortRescanFlags)` | Granular so a name change does not drop routing. |
| Port *types* beyond mono/stereo (surround, ambisonic) | ⚠ **Partial** | `ChannelLayout::Unspecified` plus an explicit channel count. An adapter that meets a surround port reports Unspecified rather than lying about stereo. Real layouts land with the mixer in Stage 4 (EPIC-4). |
| `clap.audio-ports-config` (preset layouts) | ✗ **Excluded** | A convenience over the dynamic list, which we already have. Add when a plugin we care about needs it. |
| `clap.surround`, `clap.ambisonic` | ✗ **Excluded** | Stage 4 at the earliest; both are refinements of the layout question above. |

## State

| CLAP concept | Seat | Notes |
|---|---|---|
| `clap.state` — opaque save/load | `saveState(StateWriter&)` / `loadState(StateReader&)` | Streams, not buffers: plugin states run to megabytes. Opacity is a *requirement*, not a simplification — FR-PLG-10 needs a missing plugin's state to survive in a host that cannot interpret it. |
| `clap.state-context` (preset vs project vs duplicate) | ✗ **Excluded** | Needed when preset management lands (Stage 7). Adding a context argument then is a signature change to one method. |

## Host cooperation

| CLAP concept | Seat | Notes |
|---|---|---|
| `request_restart` / `request_process` / `request_callback` | `PluginHost`, all three | |
| `clap.latency` + `host.latency.changed` | `latencyFrames()`, `PluginHost::latencyChanged()` | Feeds FR-ENG-04 delay compensation. |
| `clap.tail` + `host.tail.changed` | `tailFrames()`, `PluginHost::tailChanged()` | Used by offline render to avoid truncating a release. |
| `clap.thread-pool` | `PluginHost::requestThreadPoolExec()` + `PluginInstance::threadPoolExec()` | **The hook point FR-ENG-05 asks for.** OneBeat declines every request until the graph arrives in Stage 4; declining is always legal and the plugin does the work inline. The seat exists now so adopting it later is not a model change. |
| `clap.gui` | ✗ **Excluded from this model** | Editor windows are a platform concern, not a processing one: OB-2-08 owns them, and they live in the helper process. Putting a GUI method on `PluginInstance` would drag `NSView` into the engine, which NFR-11 forbids. |
| `clap.render` (realtime vs offline hint) | `ProcessSetup::is_offline` | |
| `clap.voice-info` | ⚠ **Partial** | `activeVoiceCount()` — a OneBeat extension, not CLAP, for the performance readout. CLAP's richer voice-info (capacity, per-voice control) is not modelled; nothing consumes it yet. |
| `clap.timer-support`, `clap.posix-fd-support` | ✗ **Excluded** | Both exist to service plugin GUIs on the main thread. They belong to the helper process and OB-2-05, not to the processing model. |
| `clap.note-name`, `clap.preset-load`, `clap.track-info`, `clap.remote-controls` | ✗ **Excluded** | Product features with their own stages: note names and remote controls with the piano roll and mixer (Stages 3–4), preset loading with the browser (Stage 7). None constrains the model's shape. |

## OneBeat additions that CLAP does not have

Worth enumerating, because these are the places a future CLAP version could
force a refactor:

| Addition | Why | Risk |
|---|---|---|
| `beginAudioBlock()` | OneBeat publishes shared data by RCU (`rt/publisher.h`) and the reclamation epoch must tick once per callback. CLAP plugins do not participate in our scheme and simply ignore it. | Low — a no-op default. |
| `activeVoiceCount()` | The performance readout. Returns -1 when unknown, so the UI shows nothing rather than a confident zero. | Low. |
| Fixed-size events | See the events table. | Medium: if a future event type needs more than 16 payload bytes, the struct grows. It is internal, so that is a recompile, not a compatibility event. |
| Explicit `State` enum | Makes DM-Q5's rule assertable. | Low. |

## Verdict

Every CLAP 1.2 core concept in the processing path — lifecycle, events,
parameters, ports, state, latency, tail, thread pool — has a seat in the model.
The exclusions fall into three groups, none of which is about the model's shape:

1. **GUI and platform** (`clap.gui`, timers, posix-fd) — OB-2-08 and the helper
   process own these; NFR-11 keeps them out of the engine.
2. **Product features with their own stage** (presets, note names, track info,
   remote controls, surround) — they consume the model, they do not constrain
   it.
3. **Conveniences over capabilities we already have** (`audio-ports-config`,
   `state-context`, `space_id`) — each is an additive change when something
   needs it.

The model is therefore fit to receive a CLAP adapter (OB-2-07) without loss, and
fit to have VST3 and AU mapped *down* into it in Stage 5. The two capabilities
that make that mapping lossy in the other direction — non-destructive parameter
modulation and per-note expression — are exactly the two that D5 was written to
protect, and both are first-class here.
