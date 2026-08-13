// Implementation of the public C ABI (ADR-002, OB-1-10).
//
// Rules this file exists to enforce:
//   - no exception ever crosses the boundary (every entry point is wrapped);
//   - no allocation on any path a UI frame takes (snapshot read, event poll,
//     command post);
//   - every entry point validates its handle and returns a status code.
#include "abi/onebeat_abi.h"

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
#include "model/command.h"
#include "model/commands.h"
#include "model/flattener.h"
#include "model/note_edit.h"
#include "plugin/scan/plugin_library.h"
#include "plugin/scan/subprocess_probe.h"

namespace {

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
  std::map<onebeat::model::InstrumentId, onebeat::model::Ticks> rack_grids;
  std::string undo_name_cache;
  std::string redo_name_cache;
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
};

namespace {

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

ob_status executeModel(ob_engine& handle, onebeat::model::CommandPtr command, const char* failure) {
  if (command == nullptr || !handle.commands.execute(std::move(command))) {
    return fail(OB_ERR_INVALID_ARGUMENT, failure);
  }
  onebeat::model::FlattenResult flattened =
      handle.flattener.flushIfDirty(handle.engine->config().sample_rate);
  if (flattened.schedule != nullptr) handle.engine->publishSchedule(std::move(flattened.schedule));
  g_last_error.clear();
  return OB_OK;
}

void publishModel(ob_engine& handle) {
  onebeat::model::FlattenResult flattened =
      handle.flattener.flushIfDirty(handle.engine->config().sample_rate);
  if (flattened.schedule != nullptr) handle.engine->publishSchedule(std::move(flattened.schedule));
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

const onebeat::model::Pattern* currentPattern(const ob_engine& handle) {
  return handle.current_pattern ? handle.project.findPattern(*handle.current_pattern) : nullptr;
}

onebeat::model::Ticks rackGrid(const ob_engine& handle, onebeat::model::InstrumentId id) {
  const auto found = handle.rack_grids.find(id);
  return found == handle.rack_grids.end() ? onebeat::model::TicksPerQuarter / 4 : found->second;
}

}  // namespace

extern "C" {

uint32_t ob_abi_version(void) {
  return OB_ABI_VERSION_PACKED;
}

const char* ob_abi_version_string(void) {
  return "1.6.0";
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
    std::string error;
    if (!engine->engine->createSandboxedInstrument(
            utf8_bundle_path, utf8_plugin_id,
            onebeat::plugin::scan::SubprocessProbe::discoverHelperPath(), error)) {
      return fail(OB_ERR_FILE_UNSUPPORTED, error.c_str());
    }
    engine->has_instance = true;
    engine->instance_missing = false;
    engine->instance_path = utf8_bundle_path;
    engine->instance_plugin_id = utf8_plugin_id;
    engine->instance_name = engine->engine->instrument().name().text();
    engine->instance_vendor.clear();
    for (const auto& row : pluginLibrary(*engine).plugins()) {
      if (row.path.text() == engine->instance_path && row.id.text() == engine->instance_plugin_id) {
        engine->instance_vendor = row.vendor.text();
        engine->instance_format = static_cast<uint32_t>(row.format);
        break;
      }
    }
    engine->instance_state.clear();
    onebeat::model::PluginRef plugin;
    plugin.format = static_cast<onebeat::model::PluginFormat>(engine->instance_format);
    plugin.id = engine->instance_plugin_id;
    plugin.name = engine->instance_name;
    plugin.vendor = engine->instance_vendor;
    plugin.path_hint = engine->instance_path;
    if (executeModel(*engine, onebeat::model::addInstrument(engine->project, plugin),
                     "Could not add the instrument to the project.") != OB_OK) {
      return fail(OB_ERR_INTERNAL, "Could not add the instrument to the project.");
    }
    for (const auto& [id, instrument] : engine->project.instruments()) {
      if (instrument.order == static_cast<int32_t>(engine->project.instruments().size() - 1)) {
        engine->selected_instrument = id;
        break;
      }
    }
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
    std::string error;
    if (!engine->engine->restoreBuiltinInstrument(error))
      return fail(OB_ERR_INTERNAL, error.c_str());
    engine->has_instance = false;
    engine->instance_missing = false;
    engine->instance_state.clear();
    if (engine->selected_instrument.has_value()) {
      if (executeModel(*engine, onebeat::model::removeInstrument(*engine->selected_instrument),
                       "Could not remove the instrument from the project.") != OB_OK) {
        return fail(OB_ERR_INTERNAL, "Could not remove the instrument from the project.");
      }
      engine->selected_instrument = std::nullopt;
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
  out_info->flags = engine->instance_missing ? OB_INSTANCE_FLAG_MISSING : 0U;
  if (engine->engine->hostedHasEditor()) out_info->flags |= OB_INSTANCE_FLAG_HAS_EDITOR;
  if (!engine->instance_missing && !engine->engine->hostedHealthy())
    out_info->flags |= OB_INSTANCE_FLAG_NEEDS_RESTART;
  out_info->param_count = engine->engine->hostedParamCount();
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
  onebeat::plugin::ParamInfo info;
  if (!engine->engine->hostedParamInfo(static_cast<uint32_t>(index), info)) {
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
  engine->engine->hostedParamValue(info.id, out_info->value);
  copyText(out_info->name, sizeof(out_info->name), info.name.text());
  copyText(out_info->module, sizeof(out_info->module), info.module.text());
  if (!engine->engine->instrument().paramValueToText(info.id, out_info->value, out_info->display,
                                                     sizeof(out_info->display))) {
    std::snprintf(out_info->display, sizeof(out_info->display), "%.3f", out_info->value);
  }
  return OB_OK;
}

ob_status ob_engine_instance_editor_open(ob_engine* engine, uint32_t instance_id) {
  if (engine == nullptr || !engine->has_instance || instance_id != engine->instance_id)
    return fail(OB_ERR_INVALID_ARGUMENT, "The plug-in instance does not exist.");
  return engine->engine->openHostedEditor()
             ? OB_OK
             : fail(OB_ERR_FILE_UNSUPPORTED, "This plug-in has no native editor.");
}

ob_status ob_engine_instance_editor_close(ob_engine* engine, uint32_t instance_id) {
  if (engine == nullptr || !engine->has_instance || instance_id != engine->instance_id)
    return fail(OB_ERR_INVALID_ARGUMENT, "The plug-in instance does not exist.");
  engine->engine->closeHostedEditor();
  return OB_OK;
}

ob_status ob_engine_instance_restart(ob_engine* engine, uint32_t instance_id) {
  if (engine == nullptr || !engine->has_instance || engine->instance_missing ||
      instance_id != engine->instance_id)
    return fail(OB_ERR_INVALID_ARGUMENT, "The plug-in instance cannot be restarted.");
  if (engine->engine->restartHostedInstrument()) return OB_OK;
  const std::string detail = engine->engine->hostedError();
  return fail(OB_ERR_INTERNAL,
              detail.empty() ? "The plug-in helper could not be restarted." : detail.c_str());
}

ob_status ob_engine_session_save(ob_engine* engine, const char* utf8_path) {
  if (engine == nullptr || utf8_path == nullptr || utf8_path[0] == '\0') {
    return fail(OB_ERR_INVALID_ARGUMENT, "A scratch session path is required.");
  }
  try {
    std::vector<uint8_t> state = engine->instance_state;
    if (engine->has_instance && !engine->instance_missing &&
        !engine->engine->saveHostedState(state)) {
      const std::string detail = engine->engine->hostedError();
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
    if (present == 0) {
      if (engine->has_instance && !engine->engine->restoreBuiltinInstrument(error))
        return fail(OB_ERR_INTERNAL, error.c_str());
      engine->has_instance = false;
      return OB_OK;
    }
    const bool available = std::filesystem::exists(path);
    if (available) {
      if (!engine->engine->createSandboxedInstrument(
              path, plugin_id, onebeat::plugin::scan::SubprocessProbe::discoverHelperPath(),
              error) ||
          !engine->engine->loadHostedState(state))
        return fail(OB_ERR_FILE_UNSUPPORTED,
                    error.empty() ? "The saved plug-in could not be restored." : error.c_str());
    } else if (!engine->engine->installMissingInstrument(name, state, error)) {
      return fail(OB_ERR_INTERNAL, error.c_str());
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
    std::string error;
    if (!engine->engine->createSandboxedInstrument(
            instrument->plugin.path_hint, instrument->plugin.id,
            onebeat::plugin::scan::SubprocessProbe::discoverHelperPath(), error)) {
      return fail(OB_ERR_FILE_UNSUPPORTED, error.c_str());
    }
    engine->has_instance = true;
    engine->instance_missing = false;
    engine->instance_path = instrument->plugin.path_hint;
    engine->instance_plugin_id = instrument->plugin.id;
    engine->instance_name = instrument->plugin.name;
    engine->instance_vendor = instrument->plugin.vendor;
    engine->instance_format = static_cast<uint32_t>(instrument->plugin.format);
    engine->selected_instrument = *id;
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
    if (engine->selected_instrument == id) {
      std::string error;
      if (!engine->engine->createSandboxedInstrument(
              plugin.path_hint, plugin.id,
              onebeat::plugin::scan::SubprocessProbe::discoverHelperPath(), error)) {
        return fail(OB_ERR_FILE_UNSUPPORTED, error.c_str());
      }
      engine->instance_path = plugin.path_hint;
      engine->instance_plugin_id = plugin.id;
      engine->instance_name = engine->engine->instrument().name().text();
      engine->instance_vendor = plugin.vendor;
      engine->instance_format = static_cast<uint32_t>(plugin.format);
      plugin.name = engine->instance_name;
    }
    return executeModel(*engine, onebeat::model::replaceInstrument(engine->project, *id, plugin),
                        "The instrument could not be replaced.");
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
    std::string error;
    if (!engine->engine->restoreBuiltinInstrument(error))
      return fail(OB_ERR_INTERNAL, error.c_str());
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
    std::string error;
    (void)engine->engine->restoreBuiltinInstrument(error);
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
    std::string error;
    (void)engine->engine->restoreBuiltinInstrument(error);
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

}  // extern "C"
