// Public CLAP adapter for OneBeat Drill Synth. The DSP core is deliberately
// independent of CLAP so it can later be reused by the VST3 adapter.
#include "synth_engine.h"

#include <clap/clap.h>

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <new>

#ifndef OB_STOCK_PLUGIN_ID
#define OB_STOCK_PLUGIN_ID "dev.onebeat.stock.drill_synth"
#define OB_STOCK_PLUGIN_NAME "OneBeat Drill Synth"
#define OB_STOCK_NOTE_NAME "Drill Synth"
#define OB_STOCK_PLUGIN_DESCRIPTION "A sample-free subtractive synth voiced for dark drill melodies and sub bass."
#endif

namespace {

using onebeat::stock::synth::clampParameter;
using onebeat::stock::synth::parameterIndex;
using onebeat::stock::synth::ParameterSpecs;
using onebeat::stock::synth::PresetCount;
using onebeat::stock::synth::SynthEngine;

struct SynthPlugin {
  clap_plugin_t plugin{};
  SynthEngine engine;
};

SynthPlugin& self(const clap_plugin_t* plugin) {
  return *static_cast<SynthPlugin*>(plugin->plugin_data);
}

void handleEvent(SynthPlugin& synth, const clap_event_header_t* header) {
  if (header == nullptr || header->space_id != CLAP_CORE_EVENT_SPACE_ID) return;
  if (header->type == CLAP_EVENT_NOTE_ON) {
    const auto* note = reinterpret_cast<const clap_event_note_t*>(header);
    synth.engine.noteOn(note->note_id, note->channel, note->key, note->velocity);
  } else if (header->type == CLAP_EVENT_NOTE_OFF || header->type == CLAP_EVENT_NOTE_CHOKE) {
    const auto* note = reinterpret_cast<const clap_event_note_t*>(header);
    synth.engine.noteOff(note->note_id, note->channel, note->key,
                         header->type == CLAP_EVENT_NOTE_CHOKE);
  } else if (header->type == CLAP_EVENT_PARAM_VALUE) {
    const auto* event = reinterpret_cast<const clap_event_param_value_t*>(header);
    if (event->param_id == onebeat::stock::synth::ParamPreset) {
      synth.engine.selectPreset(event->value);
#ifdef OB_STOCK_ORGAN
      // Organ patches should release like a keyboard instrument, not inherit
      // the synth's long pad tail and delay feedback.
      synth.engine.setParameter(onebeat::stock::synth::ParamRelease, 0.18);
      synth.engine.setParameter(onebeat::stock::synth::ParamDelay, 0.0);
#endif
    } else {
      synth.engine.setParameter(event->param_id, event->value);
    }
  } else if (header->type == CLAP_EVENT_MIDI) {
    const auto* midi = reinterpret_cast<const clap_event_midi_t*>(header);
    const uint8_t status = midi->data[0] & 0xf0U;
    const int channel = midi->data[0] & 0x0fU;
    const int key = midi->data[1] & 0x7fU;
    const int velocity = midi->data[2] & 0x7fU;
    if (status == 0x90U && velocity > 0) {
      synth.engine.noteOn(-1, channel, key, static_cast<double>(velocity) / 127.0);
    } else if (status == 0x80U || (status == 0x90U && velocity == 0)) {
      synth.engine.noteOff(-1, channel, key, false);
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
  SynthPlugin& synth = self(plugin);
  if (process == nullptr || process->audio_outputs_count == 0 || process->audio_outputs[0].data32 == nullptr) {
    return CLAP_PROCESS_CONTINUE;
  }
  clap_audio_buffer_t& output = process->audio_outputs[0];
  if (output.channel_count == 0 || output.data32[0] == nullptr) return CLAP_PROCESS_CONTINUE;

  uint32_t cursor = 0;
  const uint32_t event_count =
      process->in_events == nullptr ? 0U : process->in_events->size(process->in_events);
  for (uint32_t index = 0; index < event_count; ++index) {
    const clap_event_header_t* event = process->in_events->get(process->in_events, index);
    if (event == nullptr) continue;
    const uint32_t event_time = std::min(event->time, process->frames_count);
    if (event_time > cursor) {
      synth.engine.render(output.data32, output.channel_count, cursor, event_time - cursor);
      cursor = event_time;
    }
    handleEvent(synth, event);
  }
  if (cursor < process->frames_count) {
    synth.engine.render(output.data32, output.channel_count, cursor,
                        process->frames_count - cursor);
  }
  return CLAP_PROCESS_CONTINUE;
}

uint32_t paramsCount(const clap_plugin_t*) {
  return static_cast<uint32_t>(ParameterSpecs.size());
}

bool paramsGetInfo(const clap_plugin_t*, uint32_t index, clap_param_info_t* info) {
  if (index >= ParameterSpecs.size() || info == nullptr) return false;
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
  if (parameterIndex(id) >= ParameterSpecs.size() || value == nullptr) return false;
  *value = self(plugin).engine.parameter(id);
  return true;
}

bool paramsValueToText(const clap_plugin_t*, clap_id id, double value, char* display,
                       uint32_t size) {
  if (parameterIndex(id) >= ParameterSpecs.size() || display == nullptr || size == 0) return false;
  const double clamped = clampParameter(value);
  if (id == onebeat::stock::synth::ParamPreset) {
    const uint32_t index = std::clamp(
        static_cast<uint32_t>(clamped * static_cast<double>(PresetCount)), 0U,
        static_cast<uint32_t>(PresetCount - 1));
    std::strncpy(display, onebeat::stock::synth::presetName(index), size - 1);
    display[size - 1] = '\0';
    return true;
  }
  if (id == onebeat::stock::synth::ParamCutoff) {
    const double hz = 35.0 * std::pow(520.0, clamped);
    std::snprintf(display, size, "%.0f Hz", hz);
    return true;
  }
  if (id == onebeat::stock::synth::ParamAttack || id == onebeat::stock::synth::ParamDecay) {
    const double seconds = id == onebeat::stock::synth::ParamAttack
                               ? 0.001 + clamped * clamped * 1.5
                               : 0.03 + clamped * clamped * 2.5;
    std::snprintf(display, size, "%.2f s", seconds);
    return true;
  }
  if (id == onebeat::stock::synth::ParamRelease) {
    std::snprintf(display, size, "%.2f s", 0.02 + clamped * clamped * 4.0);
    return true;
  }
  if (id == onebeat::stock::synth::ParamDetune) {
    std::snprintf(display, size, "%+.1f st", (clamped - 0.5) * 2.0);
    return true;
  }
  if (id == onebeat::stock::synth::ParamLfoRate) {
    std::snprintf(display, size, "%.1f Hz", 0.1 + clamped * 9.9);
    return true;
  }
  std::snprintf(display, size, "%d %%", static_cast<int>(std::lround(clamped * 100.0)));
  return true;
}

bool paramsTextToValue(const clap_plugin_t*, clap_id id, const char* text, double* value) {
  if (parameterIndex(id) >= ParameterSpecs.size() || text == nullptr || value == nullptr) return false;
  if (id == onebeat::stock::synth::ParamPreset) return false;
  *value = clampParameter(std::strtod(text, nullptr) / 100.0);
  return true;
}

void paramsFlush(const clap_plugin_t* plugin, const clap_input_events_t* input,
                 const clap_output_events_t*) {
  if (input == nullptr) return;
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
  if (input || index != 0 || info == nullptr) return false;
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
  if (!input || index != 0 || info == nullptr) return false;
  *info = {};
  info->id = 0;
  info->supported_dialects = CLAP_NOTE_DIALECT_CLAP | CLAP_NOTE_DIALECT_MIDI;
  info->preferred_dialect = CLAP_NOTE_DIALECT_CLAP;
  std::strncpy(info->name, OB_STOCK_NOTE_NAME, sizeof(info->name) - 1);
  return true;
}

const clap_plugin_note_ports_t NotePorts{noteCount, noteGet};

struct SavedStateHeader {
  uint32_t magic = 0x4f425359U;  // 'OBSY'
  uint32_t version = 1;
};

bool stateSave(const clap_plugin_t* plugin, const clap_ostream_t* stream) {
  if (stream == nullptr) return false;
  SavedStateHeader header{};
  if (stream->write(stream, &header, sizeof(header)) != static_cast<int64_t>(sizeof(header))) return false;
  const SynthEngine& synth = self(plugin).engine;
  for (const auto& spec : ParameterSpecs) {
    const double value = synth.parameter(spec.id);
    if (stream->write(stream, &value, sizeof(value)) != static_cast<int64_t>(sizeof(value))) return false;
  }
  return true;
}

bool stateLoad(const clap_plugin_t* plugin, const clap_istream_t* stream) {
  if (stream == nullptr) return false;
  SavedStateHeader header{};
  if (stream->read(stream, &header, sizeof(header)) != static_cast<int64_t>(sizeof(header)) ||
      header.magic != 0x4f425359U || header.version != 1U) {
    return false;
  }
  SynthEngine& synth = self(plugin).engine;
  for (const auto& spec : ParameterSpecs) {
    double value = 0.0;
    if (stream->read(stream, &value, sizeof(value)) != static_cast<int64_t>(sizeof(value))) return false;
    synth.setParameter(spec.id, value);
  }
  return true;
}

const clap_plugin_state_t State{stateSave, stateLoad};

const void* pluginExtension(const clap_plugin_t*, const char* id) {
  if (id == nullptr) return nullptr;
  if (std::strcmp(id, CLAP_EXT_PARAMS) == 0) return &Params;
  if (std::strcmp(id, CLAP_EXT_AUDIO_PORTS) == 0) return &AudioPorts;
  if (std::strcmp(id, CLAP_EXT_NOTE_PORTS) == 0) return &NotePorts;
  if (std::strcmp(id, CLAP_EXT_STATE) == 0) return &State;
  return nullptr;
}

void pluginMainThread(const clap_plugin_t*) {}

const char* Features[]{CLAP_PLUGIN_FEATURE_INSTRUMENT, CLAP_PLUGIN_FEATURE_SYNTHESIZER,
                       CLAP_PLUGIN_FEATURE_STEREO, nullptr};
const clap_plugin_descriptor_t Descriptor{
    CLAP_VERSION,
    OB_STOCK_PLUGIN_ID,
    OB_STOCK_PLUGIN_NAME,
    "OneBeat",
    "https://github.com/spix3l/onebeat",
    "",
    "",
    "0.3.0",
    OB_STOCK_PLUGIN_DESCRIPTION,
    Features,
};

uint32_t factoryCount(const clap_plugin_factory_t*) {
  return 1;
}

const clap_plugin_descriptor_t* factoryDescriptor(const clap_plugin_factory_t*, uint32_t index) {
  return index == 0 ? &Descriptor : nullptr;
}

const clap_plugin_t* factoryCreate(const clap_plugin_factory_t*, const clap_host_t*, const char* id) {
  if (id == nullptr || std::strcmp(id, Descriptor.id) != 0) return nullptr;
  auto* synth = new (std::nothrow) SynthPlugin;
  if (synth == nullptr) return nullptr;
  synth->plugin.desc = &Descriptor;
  synth->plugin.plugin_data = synth;
  synth->plugin.init = pluginInit;
  synth->plugin.destroy = pluginDestroy;
  synth->plugin.activate = pluginActivate;
  synth->plugin.deactivate = pluginDeactivate;
  synth->plugin.start_processing = pluginStart;
  synth->plugin.stop_processing = pluginStop;
  synth->plugin.reset = pluginReset;
  synth->plugin.process = pluginProcess;
  synth->plugin.get_extension = pluginExtension;
  synth->plugin.on_main_thread = pluginMainThread;
  return &synth->plugin;
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
