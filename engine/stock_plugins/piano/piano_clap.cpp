// Public CLAP adapter for OneBeat Piano. Sound generation lives in
// piano_engine.* so the instrument can be read and tested without CLAP details.
#include "piano_engine.h"

#include <clap/clap.h>

#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <new>

namespace {

using onebeat::stock::piano::clampParameter;
using onebeat::stock::piano::parameterIndex;
using onebeat::stock::piano::ParameterSpecs;
using onebeat::stock::piano::PianoEngine;

struct PianoPlugin {
  clap_plugin_t plugin{};
  PianoEngine engine;
};

PianoPlugin& self(const clap_plugin_t* plugin) {
  return *static_cast<PianoPlugin*>(plugin->plugin_data);
}

void handleEvent(PianoPlugin& piano, const clap_event_header_t* header) {
  if (header == nullptr || header->space_id != CLAP_CORE_EVENT_SPACE_ID) {
    return;
  }
  if (header->type == CLAP_EVENT_NOTE_ON) {
    const auto* note = reinterpret_cast<const clap_event_note_t*>(header);
    piano.engine.noteOn(note->note_id, note->channel, note->key, note->velocity);
  } else if (header->type == CLAP_EVENT_NOTE_OFF || header->type == CLAP_EVENT_NOTE_CHOKE) {
    const auto* note = reinterpret_cast<const clap_event_note_t*>(header);
    piano.engine.noteOff(note->note_id, note->channel, note->key,
                         header->type == CLAP_EVENT_NOTE_CHOKE);
  } else if (header->type == CLAP_EVENT_PARAM_VALUE) {
    const auto* event = reinterpret_cast<const clap_event_param_value_t*>(header);
    piano.engine.setParameter(event->param_id, event->value);
  } else if (header->type == CLAP_EVENT_MIDI) {
    const auto* midi = reinterpret_cast<const clap_event_midi_t*>(header);
    const uint8_t status = midi->data[0] & 0xf0U;
    const int channel = midi->data[0] & 0x0fU;
    const int key = midi->data[1] & 0x7fU;
    const int velocity = midi->data[2] & 0x7fU;
    if (status == 0x90U && velocity > 0) {
      piano.engine.noteOn(-1, channel, key, static_cast<double>(velocity) / 127.0);
    } else if (status == 0x80U || (status == 0x90U && velocity == 0)) {
      piano.engine.noteOff(-1, channel, key, false);
    }
  }
}

bool pluginInit(const clap_plugin_t*) {
  return true;
}
void pluginDestroy(const clap_plugin_t* plugin) {
  delete &self(plugin);
}
bool pluginActivate(const clap_plugin_t* plugin, double sample_rate, uint32_t, uint32_t) {
  self(plugin).engine.setSampleRate(sample_rate);
  return true;
}
void pluginDeactivate(const clap_plugin_t*) {}
bool pluginStart(const clap_plugin_t*) {
  return true;
}
void pluginStop(const clap_plugin_t*) {}
void pluginReset(const clap_plugin_t* plugin) {
  self(plugin).engine.reset();
}

clap_process_status pluginProcess(const clap_plugin_t* plugin, const clap_process_t* process) {
  PianoPlugin& piano = self(plugin);
  if (process->audio_outputs_count == 0 || process->audio_outputs[0].data32 == nullptr) {
    return CLAP_PROCESS_CONTINUE;
  }
  clap_audio_buffer_t& output = process->audio_outputs[0];
  if (output.channel_count == 0 || output.data32[0] == nullptr) {
    return CLAP_PROCESS_CONTINUE;
  }

  uint32_t cursor = 0;
  const uint32_t event_count =
      process->in_events != nullptr ? process->in_events->size(process->in_events) : 0U;
  for (uint32_t index = 0; index < event_count; ++index) {
    const clap_event_header_t* event = process->in_events->get(process->in_events, index);
    if (event == nullptr) {
      continue;
    }
    const uint32_t event_time = std::min(event->time, process->frames_count);
    if (event_time > cursor) {
      piano.engine.render(output.data32, output.channel_count, cursor, event_time - cursor);
      cursor = event_time;
    }
    handleEvent(piano, event);
  }
  if (cursor < process->frames_count) {
    piano.engine.render(output.data32, output.channel_count, cursor,
                        process->frames_count - cursor);
  }
  return CLAP_PROCESS_CONTINUE;
}

uint32_t paramsCount(const clap_plugin_t*) {
  return static_cast<uint32_t>(ParameterSpecs.size());
}

bool paramsGetInfo(const clap_plugin_t*, uint32_t index, clap_param_info_t* info) {
  if (index >= ParameterSpecs.size() || info == nullptr) {
    return false;
  }
  *info = {};
  info->id = ParameterSpecs[index].id;
  info->flags = CLAP_PARAM_IS_AUTOMATABLE | CLAP_PARAM_IS_MODULATABLE;
  std::strncpy(info->name, ParameterSpecs[index].name, sizeof(info->name) - 1);
  std::strncpy(info->module, ParameterSpecs[index].module, sizeof(info->module) - 1);
  info->min_value = 0.0;
  info->max_value = 1.0;
  info->default_value = ParameterSpecs[index].default_value;
  return true;
}

bool paramsGetValue(const clap_plugin_t* plugin, clap_id id, double* value) {
  if (parameterIndex(id) >= ParameterSpecs.size() || value == nullptr) {
    return false;
  }
  *value = self(plugin).engine.parameter(id);
  return true;
}

bool paramsValueToText(const clap_plugin_t*, clap_id id, double value, char* display,
                       uint32_t size) {
  if (parameterIndex(id) >= ParameterSpecs.size() || display == nullptr || size == 0) {
    return false;
  }
  const double clamped = clampParameter(value);
  switch (id) {
    case onebeat::stock::piano::ParamPreset: {
      const uint32_t idx = std::clamp(
          static_cast<uint32_t>(clamped * static_cast<double>(onebeat::stock::piano::PresetCount)),
          0U, static_cast<uint32_t>(onebeat::stock::piano::PresetCount - 1));
      std::strncpy(display, onebeat::stock::piano::presetName(idx), size - 1);
      display[size - 1] = '\0';
      return true;
    }
    case onebeat::stock::piano::ParamAttack: {
      const double ms = (0.001 + clamped * clamped * 0.4) * 1000.0;
      std::snprintf(display, size, "%.1f ms", ms);
      return true;
    }
    case onebeat::stock::piano::ParamDecay: {
      const double sec = 0.12 + clamped * clamped * 12.0;
      std::snprintf(display, size, "%.2f s", sec);
      return true;
    }
    case onebeat::stock::piano::ParamRelease: {
      const double sec = 0.03 + clamped * clamped * 5.0;
      std::snprintf(display, size, "%.2f s", sec);
      return true;
    }
    case onebeat::stock::piano::ParamModRate: {
      const double hz = 0.2 + clamped * 7.8;
      std::snprintf(display, size, "%.1f Hz", hz);
      return true;
    }
    case onebeat::stock::piano::ParamPitch: {
      const double st = (clamped - 0.5) * 48.0;
      if (std::abs(st) < 0.05) {
        std::snprintf(display, size, "0 st");
      } else {
        std::snprintf(display, size, "%+.1f st", st);
      }
      return true;
    }
    default:
      std::snprintf(display, size, "%d %%", static_cast<int>(std::lround(clamped * 100.0)));
      return true;
  }
}

bool paramsTextToValue(const clap_plugin_t*, clap_id id, const char* display, double* value) {
  if (parameterIndex(id) >= ParameterSpecs.size() || display == nullptr || value == nullptr) {
    return false;
  }
  *value = clampParameter(std::strtod(display, nullptr) / 100.0);
  return true;
}

void paramsFlush(const clap_plugin_t* plugin, const clap_input_events_t* input,
                 const clap_output_events_t*) {
  if (input == nullptr) {
    return;
  }
  for (uint32_t index = 0; index < input->size(input); ++index) {
    handleEvent(self(plugin), input->get(input, index));
  }
}

const clap_plugin_params_t Params{paramsCount,       paramsGetInfo,     paramsGetValue,
                                  paramsValueToText, paramsTextToValue, paramsFlush};

uint32_t audioCount(const clap_plugin_t*, bool input) {
  return input ? 0U : 1U;
}

bool audioGet(const clap_plugin_t*, uint32_t index, bool input, clap_audio_port_info_t* info) {
  if (input || index != 0 || info == nullptr) {
    return false;
  }
  *info = {};
  info->id = 0;
  std::strncpy(info->name, "Main Output", sizeof(info->name) - 1);
  info->flags = CLAP_AUDIO_PORT_IS_MAIN;
  info->channel_count = 2;
  info->port_type = CLAP_PORT_STEREO;
  info->in_place_pair = CLAP_INVALID_ID;
  return true;
}

const clap_plugin_audio_ports_t AudioPorts{audioCount, audioGet};

uint32_t noteCount(const clap_plugin_t*, bool input) {
  return input ? 1U : 0U;
}

bool noteGet(const clap_plugin_t*, uint32_t index, bool input, clap_note_port_info_t* info) {
  if (!input || index != 0 || info == nullptr) {
    return false;
  }
  *info = {};
  info->id = 0;
  info->supported_dialects = CLAP_NOTE_DIALECT_CLAP | CLAP_NOTE_DIALECT_MIDI;
  info->preferred_dialect = CLAP_NOTE_DIALECT_CLAP;
  std::strncpy(info->name, "Piano", sizeof(info->name) - 1);
  return true;
}

const clap_plugin_note_ports_t NotePorts{noteCount, noteGet};

struct SavedStateHeader {
  uint32_t magic = 0x4f42504eU;
  uint32_t version = 2;
};

struct SavedState {
  uint32_t magic = 0x4f42504eU;
  uint32_t version = 2;
  std::array<double, ParameterSpecs.size()> values{};
};

bool writeAll(const clap_ostream_t* stream, const void* data, uint64_t size) {
  const auto* bytes = static_cast<const uint8_t*>(data);
  uint64_t offset = 0;
  while (offset < size) {
    const int64_t written = stream->write(stream, bytes + offset, size - offset);
    if (written <= 0) {
      return false;
    }
    offset += static_cast<uint64_t>(written);
  }
  return true;
}

bool readAll(const clap_istream_t* stream, void* data, uint64_t size) {
  auto* bytes = static_cast<uint8_t*>(data);
  uint64_t offset = 0;
  while (offset < size) {
    const int64_t read = stream->read(stream, bytes + offset, size - offset);
    if (read <= 0) {
      return false;
    }
    offset += static_cast<uint64_t>(read);
  }
  return true;
}

bool stateSave(const clap_plugin_t* plugin, const clap_ostream_t* stream) {
  SavedState state;
  for (size_t index = 0; index < ParameterSpecs.size(); ++index) {
    state.values[index] = self(plugin).engine.parameter(ParameterSpecs[index].id);
  }
  return writeAll(stream, &state, sizeof(state));
}

bool stateLoad(const clap_plugin_t* plugin, const clap_istream_t* stream) {
  SavedStateHeader header;
  if (!readAll(stream, &header, sizeof(header)) || header.magic != 0x4f42504eU) {
    return false;
  }
  if (header.version == 1) {
    std::array<double, 7> legacy_values{};
    if (!readAll(stream, legacy_values.data(), sizeof(legacy_values))) {
      return false;
    }
    for (size_t index = 0; index < legacy_values.size(); ++index) {
      self(plugin).engine.setParameter(ParameterSpecs[index].id, legacy_values[index]);
    }
    return true;
  }
  if (header.version == 2) {
    std::array<double, ParameterSpecs.size()> values{};
    if (!readAll(stream, values.data(), sizeof(values))) {
      return false;
    }
    for (size_t index = 0; index < ParameterSpecs.size(); ++index) {
      self(plugin).engine.setParameter(ParameterSpecs[index].id, values[index]);
    }
    return true;
  }
  return false;
}

const clap_plugin_state_t State{stateSave, stateLoad};

uint32_t latencyGet(const clap_plugin_t*) {
  return 0;
}
const clap_plugin_latency_t Latency{latencyGet};

uint32_t tailGet(const clap_plugin_t* plugin) {
  return static_cast<uint32_t>(self(plugin).engine.sampleRate() * 3.0);
}
const clap_plugin_tail_t Tail{tailGet};

const void* pluginExtension(const clap_plugin_t*, const char* id) {
  if (std::strcmp(id, CLAP_EXT_PARAMS) == 0) {
    return &Params;
  }
  if (std::strcmp(id, CLAP_EXT_AUDIO_PORTS) == 0) {
    return &AudioPorts;
  }
  if (std::strcmp(id, CLAP_EXT_NOTE_PORTS) == 0) {
    return &NotePorts;
  }
  if (std::strcmp(id, CLAP_EXT_STATE) == 0) {
    return &State;
  }
  if (std::strcmp(id, CLAP_EXT_LATENCY) == 0) {
    return &Latency;
  }
  if (std::strcmp(id, CLAP_EXT_TAIL) == 0) {
    return &Tail;
  }
  return nullptr;
}

void pluginMainThread(const clap_plugin_t*) {}

const char* Features[]{CLAP_PLUGIN_FEATURE_INSTRUMENT, CLAP_PLUGIN_FEATURE_SYNTHESIZER, "piano",
                       CLAP_PLUGIN_FEATURE_STEREO, nullptr};
const clap_plugin_descriptor_t Descriptor{
    CLAP_VERSION,
    "dev.onebeat.stock.piano",
    "OneBeat Piano",
    "OneBeat",
    "https://github.com/spix3l/onebeat",
    "",
    "",
    "0.2.0",
    "A responsive, sample-free stock piano for sketching ideas.",
    Features,
};

uint32_t factoryCount(const clap_plugin_factory_t*) {
  return 1;
}

const clap_plugin_descriptor_t* factoryDescriptor(const clap_plugin_factory_t*, uint32_t index) {
  return index == 0 ? &Descriptor : nullptr;
}

const clap_plugin_t* factoryCreate(const clap_plugin_factory_t*, const clap_host_t*,
                                   const char* id) {
  if (id == nullptr || std::strcmp(id, Descriptor.id) != 0) {
    return nullptr;
  }
  auto* piano = new (std::nothrow) PianoPlugin;
  if (piano == nullptr) {
    return nullptr;
  }
  piano->plugin.desc = &Descriptor;
  piano->plugin.plugin_data = piano;
  piano->plugin.init = pluginInit;
  piano->plugin.destroy = pluginDestroy;
  piano->plugin.activate = pluginActivate;
  piano->plugin.deactivate = pluginDeactivate;
  piano->plugin.start_processing = pluginStart;
  piano->plugin.stop_processing = pluginStop;
  piano->plugin.reset = pluginReset;
  piano->plugin.process = pluginProcess;
  piano->plugin.get_extension = pluginExtension;
  piano->plugin.on_main_thread = pluginMainThread;
  return &piano->plugin;
}

const clap_plugin_factory_t Factory{factoryCount, factoryDescriptor, factoryCreate};

bool entryInit(const char*) {
  return true;
}
void entryDeinit() {}
const void* entryFactory(const char* id) {
  return id != nullptr && std::strcmp(id, CLAP_PLUGIN_FACTORY_ID) == 0 ? &Factory : nullptr;
}

}  // namespace

extern "C" {
extern __attribute__((visibility("default"))) const clap_plugin_entry_t clap_entry;
const clap_plugin_entry_t clap_entry{CLAP_VERSION, entryInit, entryDeinit, entryFactory};
}
