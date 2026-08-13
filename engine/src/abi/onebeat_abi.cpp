// Implementation of the public C ABI (ADR-002, OB-1-10).
//
// Rules this file exists to enforce:
//   - no exception ever crosses the boundary (every entry point is wrapped);
//   - no allocation on any path a UI frame takes (snapshot read, event poll,
//     command post);
//   - every entry point validates its handle and returns a status code.
#include "abi/onebeat_abi.h"

#include <cstring>
#include <memory>
#include <new>
#include <string>
#include <vector>

#include "core/engine.h"
#include "plugin/scan/plugin_library.h"

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
  // Not part of the Engine: the plugin library is filesystem work and a
  // background thread, and nothing in it goes near the audio thread (OB-2-02).
  std::unique_ptr<onebeat::plugin::scan::PluginLibrary> library;
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

}  // namespace

extern "C" {

uint32_t ob_abi_version(void) {
  return OB_ABI_VERSION_PACKED;
}

const char* ob_abi_version_string(void) {
  return "1.1.0";
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
    g_last_error.clear();
    return OB_OK;
  } catch (const std::exception& exception) {
    return fail(OB_ERR_INTERNAL, exception.what());
  }
}

}  // extern "C"
