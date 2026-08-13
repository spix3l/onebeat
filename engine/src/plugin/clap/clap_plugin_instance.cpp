#include "plugin/clap/clap_plugin_instance.h"

#include <dlfcn.h>

#include <algorithm>
#include <cstring>
#include <filesystem>

namespace onebeat::plugin::clap {
namespace {

constexpr uint32_t MaxEventsPerBlock = 4096;

using RtStartFn = bool(CLAP_ABI*)(const clap_plugin_t*) OB_NONBLOCKING;
using RtVoidFn = void(CLAP_ABI*)(const clap_plugin_t*) OB_NONBLOCKING;
using RtProcessFn = clap_process_status(CLAP_ABI*)(const clap_plugin_t*,
                                                   const clap_process_t*) OB_NONBLOCKING;
using RtTailFn = uint32_t(CLAP_ABI*)(const clap_plugin_t*) OB_NONBLOCKING;

std::string binaryInside(const std::string& bundle_path) {
  namespace fs = std::filesystem;
  std::error_code error;
  const fs::path path(bundle_path);
  if (!fs::is_directory(path, error)) {
    return bundle_path;
  }
  for (const fs::directory_entry& entry :
       fs::directory_iterator(path / "Contents" / "MacOS", error)) {
    if (!error && entry.is_regular_file(error)) {
      return entry.path().string();
    }
  }
  return {};
}

uint32_t inputSize(const clap_input_events_t* list) {
  const auto* self = static_cast<const ClapPluginInstance*>(list->ctx);
  return self->inputEventCount();
}

const clap_event_header_t* inputGet(const clap_input_events_t* list, uint32_t index) {
  const auto* self = static_cast<const ClapPluginInstance*>(list->ctx);
  return self->inputEventAt(index);
}

bool outputTryPush(const clap_output_events_t* list, const clap_event_header_t* event) {
  return static_cast<ClapPluginInstance*>(list->ctx)->pushOutputEvent(event);
}

int64_t streamWrite(const clap_ostream_t* stream, const void* buffer, uint64_t size) {
  auto* writer = static_cast<StateWriter*>(stream->ctx);
  return writer->write(buffer, static_cast<size_t>(size)) ? static_cast<int64_t>(size) : -1;
}

int64_t streamRead(const clap_istream_t* stream, void* buffer, uint64_t size) {
  auto* reader = static_cast<StateReader*>(stream->ctx);
  return static_cast<int64_t>(reader->read(buffer, static_cast<size_t>(size)));
}

void hostRestart(const clap_host_t* host) {
  ClapPluginInstance::fromHost(host).callbackHost()->requestRestart();
}
void hostProcess(const clap_host_t* host) {
  ClapPluginInstance::fromHost(host).callbackHost()->requestProcess();
}
void hostCallback(const clap_host_t* host) {
  ClapPluginInstance::fromHost(host).callbackHost()->requestCallback();
}

bool isMain(const clap_host_t*) {
  return ThreadCheck::onMainThread();
}
bool isAudio(const clap_host_t*) {
  return ThreadCheck::onAudioThread();
}
void paramsRescan(const clap_host_t* host, clap_param_rescan_flags flags) {
  ClapPluginInstance::fromHost(host).callbackHost()->paramsRescan(flags);
}
void paramsClear(const clap_host_t* host, clap_id id, clap_param_clear_flags flags) {
  ClapPluginInstance::fromHost(host).callbackHost()->paramsClear(id, flags);
}
void paramsRequestFlush(const clap_host_t* host) {
  ClapPluginInstance::fromHost(host).callbackHost()->requestProcess();
}
bool audioRescanSupported(const clap_host_t*, uint32_t) {
  return true;
}
void audioRescan(const clap_host_t* host, uint32_t flags) {
  ClapPluginInstance::fromHost(host).callbackHost()->audioPortsRescan(flags);
}
uint32_t noteDialects(const clap_host_t*) {
  return CLAP_NOTE_DIALECT_CLAP | CLAP_NOTE_DIALECT_MIDI | CLAP_NOTE_DIALECT_MIDI_MPE |
         CLAP_NOTE_DIALECT_MIDI2;
}
void noteRescan(const clap_host_t* host, uint32_t flags) {
  ClapPluginInstance::fromHost(host).callbackHost()->notePortsRescan(flags);
}
void latencyChanged(const clap_host_t* host) {
  ClapPluginInstance::fromHost(host).callbackHost()->latencyChanged();
}
void tailChanged(const clap_host_t* host) {
  ClapPluginInstance::fromHost(host).callbackHost()->tailChanged();
}
void stateDirty(const clap_host_t*) {}

const clap_host_thread_check_t HostThreadCheck{isMain, isAudio};
const clap_host_params_t HostParams{paramsRescan, paramsClear, paramsRequestFlush};
const clap_host_audio_ports_t HostAudioPorts{audioRescanSupported, audioRescan};
const clap_host_note_ports_t HostNotePorts{noteDialects, noteRescan};
const clap_host_latency_t HostLatency{latencyChanged};
const clap_host_tail_t HostTail{tailChanged};
const clap_host_state_t HostState{stateDirty};

const void* hostExtension(const clap_host_t*, const char* id) {
  if (std::strcmp(id, CLAP_EXT_THREAD_CHECK) == 0) return &HostThreadCheck;
  if (std::strcmp(id, CLAP_EXT_PARAMS) == 0) return &HostParams;
  if (std::strcmp(id, CLAP_EXT_AUDIO_PORTS) == 0) return &HostAudioPorts;
  if (std::strcmp(id, CLAP_EXT_NOTE_PORTS) == 0) return &HostNotePorts;
  if (std::strcmp(id, CLAP_EXT_LATENCY) == 0) return &HostLatency;
  if (std::strcmp(id, CLAP_EXT_TAIL) == 0) return &HostTail;
  if (std::strcmp(id, CLAP_EXT_STATE) == 0) return &HostState;
  return nullptr;
}

uint32_t clapFlags(uint16_t flags) {
  uint32_t result = 0;
  if ((flags & EventFlagIsLive) != 0U) result |= CLAP_EVENT_IS_LIVE;
  if ((flags & EventFlagDontRecord) != 0U) result |= CLAP_EVENT_DONT_RECORD;
  return result;
}

uint16_t onebeatFlags(uint32_t flags) {
  uint16_t result = EventFlagNone;
  if ((flags & CLAP_EVENT_IS_LIVE) != 0U) result |= EventFlagIsLive;
  if ((flags & CLAP_EVENT_DONT_RECORD) != 0U) result |= EventFlagDontRecord;
  return result;
}

clap_event_header_t header(uint32_t size, uint32_t time, uint16_t type, uint16_t flags) {
  return clap_event_header_t{size, time, CLAP_CORE_EVENT_SPACE_ID, type, clapFlags(flags)};
}

}  // namespace

std::unique_ptr<ClapPluginInstance> ClapPluginInstance::create(PluginHost* host,
                                                               const std::string& bundle_path,
                                                               const std::string& plugin_id,
                                                               std::string& error) {
  const std::string binary = binaryInside(bundle_path);
  if (binary.empty()) {
    error = "The CLAP bundle has no loadable binary.";
    return nullptr;
  }
  void* library = ::dlopen(binary.c_str(), RTLD_NOW | RTLD_LOCAL);
  if (library == nullptr) {
    const char* detail = ::dlerror();
    error = detail != nullptr ? detail : "dlopen failed.";
    return nullptr;
  }
  const auto* entry = static_cast<const clap_plugin_entry_t*>(::dlsym(library, "clap_entry"));
  if (entry == nullptr || !clap_version_is_compatible(entry->clap_version) ||
      entry->init == nullptr || !entry->init(bundle_path.c_str())) {
    error = "The bundle does not expose a compatible CLAP entry point.";
    ::dlclose(library);
    return nullptr;
  }
  const auto* factory = static_cast<const clap_plugin_factory_t*>(
      entry->get_factory != nullptr ? entry->get_factory(CLAP_PLUGIN_FACTORY_ID) : nullptr);
  if (factory == nullptr || factory->get_plugin_count(factory) == 0) {
    error = "The CLAP bundle contains no plug-ins.";
    entry->deinit();
    ::dlclose(library);
    return nullptr;
  }

  const clap_plugin_descriptor_t* descriptor = nullptr;
  for (uint32_t index = 0; index < factory->get_plugin_count(factory); ++index) {
    const clap_plugin_descriptor_t* candidate = factory->get_plugin_descriptor(factory, index);
    if (candidate != nullptr &&
        (plugin_id.empty() || (candidate->id != nullptr && plugin_id == candidate->id))) {
      descriptor = candidate;
      break;
    }
  }
  if (descriptor == nullptr) {
    error = "The requested CLAP plug-in is not in this bundle.";
    entry->deinit();
    ::dlclose(library);
    return nullptr;
  }

  auto instance = std::unique_ptr<ClapPluginInstance>(
      new ClapPluginInstance(host, bundle_path, library, entry, nullptr));
  const clap_plugin_t* plugin =
      factory->create_plugin(factory, &instance->clap_host_, descriptor->id);
  if (plugin == nullptr || plugin->init == nullptr || !plugin->init(plugin)) {
    error = "The CLAP plug-in could not be instantiated.";
    if (plugin != nullptr && plugin->destroy != nullptr) plugin->destroy(plugin);
    instance->entry_->deinit();
    instance->entry_ = nullptr;
    instance->library_ = nullptr;
    ::dlclose(library);
    return nullptr;
  }
  instance->plugin_ = plugin;
  instance->cacheExtensions();
  return instance;
}

ClapPluginInstance::ClapPluginInstance(PluginHost* host, std::string bundle_path, void* library,
                                       const clap_plugin_entry_t* entry,
                                       const clap_plugin_t* plugin)
    : PluginInstance(host),
      bundle_path_(std::move(bundle_path)),
      library_(library),
      entry_(entry),
      plugin_(plugin) {
  clap_host_.clap_version = CLAP_VERSION;
  clap_host_.host_data = this;
  clap_host_.name = "OneBeat";
  clap_host_.vendor = "OneBeat";
  clap_host_.url = "https://github.com/spix3l/onebeat";
  clap_host_.version = "0.2.0";
  clap_host_.get_extension = hostExtension;
  clap_host_.request_restart = hostRestart;
  clap_host_.request_process = hostProcess;
  clap_host_.request_callback = hostCallback;
  input_events_ = clap_input_events_t{this, inputSize, inputGet};
  output_events_ = clap_output_events_t{this, outputTryPush};
}

ClapPluginInstance::~ClapPluginInstance() {
  hideEditor();
  if (plugin_ != nullptr) {
    if (state() == State::Processing) stopProcessing();
    if (state() == State::Active) deactivate();
    plugin_->destroy(plugin_);
  }
  if (entry_ != nullptr) entry_->deinit();
  if (library_ != nullptr) ::dlclose(library_);
}

void ClapPluginInstance::cacheExtensions() {
  params_ =
      static_cast<const clap_plugin_params_t*>(plugin_->get_extension(plugin_, CLAP_EXT_PARAMS));
  state_ = static_cast<const clap_plugin_state_t*>(plugin_->get_extension(plugin_, CLAP_EXT_STATE));
  audio_ports_ = static_cast<const clap_plugin_audio_ports_t*>(
      plugin_->get_extension(plugin_, CLAP_EXT_AUDIO_PORTS));
  note_ports_ = static_cast<const clap_plugin_note_ports_t*>(
      plugin_->get_extension(plugin_, CLAP_EXT_NOTE_PORTS));
  latency_ =
      static_cast<const clap_plugin_latency_t*>(plugin_->get_extension(plugin_, CLAP_EXT_LATENCY));
  tail_ = static_cast<const clap_plugin_tail_t*>(plugin_->get_extension(plugin_, CLAP_EXT_TAIL));
  gui_ = static_cast<const clap_plugin_gui_t*>(plugin_->get_extension(plugin_, CLAP_EXT_GUI));
}

ClapPluginInstance& ClapPluginInstance::fromHost(const clap_host_t* host) noexcept {
  return *static_cast<ClapPluginInstance*>(host->host_data);
}

PluginName ClapPluginInstance::name() const {
  return PluginName(plugin_->desc != nullptr ? plugin_->desc->name : "CLAP plug-in");
}

bool ClapPluginInstance::onConfigure(const ProcessSetup&) {
  converted_inputs_.resize(MaxEventsPerBlock);
  input_headers_.resize(MaxEventsPerBlock);
  const uint32_t in_count = audioPortCount(PortDirection::Input);
  const uint32_t out_count = audioPortCount(PortDirection::Output);
  clap_inputs_.resize(in_count);
  clap_outputs_.resize(out_count);
  input_channels_.resize(in_count);
  output_channels_.resize(out_count);
  return true;
}

bool ClapPluginInstance::onActivate() {
  const ProcessSetup& configured = setup();
  return plugin_->activate(plugin_, configured.sample_rate, configured.min_block_frames,
                           configured.max_block_frames);
}
void ClapPluginInstance::onDeactivate() {
  plugin_->deactivate(plugin_);
}
bool ClapPluginInstance::onStartProcessing() noexcept OB_NONBLOCKING {
  return reinterpret_cast<RtStartFn>(plugin_->start_processing)(plugin_);
}
void ClapPluginInstance::onStopProcessing() noexcept OB_NONBLOCKING {
  reinterpret_cast<RtVoidFn>(plugin_->stop_processing)(plugin_);
}
void ClapPluginInstance::reset() noexcept OB_NONBLOCKING {
  reinterpret_cast<RtVoidFn>(plugin_->reset)(plugin_);
}

const clap_event_header_t* ClapPluginInstance::convertInput(
    const PluginEvent& event, ClapEventStorage& storage) noexcept OB_NONBLOCKING {
  switch (event.kind()) {
    case EventType::NoteOn:
    case EventType::NoteOff:
    case EventType::NoteChoke:
    case EventType::NoteEnd: {
      const uint16_t type = event.kind() == EventType::NoteOn      ? CLAP_EVENT_NOTE_ON
                            : event.kind() == EventType::NoteOff   ? CLAP_EVENT_NOTE_OFF
                            : event.kind() == EventType::NoteChoke ? CLAP_EVENT_NOTE_CHOKE
                                                                   : CLAP_EVENT_NOTE_END;
      storage.note = {header(sizeof(clap_event_note_t), event.time, type, event.flags),
                      event.note_id,
                      event.port_index,
                      event.channel,
                      event.key,
                      event.value()};
      return &storage.note.header;
    }
    case EventType::NoteExpression:
      storage.expression = {header(sizeof(clap_event_note_expression_t), event.time,
                                   CLAP_EVENT_NOTE_EXPRESSION, event.flags),
                            static_cast<int32_t>(event.id),
                            event.note_id,
                            event.port_index,
                            event.channel,
                            event.key,
                            event.value()};
      return &storage.expression.header;
    case EventType::ParamValue:
      storage.param_value = {
          header(sizeof(clap_event_param_value_t), event.time, CLAP_EVENT_PARAM_VALUE, event.flags),
          event.id,
          nullptr,
          event.note_id,
          event.port_index,
          event.channel,
          event.key,
          event.value()};
      return &storage.param_value.header;
    case EventType::ParamModulation:
      storage.param_mod = {
          header(sizeof(clap_event_param_mod_t), event.time, CLAP_EVENT_PARAM_MOD, event.flags),
          event.id,
          nullptr,
          event.note_id,
          event.port_index,
          event.channel,
          event.key,
          event.value()};
      return &storage.param_mod.header;
    case EventType::ParamGestureBegin:
    case EventType::ParamGestureEnd:
      storage.gesture = {
          header(sizeof(clap_event_param_gesture_t), event.time,
                 event.kind() == EventType::ParamGestureBegin ? CLAP_EVENT_PARAM_GESTURE_BEGIN
                                                              : CLAP_EVENT_PARAM_GESTURE_END,
                 event.flags),
          event.id};
      return &storage.gesture.header;
    case EventType::Midi1:
      storage.midi = {header(sizeof(clap_event_midi_t), event.time, CLAP_EVENT_MIDI, event.flags),
                      static_cast<uint16_t>(event.port_index),
                      {event.payload.midi1[0], event.payload.midi1[1], event.payload.midi1[2]}};
      return &storage.midi.header;
    case EventType::MidiSysex:
      storage.sysex = {
          header(sizeof(clap_event_midi_sysex_t), event.time, CLAP_EVENT_MIDI_SYSEX, event.flags),
          static_cast<uint16_t>(event.port_index), event.payload.sysex, event.id};
      return &storage.sysex.header;
    case EventType::Midi2:
      storage.midi2 = {
          header(sizeof(clap_event_midi2_t), event.time, CLAP_EVENT_MIDI2, event.flags),
          static_cast<uint16_t>(event.port_index),
          {event.payload.midi2[0], event.payload.midi2[1], event.payload.midi2[2],
           event.payload.midi2[3]}};
      return &storage.midi2.header;
    case EventType::None:
    case EventType::TransportDiscontinuity:
      return nullptr;
  }
  return nullptr;
}

void ClapPluginInstance::prepareInputEvents(const EventListView& input) noexcept OB_NONBLOCKING {
  input_header_count_ = 0;
  const uint32_t count = std::min(input.size(), static_cast<uint32_t>(converted_inputs_.size()));
  for (uint32_t index = 0; index < count; ++index) {
    if (const clap_event_header_t* converted =
            convertInput(input[index], converted_inputs_[index])) {
      input_headers_[input_header_count_++] = converted;
    }
  }
}

void ClapPluginInstance::prepareAudio(const ProcessBlock& block) noexcept OB_NONBLOCKING {
  for (size_t port = 0; port < clap_inputs_.size(); ++port) {
    const bool present = port < block.audio_input_count;
    const uint32_t channels =
        present ? static_cast<uint32_t>(block.audio_inputs[port].numChannels()) : 0;
    for (uint32_t channel = 0; channel < channels && channel < core::MaxChannels; ++channel) {
      input_channels_[port][channel] = block.audio_inputs[port].channel(static_cast<int>(channel));
    }
    clap_inputs_[port] = clap_audio_buffer_t{input_channels_[port].data(), nullptr, channels, 0, 0};
  }
  for (size_t port = 0; port < clap_outputs_.size(); ++port) {
    const bool present = port < block.audio_output_count;
    const uint32_t channels =
        present ? static_cast<uint32_t>(block.audio_outputs[port].numChannels()) : 0;
    for (uint32_t channel = 0; channel < channels && channel < core::MaxChannels; ++channel) {
      output_channels_[port][channel] =
          block.audio_outputs[port].channel(static_cast<int>(channel));
    }
    clap_outputs_[port] =
        clap_audio_buffer_t{output_channels_[port].data(), nullptr, channels, 0, 0};
  }
}

ProcessStatus ClapPluginInstance::process(const ProcessBlock& block) noexcept OB_NONBLOCKING {
  prepareInputEvents(block.in_events);
  prepareAudio(block);
  current_output_ = block.out_events;

  clap_event_transport_t transport{};
  transport.header = header(sizeof(transport), 0, CLAP_EVENT_TRANSPORT, 0);
  if (block.transport.is_playing) transport.flags |= CLAP_TRANSPORT_IS_PLAYING;
  if (block.transport.is_recording) transport.flags |= CLAP_TRANSPORT_IS_RECORDING;
  if (block.transport.is_loop_active) transport.flags |= CLAP_TRANSPORT_IS_LOOP_ACTIVE;
  transport.flags |= CLAP_TRANSPORT_HAS_TEMPO | CLAP_TRANSPORT_HAS_BEATS_TIMELINE |
                     CLAP_TRANSPORT_HAS_SECONDS_TIMELINE | CLAP_TRANSPORT_HAS_TIME_SIGNATURE;
  transport.tempo = block.transport.tempo_bpm;
  transport.song_pos_beats =
      static_cast<clap_beattime>(block.transport.position_beats * CLAP_BEATTIME_FACTOR);
  transport.song_pos_seconds =
      static_cast<clap_sectime>(block.transport.position_seconds * CLAP_SECTIME_FACTOR);
  transport.loop_start_beats =
      static_cast<clap_beattime>(block.transport.loop_start_beats * CLAP_BEATTIME_FACTOR);
  transport.loop_end_beats =
      static_cast<clap_beattime>(block.transport.loop_end_beats * CLAP_BEATTIME_FACTOR);
  transport.tsig_num = static_cast<uint16_t>(block.transport.time_signature_numerator);
  transport.tsig_denom = static_cast<uint16_t>(block.transport.time_signature_denominator);

  clap_process_t process{};
  process.steady_time = block.steady_time_frames;
  process.frames_count = block.frames;
  process.transport = block.transport.is_valid ? &transport : nullptr;
  process.audio_inputs = clap_inputs_.data();
  process.audio_outputs = clap_outputs_.data();
  process.audio_inputs_count = static_cast<uint32_t>(clap_inputs_.size());
  process.audio_outputs_count = static_cast<uint32_t>(clap_outputs_.size());
  process.in_events = &input_events_;
  process.out_events = &output_events_;
  const clap_process_status status =
      reinterpret_cast<RtProcessFn>(plugin_->process)(plugin_, &process);
  current_output_ = nullptr;
  return static_cast<ProcessStatus>(status);
}

bool ClapPluginInstance::collectOutput(const clap_event_header_t* event) noexcept OB_NONBLOCKING {
  if (current_output_ == nullptr || event == nullptr || event->space_id != CLAP_CORE_EVENT_SPACE_ID)
    return false;
  PluginEvent converted;
  const uint16_t flags = onebeatFlags(event->flags);
  switch (event->type) {
    case CLAP_EVENT_NOTE_ON:
    case CLAP_EVENT_NOTE_OFF:
    case CLAP_EVENT_NOTE_CHOKE:
    case CLAP_EVENT_NOTE_END: {
      const auto* note = reinterpret_cast<const clap_event_note_t*>(event);
      converted = event->type == CLAP_EVENT_NOTE_ON
                      ? PluginEvent::noteOn(event->time, note->key, note->velocity, note->note_id,
                                            note->channel, note->port_index)
                  : event->type == CLAP_EVENT_NOTE_OFF
                      ? PluginEvent::noteOff(event->time, note->key, note->velocity, note->note_id,
                                             note->channel, note->port_index)
                  : event->type == CLAP_EVENT_NOTE_CHOKE
                      ? PluginEvent::noteChoke(event->time, note->key, note->note_id, note->channel,
                                               note->port_index)
                      : PluginEvent::noteEnd(event->time, note->key, note->note_id, note->channel,
                                             note->port_index);
      break;
    }
    case CLAP_EVENT_NOTE_EXPRESSION: {
      const auto* expression = reinterpret_cast<const clap_event_note_expression_t*>(event);
      converted = PluginEvent::noteExpression(
          event->time, static_cast<NoteExpressionId>(expression->expression_id), expression->value,
          expression->note_id, expression->key, expression->channel, expression->port_index);
      break;
    }
    case CLAP_EVENT_PARAM_VALUE: {
      const auto* param = reinterpret_cast<const clap_event_param_value_t*>(event);
      converted = PluginEvent::paramValue(event->time, param->param_id, param->value, flags);
      converted.note_id = param->note_id;
      converted.port_index = param->port_index;
      converted.channel = param->channel;
      converted.key = param->key;
      break;
    }
    case CLAP_EVENT_PARAM_MOD: {
      const auto* param = reinterpret_cast<const clap_event_param_mod_t*>(event);
      converted =
          PluginEvent::paramModulation(event->time, param->param_id, param->amount, param->note_id,
                                       param->key, param->channel, param->port_index);
      converted.flags = flags;
      break;
    }
    case CLAP_EVENT_PARAM_GESTURE_BEGIN:
    case CLAP_EVENT_PARAM_GESTURE_END: {
      const auto* gesture = reinterpret_cast<const clap_event_param_gesture_t*>(event);
      converted = PluginEvent::paramGesture(event->time, gesture->param_id,
                                            event->type == CLAP_EVENT_PARAM_GESTURE_BEGIN);
      converted.flags = flags;
      break;
    }
    default:
      return true;
  }
  return current_output_->push(converted);
}

uint32_t ClapPluginInstance::paramCount() const {
  return params_ != nullptr ? params_->count(plugin_) : 0;
}
bool ClapPluginInstance::paramInfo(uint32_t index, ParamInfo& out) const {
  if (params_ == nullptr) return false;
  clap_param_info_t info{};
  if (!params_->get_info(plugin_, index, &info)) return false;
  out.id = info.id;
  out.flags = info.flags;
  out.cookie = info.cookie;
  out.name.assign(info.name);
  out.module.assign(info.module);
  out.min_value = info.min_value;
  out.max_value = info.max_value;
  out.default_value = info.default_value;
  return true;
}
bool ClapPluginInstance::paramValue(ParamId param, double& out) const {
  return params_ != nullptr && params_->get_value(plugin_, param, &out);
}
bool ClapPluginInstance::paramValueToText(ParamId param, double value, char* out,
                                          size_t out_size) const {
  return params_ != nullptr &&
         params_->value_to_text(plugin_, param, value, out, static_cast<uint32_t>(out_size));
}
bool ClapPluginInstance::paramTextToValue(ParamId param, const char* text, double& out) const {
  return params_ != nullptr && params_->text_to_value(plugin_, param, text, &out);
}
void ClapPluginInstance::paramsFlush(const EventListView& in, EventList* out) {
  if (params_ == nullptr) return;
  prepareInputEvents(in);
  current_output_ = out;
  params_->flush(plugin_, &input_events_, &output_events_);
  current_output_ = nullptr;
}

uint32_t ClapPluginInstance::audioPortCount(PortDirection direction) const {
  return audio_ports_ != nullptr ? audio_ports_->count(plugin_, direction == PortDirection::Input)
                                 : 0;
}
bool ClapPluginInstance::audioPortInfo(PortDirection direction, uint32_t index,
                                       AudioPortInfo& out) const {
  if (audio_ports_ == nullptr) return false;
  clap_audio_port_info_t info{};
  if (!audio_ports_->get(plugin_, index, direction == PortDirection::Input, &info)) return false;
  out.id = info.id;
  out.name.assign(info.name);
  out.channel_count = info.channel_count;
  out.layout = info.port_type != nullptr && std::strcmp(info.port_type, CLAP_PORT_MONO) == 0
                   ? ChannelLayout::Mono
               : info.port_type != nullptr && std::strcmp(info.port_type, CLAP_PORT_STEREO) == 0
                   ? ChannelLayout::Stereo
                   : ChannelLayout::Unspecified;
  out.is_main = (info.flags & CLAP_AUDIO_PORT_IS_MAIN) != 0U;
  out.supports_in_place = info.in_place_pair != CLAP_INVALID_ID;
  out.in_place_pair = info.in_place_pair;
  return true;
}
uint32_t ClapPluginInstance::notePortCount(PortDirection direction) const {
  return note_ports_ != nullptr ? note_ports_->count(plugin_, direction == PortDirection::Input)
                                : 0;
}
bool ClapPluginInstance::notePortInfo(PortDirection direction, uint32_t index,
                                      NotePortInfo& out) const {
  if (note_ports_ == nullptr) return false;
  clap_note_port_info_t info{};
  if (!note_ports_->get(plugin_, index, direction == PortDirection::Input, &info)) return false;
  out.id = info.id;
  out.name.assign(info.name);
  out.supported_dialects = info.supported_dialects;
  out.preferred_dialect = static_cast<NoteDialect>(info.preferred_dialect);
  return true;
}

bool ClapPluginInstance::saveState(StateWriter& writer) const {
  if (state_ == nullptr) return true;
  const clap_ostream_t stream{&writer, streamWrite};
  return state_->save(plugin_, &stream);
}
bool ClapPluginInstance::loadState(StateReader& reader) {
  if (state_ == nullptr) return true;
  const clap_istream_t stream{&reader, streamRead};
  return state_->load(plugin_, &stream);
}
void ClapPluginInstance::onMainThread() {
  plugin_->on_main_thread(plugin_);
}
uint32_t ClapPluginInstance::latencyFrames() const {
  return latency_ != nullptr ? latency_->get(plugin_) : 0;
}
uint32_t ClapPluginInstance::tailFrames() const noexcept OB_NONBLOCKING {
  return tail_ != nullptr ? reinterpret_cast<RtTailFn>(tail_->get)(plugin_) : 0;
}

}  // namespace onebeat::plugin::clap
