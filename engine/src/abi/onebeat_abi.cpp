// Implementation of the public C ABI (ADR-002, OB-1-10).
//
// Rules this file exists to enforce:
//   - no exception ever crosses the boundary (every entry point is wrapped);
//   - no allocation on any path a UI frame takes (snapshot read, event poll,
//     command post);
//   - every entry point validates its handle and returns a status code.
#include "abi/onebeat_abi.h"

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <map>
#include <memory>
#include <new>
#include <optional>
#include <string>
#include <vector>

#include "core/engine.h"
#include "core/wav_loader.h"
#include "model/command.h"
#include "model/commands.h"
#include "model/flattener.h"
#include "model/note_edit.h"
#include "model/project_io.h"
#include "plugin/scan/plugin_library.h"
#include "plugin/scan/subprocess_probe.h"

namespace {

constexpr const char* kSamplePluginId = "onebeat.sample";

bool isSampleInstrument(const onebeat::model::Instrument& instrument) {
  return instrument.plugin.id == kSamplePluginId;
}

// Per-thread, so two threads failing at once cannot clobber each other's
// message (ADR-002 §2).
thread_local std::string g_last_error;  // NOLINT(*-avoid-non-const-global-variables)

ob_status fail(ob_status status, const char* message) {
  g_last_error = message;
  return status;
}

// Truncating, always-terminating copy into a fixed C array. `strncpy` does not
// terminate when the source fills the buffer, which is the classic way a POD
// boundary struct starts leaking the bytes that follow it.
void copyText(char* destination, size_t capacity, const char* source) {
  if (capacity == 0) {
    return;
  }
  if (source == nullptr) {
    destination[0] = '\0';
    return;
  }
  const size_t length = std::strlen(source);
  const size_t copied = length < capacity - 1 ? length : capacity - 1;
  std::memcpy(destination, source, copied);
  destination[copied] = '\0';
}

std::string fileName(const std::string& path) {
  const size_t slash = path.find_last_of("/\\\\");
  return slash == std::string::npos ? path : path.substr(slash + 1);
}

// NUL-separated, double-NUL-terminated — the shape Dart can build with one
// string join and one allocation, rather than marshalling an array of pointers
// across the FFI boundary and having to own their lifetimes (ADR-002 §7).
std::vector<std::string> splitDirectories(const char* utf8_directories) {
  std::vector<std::string> directories;
  if (utf8_directories == nullptr) {
    return directories;
  }
  const char* cursor = utf8_directories;
  while (*cursor != '\0') {
    const size_t length = std::strlen(cursor);
    directories.emplace_back(cursor, length);
    cursor += length + 1;
  }
  return directories;
}

}  // namespace

struct ob_engine {
  std::unique_ptr<onebeat::core::Engine> engine;
  onebeat::model::Project project;
  onebeat::model::CommandBus commands{project};
  onebeat::model::FlattenScheduler flattener{project};
  std::optional<onebeat::model::InstrumentId> selected_instrument;
  std::optional<onebeat::model::PatternId> current_pattern;
  bool pattern_preview = false;
  std::optional<onebeat::model::InstrumentId> preview_instrument;
  std::map<onebeat::model::InstrumentId, onebeat::model::Ticks> rack_grids;
  // Dense channels assigned by the flattener to arrangement audio clips. Kept
  // between publishes so a transport-only update rebuilds the same rack even
  // when the schedule itself did not become dirty.
  std::map<onebeat::model::ClipId, onebeat::core::InstrumentId> audio_channel_indices;
  std::string undo_name_cache;
  std::string redo_name_cache;
  // Where the project last came from or went to. Kept so that a save can carry
  // existing plug-in sidecars across rather than dropping them (OB-3-05), and
  // so ⌘S knows whether it has a destination at all.
  std::string project_path;
  // Canonical bytes of the project at the last save or open, hashed. The dirty
  // flag compares against this rather than counting edits: undoing back to the
  // last save leaves nothing to write, and a counter would still say otherwise.
  std::string saved_project_hash;
  std::string project_name_cache;
  // Parsed-but-unmodelled fields from a project written by a newer version.
  // Round-tripped verbatim so opening and saving never silently deletes them.
  onebeat::model::Residue residue;
  std::string project_json_cache;
  // Not part of the Engine: the plugin library is filesystem work and a
  // background thread, and nothing in it goes near the audio thread (OB-2-02).
  std::unique_ptr<onebeat::plugin::scan::PluginLibrary> library;
  bool has_instance = false;
  bool instance_missing = false;
  uint32_t instance_id = 1;
  uint32_t instance_format = OB_PLUGIN_FORMAT_CLAP;
  std::string instance_plugin_id;
  std::string instance_name;
  std::string instance_vendor;
  std::string instance_path;
  std::vector<uint8_t> instance_state;

  /* Which plug-in each instrument has hosted, and on which engine channel.
   *
   * A hosted plug-in belongs to its instrument, not to whatever lane happened to
   * be selected when it was loaded: a rack of samples plus one instrument plays
   * both, and adding the instrument does not take a sampler's voice away. The
   * channel recorded here is the dense index syncChannels assigns, so it moves
   * whenever removing an instrument renumbers the lanes after it. */
  struct HostedSlot {
    int channel = -1;
    std::string path;
    std::string plugin_id;
    /* What the plug-in calls itself, read once it was hosted. */
    std::string name;
    /* The bundle was not on disk, so a silent stand-in holds the state instead
     * (session load's "missing plug-in" case). */
    bool missing = false;
    /* Hosting was tried and failed. Kept so a broken plug-in is not respawned on
     * every subsequent model edit; cleared when the instrument's plug-in ref
     * changes. */
    bool failed = false;
  };
  std::map<onebeat::model::InstrumentId, HostedSlot> hosted;
  // Project-open state is collected before hosting is reconciled. Keeping it
  // keyed by instrument ID lets a missing or reordered lane receive the same
  // opaque bytes without coupling persistence to a dense channel index.
  std::map<onebeat::model::InstrumentId, std::vector<uint8_t>> pending_project_state;
};

