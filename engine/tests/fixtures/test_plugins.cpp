// Real CLAP fixtures used by scanning, hosting, state and containment tests.
#include <clap/clap.h>

#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <new>

#if defined(OB_TEST_PLUGIN_HANG) || defined(OB_TEST_PLUGIN_PROCESS_HANG)
#include <time.h>
#endif

#if defined(OB_TEST_PLUGIN_CRASH)
__attribute__((constructor)) void obTestCrashOnLoad() {
  volatile int* nowhere = nullptr;
  *nowhere = 1;
}
#elif defined(OB_TEST_PLUGIN_HANG)
__attribute__((constructor)) void obTestHangOnLoad() {
  while (true) {
    const timespec interval{1, 0};
    nanosleep(&interval, nullptr);
  }
}
#endif

namespace {

constexpr clap_id GainParam = 17;

struct TestPlugin {
  clap_plugin_t plugin{};
  double sample_rate = 48000.0;
  double gain = 0.5;
  double phase = 0.0;
  bool note_on = false;
};

TestPlugin& self(const clap_plugin_t* plugin) {
  return *static_cast<TestPlugin*>(plugin->plugin_data);
}

bool pluginInit(const clap_plugin_t*) {
  return true;
}
void pluginDestroy(const clap_plugin_t* plugin) {
  delete &self(plugin);
}
bool pluginActivate(const clap_plugin_t* plugin, double sample_rate, uint32_t, uint32_t) {
  self(plugin).sample_rate = sample_rate;
  return true;
}
void pluginDeactivate(const clap_plugin_t*) {}
bool pluginStart(const clap_plugin_t*) {
  return true;
}
void pluginStop(const clap_plugin_t*) {}
void pluginReset(const clap_plugin_t* plugin) {
  self(plugin).phase = 0.0;
  self(plugin).note_on = false;
}

clap_process_status pluginProcess(const clap_plugin_t* plugin, const clap_process_t* process) {
#if defined(OB_TEST_PLUGIN_PROCESS_CRASH)
  volatile int* nowhere = nullptr;
  *nowhere = 1;
#elif defined(OB_TEST_PLUGIN_PROCESS_HANG)
  while (true) {
    const timespec interval{1, 0};
    nanosleep(&interval, nullptr);
  }
#endif
  TestPlugin& instance = self(plugin);
  for (uint32_t index = 0; index < process->in_events->size(process->in_events); ++index) {
    const clap_event_header_t* header = process->in_events->get(process->in_events, index);
    if (header == nullptr || header->space_id != CLAP_CORE_EVENT_SPACE_ID) continue;
    if (header->type == CLAP_EVENT_NOTE_ON) instance.note_on = true;
    if (header->type == CLAP_EVENT_NOTE_OFF || header->type == CLAP_EVENT_NOTE_CHOKE) {
      instance.note_on = false;
    }
    if (header->type == CLAP_EVENT_PARAM_VALUE) {
      const auto* param = reinterpret_cast<const clap_event_param_value_t*>(header);
      if (param->param_id == GainParam) instance.gain = param->value;
    }
  }
  if (process->audio_outputs_count == 0) return CLAP_PROCESS_CONTINUE;
  clap_audio_buffer_t& output = process->audio_outputs[0];
  for (uint32_t frame = 0; frame < process->frames_count; ++frame) {
    const float sample = instance.note_on
                             ? static_cast<float>(std::sin(instance.phase) * instance.gain * 0.2)
                             : 0.0F;
    instance.phase += (440.0 * 6.283185307179586) / instance.sample_rate;
    for (uint32_t channel = 0; channel < output.channel_count; ++channel) {
      output.data32[channel][frame] = sample;
    }
  }
  return CLAP_PROCESS_CONTINUE;
}

uint32_t paramsCount(const clap_plugin_t*) {
  return 1;
}
bool paramsGetInfo(const clap_plugin_t*, uint32_t index, clap_param_info_t* info) {
  if (index != 0 || info == nullptr) return false;
  *info = {};
  info->id = GainParam;
  info->flags = CLAP_PARAM_IS_AUTOMATABLE | CLAP_PARAM_IS_MODULATABLE;
  std::strncpy(info->name, "Gain", sizeof(info->name) - 1);
  std::strncpy(info->module, "Output", sizeof(info->module) - 1);
  info->min_value = 0.0;
  info->max_value = 1.0;
  info->default_value = 0.5;
  return true;
}
bool paramsGetValue(const clap_plugin_t* plugin, clap_id id, double* value) {
  if (id != GainParam || value == nullptr) return false;
  *value = self(plugin).gain;
  return true;
}
bool paramsValueToText(const clap_plugin_t*, clap_id id, double value, char* display,
                       uint32_t size) {
  if (id != GainParam || display == nullptr || size == 0) return false;
  const int percent = static_cast<int>(value * 100.0);
  std::snprintf(display, size, "%d %%", percent);
  return true;
}
bool paramsTextToValue(const clap_plugin_t*, clap_id id, const char* display, double* value) {
  if (id != GainParam || display == nullptr || value == nullptr) return false;
  *value = std::strtod(display, nullptr) / 100.0;
  return true;
}
void paramsFlush(const clap_plugin_t* plugin, const clap_input_events_t* input,
                 const clap_output_events_t*) {
  for (uint32_t index = 0; index < input->size(input); ++index) {
    const clap_event_header_t* header = input->get(input, index);
    if (header != nullptr && header->type == CLAP_EVENT_PARAM_VALUE) {
      const auto* event = reinterpret_cast<const clap_event_param_value_t*>(header);
      if (event->param_id == GainParam) self(plugin).gain = event->value;
    }
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
  std::strncpy(info->name, "Main", sizeof(info->name) - 1);
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
  std::strncpy(info->name, "Notes", sizeof(info->name) - 1);
  return true;
}
const clap_plugin_note_ports_t NotePorts{noteCount, noteGet};

bool stateSave(const clap_plugin_t* plugin, const clap_ostream_t* stream) {
  const double value = self(plugin).gain;
  return stream->write(stream, &value, sizeof(value)) == static_cast<int64_t>(sizeof(value));
}
bool stateLoad(const clap_plugin_t* plugin, const clap_istream_t* stream) {
  double value = 0.0;
  if (stream->read(stream, &value, sizeof(value)) != static_cast<int64_t>(sizeof(value))) {
    return false;
  }
  self(plugin).gain = value;
  return true;
}
const clap_plugin_state_t State{stateSave, stateLoad};

uint32_t latencyGet(const clap_plugin_t*) {
  return 32;
}
const clap_plugin_latency_t Latency{latencyGet};

#if defined(OB_TEST_PLUGIN_GUI)
bool guiIsApiSupported(const clap_plugin_t*, const char* api, bool is_floating) {
  return !is_floating && api != nullptr && std::strcmp(api, CLAP_WINDOW_API_COCOA) == 0;
}
bool guiGetPreferredApi(const clap_plugin_t*, const char** api, bool* is_floating) {
  if (api == nullptr || is_floating == nullptr) return false;
  *api = CLAP_WINDOW_API_COCOA;
  *is_floating = false;
  return true;
}
bool guiCreate(const clap_plugin_t*, const char* api, bool is_floating) {
  return guiIsApiSupported(nullptr, api, is_floating);
}
void guiDestroy(const clap_plugin_t*) {}
bool guiSetScale(const clap_plugin_t*, double) {
  return false;
}
bool guiGetSize(const clap_plugin_t*, uint32_t* width, uint32_t* height) {
  if (width == nullptr || height == nullptr) return false;
  *width = 360;
  *height = 180;
  return true;
}
bool guiCanResize(const clap_plugin_t*) {
  return true;
}
bool guiGetResizeHints(const clap_plugin_t*, clap_gui_resize_hints_t*) {
  return false;
}
bool guiAdjustSize(const clap_plugin_t*, uint32_t*, uint32_t*) {
  return true;
}
bool guiSetSize(const clap_plugin_t*, uint32_t, uint32_t) {
  return true;
}
bool guiSetParent(const clap_plugin_t*, const clap_window_t* window) {
  return window != nullptr && window->cocoa != nullptr;
}
bool guiSetTransient(const clap_plugin_t*, const clap_window_t*) {
  return false;
}
void guiSuggestTitle(const clap_plugin_t*, const char*) {}
bool guiShow(const clap_plugin_t*) {
  return true;
}
bool guiHide(const clap_plugin_t*) {
  return true;
}
const clap_plugin_gui_t Gui{
    guiIsApiSupported, guiGetPreferredApi, guiCreate,         guiDestroy,    guiSetScale,
    guiGetSize,        guiCanResize,       guiGetResizeHints, guiAdjustSize, guiSetSize,
    guiSetParent,      guiSetTransient,    guiSuggestTitle,   guiShow,       guiHide};
#endif

const void* pluginExtension(const clap_plugin_t*, const char* id) {
  if (std::strcmp(id, CLAP_EXT_PARAMS) == 0) return &Params;
  if (std::strcmp(id, CLAP_EXT_AUDIO_PORTS) == 0) return &AudioPorts;
  if (std::strcmp(id, CLAP_EXT_NOTE_PORTS) == 0) return &NotePorts;
  if (std::strcmp(id, CLAP_EXT_STATE) == 0) return &State;
  if (std::strcmp(id, CLAP_EXT_LATENCY) == 0) return &Latency;
#if defined(OB_TEST_PLUGIN_GUI)
  if (std::strcmp(id, CLAP_EXT_GUI) == 0) return &Gui;
#endif
  return nullptr;
}
void pluginMainThread(const clap_plugin_t*) {}

const char* Features[]{CLAP_PLUGIN_FEATURE_INSTRUMENT, CLAP_PLUGIN_FEATURE_SYNTHESIZER,
                       CLAP_PLUGIN_FEATURE_STEREO, nullptr};
const clap_plugin_descriptor_t Descriptor{
    CLAP_VERSION,
    "dev.onebeat.test.synth",
    "OneBeat Test Synth",
    "OneBeat",
    "https://github.com/spix3l/onebeat",
    "",
    "",
    "1.0.0",
    "A deterministic CLAP fixture",
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
  if (id == nullptr || std::strcmp(id, Descriptor.id) != 0) return nullptr;
  auto* instance = new (std::nothrow) TestPlugin;
  if (instance == nullptr) return nullptr;
  instance->plugin.desc = &Descriptor;
  instance->plugin.plugin_data = instance;
  instance->plugin.init = pluginInit;
  instance->plugin.destroy = pluginDestroy;
  instance->plugin.activate = pluginActivate;
  instance->plugin.deactivate = pluginDeactivate;
  instance->plugin.start_processing = pluginStart;
  instance->plugin.stop_processing = pluginStop;
  instance->plugin.reset = pluginReset;
  instance->plugin.process = pluginProcess;
  instance->plugin.get_extension = pluginExtension;
  instance->plugin.on_main_thread = pluginMainThread;
  return &instance->plugin;
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
