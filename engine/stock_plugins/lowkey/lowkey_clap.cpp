// Lowkey is the bass-facing stock instrument. It reuses the stable plucked
// string DSP core, tuned down one octave at the note boundary, while exposing
// a dedicated identity and bass-oriented editor in the host.
#include "../guitar/guitar_engine.h"

#include <clap/clap.h>

#include <algorithm>
#include <array>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <new>

namespace {
using onebeat::stock::guitar::clampParameter;
using onebeat::stock::guitar::GuitarEngine;
using onebeat::stock::guitar::parameterIndex;
using onebeat::stock::guitar::ParameterSpecs;

struct LowkeyPlugin {
  clap_plugin_t plugin{};
  GuitarEngine engine;
};
LowkeyPlugin& self(const clap_plugin_t* p) {
  return *static_cast<LowkeyPlugin*>(p->plugin_data);
}

void handleEvent(LowkeyPlugin& bass, const clap_event_header_t* header) {
  if (header == nullptr || header->space_id != CLAP_CORE_EVENT_SPACE_ID) return;
  if (header->type == CLAP_EVENT_NOTE_ON) {
    const auto* note = reinterpret_cast<const clap_event_note_t*>(header);
    bass.engine.noteOn(note->note_id, note->channel, std::max(0, note->key - 12), note->velocity);
  } else if (header->type == CLAP_EVENT_NOTE_OFF || header->type == CLAP_EVENT_NOTE_CHOKE) {
    const auto* note = reinterpret_cast<const clap_event_note_t*>(header);
    bass.engine.noteOff(note->note_id, note->channel, std::max(0, note->key - 12),
                        header->type == CLAP_EVENT_NOTE_CHOKE);
  } else if (header->type == CLAP_EVENT_PARAM_VALUE) {
    const auto* event = reinterpret_cast<const clap_event_param_value_t*>(header);
    bass.engine.setParameter(event->param_id, event->value);
  }
}

bool init(const clap_plugin_t*) {
  return true;
}
void destroy(const clap_plugin_t* p) {
  delete &self(p);
}
bool activate(const clap_plugin_t* p, double rate, uint32_t, uint32_t) {
  self(p).engine.setSampleRate(rate);
  return true;
}
void deactivate(const clap_plugin_t*) {}
bool start(const clap_plugin_t*) {
  return true;
}
void stop(const clap_plugin_t*) {}
void reset(const clap_plugin_t* p) {
  self(p).engine.reset();
}

clap_process_status process(const clap_plugin_t* p, const clap_process_t* process_info) {
  LowkeyPlugin& bass = self(p);
  if (process_info->audio_outputs_count == 0 || process_info->audio_outputs[0].data32 == nullptr)
    return CLAP_PROCESS_CONTINUE;
  clap_audio_buffer_t& output = process_info->audio_outputs[0];
  if (output.channel_count == 0 || output.data32[0] == nullptr) return CLAP_PROCESS_CONTINUE;
  uint32_t cursor = 0;
  const uint32_t count = process_info->in_events == nullptr
                             ? 0U
                             : process_info->in_events->size(process_info->in_events);
  for (uint32_t i = 0; i < count; ++i) {
    const clap_event_header_t* event = process_info->in_events->get(process_info->in_events, i);
    if (event == nullptr) continue;
    const uint32_t time = std::min(event->time, process_info->frames_count);
    if (time > cursor) {
      bass.engine.render(output.data32, output.channel_count, cursor, time - cursor);
      cursor = time;
    }
    handleEvent(bass, event);
  }
  if (cursor < process_info->frames_count)
    bass.engine.render(output.data32, output.channel_count, cursor,
                       process_info->frames_count - cursor);
  return CLAP_PROCESS_CONTINUE;
}

uint32_t paramsCount(const clap_plugin_t*) {
  return static_cast<uint32_t>(ParameterSpecs.size());
}
bool paramsInfo(const clap_plugin_t*, uint32_t index, clap_param_info_t* info) {
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
bool paramsValue(const clap_plugin_t* p, clap_id id, double* value) {
  if (parameterIndex(id) >= ParameterSpecs.size() || value == nullptr) return false;
  *value = self(p).engine.parameter(id);
  return true;
}
bool paramsText(const clap_plugin_t*, clap_id id, double value, char* display, uint32_t size) {
  if (parameterIndex(id) >= ParameterSpecs.size() || display == nullptr || size == 0) return false;
  if (id == onebeat::stock::guitar::ParamPreset) {
    static constexpr const char* names[] = {
        "Deep Pocket",   "Tape Sub",     "Picked Modern",     "Neon Fretless",
        "Grit Room",     "Synth Bass",   "Wide Chorus",       "808 Lowkey",
        "Moog Pressure", "Rubber Band",  "Dub Siren",         "Dark Cinema",
        "Slap Snap",     "Acid Low End", "Clean Fingerstyle", "Submarine"};
    const size_t index = std::min<size_t>(static_cast<size_t>(clampParameter(value) * 16.0), 15);
    std::strncpy(display, names[index], size - 1);
    display[size - 1] = '\0';
    return true;
  }
  std::snprintf(display, size, "%d %%", static_cast<int>(clampParameter(value) * 100.0));
  return true;
}
bool paramsFromText(const clap_plugin_t*, clap_id id, const char* text, double* value) {
  if (parameterIndex(id) >= ParameterSpecs.size() || text == nullptr || value == nullptr)
    return false;
  *value = clampParameter(std::strtod(text, nullptr) / 100.0);
  return true;
}
void paramsFlush(const clap_plugin_t* p, const clap_input_events_t* input,
                 const clap_output_events_t*) {
  if (input == nullptr) return;
  for (uint32_t i = 0; i < input->size(input); ++i) handleEvent(self(p), input->get(input, i));
}
const clap_plugin_params_t Params{paramsCount, paramsInfo,     paramsValue,
                                  paramsText,  paramsFromText, paramsFlush};

uint32_t audioCount(const clap_plugin_t*, bool input) {
  return input ? 0U : 1U;
}
bool audioInfo(const clap_plugin_t*, uint32_t index, bool input, clap_audio_port_info_t* info) {
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
const clap_plugin_audio_ports_t AudioPorts{audioCount, audioInfo};
uint32_t noteCount(const clap_plugin_t*, bool input) {
  return input ? 1U : 0U;
}
bool noteInfo(const clap_plugin_t*, uint32_t index, bool input, clap_note_port_info_t* info) {
  if (!input || index != 0 || info == nullptr) return false;
  *info = {};
  info->id = 0;
  info->supported_dialects = CLAP_NOTE_DIALECT_CLAP | CLAP_NOTE_DIALECT_MIDI;
  info->preferred_dialect = CLAP_NOTE_DIALECT_CLAP;
  std::strncpy(info->name, "Lowkey Bass", sizeof(info->name) - 1);
  return true;
}
const clap_plugin_note_ports_t NotePorts{noteCount, noteInfo};

// Without this extension the host has nothing to write into the project's
// `state/` sidecar, and every setting the user made on this lane comes back as
// the factory default the next time the project is opened. Same layout as the
// guitar's, under its own magic: the two share a DSP core but not a chunk.
struct SavedStateHeader {
  uint32_t magic = 0x4f424c4bU;  // 'OBLK'
  uint32_t version = 1;
};

bool stateSave(const clap_plugin_t* p, const clap_ostream_t* stream) {
  if (stream == nullptr) return false;
  SavedStateHeader header{};
  if (stream->write(stream, &header, sizeof(header)) != static_cast<int64_t>(sizeof(header))) {
    return false;
  }
  const auto& bass = self(p);
  for (const auto& spec : ParameterSpecs) {
    const double value = bass.engine.parameter(spec.id);
    if (stream->write(stream, &value, sizeof(value)) != static_cast<int64_t>(sizeof(value))) {
      return false;
    }
  }
  return true;
}

bool stateLoad(const clap_plugin_t* p, const clap_istream_t* stream) {
  if (stream == nullptr) return false;
  SavedStateHeader header{};
  if (stream->read(stream, &header, sizeof(header)) != static_cast<int64_t>(sizeof(header)) ||
      header.magic != 0x4f424c4bU) {
    return false;
  }
  auto& bass = self(p);
  for (const auto& spec : ParameterSpecs) {
    double value = 0.0;
    if (stream->read(stream, &value, sizeof(value)) != static_cast<int64_t>(sizeof(value))) {
      return false;
    }
    bass.engine.setParameter(spec.id, value);
  }
  return true;
}

const clap_plugin_state_t State{stateSave, stateLoad};

const void* extension(const clap_plugin_t*, const char* id) {
  if (std::strcmp(id, CLAP_EXT_PARAMS) == 0) return &Params;
  if (std::strcmp(id, CLAP_EXT_AUDIO_PORTS) == 0) return &AudioPorts;
  if (std::strcmp(id, CLAP_EXT_NOTE_PORTS) == 0) return &NotePorts;
  if (std::strcmp(id, CLAP_EXT_STATE) == 0) return &State;
  return nullptr;
}
const char* Features[]{CLAP_PLUGIN_FEATURE_INSTRUMENT, CLAP_PLUGIN_FEATURE_SYNTHESIZER, "bass",
                       CLAP_PLUGIN_FEATURE_STEREO, nullptr};
const clap_plugin_descriptor_t Descriptor{CLAP_VERSION,
                                          "dev.onebeat.stock.lowkey",
                                          "Lowkey",
                                          "OneBeat",
                                          "https://github.com/spix3l/onebeat",
                                          "",
                                          "",
                                          "0.2.0",
                                          "A deep, playable stock bass instrument.",
                                          Features};
uint32_t factoryCount(const clap_plugin_factory_t*) {
  return 1;
}
const clap_plugin_descriptor_t* factoryDescriptor(const clap_plugin_factory_t*, uint32_t index) {
  return index == 0 ? &Descriptor : nullptr;
}
const clap_plugin_t* factoryCreate(const clap_plugin_factory_t*, const clap_host_t*,
                                   const char* id) {
  if (id == nullptr || std::strcmp(id, Descriptor.id) != 0) return nullptr;
  auto* bass = new (std::nothrow) LowkeyPlugin;
  if (bass == nullptr) return nullptr;
  bass->plugin.desc = &Descriptor;
  bass->plugin.plugin_data = bass;
  bass->plugin.init = init;
  bass->plugin.destroy = destroy;
  bass->plugin.activate = activate;
  bass->plugin.deactivate = deactivate;
  bass->plugin.start_processing = start;
  bass->plugin.stop_processing = stop;
  bass->plugin.reset = reset;
  bass->plugin.process = process;
  bass->plugin.get_extension = extension;
  bass->plugin.on_main_thread = [](const clap_plugin_t*) {};
  return &bass->plugin;
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