namespace {

// The project's canonical bytes, hashed. Cheap enough to be asked for by the
// UI a few times a second, and exact — two projects with the same hash write
// the same file, which is the only definition of "saved" that does not lie.
std::string projectHash(const ob_engine& handle) {
  return onebeat::model::sha256Hex(
      onebeat::model::writeProjectJson(handle.project, handle.residue));
}

// Created on first use rather than in ob_engine_create, so an engine that never
// hosts a plugin — every Stage 1 test, the offline renderer, the devtool's
// device sweep — pays nothing for it, not even a file stat.
//
// The cache lives beside the session logs, which makes the rule "point the
// engine at a scratch `log_directory` and everything it writes goes there". A
// test that did not get that would silently overwrite the developer's real
// plugin cache with an empty one.
onebeat::plugin::scan::PluginLibrary& pluginLibrary(ob_engine& handle) {
  if (handle.library == nullptr) {
    const std::string& log_directory = handle.engine->config().log_directory;
    const std::string cache_path =
        log_directory.empty() ? std::string() : log_directory + "/plugin-cache.bin";
    handle.library = std::make_unique<onebeat::plugin::scan::PluginLibrary>(
        cache_path, &handle.engine->diagnostics());
  }
  return *handle.library;
}

std::optional<onebeat::model::InstrumentId> instrumentId(const char* text) {
  if (text == nullptr) return std::nullopt;
  return onebeat::model::InstrumentId::parse(text);
}

const onebeat::model::Instrument* orderedInstrument(const ob_engine& handle, int32_t index) {
  if (index < 0 || static_cast<size_t>(index) >= handle.project.instruments().size())
    return nullptr;
  for (const auto& [id, instrument] : handle.project.instruments()) {
    (void)id;
    size_t lower = 0;
    for (const auto& [other_id, other] : handle.project.instruments()) {
      (void)other_id;
      if (other.order < instrument.order) ++lower;
    }
    if (lower == static_cast<size_t>(index)) return &instrument;
  }
  return nullptr;
}

const onebeat::model::Pattern* currentPattern(const ob_engine& handle) {
  return handle.current_pattern ? handle.project.findPattern(*handle.current_pattern) : nullptr;
}

/* Grows the current pattern so that everything drawn in it can sound.
 *
 * The flattener wraps a looping clip modulo the *pattern* length and drops what
 * falls past it, so a note past the end was accepted by the editor, stored,
 * drawn, swept over by the playhead, and never played. Nothing in the roll
 * bounded a note by the pattern length, so drawing past it was a normal thing
 * to do.
 *
 * Grow only, and to a whole bar, so a length the user chose (the rack's 16/32/
 * 64-step control, ob_engine_rack_set_length) is never quietly reduced. Clips
 * follow the same rule that control uses: a placement still exactly as long as
 * the pattern is one that fits it, and is carried along; a placement the user
 * has resized is a deliberate window and is left alone.
 *
 * Outside the command bus on purpose. This is a consequence of an edit rather
 * than an edit, and recording it would make undoing one note take two undos.
 */
void growPatternToFit(ob_engine& handle) {
  const onebeat::model::Pattern* pattern = currentPattern(handle);
  if (pattern == nullptr) return;
  const onebeat::model::PatternId pattern_id = pattern->id;
  const onebeat::model::Ticks old_length = pattern->length;
  const onebeat::model::Ticks length = onebeat::model::patternLoopLength(*pattern);
  if (length <= old_length) return;

  /* Collected before mutating: updating a clip emits a change event, and a
   * subscriber must not observe a half-walked map. */
  std::vector<onebeat::model::ClipId> fitting;
  for (const auto& [clip_id, clip] : handle.project.clips()) {
    const onebeat::model::PatternSource* source = clip.pattern();
    if (source == nullptr || source->pattern != pattern_id) continue;
    if (clip.length == old_length) fitting.push_back(clip_id);
  }

  handle.project.updatePattern(
      pattern_id, onebeat::model::ChangeField::Length,
      [length](onebeat::model::Pattern& target) { target.length = length; });
  for (const onebeat::model::ClipId clip_id : fitting) {
    handle.project.updateClip(clip_id, onebeat::model::ChangeField::Length,
                              [length](onebeat::model::Clip& target) { target.length = length; });
  }
}

/* Hands the engine the rack the model describes.
 *
 * The order here is not a choice: the schedule addresses instruments by the
 * dense index the flattener assigns in ULID order (model/flattener.h), and
 * `project.instruments()` is a map keyed by that same ULID — so walking it in
 * order *is* the index. Building the rack any other way would route every
 * channel's notes to the wrong voice. */
void syncChannels(ob_engine& handle) {
  std::vector<onebeat::core::Engine::ChannelDesc> channels;
  channels.reserve(handle.project.instruments().size() + handle.audio_channel_indices.size());
  int index = 0;
  for (const auto& [id, instrument] : handle.project.instruments()) {
    onebeat::core::Engine::ChannelDesc desc;
    /* Only a sample instrument has a WAV to load. An empty lane and a hosted
     * plug-in both leave this blank, which leaves that channel silent rather
     * than sounding whatever the slot held before. */
    if (isSampleInstrument(instrument)) desc.sample_path = instrument.plugin.path_hint;
    desc.gain = instrument.gain;
    desc.pan = instrument.pan;
    desc.muted = instrument.muted;
    channels.push_back(std::move(desc));
    if (handle.selected_instrument.has_value() && *handle.selected_instrument == id) {
      handle.engine->setAuditionChannel(index);
    }
    ++index;
  }

  // The flattener assigns audio clips in project clip-map order, immediately
  // after instruments. Reproduce that order here so each AudioStart event hits
  // the channel whose worker thread loaded its corresponding file.
  for (const auto& [clip_id, channel_index] : handle.audio_channel_indices) {
    const onebeat::model::Clip* clip = handle.project.findClip(clip_id);
    const onebeat::model::AudioSource* audio = clip == nullptr ? nullptr : clip->audio();
    if (audio == nullptr) continue;
    onebeat::core::Engine::ChannelDesc desc;
    desc.sample_path = audio->path;
    desc.gain = audio->gain;
    desc.muted = clip->muted;
    desc.one_shot = true;
    if (channel_index != static_cast<onebeat::core::InstrumentId>(channels.size())) {
      // This should only be possible after a malformed model/map mismatch; do
      // not silently route a song to the wrong sampler if it ever happens.
      continue;
    }
    channels.push_back(std::move(desc));
  }
  handle.engine->setChannels(std::move(channels));
}

/* The dense channel an instrument's voice sounds on: its position in
 * `project.instruments()`, which is the order syncChannels and the flattener
 * both walk. -1 when the instrument is not in the project. */
int channelIndexOf(const ob_engine& handle, const onebeat::model::InstrumentId& id) {
  int index = 0;
  for (const auto& [other, instrument] : handle.project.instruments()) {
    (void)instrument;
    if (other == id) return index;
    ++index;
  }
  return -1;
}

/* An instrument that sounds through a hosted plug-in rather than through a
 * channel's built-in sampler: it names a plug-in, and that plug-in is not the
 * sample player every WAV lane uses. */
bool isHostedInstrument(const onebeat::model::Instrument& instrument) {
  return !instrument.plugin.id.empty() && !isSampleInstrument(instrument);
}

/* Brings the hosted plug-ins in line with the model's instruments.
 *
 * Hosting belongs to an instrument, not to a selection and not to a channel
 * number. Adding an instrument must therefore not take the voice of whichever
 * lane happened to be selected — the bug that made a new plug-in play out of
 * the last sample's channel — and deleting a lane must carry the plug-ins after
 * it down to their new indices rather than leave them pointing at a neighbour.
 *
 * Runs from publishModel, so every path that can change the rack (add, replace,
 * delete, undo, open) reconciles through here and nowhere else. */
void syncHostedInstruments(ob_engine& handle) {
  std::vector<int> destination(static_cast<size_t>(onebeat::core::MaxRackChannels));
  for (size_t channel = 0; channel < destination.size(); ++channel) {
    destination[channel] = static_cast<int>(channel);
  }

  /* What is hosted already: keep it where its instrument now sits, or drop it
   * when the instrument is gone or has been given a different plug-in. */
  std::vector<onebeat::model::InstrumentId> dropped;
  for (auto& [id, slot] : handle.hosted) {
    const onebeat::model::Instrument* instrument = handle.project.findInstrument(id);
    const bool keeps_plugin = instrument != nullptr && isHostedInstrument(*instrument) &&
                              instrument->plugin.id == slot.plugin_id &&
                              instrument->plugin.path_hint == slot.path;
    const int index = keeps_plugin ? channelIndexOf(handle, id) : -1;
    const bool usable = index >= 0 && index < onebeat::core::MaxRackChannels;
    if (slot.channel >= 0 && slot.channel < static_cast<int>(destination.size())) {
      destination[static_cast<size_t>(slot.channel)] = usable ? index : -1;
    }
    if (!usable) {
      dropped.push_back(id);
      continue;
    }
    slot.channel = index;
  }
  for (const onebeat::model::InstrumentId& id : dropped) handle.hosted.erase(id);
  std::string error;
  (void)handle.engine->remapHostedInstruments(destination, error);

  /* What should be hosted and is not. Collected first: hosting reads the
   * instrument map, and the naming fix-up below writes to it. */
  std::vector<std::pair<onebeat::model::InstrumentId, int>> to_host;
  int index = 0;
  for (const auto& [id, instrument] : handle.project.instruments()) {
    const int channel = index++;
    if (!isHostedInstrument(instrument)) continue;
    if (handle.hosted.count(id) != 0) continue;
    if (channel >= onebeat::core::MaxRackChannels) continue;
    to_host.emplace_back(id, channel);
  }

  for (const auto& [id, channel] : to_host) {
    const onebeat::model::Instrument* instrument = handle.project.findInstrument(id);
    if (instrument == nullptr) continue;
    ob_engine::HostedSlot slot;
    slot.channel = channel;
    slot.path = instrument->plugin.path_hint;
    slot.plugin_id = instrument->plugin.id;
    slot.missing = slot.path.empty() || !std::filesystem::exists(slot.path);
    std::string host_error;
    if (slot.missing) {
      /* The bundle is not on this machine. A silent stand-in keeps the lane, its
       * notes and its saved state rather than dropping them. */
      const auto state = handle.pending_project_state.find(id);
      static const std::vector<uint8_t> empty_state;
      const std::vector<uint8_t>& bytes =
          state == handle.pending_project_state.end() ? empty_state : state->second;
      slot.failed = !handle.engine->installMissingInstrument(instrument->plugin.name, bytes,
                                                             channel, host_error);
    } else {
      slot.failed = !handle.engine->createSandboxedInstrument(
          slot.path, slot.plugin_id, onebeat::plugin::scan::SubprocessProbe::discoverHelperPath(),
          channel, host_error);
    }
    if (!slot.failed) {
      slot.name = handle.engine->channelInstrument(channel).name().text();
    }
    /* A lane added straight from a bundle path — the integration driver, a
     * project written elsewhere — has only the plug-in ID to go on. Now that the
     * plug-in has introspected, give the lane the name it calls itself. A
     * consequence of hosting rather than an edit, so it stays out of the undo
     * history for the same reason growPatternToFit does. */
    if (!slot.name.empty() && instrument->plugin.name == instrument->plugin.id) {
      const std::string name = slot.name;
      const bool rename_lane = instrument->name == instrument->plugin.id;
      handle.project.updateInstrument(id, onebeat::model::ChangeField::Name,
                                      [&name, rename_lane](onebeat::model::Instrument& value) {
                                        value.plugin.name = name;
                                        if (rename_lane) value.name = name;
                                      });
    }
    handle.hosted.emplace(id, std::move(slot));
  }
}

/* Which channel the single-instance ABI surface — parameters, the editor, the
 * scratch session — talks to: the selected instrument's. Channel 0 is the
 * fallback for a scratch instance that has no instrument behind it at all. */
int instanceChannel(const ob_engine& handle) {
  if (!handle.selected_instrument.has_value()) return 0;
  const int channel = channelIndexOf(handle, *handle.selected_instrument);
  return channel < 0 ? 0 : channel;
}

/* Refreshes what ob_engine_instance_at and the parameter calls report: the
 * selected instrument's plug-in. The instance surface is a view of the
 * selection, not a second place where hosting is decided. */
void refreshInstanceView(ob_engine& handle) {
  handle.has_instance = false;
  handle.instance_missing = false;
  if (!handle.selected_instrument.has_value()) return;
  const onebeat::model::Instrument* instrument =
      handle.project.findInstrument(*handle.selected_instrument);
  if (instrument == nullptr) return;
  handle.instance_path = instrument->plugin.path_hint;
  handle.instance_plugin_id = instrument->plugin.id;
  handle.instance_name = instrument->plugin.name;
  handle.instance_vendor = instrument->plugin.vendor;
  handle.instance_format = static_cast<uint32_t>(instrument->plugin.format);
  const auto hosted = handle.hosted.find(*handle.selected_instrument);
  if (hosted == handle.hosted.end() || hosted->second.failed) return;
  if (!hosted->second.name.empty()) handle.instance_name = hosted->second.name;
  handle.has_instance = true;
  handle.instance_missing = hosted->second.missing;
}

void publishModel(ob_engine& handle) {
  /* Before the flatten, so the schedule is built from the grown pattern rather
   * than from the one that was too short to hold the edit just made. */
  growPatternToFit(handle);
  onebeat::model::FlattenResult flattened;
  if (handle.pattern_preview && handle.current_pattern.has_value()) {
    onebeat::model::Project preview;
    onebeat::model::Project::Tables tables = handle.project.copyTables();
    tables.clips.clear();
    const onebeat::model::Pattern* pattern = currentPattern(handle);
    if (pattern != nullptr) {
      for (const auto& [clip_id, source_clip] : handle.project.clips()) {
        const auto* source = source_clip.pattern();
        if (source == nullptr || source->pattern != *handle.current_pattern) continue;
        onebeat::model::Clip clip = source_clip;
        clip.start = 0;
        clip.length = pattern->length;
        tables.clips.emplace(clip_id, std::move(clip));
        break;
      }
      if (handle.preview_instrument.has_value()) {
        auto preview_pattern = tables.patterns.find(*handle.current_pattern);
        if (preview_pattern != tables.patterns.end()) {
          for (auto sequence = preview_pattern->second.sequences.begin();
               sequence != preview_pattern->second.sequences.end();) {
            if (sequence->first == *handle.preview_instrument) {
              ++sequence;
            } else {
              sequence = preview_pattern->second.sequences.erase(sequence);
            }
          }
        }
      }
    }
    preview.adopt(std::move(tables));
    flattened = onebeat::model::flatten(
        preview, onebeat::model::FlattenOptions{handle.engine->config().sample_rate, 1});
  } else {
    flattened = handle.flattener.flushIfDirty(handle.engine->config().sample_rate);
  }
  if (flattened.schedule != nullptr) {
    handle.audio_channel_indices = std::move(flattened.audio_channel_index);
  }
  /* Every model edit that can change what a channel sounds like — adding an
   * instrument, loading a sample, gain, pan, mute, reordering — reaches the
   * engine through here, for the same reason the schedule does. */
  syncChannels(handle);
  /* And every edit that can change which lane a plug-in belongs to reconciles
   * hosting here, for the same reason. */
  syncHostedInstruments(handle);
  // A project load supplies state by stable instrument ID. Hosting happens as
  // part of this publish, so restore any chunks that could not be handed to a
  // MissingPlugin constructor before exposing the instance to the UI.
  for (auto it = handle.pending_project_state.begin(); it != handle.pending_project_state.end();) {
    const int channel = channelIndexOf(handle, it->first);
    if (channel >= 0 && handle.engine->loadHostedState(channel, it->second)) {
      it = handle.pending_project_state.erase(it);
    } else {
      ++it;
    }
  }
  refreshInstanceView(handle);
  if (flattened.schedule != nullptr) {
    handle.engine->publishSchedule(std::move(flattened.schedule));
  }

  // The transport must cover the complete arrangement, not just the current
  // piano-roll pattern. In particular, a long audio clip must not be cut back
  // to the default one-bar loop while the song is playing.
  double loop_end_beats = 4.0;
  const onebeat::model::Pattern* pattern = currentPattern(handle);
  if (pattern != nullptr) {
    loop_end_beats =
        std::max(loop_end_beats, static_cast<double>(pattern->length) /
                                     static_cast<double>(onebeat::model::TicksPerQuarter));
  }
  for (const auto& [clip_id, clip] : handle.project.clips()) {
    (void)clip_id;
    if (clip.audio() == nullptr) continue;
    const double clip_end = static_cast<double>(clip.start + clip.length) /
                            static_cast<double>(onebeat::model::TicksPerQuarter);
    loop_end_beats = std::max(loop_end_beats, clip_end);
  }
  if (flattened.length_frames > 0) {
    loop_end_beats = std::max(
        loop_end_beats,
        handle.engine->transportForTests().timeMap().framesToBeats(flattened.length_frames));
  }
  ob_command loop{};
  loop.type = OB_CMD_SET_LOOP;
  loop.f64_a = 0.0;
  loop.f64_b = loop_end_beats;
  loop.i64_a = 1;
  handle.engine->postCommand(loop);
}

ob_status executeModel(ob_engine& handle, onebeat::model::CommandPtr command, const char* failure) {
  if (command == nullptr || !handle.commands.execute(std::move(command))) {
    return fail(OB_ERR_INVALID_ARGUMENT, failure);
  }
  publishModel(handle);
  g_last_error.clear();
  return OB_OK;
}

bool initialiseRack(ob_engine& handle) {
  if (!handle.commands.execute(onebeat::model::addPattern(handle.project, "Pattern 1",
                                                          onebeat::model::TicksPerBarFourFour))) {
    return false;
  }
  handle.current_pattern = handle.project.patterns().begin()->first;
  if (!handle.commands.execute(onebeat::model::addLane(handle.project, "Patterns"))) return false;
  const onebeat::model::ArrangementLaneId lane = handle.project.lanes().begin()->first;
  if (!handle.commands.execute(onebeat::model::addClip(
          handle.project, lane, onebeat::model::PatternSource{*handle.current_pattern}, 0,
          onebeat::model::TicksPerBarFourFour))) {
    return false;
  }
  handle.commands.clear();
  publishModel(handle);
  return true;
}

onebeat::model::Ticks rackGrid(const ob_engine& handle, onebeat::model::InstrumentId id) {
  const auto found = handle.rack_grids.find(id);
  return found == handle.rack_grids.end() ? onebeat::model::TicksPerQuarter / 4 : found->second;
}

// --------------------------------------------------------------------------
// ABI 1.7 helpers: notes, patterns, lanes and clips
// --------------------------------------------------------------------------

std::optional<onebeat::model::PatternId> patternId(const char* text) {
  if (text == nullptr || text[0] == '\0') return std::nullopt;
  return onebeat::model::PatternId::parse(text);
}

std::optional<onebeat::model::ArrangementLaneId> laneId(const char* text) {
  if (text == nullptr || text[0] == '\0') return std::nullopt;
  return onebeat::model::ArrangementLaneId::parse(text);
}

std::optional<onebeat::model::ClipId> clipId(const char* text) {
  if (text == nullptr || text[0] == '\0') return std::nullopt;
  return onebeat::model::ClipId::parse(text);
}

const onebeat::model::NoteSequence* sequenceFor(const ob_engine& handle,
                                                onebeat::model::InstrumentId id) {
  const onebeat::model::Pattern* pattern = currentPattern(handle);
  if (pattern == nullptr) return nullptr;
  const auto found = pattern->sequences.find(id);
  return found == pattern->sequences.end() ? nullptr : &found->second;
}

// The boundary's ob_note is int32 where the model is int16/uint16, because a
// C ABI struct with narrow fields invites padding surprises. Narrowing here is
// safe: every value is validated against the model's own range first.
std::vector<onebeat::model::Note> toModelNotes(const ob_note* notes, int32_t count) {
  std::vector<onebeat::model::Note> result;
  if (notes == nullptr || count <= 0) return result;
  result.reserve(static_cast<size_t>(count));
  for (int32_t index = 0; index < count; ++index) {
    onebeat::model::Note note;
    note.start = notes[index].start;
    note.length = notes[index].length;
    note.key = static_cast<int16_t>(notes[index].key);
    note.velocity = static_cast<onebeat::model::Velocity>(notes[index].velocity);
    if (!onebeat::model::isValidNote(note)) return {};
    result.push_back(note);
  }
  return result;
}

// Resolves the (current pattern, instrument) pair every note edit is addressed
// by. Returns false and leaves the outputs untouched when either is missing.
bool resolveNoteTarget(ob_engine& handle, const char* utf8_instrument_id,
                       onebeat::model::PatternId& out_pattern,
                       onebeat::model::InstrumentId& out_instrument) {
  const auto id = instrumentId(utf8_instrument_id);
  const onebeat::model::Pattern* pattern = currentPattern(handle);
  if (!id || pattern == nullptr || handle.project.findInstrument(*id) == nullptr) return false;
  out_pattern = pattern->id;
  out_instrument = *id;
  return true;
}

std::optional<onebeat::model::NoteGrid> optionalGrid(int64_t snap_ticks) {
  if (snap_ticks <= 0) return std::nullopt;
  return onebeat::model::NoteGrid{snap_ticks, 0};
}

size_t patternNoteCount(const onebeat::model::Pattern& pattern) {
  size_t total = 0;
  for (const auto& [instrument, sequence] : pattern.sequences) {
    (void)instrument;
    total += sequence.size();
  }
  return total;
}

// Lanes are drawn in `order`, which is a field rather than the map's position
// (FR-PRJ-02), so every read path sorts by it before indexing.
std::vector<const onebeat::model::ArrangementLane*> orderedLanes(const ob_engine& handle) {
  std::vector<const onebeat::model::ArrangementLane*> lanes;
  lanes.reserve(handle.project.lanes().size());
  for (const auto& [id, lane] : handle.project.lanes()) {
    (void)id;
    lanes.push_back(&lane);
  }
  std::sort(lanes.begin(), lanes.end(),
            [](const onebeat::model::ArrangementLane* a, const onebeat::model::ArrangementLane* b) {
              if (a->order != b->order) return a->order < b->order;
              return a->id.raw() < b->id.raw();
            });
  return lanes;
}

// Clips in painting order: lane by lane, left to right. Stable, so a repaint
// cannot reshuffle overlapping clips under the cursor.
std::vector<const onebeat::model::Clip*> orderedClips(const ob_engine& handle) {
  std::map<onebeat::model::ArrangementLaneId, int32_t> lane_order;
  for (const auto& [id, lane] : handle.project.lanes()) lane_order[id] = lane.order;

  std::vector<const onebeat::model::Clip*> clips;
  clips.reserve(handle.project.clips().size());
  for (const auto& [id, clip] : handle.project.clips()) {
    (void)id;
    clips.push_back(&clip);
  }
  std::sort(clips.begin(), clips.end(),
            [&lane_order](const onebeat::model::Clip* a, const onebeat::model::Clip* b) {
              const int32_t lane_a = lane_order.count(a->lane) != 0 ? lane_order[a->lane] : 0;
              const int32_t lane_b = lane_order.count(b->lane) != 0 ? lane_order[b->lane] : 0;
              if (lane_a != lane_b) return lane_a < lane_b;
              if (a->start != b->start) return a->start < b->start;
              return a->id.raw() < b->id.raw();
            });
  return clips;
}

// "Verse Drums" -> "Verse Drums 2", then 3, and so on. The derived name is what
// makes a cloned pattern recognisable in the selector without the user having
// to rename it first (OB-3-11 §4).
std::string derivedPatternName(const ob_engine& handle, const std::string& base) {
  for (int suffix = 2; suffix < 1000; ++suffix) {
    const std::string candidate = base + " " + std::to_string(suffix);
    bool taken = false;
    for (const auto& [id, pattern] : handle.project.patterns()) {
      (void)id;
      if (pattern.name == candidate) {
        taken = true;
        break;
      }
    }
    if (!taken) return candidate;
  }
  return base + " copy";
}

// Executes a create command and reports the ID it minted, by diffing the map.
// The command layer mints IDs internally and does not surface them, and diffing
// is both cheap at this scale and immune to assumptions about map ordering.
template <typename Id, typename Map>
std::optional<Id> executeAndFindNew(ob_engine& handle, const Map& map,
                                    onebeat::model::CommandPtr command) {
  std::vector<Id> before;
  before.reserve(map.size());
  for (const auto& [id, entity] : map) {
    (void)entity;
    before.push_back(id);
  }
  if (command == nullptr || !handle.commands.execute(std::move(command))) return std::nullopt;
  for (const auto& [id, entity] : map) {
    (void)entity;
    if (std::find(before.begin(), before.end(), id) == before.end()) return id;
  }
  return std::nullopt;
}

// Copies a pattern's meta and every sequence into a fresh pattern. Used by both
// `Duplicate pattern` (which repoints nothing) and `Make unique` (which
// repoints the selected clips) — the difference between the two is entirely in
// what the caller does next, which is why the clone itself is shared code.
//
// Assumes an open transaction: the clone is several commands and must undo as
// one entry.
std::optional<onebeat::model::PatternId> clonePattern(ob_engine& handle,
                                                      const onebeat::model::Pattern& source,
                                                      const std::string& name) {
  const auto created = executeAndFindNew<onebeat::model::PatternId>(
      handle, handle.project.patterns(),
      onebeat::model::addPattern(handle.project, name, source.length));
  if (!created) return std::nullopt;

  const onebeat::model::ColorHex color = source.color;
  const double swing = source.swing;
  if (!handle.commands.execute(onebeat::model::editPatternMeta(
          handle.project, *created, onebeat::model::ChangeField::Color,
          [&color, swing](onebeat::model::PatternMeta& meta) {
            meta.color = color;
            meta.swing = swing;
          },
          "Copy pattern settings"))) {
    return std::nullopt;
  }

  for (const auto& [instrument, sequence] : source.sequences) {
    if (sequence.empty()) continue;
    if (!handle.commands.execute(
            onebeat::model::insertNotes(*created, instrument, sequence.notes()))) {
      return std::nullopt;
    }
  }
  return created;
}

}  // namespace

extern "C" {

uint32_t ob_abi_version(void) {
  return OB_ABI_VERSION_PACKED;
}

const char* ob_abi_version_string(void) {
  return "1.11.0";
}

const char* ob_last_error_message(void) {
  return g_last_error.empty() ? "" : g_last_error.c_str();
}

const char* ob_status_name(ob_status status) {
  switch (status) {
    case OB_OK:
      return "OB_OK";
    case OB_ERR_INVALID_ARGUMENT:
      return "OB_ERR_INVALID_ARGUMENT";
    case OB_ERR_OUT_OF_MEMORY:
      return "OB_ERR_OUT_OF_MEMORY";
    case OB_ERR_DEVICE_UNAVAILABLE:
      return "OB_ERR_DEVICE_UNAVAILABLE";
    case OB_ERR_DEVICE_FORMAT_UNSUPPORTED:
      return "OB_ERR_DEVICE_FORMAT_UNSUPPORTED";
    case OB_ERR_ALREADY_RUNNING:
      return "OB_ERR_ALREADY_RUNNING";
    case OB_ERR_NOT_RUNNING:
      return "OB_ERR_NOT_RUNNING";
    case OB_ERR_QUEUE_FULL:
      return "OB_ERR_QUEUE_FULL";
    case OB_ERR_FILE_NOT_FOUND:
      return "OB_ERR_FILE_NOT_FOUND";
    case OB_ERR_FILE_UNSUPPORTED:
      return "OB_ERR_FILE_UNSUPPORTED";
    case OB_ERR_INTERNAL:
      return "OB_ERR_INTERNAL";
  }
  return "OB_ERR_INTERNAL";
}

ob_status ob_engine_create(const ob_engine_config* config, ob_engine** out_engine) {
  if (out_engine == nullptr) {
    return fail(OB_ERR_INVALID_ARGUMENT, "out_engine must not be null.");
  }
  try {
    onebeat::core::EngineConfig engine_config;
    if (config != nullptr) {
      if (config->sample_rate > 0.0) {
        engine_config.sample_rate = config->sample_rate;
      }
      if (config->block_frames > 0) {
        engine_config.block_frames = config->block_frames;
      }
      engine_config.use_null_device = config->use_null_device != 0;
      if (config->log_directory != nullptr) {
        engine_config.log_directory = config->log_directory;
      }
    }

    auto handle = std::make_unique<ob_engine>();
    handle->engine = std::make_unique<onebeat::core::Engine>(std::move(engine_config));

    std::string error;
    if (!handle->engine->initialise(error)) {
      return fail(OB_ERR_DEVICE_UNAVAILABLE, error.c_str());
    }
    if (!initialiseRack(*handle)) {
      return fail(OB_ERR_INTERNAL, "The default pattern could not be created.");
    }
    // The empty project the app opens with is not a project with unsaved
    // changes: closing it must not ask to save a rack nobody touched.
    handle->saved_project_hash = projectHash(*handle);
    *out_engine = handle.release();
    g_last_error.clear();
    return OB_OK;
  } catch (const std::bad_alloc&) {
    return fail(OB_ERR_OUT_OF_MEMORY, "Out of memory while creating the engine.");
  } catch (const std::exception& exception) {
    return fail(OB_ERR_INTERNAL, exception.what());
  } catch (...) {
    return fail(OB_ERR_INTERNAL, "Unknown failure while creating the engine.");
  }
}

void ob_engine_destroy(ob_engine* engine) {
  if (engine == nullptr) {
    return;
  }
  try {
    delete engine;
  } catch (...) {
    // Destruction must not throw across the boundary, ever.
  }
}

ob_status ob_engine_start(ob_engine* engine) {
  if (engine == nullptr) {
    return fail(OB_ERR_INVALID_ARGUMENT, "engine must not be null.");
  }
  try {
    std::string error;
    if (!engine->engine->start(error)) {
      return fail(OB_ERR_DEVICE_UNAVAILABLE, error.c_str());
    }
    return OB_OK;
  } catch (const std::exception& exception) {
    return fail(OB_ERR_INTERNAL, exception.what());
  }
}

ob_status ob_engine_stop(ob_engine* engine) {
  if (engine == nullptr) {
    return fail(OB_ERR_INVALID_ARGUMENT, "engine must not be null.");
  }
  try {
    engine->engine->stop();
    return OB_OK;
  } catch (const std::exception& exception) {
    return fail(OB_ERR_INTERNAL, exception.what());
  }
}

ob_status ob_engine_post_command(ob_engine* engine, const ob_command* command) {
  if (engine == nullptr || command == nullptr) {
    return fail(OB_ERR_INVALID_ARGUMENT, "engine and command must not be null.");
  }
  if (command->type == OB_CMD_SET_TEMPO && command->f64_a >= 20.0 && command->f64_a <= 999.0) {
    onebeat::model::TransportState transport = engine->project.transport();
    if (std::abs(transport.tempo - command->f64_a) > 0.0001) {
      transport.tempo = command->f64_a;
      (void)engine->commands.execute(onebeat::model::setTransport(engine->project, transport));
      publishModel(*engine);
    }
  }
  // Allocation-free, lock-free: this is on the UI frame path.
  if (!engine->engine->postCommand(*command)) {
    return OB_ERR_QUEUE_FULL;
  }
  return OB_OK;
}

ob_status ob_engine_read_snapshot(ob_engine* engine, ob_snapshot* out_snapshot) {
  if (engine == nullptr || out_snapshot == nullptr) {
    return fail(OB_ERR_INVALID_ARGUMENT, "engine and out_snapshot must not be null.");
  }
  engine->engine->readSnapshot(*out_snapshot);
  return OB_OK;
}

int32_t ob_engine_poll_event(ob_engine* engine, ob_event* out_event) {
  if (engine == nullptr || out_event == nullptr) {
    return 0;
  }
  return engine->engine->pollEvent(*out_event) ? 1 : 0;
}

ob_status ob_engine_load_sample(ob_engine* engine, const char* utf8_path) {
  if (engine == nullptr) {
    return fail(OB_ERR_INVALID_ARGUMENT, "engine must not be null.");
  }
  try {
    engine->engine->requestSampleLoad(utf8_path != nullptr ? std::string(utf8_path)
                                                           : std::string());
    return OB_OK;
  } catch (const std::exception& exception) {
    return fail(OB_ERR_INTERNAL, exception.what());
  }
}

ob_status ob_engine_set_step_pattern(ob_engine* engine, const uint8_t* steps, int32_t step_count,
                                     int32_t midi_note, double step_beats) {
  if (engine == nullptr || steps == nullptr || step_count <= 0 || step_beats <= 0.0) {
    return fail(OB_ERR_INVALID_ARGUMENT,
                "A pattern needs at least one step and a positive length.");
  }
  try {
    onebeat::core::Engine& core = *engine->engine;
    const onebeat::core::TimeMap& time_map = core.transportForTests().timeMap();
    const auto step_frames = static_cast<int64_t>(time_map.beatsToFrames(step_beats));

    onebeat::core::ScheduleBuilder builder;
    for (int32_t index = 0; index < step_count; ++index) {
      if (steps[index] == 0) {
        continue;
      }
      const float velocity = static_cast<float>(steps[index]) / 127.0F;
      builder.addNote(onebeat::core::DefaultInstrument, static_cast<int16_t>(midi_note), velocity,
                      static_cast<int64_t>(index) * step_frames, step_frames);
    }
    builder.setLengthFrames(static_cast<int64_t>(step_count) * step_frames);
    core.publishSchedule(builder.build(core.config().sample_rate, core.scheduleGeneration() + 1));

    // The pattern defines the loop region, so play is immediately musical.
    ob_command loop{};
    loop.type = OB_CMD_SET_LOOP;
    loop.f64_a = 0.0;
    loop.f64_b = step_beats * static_cast<double>(step_count);
    loop.i64_a = 1;
    core.postCommand(loop);
    return OB_OK;
  } catch (const std::exception& exception) {
    return fail(OB_ERR_INTERNAL, exception.what());
  }
}

const char* ob_engine_output_device_name(ob_engine* engine) {
  if (engine == nullptr) {
    return "";
  }
  // Stable storage per engine handle: the caller may hold the pointer until the
  // next call (ADR-002 §7).
  static thread_local std::string name;  // NOLINT(*-avoid-non-const-global-variables)
  try {
    name = engine->engine->deviceName();
  } catch (...) {
    name = "";
  }
  return name.c_str();
}

/* --------------------------------------------------------------------------
 * Plugin library (OB-2-02)
 * ------------------------------------------------------------------------ */

ob_status ob_engine_plugin_cache_load(ob_engine* engine) {
  if (engine == nullptr) {
    return fail(OB_ERR_INVALID_ARGUMENT, "engine must not be null.");
  }
  try {
    onebeat::plugin::scan::PluginLibrary& library = pluginLibrary(*engine);
    library.loadCache();
    g_last_error.clear();
    return OB_OK;
  } catch (const std::bad_alloc&) {
    return fail(OB_ERR_OUT_OF_MEMORY, "Out of memory while loading the plugin cache.");
  } catch (const std::exception& exception) {
    return fail(OB_ERR_INTERNAL, exception.what());
  }
}

ob_status ob_engine_plugin_scan_start(ob_engine* engine, const char* utf8_directories) {
  if (engine == nullptr) {
    return fail(OB_ERR_INVALID_ARGUMENT, "engine must not be null.");
  }
  try {
    onebeat::plugin::scan::PluginLibrary& library = pluginLibrary(*engine);
    library.setSearchPaths(splitDirectories(utf8_directories));
    if (!library.startScan()) {
      return fail(OB_ERR_ALREADY_RUNNING, "A plugin scan is already running.");
    }
    g_last_error.clear();
    return OB_OK;
  } catch (const std::bad_alloc&) {
    return fail(OB_ERR_OUT_OF_MEMORY, "Out of memory while starting the plugin scan.");
  } catch (const std::exception& exception) {
    return fail(OB_ERR_INTERNAL, exception.what());
  }
}

ob_status ob_engine_plugin_scan_cancel(ob_engine* engine) {
  if (engine == nullptr) {
    return fail(OB_ERR_INVALID_ARGUMENT, "engine must not be null.");
  }
  try {
    pluginLibrary(*engine).cancelScan();
    g_last_error.clear();
    return OB_OK;
  } catch (const std::exception& exception) {
    return fail(OB_ERR_INTERNAL, exception.what());
  }
}

ob_status ob_engine_plugin_retry(ob_engine* engine, const char* utf8_path) {
  if (engine == nullptr || utf8_path == nullptr || utf8_path[0] == '\0') {
    return fail(OB_ERR_INVALID_ARGUMENT, "engine and plugin path must not be null or empty.");
  }
  try {
    if (!pluginLibrary(*engine).retryPlugin(utf8_path)) {
      return fail(OB_ERR_ALREADY_RUNNING, "A plugin scan is already running.");
    }
    g_last_error.clear();
    return OB_OK;
  } catch (const std::bad_alloc&) {
    return fail(OB_ERR_OUT_OF_MEMORY, "Out of memory while retrying the plugin scan.");
  } catch (const std::exception& exception) {
    return fail(OB_ERR_INTERNAL, exception.what());
  }
}

ob_status ob_engine_plugin_scan_status(ob_engine* engine, ob_plugin_scan_status* out_status) {
  if (engine == nullptr || out_status == nullptr) {
    return fail(OB_ERR_INVALID_ARGUMENT, "engine and out_status must not be null.");
  }
  try {
    onebeat::plugin::scan::PluginLibrary& library = pluginLibrary(*engine);
    // Folding streamed results into the list happens here rather than in a
    // timer, so the list only ever changes on a call the UI made.
    library.pump();

    const onebeat::plugin::scan::ScanProgress progress = library.progress();
    std::memset(out_status, 0, sizeof(*out_status));
    out_status->struct_size = static_cast<uint32_t>(sizeof(*out_status));
    out_status->state = static_cast<uint32_t>(progress.state);
    out_status->bundles_discovered = progress.bundles_discovered;
    out_status->bundles_reused = progress.bundles_reused;
    out_status->bundles_probed = progress.bundles_probed;
    out_status->plugins_found = progress.plugins_found;
    out_status->plugin_count = static_cast<uint32_t>(library.plugins().size());
    out_status->list_generation = static_cast<uint32_t>(library.generation());
    copyText(out_status->current, sizeof(out_status->current), progress.current.text());
    g_last_error.clear();
    return OB_OK;
  } catch (const std::exception& exception) {
    return fail(OB_ERR_INTERNAL, exception.what());
  }
}

ob_status ob_engine_plugin_at(ob_engine* engine, int32_t index, ob_plugin_info* out_info) {
  if (engine == nullptr || out_info == nullptr) {
    return fail(OB_ERR_INVALID_ARGUMENT, "engine and out_info must not be null.");
  }
  try {
    const auto& plugins = pluginLibrary(*engine).plugins();
    if (index < 0 || static_cast<size_t>(index) >= plugins.size()) {
      return fail(OB_ERR_INVALID_ARGUMENT, "Plugin index is out of range.");
    }
    const onebeat::plugin::scan::PluginDescriptor& descriptor = plugins[static_cast<size_t>(index)];

    std::memset(out_info, 0, sizeof(*out_info));
    out_info->struct_size = static_cast<uint32_t>(sizeof(*out_info));
    out_info->format = static_cast<uint32_t>(descriptor.format);
    out_info->outcome = static_cast<uint32_t>(descriptor.outcome);
    out_info->flags = descriptor.flags;
    out_info->features = descriptor.features;
    out_info->param_count = descriptor.param_count;
    out_info->index_in_bundle = descriptor.index_in_bundle;
    out_info->audio_input_count = descriptor.audio_input_count;
    out_info->audio_output_count = descriptor.audio_output_count;
    out_info->note_input_count = descriptor.note_input_count;
    out_info->note_output_count = descriptor.note_output_count;
    out_info->scanned_at_nanos = descriptor.scanned_at_nanos;
    copyText(out_info->id, sizeof(out_info->id), descriptor.id.text());
    copyText(out_info->name, sizeof(out_info->name), descriptor.name.text());
    copyText(out_info->vendor, sizeof(out_info->vendor), descriptor.vendor.text());
    copyText(out_info->version, sizeof(out_info->version), descriptor.version.text());
    copyText(out_info->path, sizeof(out_info->path), descriptor.path.text());
    out_info->failure_phase = static_cast<uint32_t>(descriptor.failure_phase);
    out_info->failure_signal = descriptor.failure_signal;
    out_info->retry_count = descriptor.retry_count;
    g_last_error.clear();
    return OB_OK;
  } catch (const std::exception& exception) {
    return fail(OB_ERR_INTERNAL, exception.what());
  }
}

ob_status ob_engine_instance_add(ob_engine* engine, const char* utf8_bundle_path,
                                 const char* utf8_plugin_id) {
  if (engine == nullptr || utf8_bundle_path == nullptr || utf8_bundle_path[0] == '\0' ||
      utf8_plugin_id == nullptr || utf8_plugin_id[0] == '\0') {
    return fail(OB_ERR_INVALID_ARGUMENT, "A plug-in bundle path and ID are required.");
  }
  try {
    /* The instrument comes first and hosting follows it. The plug-in then lands
     * on the lane it owns instead of on whichever lane was selected — a rack of
     * samples keeps every one of its voices when an instrument is added. */
    onebeat::model::PluginRef plugin;
    plugin.format = onebeat::model::PluginFormat::Clap;
    plugin.id = utf8_plugin_id;
    plugin.name = utf8_plugin_id;
    plugin.path_hint = utf8_bundle_path;
    for (const auto& row : pluginLibrary(*engine).plugins()) {
      if (row.path.text() == plugin.path_hint && row.id.text() == plugin.id) {
        plugin.format = row.format;
        plugin.name = row.name.text();
        plugin.vendor = row.vendor.text();
        break;
      }
    }
    engine->instance_state.clear();
    if (executeModel(*engine, onebeat::model::addInstrument(engine->project, plugin),
                     "Could not add the instrument to the project.") != OB_OK) {
      return fail(OB_ERR_INTERNAL, "Could not add the instrument to the project.");
    }
    /* executeModel published the model, and publishing is what hosts the
     * plug-in (syncHostedInstruments). */
    std::optional<onebeat::model::InstrumentId> added;
    for (const auto& [id, instrument] : engine->project.instruments()) {
      if (instrument.order == static_cast<int32_t>(engine->project.instruments().size() - 1)) {
        added = id;
        break;
      }
    }
    if (!added.has_value()) {
      return fail(OB_ERR_INTERNAL, "Could not add the instrument to the project.");
    }
    const auto hosted = engine->hosted.find(*added);
    if (hosted == engine->hosted.end() || hosted->second.failed) {
      /* Nothing was added as far as the user is concerned, so the failed lane
       * goes back out rather than sitting silent in the rack. */
      (void)engine->commands.undo();
      publishModel(*engine);
      return fail(OB_ERR_FILE_UNSUPPORTED, "The plug-in could not be hosted.");
    }
    engine->selected_instrument = added;
    refreshInstanceView(*engine);
    syncChannels(*engine);
    g_last_error.clear();
    return OB_OK;
  } catch (const std::bad_alloc&) {
    return fail(OB_ERR_OUT_OF_MEMORY, "Out of memory while adding the plug-in.");
  } catch (const std::exception& exception) {
    return fail(OB_ERR_INTERNAL, exception.what());
  }
}

ob_status ob_engine_instance_remove(ob_engine* engine, uint32_t instance_id) {
  if (engine == nullptr || !engine->has_instance || instance_id != engine->instance_id) {
    return fail(OB_ERR_INVALID_ARGUMENT, "The plug-in instance does not exist.");
  }
  try {
    engine->instance_state.clear();
    if (engine->selected_instrument.has_value()) {
      /* Removing the instrument is what un-hosts the plug-in: publishing the
       * model reconciles hosting, here as everywhere else. */
      if (executeModel(*engine, onebeat::model::removeInstrument(*engine->selected_instrument),
                       "Could not remove the instrument from the project.") != OB_OK) {
        return fail(OB_ERR_INTERNAL, "Could not remove the instrument from the project.");
      }
      engine->selected_instrument = std::nullopt;
      refreshInstanceView(*engine);
    } else {
      /* A scratch instance with no instrument behind it (session load). */
      std::string error;
      if (!engine->engine->restoreBuiltinInstrument(instanceChannel(*engine), error))
        return fail(OB_ERR_INTERNAL, error.c_str());
      engine->has_instance = false;
      engine->instance_missing = false;
    }
    return OB_OK;
  } catch (const std::exception& exception) {
    return fail(OB_ERR_INTERNAL, exception.what());
  }
}

int32_t ob_engine_instance_count(ob_engine* engine) {
  return engine != nullptr && engine->has_instance ? 1 : 0;
}

ob_status ob_engine_instance_at(ob_engine* engine, int32_t index, ob_instance_info* out_info) {
  if (engine == nullptr || out_info == nullptr || index != 0 || !engine->has_instance) {
    return fail(OB_ERR_INVALID_ARGUMENT, "Plug-in instance index is out of range.");
  }
  std::memset(out_info, 0, sizeof(*out_info));
  out_info->struct_size = sizeof(*out_info);
  out_info->instance_id = engine->instance_id;
  out_info->format = engine->instance_format;
  const int channel = instanceChannel(*engine);
  out_info->flags = engine->instance_missing ? OB_INSTANCE_FLAG_MISSING : 0U;
  if (engine->engine->hostedHasEditor(channel)) out_info->flags |= OB_INSTANCE_FLAG_HAS_EDITOR;
  if (!engine->instance_missing && !engine->engine->hostedHealthy(channel))
    out_info->flags |= OB_INSTANCE_FLAG_NEEDS_RESTART;
  out_info->param_count = engine->engine->hostedParamCount(channel);
  copyText(out_info->plugin_id, sizeof(out_info->plugin_id), engine->instance_plugin_id.c_str());
  copyText(out_info->name, sizeof(out_info->name), engine->instance_name.c_str());
  copyText(out_info->vendor, sizeof(out_info->vendor), engine->instance_vendor.c_str());
  copyText(out_info->path, sizeof(out_info->path), engine->instance_path.c_str());
  return OB_OK;
}

ob_status ob_engine_param_at(ob_engine* engine, uint32_t instance_id, int32_t index,
                             ob_param_info* out_info) {
  if (engine == nullptr || out_info == nullptr || !engine->has_instance ||
      instance_id != engine->instance_id || index < 0) {
    return fail(OB_ERR_INVALID_ARGUMENT, "Plug-in parameter index is out of range.");
  }
  const int channel = instanceChannel(*engine);
  onebeat::plugin::ParamInfo info;
  if (!engine->engine->hostedParamInfo(channel, static_cast<uint32_t>(index), info)) {
    return fail(OB_ERR_INVALID_ARGUMENT, "Plug-in parameter index is out of range.");
  }
  std::memset(out_info, 0, sizeof(*out_info));
  out_info->struct_size = sizeof(*out_info);
  out_info->instance_id = instance_id;
  out_info->param_id = info.id;
  out_info->flags = info.flags;
  out_info->min_value = info.min_value;
  out_info->max_value = info.max_value;
  out_info->default_value = info.default_value;
  engine->engine->hostedParamValue(channel, info.id, out_info->value);
  copyText(out_info->name, sizeof(out_info->name), info.name.text());
  copyText(out_info->module, sizeof(out_info->module), info.module.text());
  if (!engine->engine->channelInstrument(channel).paramValueToText(
          info.id, out_info->value, out_info->display, sizeof(out_info->display))) {
    std::snprintf(out_info->display, sizeof(out_info->display), "%.3f", out_info->value);
  }
  return OB_OK;
}

ob_status ob_engine_instance_editor_open(ob_engine* engine, uint32_t instance_id) {
  if (engine == nullptr || !engine->has_instance || instance_id != engine->instance_id)
    return fail(OB_ERR_INVALID_ARGUMENT, "The plug-in instance does not exist.");
  return engine->engine->openHostedEditor(instanceChannel(*engine))
             ? OB_OK
             : fail(OB_ERR_FILE_UNSUPPORTED, "This plug-in has no native editor.");
}

ob_status ob_engine_instance_editor_close(ob_engine* engine, uint32_t instance_id) {
  if (engine == nullptr || !engine->has_instance || instance_id != engine->instance_id)
    return fail(OB_ERR_INVALID_ARGUMENT, "The plug-in instance does not exist.");
  engine->engine->closeHostedEditor(instanceChannel(*engine));
  return OB_OK;
}

ob_status ob_engine_instance_restart(ob_engine* engine, uint32_t instance_id) {
  if (engine == nullptr || !engine->has_instance || engine->instance_missing ||
      instance_id != engine->instance_id)
    return fail(OB_ERR_INVALID_ARGUMENT, "The plug-in instance cannot be restarted.");
  const int channel = instanceChannel(*engine);
  if (engine->engine->restartHostedInstrument(channel)) return OB_OK;
  const std::string detail = engine->engine->hostedError(channel);
  return fail(OB_ERR_INTERNAL,
              detail.empty() ? "The plug-in helper could not be restarted." : detail.c_str());
}

ob_status ob_engine_session_save(ob_engine* engine, const char* utf8_path) {
  if (engine == nullptr || utf8_path == nullptr || utf8_path[0] == '\0') {
    return fail(OB_ERR_INVALID_ARGUMENT, "A scratch session path is required.");
  }
  try {
    const int channel = instanceChannel(*engine);
    std::vector<uint8_t> state = engine->instance_state;
    if (engine->has_instance && !engine->instance_missing &&
        !engine->engine->saveHostedState(channel, state)) {
      const std::string detail = engine->engine->hostedError(channel);
      return fail(OB_ERR_INTERNAL,
                  detail.empty() ? "The plug-in state could not be saved." : detail.c_str());
    }
    std::ofstream file(utf8_path, std::ios::binary | std::ios::trunc);
    if (!file) return fail(OB_ERR_INTERNAL, "The scratch session could not be created.");
    const uint32_t magic = 0x4F425332U;  // OBS2
    const uint32_t version = 1;
    const uint32_t present = engine->has_instance ? 1U : 0U;
    const uint32_t lengths[] = {static_cast<uint32_t>(engine->instance_plugin_id.size()),
                                static_cast<uint32_t>(engine->instance_name.size()),
                                static_cast<uint32_t>(engine->instance_vendor.size()),
                                static_cast<uint32_t>(engine->instance_path.size()),
                                static_cast<uint32_t>(state.size())};
    file.write(reinterpret_cast<const char*>(&magic), sizeof(magic));
    file.write(reinterpret_cast<const char*>(&version), sizeof(version));
    file.write(reinterpret_cast<const char*>(&present), sizeof(present));
    file.write(reinterpret_cast<const char*>(&engine->instance_format),
               sizeof(engine->instance_format));
    file.write(reinterpret_cast<const char*>(lengths), sizeof(lengths));
    file.write(engine->instance_plugin_id.data(), lengths[0]);
    file.write(engine->instance_name.data(), lengths[1]);
    file.write(engine->instance_vendor.data(), lengths[2]);
    file.write(engine->instance_path.data(), lengths[3]);
    if (!state.empty())
      file.write(reinterpret_cast<const char*>(state.data()),
                 static_cast<std::streamsize>(state.size()));
    if (!file) return fail(OB_ERR_INTERNAL, "The scratch session could not be written.");
    engine->instance_state = std::move(state);
    return OB_OK;
  } catch (const std::exception& exception) {
    return fail(OB_ERR_INTERNAL, exception.what());
  }
}

ob_status ob_engine_session_load(ob_engine* engine, const char* utf8_path) {
  if (engine == nullptr || utf8_path == nullptr || utf8_path[0] == '\0') {
    return fail(OB_ERR_INVALID_ARGUMENT, "A scratch session path is required.");
  }
  try {
    std::ifstream file(utf8_path, std::ios::binary);
    if (!file) return fail(OB_ERR_FILE_NOT_FOUND, "The scratch session was not found.");
    uint32_t magic = 0, version = 0, present = 0, format = 0, lengths[5]{};
    file.read(reinterpret_cast<char*>(&magic), sizeof(magic));
    file.read(reinterpret_cast<char*>(&version), sizeof(version));
    file.read(reinterpret_cast<char*>(&present), sizeof(present));
    file.read(reinterpret_cast<char*>(&format), sizeof(format));
    file.read(reinterpret_cast<char*>(lengths), sizeof(lengths));
    if (!file || magic != 0x4F425332U || version != 1 || lengths[0] > 4096 || lengths[1] > 4096 ||
        lengths[2] > 4096 || lengths[3] > 16384 || lengths[4] > 64U * 1024U * 1024U) {
      return fail(OB_ERR_FILE_UNSUPPORTED, "The scratch session is invalid.");
    }
    auto readString = [&file](uint32_t size) {
      std::string value(size, '\0');
      if (size) file.read(value.data(), size);
      return value;
    };
    const std::string plugin_id = readString(lengths[0]);
    const std::string name = readString(lengths[1]);
    const std::string vendor = readString(lengths[2]);
    const std::string path = readString(lengths[3]);
    std::vector<uint8_t> state(lengths[4]);
    if (!state.empty())
      file.read(reinterpret_cast<char*>(state.data()), static_cast<std::streamsize>(state.size()));
    if (!file) return fail(OB_ERR_FILE_UNSUPPORTED, "The scratch session is truncated.");
    std::string error;
    /* The scratch session restores one plug-in onto the selected instrument's
     * channel — it predates per-instrument hosting and stays a crash-recovery
     * path for the current selection rather than a second project format. */
    const int channel = instanceChannel(*engine);
    if (present == 0) {
      if (engine->has_instance && !engine->engine->restoreBuiltinInstrument(channel, error))
        return fail(OB_ERR_INTERNAL, error.c_str());
      engine->has_instance = false;
      return OB_OK;
    }
    const bool available = std::filesystem::exists(path);
    if (available) {
      if (!engine->engine->createSandboxedInstrument(
              path, plugin_id, onebeat::plugin::scan::SubprocessProbe::discoverHelperPath(),
              channel, error) ||
          !engine->engine->loadHostedState(channel, state))
        return fail(OB_ERR_FILE_UNSUPPORTED,
                    error.empty() ? "The saved plug-in could not be restored." : error.c_str());
    } else if (!engine->engine->installMissingInstrument(name, state, channel, error)) {
      return fail(OB_ERR_INTERNAL, error.c_str());
    }
    if (engine->selected_instrument.has_value()) {
      /* Keep the reconciler's view in step with what was just hosted, so the
       * next model publish does not tear the restored plug-in back out. */
      ob_engine::HostedSlot slot;
      slot.channel = channel;
      slot.path = path;
      slot.plugin_id = plugin_id;
      slot.name = name;
      slot.missing = !available;
      engine->hosted[*engine->selected_instrument] = std::move(slot);
    }
    engine->has_instance = true;
    engine->instance_missing = !available;
    engine->instance_format = format;
    engine->instance_plugin_id = plugin_id;
    engine->instance_name = name;
    engine->instance_vendor = vendor;
    engine->instance_path = path;
    engine->instance_state = std::move(state);
    return OB_OK;
  } catch (const std::exception& exception) {
    return fail(OB_ERR_INTERNAL, exception.what());
  }
}

int32_t ob_engine_instrument_count(ob_engine* engine) {
  if (engine == nullptr) return 0;
  const size_t count = engine->project.instruments().size();
  return count > static_cast<size_t>(INT32_MAX) ? INT32_MAX : static_cast<int32_t>(count);
}

ob_status ob_engine_instrument_at(ob_engine* engine, int32_t index, ob_instrument_info* out_info) {
  if (engine == nullptr || out_info == nullptr) {
    return fail(OB_ERR_INVALID_ARGUMENT, "An engine and output row are required.");
  }
  const onebeat::model::Instrument* instrument = orderedInstrument(*engine, index);
  if (instrument == nullptr) {
    return fail(OB_ERR_INVALID_ARGUMENT, "Instrument index is out of range.");
  }
  std::memset(out_info, 0, sizeof(*out_info));
  out_info->struct_size = sizeof(*out_info);
  out_info->order = instrument->order;
  if (instrument->muted) out_info->flags |= 1U;
  if (engine->selected_instrument.has_value() && *engine->selected_instrument == instrument->id) {
    out_info->flags |= 2U;
  }
  const onebeat::model::InstrumentImpact impact = engine->project.instrumentImpact(instrument->id);
  out_info->affected_pattern_count = static_cast<uint32_t>(impact.patterns.size());
  out_info->affected_clip_count = static_cast<uint32_t>(impact.pattern_clips.size());
  out_info->affected_note_count = static_cast<uint32_t>(impact.note_count);
  copyText(out_info->id, sizeof(out_info->id), instrument->id.str().c_str());
  copyText(out_info->name, sizeof(out_info->name), instrument->name.c_str());
  copyText(out_info->color, sizeof(out_info->color), instrument->color.c_str());
  copyText(out_info->plugin_id, sizeof(out_info->plugin_id), instrument->plugin.id.c_str());
  copyText(out_info->plugin_name, sizeof(out_info->plugin_name), instrument->plugin.name.c_str());
  copyText(out_info->plugin_vendor, sizeof(out_info->plugin_vendor),
           instrument->plugin.vendor.c_str());
  copyText(out_info->plugin_path, sizeof(out_info->plugin_path),
           instrument->plugin.path_hint.c_str());
  out_info->gain = instrument->gain;
  out_info->pan = instrument->pan;
  g_last_error.clear();
  return OB_OK;
}

ob_status ob_engine_instrument_select(ob_engine* engine, const char* utf8_instrument_id) {
  if (engine == nullptr) return fail(OB_ERR_INVALID_ARGUMENT, "engine must not be null.");
  const auto id = instrumentId(utf8_instrument_id);
  const onebeat::model::Instrument* instrument = id ? engine->project.findInstrument(*id) : nullptr;
  if (instrument == nullptr) return fail(OB_ERR_INVALID_ARGUMENT, "The instrument does not exist.");
  if (engine->selected_instrument == id) return OB_OK;
  try {
    /* Selection no longer hosts or un-hosts anything. Every instrument already
     * holds its own voice — a sample on its channel's sampler, a plug-in on the
     * channel it was loaded onto — and tearing that down on selection is what
     * silenced the other lanes when a plug-in lane was picked.
     *
     * No sample load here either, for the same reason: reloading on selection is
     * exactly the bug that made every lane play whichever sample was touched
     * last. */
    engine->selected_instrument = *id;
    refreshInstanceView(*engine);
    /* Moves the audition voice onto the newly selected channel and republishes
     * every channel's gain, pan and mute from the model — which is where the
     * per-channel mix now lives, so switching channels cannot carry the
     * previous channel's levels over to the next one. */
    syncChannels(*engine);
    g_last_error.clear();
    return OB_OK;
  } catch (const std::exception& exception) {
    return fail(OB_ERR_INTERNAL, exception.what());
  }
}

ob_status ob_engine_instrument_rename(ob_engine* engine, const char* utf8_instrument_id,
                                      const char* utf8_name) {
  if (engine == nullptr || utf8_name == nullptr || utf8_name[0] == '\0') {
    return fail(OB_ERR_INVALID_ARGUMENT, "An instrument and non-empty name are required.");
  }
  const auto id = instrumentId(utf8_instrument_id);
  if (!id) return fail(OB_ERR_INVALID_ARGUMENT, "The instrument ID is invalid.");
  const std::string name = utf8_name;
  return executeModel(
      *engine,
      onebeat::model::editInstrument(
          engine->project, *id, onebeat::model::ChangeField::Name,
          [&name](onebeat::model::Instrument& value) { value.name = name; }, "Rename instrument"),
      "The instrument does not exist.");
}

ob_status ob_engine_instrument_recolor(ob_engine* engine, const char* utf8_instrument_id,
                                       const char* utf8_color) {
  if (engine == nullptr || utf8_color == nullptr || std::strlen(utf8_color) != 7 ||
      utf8_color[0] != '#') {
    return fail(OB_ERR_INVALID_ARGUMENT, "Colour must be #RRGGBB.");
  }
  const auto id = instrumentId(utf8_instrument_id);
  if (!id) return fail(OB_ERR_INVALID_ARGUMENT, "The instrument ID is invalid.");
  const std::string color = utf8_color;
  return executeModel(*engine,
                      onebeat::model::editInstrument(
                          engine->project, *id, onebeat::model::ChangeField::Color,
                          [&color](onebeat::model::Instrument& value) { value.color = color; },
                          "Recolour instrument"),
                      "The instrument does not exist.");
}

ob_status ob_engine_instrument_reorder(ob_engine* engine, const char* utf8_instrument_id,
                                       int32_t order) {
  if (engine == nullptr) return fail(OB_ERR_INVALID_ARGUMENT, "engine must not be null.");
  const auto id = instrumentId(utf8_instrument_id);
  if (!id) return fail(OB_ERR_INVALID_ARGUMENT, "The instrument ID is invalid.");
  const onebeat::model::Instrument* instrument = engine->project.findInstrument(*id);
  if (instrument == nullptr) return fail(OB_ERR_INVALID_ARGUMENT, "The instrument does not exist.");
  if (instrument->order == order) return OB_OK;
  return executeModel(*engine, onebeat::model::reorderInstrument(engine->project, *id, order),
                      "Could not reorder the instrument.");
}

ob_status ob_engine_instrument_set_muted(ob_engine* engine, const char* utf8_instrument_id,
                                         int32_t muted) {
  if (engine == nullptr) return fail(OB_ERR_INVALID_ARGUMENT, "engine must not be null.");
  const auto id = instrumentId(utf8_instrument_id);
  if (!id) return fail(OB_ERR_INVALID_ARGUMENT, "The instrument ID is invalid.");
  return executeModel(*engine,
                      onebeat::model::editInstrument(
                          engine->project, *id, onebeat::model::ChangeField::Muted,
                          [muted](onebeat::model::Instrument& value) { value.muted = muted != 0; },
                          muted != 0 ? "Mute instrument" : "Unmute instrument"),
                      "The instrument does not exist.");
}

ob_status ob_engine_instrument_replace(ob_engine* engine, const char* utf8_instrument_id,
                                       const char* utf8_bundle_path, const char* utf8_plugin_id) {
  if (engine == nullptr || utf8_bundle_path == nullptr || utf8_bundle_path[0] == '\0' ||
      utf8_plugin_id == nullptr || utf8_plugin_id[0] == '\0') {
    return fail(OB_ERR_INVALID_ARGUMENT, "An instrument, plug-in path and ID are required.");
  }
  const auto id = instrumentId(utf8_instrument_id);
  if (!id || engine->project.findInstrument(*id) == nullptr) {
    return fail(OB_ERR_INVALID_ARGUMENT, "The instrument does not exist.");
  }
  try {
    onebeat::model::PluginRef plugin;
    plugin.format = onebeat::model::PluginFormat::Clap;
    plugin.id = utf8_plugin_id;
    plugin.name = utf8_plugin_id;
    plugin.path_hint = utf8_bundle_path;
    for (const auto& row : pluginLibrary(*engine).plugins()) {
      if (row.path.text() == plugin.path_hint && row.id.text() == plugin.id) {
        plugin.format = row.format;
        plugin.name = row.name.text();
        plugin.vendor = row.vendor.text();
        break;
      }
    }
    /* Publishing the model is what swaps the voice on this lane's channel, and
     * only on this lane's channel — dropping a plug-in on one row leaves every
     * other row playing what it played before. */
    const ob_status status =
        executeModel(*engine, onebeat::model::replaceInstrument(engine->project, *id, plugin),
                     "The instrument could not be replaced.");
    if (status != OB_OK) return status;
    const auto hosted = engine->hosted.find(*id);
    if (hosted == engine->hosted.end() || hosted->second.failed) {
      (void)engine->commands.undo();
      publishModel(*engine);
      return fail(OB_ERR_FILE_UNSUPPORTED, "The plug-in could not be hosted.");
    }
    return OB_OK;
  } catch (const std::exception& exception) {
    return fail(OB_ERR_INTERNAL, exception.what());
  }
}

ob_status ob_engine_instrument_duplicate(ob_engine* engine, const char* utf8_instrument_id) {
  if (engine == nullptr) return fail(OB_ERR_INVALID_ARGUMENT, "engine must not be null.");
  const auto id = instrumentId(utf8_instrument_id);
  if (!id) return fail(OB_ERR_INVALID_ARGUMENT, "The instrument ID is invalid.");
  const ob_status status =
      executeModel(*engine, onebeat::model::duplicateInstrument(engine->project, *id),
                   "The instrument could not be duplicated.");
  if (status != OB_OK) return status;
  const onebeat::model::Instrument* duplicate =
      orderedInstrument(*engine, static_cast<int32_t>(engine->project.instruments().size() - 1));
  if (duplicate != nullptr) engine->selected_instrument = duplicate->id;
  return OB_OK;
}

ob_status ob_engine_instrument_remove(ob_engine* engine, const char* utf8_instrument_id) {
  if (engine == nullptr) return fail(OB_ERR_INVALID_ARGUMENT, "engine must not be null.");
  const auto id = instrumentId(utf8_instrument_id);
  if (!id || engine->project.findInstrument(*id) == nullptr) {
    return fail(OB_ERR_INVALID_ARGUMENT, "The instrument does not exist.");
  }
  if (engine->selected_instrument == id) {
    engine->has_instance = false;
    engine->selected_instrument = std::nullopt;
  }
  const ob_status status = executeModel(*engine, onebeat::model::removeInstrument(*id),
                                        "The instrument could not be removed.");
  if (status != OB_OK) return status;
  if (!engine->selected_instrument.has_value() && !engine->project.instruments().empty()) {
    const onebeat::model::Instrument* first = orderedInstrument(*engine, 0);
    if (first != nullptr) {
      const std::string next = first->id.str();
      (void)ob_engine_instrument_select(engine, next.c_str());
    }
  }
  return OB_OK;
}

ob_status ob_engine_instrument_add_empty(ob_engine* engine, const char* utf8_name) {
  if (engine == nullptr) return fail(OB_ERR_INVALID_ARGUMENT, "engine must not be null.");
  try {
    std::string name = (utf8_name != nullptr && utf8_name[0] != '\0') ? utf8_name : "Channel";
    onebeat::model::PluginRef plugin;  // no plug-in: an empty lane
    if (executeModel(*engine, onebeat::model::addInstrument(engine->project, name, plugin),
                     "Could not add the channel.") != OB_OK) {
      return fail(OB_ERR_INTERNAL, "Could not add the channel.");
    }
    // An empty lane is a blank work surface, not an implicit selection. Keep
    // the current inspector selection unchanged so adding a channel cannot
    // make an unrelated inspector appear or jump to the new row.
    return OB_OK;
  } catch (const std::exception& exception) {
    return fail(OB_ERR_INTERNAL, exception.what());
  }
}

ob_status ob_engine_instrument_add_sample(ob_engine* engine, const char* utf8_name,
                                          const char* utf8_sample_path) {
  if (engine == nullptr || utf8_name == nullptr || utf8_name[0] == '\0' ||
      utf8_sample_path == nullptr || utf8_sample_path[0] == '\0') {
    return fail(OB_ERR_INVALID_ARGUMENT, "A sample name and path are required.");
  }
  if (!std::filesystem::is_regular_file(utf8_sample_path)) {
    return fail(OB_ERR_FILE_NOT_FOUND, "The sample file does not exist.");
  }
  try {
    /* No global un-hosting here: a sample lane plays its own channel's sampler,
     * and adding one must leave the plug-ins on the other lanes alone. */
    onebeat::model::PluginRef plugin;
    plugin.format = onebeat::model::PluginFormat::Builtin;
    plugin.id = kSamplePluginId;
    plugin.name = utf8_name;
    plugin.vendor = "OneBeat";
    plugin.path_hint = utf8_sample_path;
    if (executeModel(*engine, onebeat::model::addInstrument(engine->project, utf8_name, plugin),
                     "Could not add the sample instrument.") != OB_OK) {
      return fail(OB_ERR_INTERNAL, "Could not add the sample instrument.");
    }
    const int32_t count = static_cast<int32_t>(engine->project.instruments().size());
    for (const auto& [id, instrument] : engine->project.instruments()) {
      if (instrument.order == count - 1) {
        engine->selected_instrument = id;
        break;
      }
    }
    engine->has_instance = false;
    /* The sample reaches its own channel through syncChannels, which the
     * executeModel above already ran. Loading it here as well would put it on
     * whatever slot the global sampler happened to be. */
    syncChannels(*engine);
    return OB_OK;
  } catch (const std::exception& exception) {
    return fail(OB_ERR_INTERNAL, exception.what());
  }
}

ob_status ob_engine_instrument_replace_sample(ob_engine* engine, const char* utf8_instrument_id,
                                              const char* utf8_name, const char* utf8_sample_path) {
  if (engine == nullptr || utf8_name == nullptr || utf8_name[0] == '\0' ||
      utf8_sample_path == nullptr || utf8_sample_path[0] == '\0') {
    return fail(OB_ERR_INVALID_ARGUMENT, "A sample name and path are required.");
  }
  if (!std::filesystem::is_regular_file(utf8_sample_path)) {
    return fail(OB_ERR_FILE_NOT_FOUND, "The sample file does not exist.");
  }
  const auto id = instrumentId(utf8_instrument_id);
  if (!id || engine->project.findInstrument(*id) == nullptr) {
    return fail(OB_ERR_INVALID_ARGUMENT, "The instrument does not exist.");
  }
  try {
    /* Replacing this lane's voice is a per-channel change; publishing the model
     * drops whatever plug-in this lane held and leaves the others hosted. */
    onebeat::model::PluginRef plugin;
    plugin.format = onebeat::model::PluginFormat::Builtin;
    plugin.id = kSamplePluginId;
    plugin.name = utf8_name;
    plugin.vendor = "OneBeat";
    plugin.path_hint = utf8_sample_path;
    const ob_status status =
        executeModel(*engine, onebeat::model::replaceInstrument(engine->project, *id, plugin),
                     "The sample instrument could not be replaced.");
    if (status != OB_OK) return status;
    engine->selected_instrument = *id;
    engine->has_instance = false;
    /* Re-run now that the selection has moved, so the audition voice follows
     * the replaced channel. The sample itself came in with executeModel. */
    syncChannels(*engine);
    return OB_OK;
  } catch (const std::exception& exception) {
    return fail(OB_ERR_INTERNAL, exception.what());
  }
}

ob_status ob_engine_instrument_set_gain(ob_engine* engine, const char* utf8_instrument_id,
                                        float gain) {
  if (engine == nullptr) return fail(OB_ERR_INVALID_ARGUMENT, "engine must not be null.");
  const auto id = instrumentId(utf8_instrument_id);
  if (!id || engine->project.findInstrument(*id) == nullptr) {
    return fail(OB_ERR_INVALID_ARGUMENT, "The instrument does not exist.");
  }
  const float clamped = std::clamp(gain, 0.0F, 2.0F);
  const ob_status status =
      executeModel(*engine,
                   onebeat::model::editInstrument(
                       engine->project, *id, onebeat::model::ChangeField::Gain,
                       [clamped](onebeat::model::Instrument& value) { value.gain = clamped; },
                       "Set instrument gain"),
                   "The instrument does not exist.");
  if (status != OB_OK) return status;
  // Every channel carries its own gain now, and executeModel has already
  // published all of them — so there is no "apply it when selected" case left.
  return OB_OK;
}

ob_status ob_engine_instrument_set_pan(ob_engine* engine, const char* utf8_instrument_id,
                                       float pan) {
  if (engine == nullptr) return fail(OB_ERR_INVALID_ARGUMENT, "engine must not be null.");
  const auto id = instrumentId(utf8_instrument_id);
  if (!id || engine->project.findInstrument(*id) == nullptr) {
    return fail(OB_ERR_INVALID_ARGUMENT, "The instrument does not exist.");
  }
  const float clamped = std::clamp(pan, -1.0F, 1.0F);
  const ob_status status =
      executeModel(*engine,
                   onebeat::model::editInstrument(
                       engine->project, *id, onebeat::model::ChangeField::Pan,
                       [clamped](onebeat::model::Instrument& value) { value.pan = clamped; },
                       "Set instrument pan"),
                   "The instrument does not exist.");
  if (status != OB_OK) return status;
  // As for gain: per-channel pan is published by executeModel for every channel.
  return OB_OK;
}

int32_t ob_engine_project_can_undo(ob_engine* engine) {
  return engine != nullptr && engine->commands.canUndo() ? 1 : 0;
}

int32_t ob_engine_project_can_redo(ob_engine* engine) {
  return engine != nullptr && engine->commands.canRedo() ? 1 : 0;
}

const char* ob_engine_project_undo_name(ob_engine* engine) {
  if (engine == nullptr) return "";
  engine->undo_name_cache = engine->commands.undoName();
  return engine->undo_name_cache.c_str();
}

const char* ob_engine_project_redo_name(ob_engine* engine) {
  if (engine == nullptr) return "";
  engine->redo_name_cache = engine->commands.redoName();
  return engine->redo_name_cache.c_str();
}

ob_status ob_engine_project_undo(ob_engine* engine) {
  if (engine == nullptr || !engine->commands.undo()) {
    return fail(OB_ERR_INVALID_ARGUMENT, "There is no project edit to undo.");
  }
  if (engine->selected_instrument.has_value() &&
      engine->project.findInstrument(*engine->selected_instrument) == nullptr) {
    /* The selected lane was undone out of existence; publishModel below drops
     * whatever it had hosted. */
    engine->has_instance = false;
    engine->selected_instrument = std::nullopt;
  }
  publishModel(*engine);
  g_last_error.clear();
  return OB_OK;
}

ob_status ob_engine_project_redo(ob_engine* engine) {
  if (engine == nullptr || !engine->commands.redo()) {
    return fail(OB_ERR_INVALID_ARGUMENT, "There is no project edit to redo.");
  }
  if (engine->selected_instrument.has_value() &&
      engine->project.findInstrument(*engine->selected_instrument) == nullptr) {
    /* The selected lane was undone out of existence; publishModel below drops
     * whatever it had hosted. */
    engine->has_instance = false;
    engine->selected_instrument = std::nullopt;
  }
  publishModel(*engine);
  g_last_error.clear();
  return OB_OK;
}

ob_status ob_engine_rack_pattern(ob_engine* engine, ob_rack_pattern_info* out_info) {
  if (engine == nullptr || out_info == nullptr) {
    return fail(OB_ERR_INVALID_ARGUMENT, "An engine and output pattern are required.");
  }
  const onebeat::model::Pattern* pattern = currentPattern(*engine);
  if (pattern == nullptr) return fail(OB_ERR_INTERNAL, "The current pattern is unavailable.");
  std::memset(out_info, 0, sizeof(*out_info));
  out_info->struct_size = sizeof(*out_info);
  out_info->length_ticks = pattern->length;
  out_info->base_grid_ticks = onebeat::model::TicksPerQuarter / 4;
  out_info->swing = pattern->swing;
  copyText(out_info->id, sizeof(out_info->id), pattern->id.str().c_str());
  copyText(out_info->name, sizeof(out_info->name), pattern->name.c_str());
  g_last_error.clear();
  return OB_OK;
}

int32_t ob_engine_rack_row_count(ob_engine* engine) {
  return ob_engine_instrument_count(engine);
}

ob_status ob_engine_rack_row_at(ob_engine* engine, int32_t index, ob_rack_row_info* out_info) {
  if (engine == nullptr || out_info == nullptr) {
    return fail(OB_ERR_INVALID_ARGUMENT, "An engine and output rack row are required.");
  }
  const onebeat::model::Pattern* pattern = currentPattern(*engine);
  const onebeat::model::Instrument* instrument = orderedInstrument(*engine, index);
  if (pattern == nullptr || instrument == nullptr) {
    return fail(OB_ERR_INVALID_ARGUMENT, "Rack row index is out of range.");
  }

  std::memset(out_info, 0, sizeof(*out_info));
  out_info->struct_size = sizeof(*out_info);
  out_info->grid_ticks = rackGrid(*engine, instrument->id);
  out_info->step_count = static_cast<int32_t>(std::min<int64_t>(
      OB_RACK_MAX_STEPS, (pattern->length + out_info->grid_ticks - 1) / out_info->grid_ticks));
  copyText(out_info->instrument_id, sizeof(out_info->instrument_id), instrument->id.str().c_str());

  const auto sequence = pattern->sequences.find(instrument->id);
  if (sequence == pattern->sequences.end()) {
    g_last_error.clear();
    return OB_OK;
  }
  out_info->flags |= 1U;
  out_info->note_count = static_cast<uint32_t>(sequence->second.size());
  for (const onebeat::model::Note& note : sequence->second.notes()) {
    const bool on_grid = note.key == 60 && note.start % out_info->grid_ticks == 0;
    const int64_t step = on_grid ? note.start / out_info->grid_ticks : -1;
    if (step < 0 || step >= out_info->step_count) {
      ++out_info->off_grid_count;
      continue;
    }
    out_info->step_active[step] = 1;
    out_info->step_velocity[step] = std::max(out_info->step_velocity[step], note.velocity);
  }
  if (out_info->off_grid_count != 0) out_info->flags |= 2U;
  g_last_error.clear();
  return OB_OK;
}

ob_status ob_engine_rack_set_row_grid(ob_engine* engine, const char* utf8_instrument_id,
                                      int64_t grid_ticks) {
  if (engine == nullptr || (grid_ticks != 120 && grid_ticks != 240 && grid_ticks != 480)) {
    return fail(OB_ERR_INVALID_ARGUMENT, "Rack grid must be 1/8, 1/16, or 1/32.");
  }
  const auto id = instrumentId(utf8_instrument_id);
  if (!id || engine->project.findInstrument(*id) == nullptr) {
    return fail(OB_ERR_INVALID_ARGUMENT, "The instrument does not exist.");
  }
  engine->rack_grids[*id] = grid_ticks;
  g_last_error.clear();
  return OB_OK;
}

ob_status ob_engine_rack_set_length(ob_engine* engine, int32_t base_step_count) {
  if (engine == nullptr ||
      (base_step_count != 16 && base_step_count != 32 && base_step_count != 64)) {
    return fail(OB_ERR_INVALID_ARGUMENT, "Pattern length must be 16, 32, or 64 steps.");
  }
  const onebeat::model::Pattern* pattern = currentPattern(*engine);
  if (pattern == nullptr) return fail(OB_ERR_INTERNAL, "The current pattern is unavailable.");
  const onebeat::model::Ticks length =
      static_cast<onebeat::model::Ticks>(base_step_count) * onebeat::model::TicksPerQuarter / 4;
  const onebeat::model::Ticks old_length = pattern->length;
  for (const auto& [clip_id, clip] : engine->project.clips()) {
    if (const auto* src = clip.pattern()) {
      if (src->pattern == pattern->id && clip.length == old_length) {
        (void)engine->commands.execute(onebeat::model::editClip(
            engine->project, clip_id, onebeat::model::ChangeField::Length,
            [length](onebeat::model::Clip& c) { c.length = length; }, "Resize clip"));
      }
    }
  }
  return executeModel(*engine,
                      onebeat::model::editPatternMeta(
                          engine->project, pattern->id, onebeat::model::ChangeField::Length,
                          [length](onebeat::model::PatternMeta& value) { value.length = length; },
                          "Resize pattern"),
                      "The pattern could not be resized.");
}

ob_status ob_engine_rack_set_swing(ob_engine* engine, double swing) {
  if (engine == nullptr || swing < 0.0 || swing > 1.0) {
    return fail(OB_ERR_INVALID_ARGUMENT, "Swing must be between 0 and 1.");
  }
  const onebeat::model::Pattern* pattern = currentPattern(*engine);
  if (pattern == nullptr) return fail(OB_ERR_INTERNAL, "The current pattern is unavailable.");
  return executeModel(
      *engine,
      onebeat::model::editPatternMeta(
          engine->project, pattern->id, onebeat::model::ChangeField::Transforms,
          [swing](onebeat::model::PatternMeta& value) { value.swing = swing; }, "Set swing"),
      "Swing could not be changed.");
}

ob_status ob_engine_rack_toggle_step(ob_engine* engine, const char* utf8_instrument_id,
                                     int32_t step_index) {
  if (engine == nullptr || step_index < 0) {
    return fail(OB_ERR_INVALID_ARGUMENT, "A rack step is required.");
  }
  const auto id = instrumentId(utf8_instrument_id);
  const onebeat::model::Pattern* pattern = currentPattern(*engine);
  if (!id || pattern == nullptr || engine->project.findInstrument(*id) == nullptr) {
    return fail(OB_ERR_INVALID_ARGUMENT, "The rack row does not exist.");
  }
  const onebeat::model::Ticks grid = rackGrid(*engine, *id);
  if (static_cast<onebeat::model::Ticks>(step_index) * grid >= pattern->length) {
    return fail(OB_ERR_INVALID_ARGUMENT, "Rack step is outside the pattern.");
  }
  return executeModel(*engine,
                      onebeat::model::toggleStep(engine->project, pattern->id, *id, 60, step_index,
                                                 onebeat::model::NoteGrid{grid, 0}),
                      "The rack step could not be changed.");
}

ob_status ob_engine_rack_set_step_velocity(ob_engine* engine, const char* utf8_instrument_id,
                                           int32_t step_index, uint16_t velocity) {
  if (engine == nullptr || step_index < 0 || velocity > onebeat::model::MaxVelocity) {
    return fail(OB_ERR_INVALID_ARGUMENT, "A valid rack velocity is required.");
  }
  const auto id = instrumentId(utf8_instrument_id);
  const onebeat::model::Pattern* pattern = currentPattern(*engine);
  const onebeat::model::Instrument* instrument = id ? engine->project.findInstrument(*id) : nullptr;
  if (!id || pattern == nullptr || instrument == nullptr) {
    return fail(OB_ERR_INVALID_ARGUMENT, "The rack row does not exist.");
  }
  const onebeat::model::Ticks grid = rackGrid(*engine, *id);
  if (static_cast<onebeat::model::Ticks>(step_index) * grid >= pattern->length) {
    return fail(OB_ERR_INVALID_ARGUMENT, "Rack step is outside the pattern.");
  }
  const auto sequence = pattern->sequences.find(*id);
  onebeat::model::StepCell cell;
  if (sequence != pattern->sequences.end()) {
    cell = onebeat::model::inspectStep(sequence->second, 60, step_index,
                                       onebeat::model::NoteGrid{grid, 0});
  }
  if (cell.on_grid.empty()) {
    onebeat::model::Note note;
    note.start = static_cast<onebeat::model::Ticks>(step_index) * grid;
    note.length = grid;
    note.key = 60;
    note.velocity = velocity;
    return executeModel(*engine, onebeat::model::insertNotes(pattern->id, *id, {note}),
                        "The step velocity could not be changed.");
  }
  return executeModel(*engine,
                      onebeat::model::setNoteVelocity(pattern->id, *id, cell.on_grid, velocity),
                      "The step velocity could not be changed.");
}

ob_status ob_engine_rack_remove_sequence(ob_engine* engine, const char* utf8_instrument_id) {
  if (engine == nullptr) return fail(OB_ERR_INVALID_ARGUMENT, "engine must not be null.");
  const auto id = instrumentId(utf8_instrument_id);
  const onebeat::model::Pattern* pattern = currentPattern(*engine);
  if (!id || pattern == nullptr) return fail(OB_ERR_INVALID_ARGUMENT, "The rack row is invalid.");
  const auto sequence = pattern->sequences.find(*id);
  if (sequence == pattern->sequences.end()) return OB_OK;
  return executeModel(*engine,
                      onebeat::model::removeNotes(pattern->id, *id, sequence->second.notes()),
                      "The sequence could not be removed from the pattern.");
}

ob_status ob_engine_rack_gesture_begin(ob_engine* engine, const char* utf8_name) {
  if (engine == nullptr || engine->commands.inTransaction()) {
    return fail(OB_ERR_INVALID_ARGUMENT, "A rack gesture is already active.");
  }
  engine->commands.beginTransaction(utf8_name == nullptr || utf8_name[0] == '\0' ? "Paint steps"
                                                                                 : utf8_name);
  g_last_error.clear();
  return OB_OK;
}

ob_status ob_engine_rack_gesture_commit(ob_engine* engine) {
  if (engine == nullptr || !engine->commands.inTransaction()) {
    return fail(OB_ERR_INVALID_ARGUMENT, "There is no rack gesture to commit.");
  }
  engine->commands.commitTransaction();
  publishModel(*engine);
  g_last_error.clear();
  return OB_OK;
}

ob_status ob_engine_rack_gesture_abort(ob_engine* engine) {
  if (engine == nullptr || !engine->commands.inTransaction()) {
    return fail(OB_ERR_INVALID_ARGUMENT, "There is no rack gesture to cancel.");
  }
  engine->commands.abortTransaction();
  publishModel(*engine);
  g_last_error.clear();
  return OB_OK;
}

/* ------------------------------------------------------------------------- */
/* Notes: the piano roll (ABI 1.7, OB-3-10)                                   */
/* ------------------------------------------------------------------------- */

int32_t ob_engine_note_count(ob_engine* engine, const char* utf8_instrument_id) {
  if (engine == nullptr) return 0;
  const auto id = instrumentId(utf8_instrument_id);
  if (!id) return 0;
  const onebeat::model::NoteSequence* sequence = sequenceFor(*engine, *id);
  return sequence == nullptr ? 0 : static_cast<int32_t>(sequence->size());
}

ob_status ob_engine_notes_read(ob_engine* engine, const char* utf8_instrument_id,
                               ob_note* out_notes, int32_t capacity, int32_t* out_count) {
  if (engine == nullptr || out_count == nullptr || capacity < 0 ||
      (capacity > 0 && out_notes == nullptr)) {
    return fail(OB_ERR_INVALID_ARGUMENT, "An engine and note output buffer are required.");
  }
  *out_count = 0;
  const auto id = instrumentId(utf8_instrument_id);
  if (!id) return fail(OB_ERR_INVALID_ARGUMENT, "The instrument id is invalid.");

  const onebeat::model::NoteSequence* sequence = sequenceFor(*engine, *id);
  if (sequence == nullptr) {
    g_last_error.clear();
    return OB_OK;
  }
  int32_t written = 0;
  for (const onebeat::model::Note& note : sequence->notes()) {
    if (written >= capacity) break;
    out_notes[written].start = note.start;
    out_notes[written].length = note.length;
    out_notes[written].key = note.key;
    out_notes[written].velocity = note.velocity;
    ++written;
  }
  *out_count = written;
  g_last_error.clear();
  return OB_OK;
}

ob_status ob_engine_note_add(ob_engine* engine, const char* utf8_instrument_id, int64_t start,
                             int64_t length, int32_t key, int32_t velocity) {
  onebeat::model::PatternId pattern;
  onebeat::model::InstrumentId instrument;
  if (engine == nullptr || !resolveNoteTarget(*engine, utf8_instrument_id, pattern, instrument)) {
    return fail(OB_ERR_INVALID_ARGUMENT, "The instrument does not exist in this pattern.");
  }
  if (start < 0 || length <= 0 || key < 0 || key > 127 ||
      velocity > static_cast<int32_t>(onebeat::model::MaxVelocity)) {
    return fail(OB_ERR_INVALID_ARGUMENT, "The note is out of range.");
  }
  // A velocity of 0 means "use the instrument's default", which is what the
  // pencil tool wants; anything else is an explicit value from the UI.
  if (velocity <= 0) {
    return executeModel(*engine,
                        onebeat::model::addNote(engine->project, pattern, instrument, start, length,
                                                static_cast<int16_t>(key)),
                        "The note could not be added.");
  }
  onebeat::model::Note note;
  note.start = start;
  note.length = length;
  note.key = static_cast<int16_t>(key);
  note.velocity = static_cast<onebeat::model::Velocity>(velocity);
  return executeModel(*engine, onebeat::model::insertNotes(pattern, instrument, {note}),
                      "The note could not be added.");
}

ob_status ob_engine_notes_remove(ob_engine* engine, const char* utf8_instrument_id,
                                 const ob_note* notes, int32_t count) {
  onebeat::model::PatternId pattern;
  onebeat::model::InstrumentId instrument;
  if (engine == nullptr || !resolveNoteTarget(*engine, utf8_instrument_id, pattern, instrument)) {
    return fail(OB_ERR_INVALID_ARGUMENT, "The instrument does not exist in this pattern.");
  }
  std::vector<onebeat::model::Note> selection = toModelNotes(notes, count);
  if (selection.empty()) return fail(OB_ERR_INVALID_ARGUMENT, "No valid notes were given.");
  return executeModel(*engine,
                      onebeat::model::removeNotes(pattern, instrument, std::move(selection)),
                      "The notes could not be removed.");
}

ob_status ob_engine_notes_move(ob_engine* engine, const char* utf8_instrument_id,
                               const ob_note* notes, int32_t count, int64_t delta_ticks,
                               int32_t semitones, int64_t snap_ticks) {
  onebeat::model::PatternId pattern;
  onebeat::model::InstrumentId instrument;
  if (engine == nullptr || !resolveNoteTarget(*engine, utf8_instrument_id, pattern, instrument)) {
    return fail(OB_ERR_INVALID_ARGUMENT, "The instrument does not exist in this pattern.");
  }
  std::vector<onebeat::model::Note> selection = toModelNotes(notes, count);
  if (selection.empty()) return fail(OB_ERR_INVALID_ARGUMENT, "No valid notes were given.");
  return executeModel(
      *engine,
      onebeat::model::moveNotes(pattern, instrument, std::move(selection), delta_ticks,
                                static_cast<int16_t>(semitones), optionalGrid(snap_ticks)),
      "The notes could not be moved.");
}

ob_status ob_engine_notes_resize(ob_engine* engine, const char* utf8_instrument_id,
                                 const ob_note* notes, int32_t count, int64_t length_delta,
                                 int64_t snap_ticks) {
  onebeat::model::PatternId pattern;
  onebeat::model::InstrumentId instrument;
  if (engine == nullptr || !resolveNoteTarget(*engine, utf8_instrument_id, pattern, instrument)) {
    return fail(OB_ERR_INVALID_ARGUMENT, "The instrument does not exist in this pattern.");
  }
  std::vector<onebeat::model::Note> selection = toModelNotes(notes, count);
  if (selection.empty()) return fail(OB_ERR_INVALID_ARGUMENT, "No valid notes were given.");
  return executeModel(*engine,
                      onebeat::model::resizeNotes(pattern, instrument, std::move(selection),
                                                  length_delta, optionalGrid(snap_ticks)),
                      "The notes could not be resized.");
}

ob_status ob_engine_notes_set_velocity(ob_engine* engine, const char* utf8_instrument_id,
                                       const ob_note* notes, int32_t count, int32_t velocity) {
  onebeat::model::PatternId pattern;
  onebeat::model::InstrumentId instrument;
  if (engine == nullptr || !resolveNoteTarget(*engine, utf8_instrument_id, pattern, instrument)) {
    return fail(OB_ERR_INVALID_ARGUMENT, "The instrument does not exist in this pattern.");
  }
  if (velocity < 1 || velocity > static_cast<int32_t>(onebeat::model::MaxVelocity)) {
    return fail(OB_ERR_INVALID_ARGUMENT, "Velocity must be between 1 and 16383.");
  }
  std::vector<onebeat::model::Note> selection = toModelNotes(notes, count);
  if (selection.empty()) return fail(OB_ERR_INVALID_ARGUMENT, "No valid notes were given.");
  return executeModel(
      *engine,
      onebeat::model::setNoteVelocity(pattern, instrument, std::move(selection),
                                      static_cast<onebeat::model::Velocity>(velocity)),
      "The note velocity could not be changed.");
}

ob_status ob_engine_notes_quantise(ob_engine* engine, const char* utf8_instrument_id,
                                   const ob_note* notes, int32_t count, int64_t grid_ticks,
                                   double strength) {
  onebeat::model::PatternId pattern;
  onebeat::model::InstrumentId instrument;
  if (engine == nullptr || !resolveNoteTarget(*engine, utf8_instrument_id, pattern, instrument)) {
    return fail(OB_ERR_INVALID_ARGUMENT, "The instrument does not exist in this pattern.");
  }
  if (grid_ticks <= 0 || strength < 0.0 || strength > 1.0) {
    return fail(OB_ERR_INVALID_ARGUMENT, "Quantise needs a positive grid and 0..1 strength.");
  }
  std::vector<onebeat::model::Note> selection = toModelNotes(notes, count);
  if (selection.empty()) return fail(OB_ERR_INVALID_ARGUMENT, "No valid notes were given.");
  return executeModel(
      *engine,
      onebeat::model::quantiseNotes(pattern, instrument, std::move(selection),
                                    onebeat::model::NoteGrid{grid_ticks, 0}, strength),
      "The notes could not be quantised.");
}

ob_status ob_engine_notes_duplicate(ob_engine* engine, const char* utf8_instrument_id,
                                    const ob_note* notes, int32_t count, int64_t delta_ticks) {
  onebeat::model::PatternId pattern;
  onebeat::model::InstrumentId instrument;
  if (engine == nullptr || !resolveNoteTarget(*engine, utf8_instrument_id, pattern, instrument)) {
    return fail(OB_ERR_INVALID_ARGUMENT, "The instrument does not exist in this pattern.");
  }
  std::vector<onebeat::model::Note> selection = toModelNotes(notes, count);
  if (selection.empty()) return fail(OB_ERR_INVALID_ARGUMENT, "No valid notes were given.");
  return executeModel(*engine,
                      onebeat::model::duplicateNotes(pattern, instrument, std::move(selection),
                                                     delta_ticks, std::nullopt),
                      "The notes could not be duplicated.");
}

/* ------------------------------------------------------------------------- */
/* Patterns (ABI 1.7, OB-3-11)                                                */
/* ------------------------------------------------------------------------- */

int32_t ob_engine_pattern_count(ob_engine* engine) {
  return engine == nullptr ? 0 : static_cast<int32_t>(engine->project.patterns().size());
}

ob_status ob_engine_pattern_at(ob_engine* engine, int32_t index, ob_pattern_info* out_info) {
  if (engine == nullptr || out_info == nullptr || index < 0 ||
      static_cast<size_t>(index) >= engine->project.patterns().size()) {
    return fail(OB_ERR_INVALID_ARGUMENT, "Pattern index is out of range.");
  }
  auto entry = engine->project.patterns().begin();
  std::advance(entry, index);
  const onebeat::model::Pattern& pattern = entry->second;

  std::memset(out_info, 0, sizeof(*out_info));
  out_info->struct_size = sizeof(*out_info);
  out_info->flags = (engine->current_pattern.has_value() && *engine->current_pattern == pattern.id)
                        ? OB_PATTERN_FLAG_CURRENT
                        : 0U;
  out_info->length_ticks = pattern.length;
  out_info->swing = pattern.swing;
  out_info->usage_count = static_cast<uint32_t>(engine->project.patternUsageCount(pattern.id));
  out_info->note_count = static_cast<uint32_t>(patternNoteCount(pattern));
  copyText(out_info->id, sizeof(out_info->id), pattern.id.str().c_str());
  copyText(out_info->name, sizeof(out_info->name), pattern.name.c_str());
  copyText(out_info->color, sizeof(out_info->color), pattern.color.c_str());
  g_last_error.clear();
  return OB_OK;
}

ob_status ob_engine_pattern_select(ob_engine* engine, const char* utf8_pattern_id) {
  if (engine == nullptr) return fail(OB_ERR_INVALID_ARGUMENT, "engine must not be null.");
  const auto id = patternId(utf8_pattern_id);
  if (!id || engine->project.findPattern(*id) == nullptr) {
    return fail(OB_ERR_INVALID_ARGUMENT, "The pattern does not exist.");
  }
  engine->current_pattern = *id;
  // Selection is not an edit, so nothing is recorded — but the loop length the
  // transport uses follows the current pattern, so the schedule is republished.
  publishModel(*engine);
  g_last_error.clear();
  return OB_OK;
}

ob_status ob_engine_pattern_preview_start(ob_engine* engine, const char* utf8_pattern_id) {
  if (engine == nullptr) return fail(OB_ERR_INVALID_ARGUMENT, "engine must not be null.");
  const auto id = patternId(utf8_pattern_id);
  if (!id || engine->project.findPattern(*id) == nullptr) {
    return fail(OB_ERR_INVALID_ARGUMENT, "The pattern does not exist.");
  }
  engine->current_pattern = *id;
  engine->pattern_preview = true;
  engine->preview_instrument.reset();
  publishModel(*engine);
  ob_command seek{};
  seek.type = OB_CMD_TRANSPORT_SEEK_BEATS;
  seek.f64_a = 0.0;
  engine->engine->postCommand(seek);
  ob_command play{};
  play.type = OB_CMD_TRANSPORT_PLAY;
  engine->engine->postCommand(play);
  g_last_error.clear();
  return OB_OK;
}

ob_status ob_engine_pattern_preview_channel_start(ob_engine* engine,
                                                  const char* utf8_pattern_id,
                                                  const char* utf8_instrument_id) {
  if (engine == nullptr) return fail(OB_ERR_INVALID_ARGUMENT, "engine must not be null.");
  const auto pattern = patternId(utf8_pattern_id);
  const auto instrument = instrumentId(utf8_instrument_id);
  if (!pattern || engine->project.findPattern(*pattern) == nullptr ||
      !instrument || engine->project.findInstrument(*instrument) == nullptr) {
    return fail(OB_ERR_INVALID_ARGUMENT, "The pattern or instrument does not exist.");
  }
  engine->current_pattern = *pattern;
  engine->preview_instrument = *instrument;
  engine->pattern_preview = true;
  publishModel(*engine);
  ob_command seek{};
  seek.type = OB_CMD_TRANSPORT_SEEK_BEATS;
  seek.f64_a = 0.0;
  engine->engine->postCommand(seek);
  ob_command play{};
  play.type = OB_CMD_TRANSPORT_PLAY;
  engine->engine->postCommand(play);
  g_last_error.clear();
  return OB_OK;
}

ob_status ob_engine_pattern_preview_stop(ob_engine* engine) {
  if (engine == nullptr) return fail(OB_ERR_INVALID_ARGUMENT, "engine must not be null.");
  if (engine->pattern_preview) {
    engine->pattern_preview = false;
    engine->preview_instrument.reset();
    engine->flattener.markDirty();
    publishModel(*engine);
  }
  g_last_error.clear();
  return OB_OK;
}

ob_status ob_engine_pattern_create(ob_engine* engine, const char* utf8_name) {
  if (engine == nullptr) return fail(OB_ERR_INVALID_ARGUMENT, "engine must not be null.");
  const std::string name = (utf8_name == nullptr || utf8_name[0] == '\0')
                               ? derivedPatternName(*engine, "Pattern")
                               : std::string(utf8_name);
  const auto created = executeAndFindNew<onebeat::model::PatternId>(
      *engine, engine->project.patterns(),
      onebeat::model::addPattern(engine->project, name, onebeat::model::TicksPerBarFourFour));
  if (!created) return fail(OB_ERR_INTERNAL, "The pattern could not be created.");
  engine->current_pattern = *created;
  publishModel(*engine);
  g_last_error.clear();
  return OB_OK;
}

ob_status ob_engine_pattern_rename(ob_engine* engine, const char* utf8_pattern_id,
                                   const char* utf8_name) {
  if (engine == nullptr || utf8_name == nullptr || utf8_name[0] == '\0') {
    return fail(OB_ERR_INVALID_ARGUMENT, "A pattern name is required.");
  }
  const auto id = patternId(utf8_pattern_id);
  if (!id || engine->project.findPattern(*id) == nullptr) {
    return fail(OB_ERR_INVALID_ARGUMENT, "The pattern does not exist.");
  }
  const std::string name = utf8_name;
  return executeModel(
      *engine,
      onebeat::model::editPatternMeta(
          engine->project, *id, onebeat::model::ChangeField::Name,
          [&name](onebeat::model::PatternMeta& meta) { meta.name = name; }, "Rename pattern"),
      "The pattern could not be renamed.");
}

ob_status ob_engine_pattern_recolor(ob_engine* engine, const char* utf8_pattern_id,
                                    const char* utf8_color) {
  if (engine == nullptr || utf8_color == nullptr) {
    return fail(OB_ERR_INVALID_ARGUMENT, "A pattern colour is required.");
  }
  const auto id = patternId(utf8_pattern_id);
  if (!id || engine->project.findPattern(*id) == nullptr) {
    return fail(OB_ERR_INVALID_ARGUMENT, "The pattern does not exist.");
  }
  const std::string color = utf8_color;
  return executeModel(
      *engine,
      onebeat::model::editPatternMeta(
          engine->project, *id, onebeat::model::ChangeField::Color,
          [&color](onebeat::model::PatternMeta& meta) { meta.color = color; }, "Recolour pattern"),
      "The pattern could not be recoloured.");
}

ob_status ob_engine_pattern_duplicate(ob_engine* engine, const char* utf8_pattern_id) {
  if (engine == nullptr) return fail(OB_ERR_INVALID_ARGUMENT, "engine must not be null.");
  const auto id = patternId(utf8_pattern_id);
  const onebeat::model::Pattern* source = id ? engine->project.findPattern(*id) : nullptr;
  if (source == nullptr) return fail(OB_ERR_INVALID_ARGUMENT, "The pattern does not exist.");

  engine->commands.beginTransaction("Duplicate pattern");
  const auto clone = clonePattern(*engine, *source, derivedPatternName(*engine, source->name));
  if (!clone) {
    engine->commands.abortTransaction();
    return fail(OB_ERR_INTERNAL, "The pattern could not be duplicated.");
  }
  engine->commands.commitTransaction();
  engine->current_pattern = *clone;
  publishModel(*engine);
  g_last_error.clear();
  return OB_OK;
}

ob_status ob_engine_pattern_remove(ob_engine* engine, const char* utf8_pattern_id) {
  if (engine == nullptr) return fail(OB_ERR_INVALID_ARGUMENT, "engine must not be null.");
  const auto id = patternId(utf8_pattern_id);
  if (!id || engine->project.findPattern(*id) == nullptr) {
    return fail(OB_ERR_INVALID_ARGUMENT, "The pattern does not exist.");
  }
  if (engine->project.patterns().size() <= 1) {
    return fail(OB_ERR_INVALID_ARGUMENT, "The last pattern cannot be deleted.");
  }
  const ob_status status = executeModel(*engine, onebeat::model::removePattern(*id),
                                        "The pattern could not be deleted.");
  if (status != OB_OK) return status;
  // The selection has to land somewhere real, or every subsequent read fails.
  if (engine->current_pattern.has_value() && *engine->current_pattern == *id) {
    engine->current_pattern = engine->project.patterns().begin()->first;
    publishModel(*engine);
  }
  return OB_OK;
}

/* ------------------------------------------------------------------------- */
/* Arrangement lanes (ABI 1.7, OB-3-12)                                       */
/* ------------------------------------------------------------------------- */

int32_t ob_engine_lane_count(ob_engine* engine) {
  return engine == nullptr ? 0 : static_cast<int32_t>(engine->project.lanes().size());
}

ob_status ob_engine_lane_at(ob_engine* engine, int32_t index, ob_lane_info* out_info) {
  if (engine == nullptr || out_info == nullptr || index < 0) {
    return fail(OB_ERR_INVALID_ARGUMENT, "An engine and output lane are required.");
  }
  const std::vector<const onebeat::model::ArrangementLane*> lanes = orderedLanes(*engine);
  if (static_cast<size_t>(index) >= lanes.size()) {
    return fail(OB_ERR_INVALID_ARGUMENT, "Lane index is out of range.");
  }
  const onebeat::model::ArrangementLane& lane = *lanes[static_cast<size_t>(index)];

  std::memset(out_info, 0, sizeof(*out_info));
  out_info->struct_size = sizeof(*out_info);
  out_info->flags = (lane.muted ? OB_LANE_FLAG_MUTED : 0U) |
                    (lane.soloed ? OB_LANE_FLAG_SOLOED : 0U) |
                    (lane.collapsed ? OB_LANE_FLAG_COLLAPSED : 0U);
  out_info->order = lane.order;
  out_info->height = lane.height;
  out_info->clip_count = static_cast<uint32_t>(engine->project.clipsOnLane(lane.id).size());
  copyText(out_info->id, sizeof(out_info->id), lane.id.str().c_str());
  copyText(out_info->name, sizeof(out_info->name), lane.name.c_str());
  copyText(out_info->color, sizeof(out_info->color), lane.color.c_str());
  g_last_error.clear();
  return OB_OK;
}

ob_status ob_engine_lane_create(ob_engine* engine, const char* utf8_name) {
  if (engine == nullptr) return fail(OB_ERR_INVALID_ARGUMENT, "engine must not be null.");
  const std::string name = (utf8_name == nullptr || utf8_name[0] == '\0')
                               ? "Lane " + std::to_string(engine->project.lanes().size() + 1)
                               : std::string(utf8_name);
  return executeModel(*engine, onebeat::model::addLane(engine->project, name),
                      "The lane could not be created.");
}

// Every lane field below is one editLane command, which is what makes each of
// them undoable on its own and coalescable inside a drag.
namespace {

ob_status editLaneField(ob_engine* engine, const char* utf8_lane_id,
                        onebeat::model::ChangeField field,
                        const std::function<void(onebeat::model::ArrangementLane&)>& mutator,
                        const char* name, const char* failure) {
  if (engine == nullptr) return fail(OB_ERR_INVALID_ARGUMENT, "engine must not be null.");
  const auto id = laneId(utf8_lane_id);
  if (!id || engine->project.findLane(*id) == nullptr) {
    return fail(OB_ERR_INVALID_ARGUMENT, "The lane does not exist.");
  }
  return executeModel(*engine, onebeat::model::editLane(engine->project, *id, field, mutator, name),
                      failure);
}

}  // namespace

ob_status ob_engine_lane_rename(ob_engine* engine, const char* utf8_lane_id,
                                const char* utf8_name) {
  if (utf8_name == nullptr || utf8_name[0] == '\0') {
    return fail(OB_ERR_INVALID_ARGUMENT, "A lane name is required.");
  }
  const std::string name = utf8_name;
  return editLaneField(
      engine, utf8_lane_id, onebeat::model::ChangeField::Name,
      [&name](onebeat::model::ArrangementLane& lane) { lane.name = name; }, "Rename lane",
      "The lane could not be renamed.");
}

ob_status ob_engine_lane_recolor(ob_engine* engine, const char* utf8_lane_id,
                                 const char* utf8_color) {
  if (utf8_color == nullptr) return fail(OB_ERR_INVALID_ARGUMENT, "A lane colour is required.");
  const std::string color = utf8_color;
  return editLaneField(
      engine, utf8_lane_id, onebeat::model::ChangeField::Color,
      [&color](onebeat::model::ArrangementLane& lane) { lane.color = color; }, "Recolour lane",
      "The lane could not be recoloured.");
}

ob_status ob_engine_lane_reorder(ob_engine* engine, const char* utf8_lane_id, int32_t order) {
  return editLaneField(
      engine, utf8_lane_id, onebeat::model::ChangeField::Order,
      [order](onebeat::model::ArrangementLane& lane) { lane.order = order; }, "Reorder lane",
      "The lane could not be reordered.");
}

ob_status ob_engine_lane_set_height(ob_engine* engine, const char* utf8_lane_id, int32_t height) {
  if (height < 24 || height > 400) {
    return fail(OB_ERR_INVALID_ARGUMENT, "Lane height must be between 24 and 400.");
  }
  return editLaneField(
      engine, utf8_lane_id, onebeat::model::ChangeField::Height,
      [height](onebeat::model::ArrangementLane& lane) { lane.height = height; }, "Resize lane",
      "The lane could not be resized.");
}

ob_status ob_engine_lane_set_muted(ob_engine* engine, const char* utf8_lane_id, int32_t muted) {
  const bool value = muted != 0;
  return editLaneField(
      engine, utf8_lane_id, onebeat::model::ChangeField::Muted,
      [value](onebeat::model::ArrangementLane& lane) { lane.muted = value; },
      value ? "Mute lane events" : "Unmute lane events", "The lane could not be muted.");
}

ob_status ob_engine_lane_set_soloed(ob_engine* engine, const char* utf8_lane_id, int32_t soloed) {
  const bool value = soloed != 0;
  return editLaneField(
      engine, utf8_lane_id, onebeat::model::ChangeField::Soloed,
      [value](onebeat::model::ArrangementLane& lane) { lane.soloed = value; },
      value ? "Solo lane" : "Unsolo lane", "The lane could not be soloed.");
}

ob_status ob_engine_lane_set_collapsed(ob_engine* engine, const char* utf8_lane_id,
                                       int32_t collapsed) {
  const bool value = collapsed != 0;
  return editLaneField(
      engine, utf8_lane_id, onebeat::model::ChangeField::Collapsed,
      [value](onebeat::model::ArrangementLane& lane) { lane.collapsed = value; },
      value ? "Collapse lane" : "Expand lane", "The lane could not be collapsed.");
}

ob_status ob_engine_lane_remove(ob_engine* engine, const char* utf8_lane_id) {
  if (engine == nullptr) return fail(OB_ERR_INVALID_ARGUMENT, "engine must not be null.");
  const auto id = laneId(utf8_lane_id);
  if (!id || engine->project.findLane(*id) == nullptr) {
    return fail(OB_ERR_INVALID_ARGUMENT, "The lane does not exist.");
  }
  return executeModel(*engine, onebeat::model::removeLane(*id), "The lane could not be deleted.");
}

/* ------------------------------------------------------------------------- */
/* Clips (ABI 1.7, OB-3-12/13)                                                */
/* ------------------------------------------------------------------------- */

int32_t ob_engine_clip_count(ob_engine* engine) {
  return engine == nullptr ? 0 : static_cast<int32_t>(engine->project.clips().size());
}

ob_status ob_engine_clip_at(ob_engine* engine, int32_t index, ob_clip_info* out_info) {
  if (engine == nullptr || out_info == nullptr || index < 0) {
    return fail(OB_ERR_INVALID_ARGUMENT, "An engine and output clip are required.");
  }
  const std::vector<const onebeat::model::Clip*> clips = orderedClips(*engine);
  if (static_cast<size_t>(index) >= clips.size()) {
    return fail(OB_ERR_INVALID_ARGUMENT, "Clip index is out of range.");
  }
  const onebeat::model::Clip& clip = *clips[static_cast<size_t>(index)];

  std::memset(out_info, 0, sizeof(*out_info));
  out_info->struct_size = sizeof(*out_info);
  out_info->flags = (clip.muted ? OB_CLIP_FLAG_MUTED : 0U) |
                    (clip.transforms.loop ? OB_CLIP_FLAG_LOOP : 0U) |
                    (clip.audio() != nullptr ? OB_CLIP_FLAG_AUDIO : 0U);
  out_info->start_ticks = clip.start;
  out_info->length_ticks = clip.length;
  out_info->window_start_ticks = clip.transforms.window_start;
  out_info->transpose = clip.transforms.transpose;
  copyText(out_info->id, sizeof(out_info->id), clip.id.str().c_str());
  copyText(out_info->lane_id, sizeof(out_info->lane_id), clip.lane.str().c_str());

  // Audio clips carry their own source name and duration. The path remains in
  // the model for project save/reopen, while the UI only needs the display name.
  if (const onebeat::model::AudioSource* audio = clip.audio()) {
    copyText(out_info->name, sizeof(out_info->name), fileName(audio->path).c_str());
    copyText(out_info->color, sizeof(out_info->color), "#50B8C6");
    copyText(out_info->audio_path, sizeof(out_info->audio_path), audio->path.c_str());
    g_last_error.clear();
    return OB_OK;
  }

  // Automation clips also have an empty pattern id; they remain unrendered
  // until their editor exists.
  const onebeat::model::PatternSource* source = clip.pattern();
  if (source == nullptr) {
    g_last_error.clear();
    return OB_OK;
  }
  copyText(out_info->pattern_id, sizeof(out_info->pattern_id), source->pattern.str().c_str());
  const onebeat::model::Pattern* pattern = engine->project.findPattern(source->pattern);
  if (pattern != nullptr) {
    out_info->pattern_length_ticks = pattern->length;
    out_info->note_count = static_cast<uint32_t>(patternNoteCount(*pattern));
    out_info->usage_count = static_cast<uint32_t>(engine->project.patternUsageCount(pattern->id));
    copyText(out_info->name, sizeof(out_info->name), pattern->name.c_str());
    copyText(out_info->color, sizeof(out_info->color), pattern->color.c_str());
  }
  g_last_error.clear();
  return OB_OK;
}

ob_status ob_engine_clip_add(ob_engine* engine, const char* utf8_lane_id,
                             const char* utf8_pattern_id, int64_t start_ticks,
                             int64_t length_ticks) {
  if (engine == nullptr || start_ticks < 0 || length_ticks <= 0) {
    return fail(OB_ERR_INVALID_ARGUMENT,
                "A clip needs a non-negative start and a positive length.");
  }
  const auto lane = laneId(utf8_lane_id);
  if (!lane || engine->project.findLane(*lane) == nullptr) {
    return fail(OB_ERR_INVALID_ARGUMENT, "The lane does not exist.");
  }
  const auto requested = patternId(utf8_pattern_id);
  const std::optional<onebeat::model::PatternId> target =
      requested.has_value() ? requested : engine->current_pattern;
  if (!target || engine->project.findPattern(*target) == nullptr) {
    return fail(OB_ERR_INVALID_ARGUMENT, "The pattern does not exist.");
  }
  return executeModel(
      *engine,
      onebeat::model::addClip(engine->project, *lane, onebeat::model::PatternSource{*target},
                              start_ticks, length_ticks),
      "The clip could not be placed.");
}

ob_status ob_engine_audio_clip_add(ob_engine* engine, const char* utf8_lane_id,
                                   const char* utf8_sample_path, int64_t start_ticks) {
  if (engine == nullptr || utf8_sample_path == nullptr || utf8_sample_path[0] == '\0' ||
      start_ticks < 0) {
    return fail(OB_ERR_INVALID_ARGUMENT,
                "An audio clip needs a sample path and non-negative start.");
  }
  const auto lane = laneId(utf8_lane_id);
  if (!lane || engine->project.findLane(*lane) == nullptr) {
    return fail(OB_ERR_INVALID_ARGUMENT, "The lane does not exist.");
  }

  std::string error;
  const std::unique_ptr<onebeat::core::SampleData> sample =
      onebeat::core::loadAudioFile(utf8_sample_path, error);
  if (sample == nullptr || sample->sample_rate <= 0.0 || sample->frames <= 0) {
    return fail(OB_ERR_FILE_UNSUPPORTED,
                error.empty() ? "The sample could not be read." : error.c_str());
  }

  const double beats = (static_cast<double>(sample->frames) / sample->sample_rate) *
                       engine->project.transport().tempo / 60.0;
  const int64_t length = std::max<int64_t>(
      1, static_cast<int64_t>(std::llround(beats * onebeat::model::TicksPerQuarter)));
  onebeat::model::AudioSource source;
  source.path = utf8_sample_path;
  source.destination = engine->project.masterTrack();
  return executeModel(*engine,
                      onebeat::model::addClip(engine->project, *lane, source, start_ticks, length),
                      "The audio clip could not be placed.");
}

ob_status ob_engine_clip_move(ob_engine* engine, const char* utf8_clip_id, const char* utf8_lane_id,
                              int64_t start_ticks) {
  if (engine == nullptr || start_ticks < 0) {
    return fail(OB_ERR_INVALID_ARGUMENT, "A clip start must not be negative.");
  }
  const auto id = clipId(utf8_clip_id);
  if (!id || engine->project.findClip(*id) == nullptr) {
    return fail(OB_ERR_INVALID_ARGUMENT, "The clip does not exist.");
  }
  // An empty lane id means "same lane": the common case is a horizontal drag,
  // and making the caller echo the current lane back invites it getting it
  // wrong during a multi-clip move.
  std::optional<onebeat::model::ArrangementLaneId> lane = laneId(utf8_lane_id);
  if (lane && engine->project.findLane(*lane) == nullptr) {
    return fail(OB_ERR_INVALID_ARGUMENT, "The lane does not exist.");
  }
  const ob_status status =
      executeModel(*engine,
                   onebeat::model::editClip(
                       engine->project, *id, onebeat::model::ChangeField::Start,
                       [lane, start_ticks](onebeat::model::Clip& clip) {
                         clip.start = start_ticks;
                         if (lane) clip.lane = *lane;
                       },
                       "Move clip"),
                   "The clip could not be moved.");
  return status;
}

ob_status ob_engine_clip_resize(ob_engine* engine, const char* utf8_clip_id, int64_t length_ticks) {
  if (engine == nullptr || length_ticks <= 0) {
    return fail(OB_ERR_INVALID_ARGUMENT, "A clip length must be positive.");
  }
  const auto id = clipId(utf8_clip_id);
  if (!id || engine->project.findClip(*id) == nullptr) {
    return fail(OB_ERR_INVALID_ARGUMENT, "The clip does not exist.");
  }
  return executeModel(
      *engine,
      onebeat::model::editClip(
          engine->project, *id, onebeat::model::ChangeField::Length,
          [length_ticks](onebeat::model::Clip& clip) { clip.length = length_ticks; },
          "Resize clip"),
      "The clip could not be resized.");
}

ob_status ob_engine_clip_duplicate(ob_engine* engine, const char* utf8_clip_id,
                                   const char* utf8_lane_id, int64_t start_ticks) {
  if (engine == nullptr || start_ticks < 0) {
    return fail(OB_ERR_INVALID_ARGUMENT, "A clip start must not be negative.");
  }
  const auto id = clipId(utf8_clip_id);
  const onebeat::model::Clip* source = id ? engine->project.findClip(*id) : nullptr;
  if (source == nullptr) return fail(OB_ERR_INVALID_ARGUMENT, "The clip does not exist.");

  const std::optional<onebeat::model::ArrangementLaneId> requested = laneId(utf8_lane_id);
  const onebeat::model::ArrangementLaneId lane = requested.value_or(source->lane);
  if (engine->project.findLane(lane) == nullptr) {
    return fail(OB_ERR_INVALID_ARGUMENT, "The lane does not exist.");
  }
  // Copy-drag duplicates the transforms too: a transposed clip that loses its
  // transpose when ⌥-dragged would be a silent data loss the user only hears.
  const onebeat::model::ClipSource clip_source = source->source;
  const onebeat::model::ClipTransforms transforms = source->transforms;
  const bool muted = source->muted;
  const onebeat::model::Ticks length = source->length;

  engine->commands.beginTransaction("Duplicate clip");
  const auto created = executeAndFindNew<onebeat::model::ClipId>(
      *engine, engine->project.clips(),
      onebeat::model::addClip(engine->project, lane, clip_source, start_ticks, length));
  if (!created || !engine->commands.execute(onebeat::model::editClip(
                      engine->project, *created, onebeat::model::ChangeField::Transforms,
                      [transforms, muted](onebeat::model::Clip& clip) {
                        clip.transforms = transforms;
                        clip.muted = muted;
                      },
                      "Copy clip settings"))) {
    engine->commands.abortTransaction();
    return fail(OB_ERR_INTERNAL, "The clip could not be duplicated.");
  }
  engine->commands.commitTransaction();
  publishModel(*engine);
  g_last_error.clear();
  return OB_OK;
}

ob_status ob_engine_clip_remove(ob_engine* engine, const char* utf8_clip_id) {
  if (engine == nullptr) return fail(OB_ERR_INVALID_ARGUMENT, "engine must not be null.");
  const auto id = clipId(utf8_clip_id);
  if (!id || engine->project.findClip(*id) == nullptr) {
    return fail(OB_ERR_INVALID_ARGUMENT, "The clip does not exist.");
  }
  const bool audio_clip = engine->project.findClip(*id)->audio() != nullptr;
  std::optional<onebeat::core::InstrumentId> audio_channel;
  if (const auto found = engine->audio_channel_indices.find(*id);
      found != engine->audio_channel_indices.end()) {
    audio_channel = found->second;
  }
  const ob_status status =
      executeModel(*engine, onebeat::model::removeClip(*id), "The clip could not be deleted.");
  if (status == OB_OK && audio_clip && audio_channel.has_value()) {
    engine->engine->requestChannelReset(static_cast<int>(*audio_channel));
  }
  return status;
}

namespace {

ob_status editClipField(ob_engine* engine, const char* utf8_clip_id,
                        onebeat::model::ChangeField field,
                        const std::function<void(onebeat::model::Clip&)>& mutator, const char* name,
                        const char* failure) {
  if (engine == nullptr) return fail(OB_ERR_INVALID_ARGUMENT, "engine must not be null.");
  const auto id = clipId(utf8_clip_id);
  if (!id || engine->project.findClip(*id) == nullptr) {
    return fail(OB_ERR_INVALID_ARGUMENT, "The clip does not exist.");
  }
  return executeModel(*engine, onebeat::model::editClip(engine->project, *id, field, mutator, name),
                      failure);
}

}  // namespace

ob_status ob_engine_clip_set_muted(ob_engine* engine, const char* utf8_clip_id, int32_t muted) {
  const bool value = muted != 0;
  return editClipField(
      engine, utf8_clip_id, onebeat::model::ChangeField::Muted,
      [value](onebeat::model::Clip& clip) { clip.muted = value; },
      value ? "Mute clip" : "Unmute clip", "The clip could not be muted.");
}

ob_status ob_engine_clip_set_loop(ob_engine* engine, const char* utf8_clip_id, int32_t loop) {
  const bool value = loop != 0;
  return editClipField(
      engine, utf8_clip_id, onebeat::model::ChangeField::Transforms,
      [value](onebeat::model::Clip& clip) { clip.transforms.loop = value; },
      value ? "Loop clip" : "Stop clip at its end", "The clip loop mode could not be changed.");
}

ob_status ob_engine_clip_set_window_start(ob_engine* engine, const char* utf8_clip_id,
                                          int64_t window_start_ticks) {
  if (window_start_ticks < 0) {
    return fail(OB_ERR_INVALID_ARGUMENT, "A clip window start must not be negative.");
  }
  return editClipField(
      engine, utf8_clip_id, onebeat::model::ChangeField::Transforms,
      [window_start_ticks](onebeat::model::Clip& clip) {
        clip.transforms.window_start = window_start_ticks;
      },
      "Set clip offset", "The clip offset could not be changed.");
}

ob_status ob_engine_clip_set_transpose(ob_engine* engine, const char* utf8_clip_id,
                                       int32_t semitones) {
  if (semitones < -48 || semitones > 48) {
    return fail(OB_ERR_INVALID_ARGUMENT, "Transpose must be between -48 and 48 semitones.");
  }
  const int16_t value = static_cast<int16_t>(semitones);
  return editClipField(
      engine, utf8_clip_id, onebeat::model::ChangeField::Transforms,
      [value](onebeat::model::Clip& clip) { clip.transforms.transpose = value; }, "Transpose clip",
      "The clip could not be transposed.");
}

ob_status ob_engine_clips_make_unique(ob_engine* engine, const char* utf8_clip_ids) {
  if (engine == nullptr) return fail(OB_ERR_INVALID_ARGUMENT, "engine must not be null.");
  const std::vector<std::string> raw_ids = splitDirectories(utf8_clip_ids);
  if (raw_ids.empty()) return fail(OB_ERR_INVALID_ARGUMENT, "No clips were given.");

  std::vector<onebeat::model::ClipId> targets;
  targets.reserve(raw_ids.size());
  const onebeat::model::Pattern* source = nullptr;
  for (const std::string& text : raw_ids) {
    const auto id = clipId(text.c_str());
    const onebeat::model::Clip* clip = id ? engine->project.findClip(*id) : nullptr;
    const onebeat::model::PatternSource* pattern_source =
        clip == nullptr ? nullptr : clip->pattern();
    if (pattern_source == nullptr) {
      return fail(OB_ERR_INVALID_ARGUMENT, "Make unique needs existing pattern clips.");
    }
    const onebeat::model::Pattern* pattern = engine->project.findPattern(pattern_source->pattern);
    if (pattern == nullptr) return fail(OB_ERR_INVALID_ARGUMENT, "The clip's pattern is missing.");
    // One clone for the whole selection, so the clips stay linked to each other
    // while being cut loose from everything outside it (OB-3-11 §4).
    if (source == nullptr) {
      source = pattern;
    } else if (source->id != pattern->id) {
      return fail(OB_ERR_INVALID_ARGUMENT, "The selected clips use different patterns.");
    }
    targets.push_back(*id);
  }

  engine->commands.beginTransaction("Make unique");
  const auto clone = clonePattern(*engine, *source, derivedPatternName(*engine, source->name));
  if (!clone) {
    engine->commands.abortTransaction();
    return fail(OB_ERR_INTERNAL, "The pattern could not be cloned.");
  }
  const onebeat::model::PatternId clone_id = *clone;
  for (const onebeat::model::ClipId& target : targets) {
    if (!engine->commands.execute(onebeat::model::editClip(
            engine->project, target, onebeat::model::ChangeField::Source,
            [clone_id](onebeat::model::Clip& clip) {
              clip.source = onebeat::model::PatternSource{clone_id};
            },
            "Repoint clip"))) {
      engine->commands.abortTransaction();
      return fail(OB_ERR_INTERNAL, "The clip could not be repointed.");
    }
  }
  engine->commands.commitTransaction();
  engine->current_pattern = clone_id;
  publishModel(*engine);
  g_last_error.clear();
  return OB_OK;
}

ob_status ob_engine_project_new(ob_engine* engine) {
  if (engine == nullptr) return fail(OB_ERR_INVALID_ARGUMENT, "engine must not be null.");
  try {
    onebeat::model::Project fresh;
    const onebeat::model::PatternId pattern =
        fresh.createPattern("Pattern 1", onebeat::model::TicksPerBarFourFour);
    const onebeat::model::ArrangementLaneId lane = fresh.createLane("Patterns");
    if (!fresh
             .createClip(lane, onebeat::model::PatternSource{pattern}, 0,
                         onebeat::model::TicksPerBarFourFour)
             .valid()) {
      return fail(OB_ERR_INTERNAL, "The new project could not be created.");
    }

    engine->project.adopt(fresh.copyTables());
    engine->commands.clear();
    engine->rack_grids.clear();
    engine->selected_instrument = std::nullopt;
    engine->current_pattern = pattern;
    engine->project_path.clear();
    engine->residue = onebeat::model::Residue{};
    engine->pending_project_state.clear();
    engine->hosted.clear();
    engine->has_instance = false;
    engine->instance_missing = false;
    engine->instance_state.clear();
    publishModel(*engine);
    engine->saved_project_hash = projectHash(*engine);
    g_last_error.clear();
    return OB_OK;
  } catch (const std::exception& exception) {
    return fail(OB_ERR_INTERNAL, exception.what());
  } catch (...) {
    return fail(OB_ERR_INTERNAL, "Unknown failure while creating the project.");
  }
}

ob_status ob_engine_project_save(ob_engine* engine, const char* utf8_path) {
  if (engine == nullptr || utf8_path == nullptr || utf8_path[0] == '\0') {
    return fail(OB_ERR_INVALID_ARGUMENT, "A project path is required.");
  }
  try {
    onebeat::model::SaveOptions options;
    options.created_with = std::string("OneBeat ") + ob_abi_version_string();
    // Carry existing sidecars across: this engine does not yet route per
    // instrument plug-in state through the project writer (that lands with the
    // Stage 4 mixer), and dropping them on save would be data loss.
    options.copy_state_from = engine->project_path;
    options.state_provider = [engine](onebeat::model::InstrumentId id) {
      const int channel = channelIndexOf(*engine, id);
      std::vector<uint8_t> bytes;
      if (channel < 0 || !engine->engine->saveHostedState(channel, bytes)) {
        return std::vector<std::byte>{};
      }
      std::vector<std::byte> state(bytes.size());
      if (!bytes.empty()) {
        std::memcpy(state.data(), bytes.data(), bytes.size());
      }
      return state;
    };

    const onebeat::model::SaveReport report =
        onebeat::model::saveProject(utf8_path, engine->project, engine->residue, options);
    if (!report.ok) {
      return fail(OB_ERR_INTERNAL,
                  report.error.empty() ? "The project could not be saved." : report.error.c_str());
    }
    // State references are persistence bookkeeping, not a user edit. Fold the
    // records into the model without adding undo commands so the dirty hash
    // agrees with the project.json just written.
    for (const auto& [id, record] : report.state_written) {
      (void)engine->project.updateInstrument(id, onebeat::model::ChangeField::Plugin,
                                             [&record](onebeat::model::Instrument& instrument) {
                                               instrument.plugin.state_ref = record.state_ref;
                                               instrument.plugin.state_sha256 = record.sha256;
                                             });
    }
    engine->project_path = utf8_path;
    engine->saved_project_hash = projectHash(*engine);
    g_last_error.clear();
    return OB_OK;
  } catch (const std::exception& exception) {
    return fail(OB_ERR_INTERNAL, exception.what());
  } catch (...) {
    return fail(OB_ERR_INTERNAL, "Unknown failure while saving the project.");
  }
}

ob_status ob_engine_project_open(ob_engine* engine, const char* utf8_path) {
  if (engine == nullptr || utf8_path == nullptr || utf8_path[0] == '\0') {
    return fail(OB_ERR_INVALID_ARGUMENT, "A project path is required.");
  }
  try {
    if (!std::filesystem::exists(utf8_path)) {
      return fail(OB_ERR_FILE_NOT_FOUND, "The project does not exist.");
    }
    onebeat::model::Residue residue;
    engine->pending_project_state.clear();
    onebeat::model::LoadOptions load_options;
    load_options.state_sink = [engine](onebeat::model::InstrumentId id,
                                       const std::vector<std::byte>& bytes) {
      std::vector<uint8_t> state(bytes.size());
      if (!bytes.empty()) {
        std::memcpy(state.data(), bytes.data(), bytes.size());
      }
      engine->pending_project_state[id] = std::move(state);
    };
    const onebeat::model::LoadReport report =
        onebeat::model::loadProject(utf8_path, engine->project, residue, load_options);
    if (!report.ok) {
      // loadProject leaves the project untouched on failure, so the session the
      // user already had open survives an unreadable file.
      const std::string detail = report.describe();
      return fail(OB_ERR_FILE_UNSUPPORTED,
                  detail.empty() ? "The project could not be opened." : detail.c_str());
    }
    engine->residue = std::move(residue);
    engine->project_path = utf8_path;
    engine->hosted.clear();
    engine->has_instance = false;
    engine->instance_missing = false;
    engine->instance_state.clear();

    // The history belongs to the session that made it: an opened file has no
    // edits to undo, and keeping the old stack would let undo reach back into a
    // project that is no longer loaded.
    engine->commands.clear();
    engine->rack_grids.clear();
    engine->selected_instrument = std::nullopt;
    engine->current_pattern = engine->project.patterns().empty()
                                  ? std::optional<onebeat::model::PatternId>{}
                                  : engine->project.patterns().begin()->first;
    engine->flattener.markDirty();
    publishModel(*engine);
    engine->saved_project_hash = projectHash(*engine);
    g_last_error.clear();
    return OB_OK;
  } catch (const std::exception& exception) {
    return fail(OB_ERR_INTERNAL, exception.what());
  } catch (...) {
    return fail(OB_ERR_INTERNAL, "Unknown failure while opening the project.");
  }
}

const char* ob_engine_project_json(ob_engine* engine) {
  if (engine == nullptr) return "";
  try {
    engine->project_json_cache = onebeat::model::writeProjectJson(engine->project, engine->residue);
    return engine->project_json_cache.c_str();
  } catch (...) {
    return "";
  }
}

const char* ob_engine_project_path(ob_engine* engine) {
  if (engine == nullptr) return "";
  return engine->project_path.c_str();
}

const char* ob_engine_project_name(ob_engine* engine) {
  if (engine == nullptr) return "";
  try {
    engine->project_name_cache = engine->project.meta().name;
    return engine->project_name_cache.c_str();
  } catch (...) {
    return "";
  }
}

ob_status ob_engine_project_set_name(ob_engine* engine, const char* utf8_name) {
  if (engine == nullptr || utf8_name == nullptr || utf8_name[0] == '\0') {
    return fail(OB_ERR_INVALID_ARGUMENT, "A project name is required.");
  }
  try {
    onebeat::model::ProjectMeta meta = engine->project.meta();
    if (meta.name == utf8_name) {
      g_last_error.clear();
      return OB_OK;
    }
    meta.name = utf8_name;
    if (!engine->commands.execute(onebeat::model::setProjectMeta(engine->project, meta))) {
      return fail(OB_ERR_INTERNAL, "The project could not be renamed.");
    }
    // Renaming changes nothing audible, so there is nothing to flatten — but
    // the history entry and the dirty flag are both real.
    engine->commands.seal();
    g_last_error.clear();
    return OB_OK;
  } catch (const std::exception& exception) {
    return fail(OB_ERR_INTERNAL, exception.what());
  } catch (...) {
    return fail(OB_ERR_INTERNAL, "Unknown failure while renaming the project.");
  }
}

int32_t ob_engine_project_is_modified(ob_engine* engine) {
  if (engine == nullptr) return 0;
  try {
    return projectHash(*engine) == engine->saved_project_hash ? 0 : 1;
  } catch (...) {
    // Unable to tell: say modified, because the failure mode of a false "saved"
    // is losing work and the failure mode of a false "edited" is a needless
    // prompt.
    return 1;
  }
}

}  // extern "C"
