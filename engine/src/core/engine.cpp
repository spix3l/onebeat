#include "core/engine.h"

#include <algorithm>
#include <cmath>
#include <cstring>

#include "core/wav_loader.h"
#include "plugin/missing_plugin.h"
#include "plugin/sandbox/sandboxed_plugin_proxy.h"
#include "plugin/state.h"

namespace onebeat::core {
namespace {

constexpr int SnapshotVersion = OB_SNAPSHOT_VERSION;

void copyText(char* destination, size_t capacity, const std::string& source) {
  const size_t length = std::min(source.size(), capacity - 1);
  std::memcpy(destination, source.data(), length);
  destination[length] = '\0';
}

uint64_t samplePathHash(const std::string& path) {
  if (path.empty()) return 0;
  uint64_t hash = 0xCBF29CE484222325ULL;
  for (const char character : path) {
    hash ^= static_cast<unsigned char>(character);
    hash *= 0x100000001B3ULL;
  }
  return hash;
}

}  // namespace

// --------------------------------------------------------------------------
// SnapshotSlot
// --------------------------------------------------------------------------

void SnapshotSlot::write(const ob_snapshot& snapshot) noexcept OB_NONBLOCKING {
  uint64_t words[WordCount];
  std::memcpy(words, &snapshot, sizeof(snapshot));

  const uint32_t start = sequence_.load(std::memory_order_relaxed);
  sequence_.store(start + 1, std::memory_order_release);  // odd: write in progress
  for (size_t index = 0; index < WordCount; ++index) {
    words_[index].store(words[index], std::memory_order_relaxed);
  }
  sequence_.store(start + 2, std::memory_order_release);  // even: consistent
}

bool SnapshotSlot::read(ob_snapshot& out) const noexcept OB_NONBLOCKING {
  // Bounded retries: a reader must never spin unboundedly behind a writer that
  // has been descheduled. Six attempts is far beyond what a 350 Hz writer and a
  // 120 Hz reader can collide on; failing returns the caller's previous value.
  for (int attempt = 0; attempt < 6; ++attempt) {
    const uint32_t before = sequence_.load(std::memory_order_acquire);
    if (before == 0) {
      return false;  // nothing has ever been published; the caller keeps its value
    }
    if ((before & 1U) != 0U) {
      continue;
    }
    uint64_t words[WordCount];
    for (size_t index = 0; index < WordCount; ++index) {
      words[index] = words_[index].load(std::memory_order_relaxed);
    }
    const uint32_t after = sequence_.load(std::memory_order_acquire);
    if (before == after) {
      std::memcpy(&out, words, sizeof(out));
      return true;
    }
  }
  return false;
}

// --------------------------------------------------------------------------
// Engine
// --------------------------------------------------------------------------

Engine::Engine(EngineConfig config) : config_(std::move(config)) {
  // Every slot exists from construction. Adding a channel later then costs a
  // flag and a sample load, never an allocation the audio thread could race.
  for (auto& channel : channels_) {
    channel = std::make_unique<Channel>(&host_bridge_, &rt_log_);
  }
  preview_channel_ = std::make_unique<Channel>(&host_bridge_, &rt_log_);
  preview_channel_->active.store(true, std::memory_order_release);
  // Slot 0 is the engine's voice when there is no project rack at all: the
  // audition path, the v0.1 behaviour, and every test that loads one sample.
  channels_[0]->active.store(true, std::memory_order_release);
}

plugin::PluginInstance& Engine::channelInstrument(int index) noexcept OB_NONBLOCKING {
  const std::unique_ptr<plugin::PluginInstance>& hosted = hosted_[static_cast<size_t>(index)];
  if (hosted != nullptr) return *hosted;
  return channels_[static_cast<size_t>(index)]->instrument;
}

const plugin::PluginInstance& Engine::channelInstrument(int index) const noexcept OB_NONBLOCKING {
  const std::unique_ptr<plugin::PluginInstance>& hosted = hosted_[static_cast<size_t>(index)];
  if (hosted != nullptr) return *hosted;
  return channels_[static_cast<size_t>(index)]->instrument;
}

Engine::~Engine() {
  stop();
  housekeeping_active_.store(false, std::memory_order_release);
  work_signal_.notify_all();
  if (housekeeping_.joinable()) {
    housekeeping_.join();
  }
  device_.reset();
  diagnostics_.clearRunningMarker();
  diagnostics_.close();
}

bool Engine::initialise(std::string& error) {
  diagnostics_.open(config_.log_directory);
  diagnostics_.installCrashHandler();
  diagnostics_.writeRunningMarker();

  device_ = config_.use_null_device
                ? audio_io::createNullAudioDevice(config_.free_running_null_device)
                : audio_io::createPlatformAudioDevice();
  device_->setRenderCallback(this);
  device_->setNotificationCallback(
      [this](audio_io::DeviceNotification notification, const std::string& detail) {
        onDeviceNotification(notification, detail);
      });

  audio_io::StreamFormat requested;
  requested.sample_rate = config_.sample_rate;
  requested.block_frames = config_.block_frames;
  audio_io::StreamFormat granted;
  if (!device_->open(requested, granted, error)) {
    diagnostics_.log(LogLevel::Error, "audio", error);
    return false;
  }

  config_.sample_rate = granted.sample_rate;
  config_.block_frames = granted.block_frames;

  plugin::ThreadCheck::enterMainThread();
  transport_.prepare(granted.sample_rate, 120.0);

  // Every audio-thread allocation the instrument will ever need happens inside
  // configure(); after activate() returns, the RT path is allocation-free.
  plugin::ProcessSetup setup;
  setup.sample_rate = granted.sample_rate;
  setup.max_block_frames = static_cast<uint32_t>(granted.block_frames);
  setup.is_offline = config_.use_null_device;
  // Every channel, not just the ones in use: a slot activated later would have
  // to allocate, and the thread that would add it is the one holding the model.
  for (auto& channel : channels_) {
    if (!channel->instrument.configure(setup) || !channel->instrument.activate()) {
      error = "The built-in instrument could not be configured for this device format.";
      diagnostics_.log(LogLevel::Error, "plugin", error);
      return false;
    }
  }
  if (!preview_channel_->instrument.configure(setup) || !preview_channel_->instrument.activate()) {
    error = "The sample preview instrument could not be configured for this device format.";
    diagnostics_.log(LogLevel::Error, "plugin", error);
    return false;
  }

  // One channel's worth of interleaved-by-plane stereo scratch.
  channel_scratch_.assign(static_cast<size_t>(granted.block_frames) * MaxChannels, 0.0F);

  // Sized for the worst honest case rather than the typical one: the command
  // ring holds 1024 entries, and a block can in principle carry a schedule event
  // on every frame. Overflow is counted and logged, never grown.
  command_events_.reserve(CommandQueueCapacity);
  chunk_events_.reserve(CommandQueueCapacity + static_cast<uint32_t>(granted.block_frames) * 2U);

  // An empty schedule, so the audio thread never sees a null pointer.
  ScheduleBuilder builder;
  publishSchedule(builder.setLengthFrames(0).build(granted.sample_rate, 0));

  latency_frames_output_ = device_->outputLatencyFrames();
  latency_frames_roundtrip_ = device_->roundTripLatencyFrames();

  // Prime the snapshot before anything can read it.
  publishSnapshot(ProcessContext{}, 0);

  diagnostics_.logf(LogLevel::Info, "audio", "device '%s' open at %.0f Hz, %d frames, latency %d",
                    device_->deviceName().c_str(), granted.sample_rate, granted.block_frames,
                    device_->roundTripLatencyFrames());

  housekeeping_active_.store(true, std::memory_order_release);
  housekeeping_ = std::thread([this] { housekeepingLoop(); });
  return true;
}

bool Engine::start(std::string& error) {
  if (device_ == nullptr) {
    error = "The engine has not been initialised.";
    return false;
  }
  if (!device_->start(error)) {
    diagnostics_.log(LogLevel::Error, "audio", error);
    return false;
  }
  running_.store(true, std::memory_order_release);
  rt_log_.log(rt::LogLevel::Info, rt::RtMessage::CallbackStarted,
              static_cast<int64_t>(config_.sample_rate), config_.block_frames);
  return true;
}

void Engine::stop() {
  if (!running_.exchange(false)) {
    return;
  }
  if (device_ != nullptr) {
    device_->stop();
  }
}

bool Engine::isRunning() const {
  return running_.load(std::memory_order_acquire);
}

std::string Engine::deviceName() const {
  return device_ != nullptr ? device_->deviceName() : std::string("No device");
}

namespace {

bool isRackChannel(int channel) noexcept {
  return channel >= 0 && channel < MaxRackChannels;
}

}  // namespace

bool Engine::installHostedInstrument(std::unique_ptr<plugin::PluginInstance> instance, int channel,
                                     std::string& error) {
  if (instance == nullptr) {
    error = "The hosted plug-in instance is missing.";
    return false;
  }
  if (!isRackChannel(channel)) {
    error = "The channel the plug-in was loaded onto does not exist.";
    return false;
  }
  plugin::ProcessSetup setup;
  setup.sample_rate = config_.sample_rate;
  setup.max_block_frames = static_cast<uint32_t>(config_.block_frames);
  setup.is_offline = config_.use_null_device;
  if (!instance->configure(setup) || !instance->activate()) {
    error = "The hosted plug-in could not be configured for the active audio device.";
    return false;
  }

  const bool resume = isRunning();
  if (resume) stop();
  std::unique_ptr<plugin::PluginInstance>& slot = hosted_[static_cast<size_t>(channel)];
  if (slot != nullptr) slot->deactivate();
  // The hosted voice takes over the channel its own instrument owns, and only
  // that one: the lanes either side keep the samplers they were given.
  slot = std::move(instance);
  channels_[static_cast<size_t>(channel)]->active.store(true, std::memory_order_release);
  if (resume && !start(error)) return false;
  return true;
}

bool Engine::restoreBuiltinInstrument(int channel, std::string& error) {
  if (!isRackChannel(channel) || hosted_[static_cast<size_t>(channel)] == nullptr) return true;
  const bool resume = isRunning();
  if (resume) stop();
  std::unique_ptr<plugin::PluginInstance>& slot = hosted_[static_cast<size_t>(channel)];
  slot->deactivate();
  slot.reset();
  if (resume && !start(error)) return false;
  return true;
}

bool Engine::hasHostedInstrument(int channel) const noexcept {
  return isRackChannel(channel) && hosted_[static_cast<size_t>(channel)] != nullptr;
}

bool Engine::remapHostedInstruments(const std::vector<int>& destination, std::string& error) {
  bool moves_anything = false;
  for (size_t channel = 0; channel < destination.size() && channel < hosted_.size(); ++channel) {
    if (hosted_[channel] == nullptr) continue;
    if (destination[channel] != static_cast<int>(channel)) moves_anything = true;
  }
  // Channels past the end of the mapping keep what they hold: a caller that
  // describes only the rack's first N lanes is not asking to silence the rest.
  if (!moves_anything) return true;

  const bool resume = isRunning();
  if (resume) stop();
  std::array<std::unique_ptr<plugin::PluginInstance>, MaxRackChannels> moved;
  for (size_t channel = 0; channel < hosted_.size(); ++channel) {
    if (hosted_[channel] == nullptr) continue;
    const int target =
        channel < destination.size() ? destination[channel] : static_cast<int>(channel);
    if (!isRackChannel(target)) {
      // Dropped: the instrument that owned this plug-in is gone.
      hosted_[channel]->deactivate();
      hosted_[channel].reset();
      continue;
    }
    moved[static_cast<size_t>(target)] = std::move(hosted_[channel]);
  }
  hosted_ = std::move(moved);
  for (size_t channel = 0; channel < hosted_.size(); ++channel) {
    if (hosted_[channel] != nullptr) {
      channels_[channel]->active.store(true, std::memory_order_release);
    }
  }
  if (resume && !start(error)) return false;
  return true;
}

bool Engine::createSandboxedInstrument(const std::string& bundle_path, const std::string& plugin_id,
                                       const std::string& helper_path, int channel,
                                       std::string& error) {
  auto instance = std::make_unique<plugin::sandbox::SandboxedPluginProxy>(
      &host_bridge_, bundle_path, plugin_id, helper_path);
  return installHostedInstrument(std::move(instance), channel, error);
}

bool Engine::installMissingInstrument(const std::string& name, const std::vector<uint8_t>& state,
                                      int channel, std::string& error) {
  return installHostedInstrument(
      std::make_unique<plugin::MissingPlugin>(&host_bridge_, name, state), channel, error);
}

plugin::PluginInstance* Engine::hostedAt(int channel) const noexcept {
  return isRackChannel(channel) ? hosted_[static_cast<size_t>(channel)].get() : nullptr;
}

uint32_t Engine::hostedParamCount(int channel) const {
  const plugin::PluginInstance* hosted = hostedAt(channel);
  return hosted != nullptr ? hosted->paramCount() : 0;
}

bool Engine::hostedParamInfo(int channel, uint32_t index, plugin::ParamInfo& out) const {
  const plugin::PluginInstance* hosted = hostedAt(channel);
  return hosted != nullptr && hosted->paramInfo(index, out);
}

bool Engine::hostedParamValue(int channel, plugin::ParamId param, double& out) const {
  const plugin::PluginInstance* hosted = hostedAt(channel);
  return hosted != nullptr && hosted->paramValue(param, out);
}

bool Engine::saveHostedState(int channel, std::vector<uint8_t>& out) const {
  const plugin::PluginInstance* hosted = hostedAt(channel);
  if (hosted == nullptr) return false;
  plugin::MemoryStateWriter writer;
  if (!hosted->saveState(writer)) return false;
  out = writer.bytes();
  return true;
}

std::string Engine::hostedError(int channel) const {
  const auto* proxy = dynamic_cast<const plugin::sandbox::SandboxedPluginProxy*>(hostedAt(channel));
  return proxy != nullptr ? proxy->lastError() : std::string();
}

bool Engine::loadHostedState(int channel, const std::vector<uint8_t>& bytes) {
  plugin::PluginInstance* hosted = hostedAt(channel);
  if (hosted == nullptr) return false;
  plugin::MemoryStateReader reader(bytes);
  return hosted->loadState(reader);
}

bool Engine::hostedHasEditor(int channel) const {
  const auto* proxy = dynamic_cast<const plugin::sandbox::SandboxedPluginProxy*>(hostedAt(channel));
  return proxy != nullptr && proxy->hasEditor();
}

bool Engine::hostedHealthy(int channel) const {
  const auto* proxy = dynamic_cast<const plugin::sandbox::SandboxedPluginProxy*>(hostedAt(channel));
  return proxy == nullptr || proxy->healthy();
}

bool Engine::restartHostedInstrument(int channel) {
  auto* proxy = dynamic_cast<plugin::sandbox::SandboxedPluginProxy*>(hostedAt(channel));
  return proxy != nullptr && proxy->restartHost();
}

bool Engine::openHostedEditor(int channel) {
  auto* proxy = dynamic_cast<plugin::sandbox::SandboxedPluginProxy*>(hostedAt(channel));
  return proxy != nullptr && proxy->openEditor();
}

void Engine::closeHostedEditor(int channel) {
  auto* proxy = dynamic_cast<plugin::sandbox::SandboxedPluginProxy*>(hostedAt(channel));
  if (proxy != nullptr) proxy->closeEditor();
}

// --------------------------------------------------------------------------
// Audio thread
// --------------------------------------------------------------------------

void Engine::renderAudio(const audio_io::RenderBlock& block) noexcept OB_NONBLOCKING {
  ProcessContext context;
  context.output =
      AudioBufferView(block.outputs, std::min(block.num_channels, MaxChannels), block.num_frames);
  context.num_frames = block.num_frames;
  context.host_time_ns = block.host_time_ns;
  context.stream_time_frames = block.stream_time_frames;
  process(context);
}

void Engine::process(const ProcessContext& context) noexcept OB_NONBLOCKING {
  // Claims the audio-thread role for the duration of the call, so every
  // `[audio-thread]` assertion below this point is checked and every
  // `[main-thread]` one trips. The offline driver calls process() from an
  // ordinary thread and gets the same discipline for free.
  plugin::ThreadCheck::enterAudioThread();
  const uint64_t started_ns = rt::monotonicNanos();

  // Exactly one epoch tick per block on every publisher the audio thread reads:
  // reclamation correctness depends on it (rt/publisher.h). The instrument gets
  // one tick per *callback*, not per process() call — a callback split at a loop
  // seam is still one block.
  schedule_.beginBlock();
  for (int index = 0; index < MaxRackChannels; ++index) {
    Channel& channel = *channels_[static_cast<size_t>(index)];
    if (!channel.active.load(std::memory_order_acquire)) continue;
    channelInstrument(index).beginAudioBlock();
  }
  preview_channel_->instrument.beginAudioBlock();

  plugin::EventList block_events = command_events_.list();
  drainCommands(block_events);

  const AudioBufferView& output = context.output;
  output.clear();

  if (transport_.playing()) {
    runSchedule(output, 0, context.num_frames, block_events);
  } else {
    // Stopped: no schedule, but manual note commands still sound (FR-ENG-06's
    // audition path), so the block's command events still go to the instrument.
    processChunk(output, 0, context.num_frames, nullptr, 0, &block_events);
  }

  // Master gain and metering in one pass.
  float peak_left = 0.0F;
  float peak_right = 0.0F;
  double sum_left = 0.0;
  double sum_right = 0.0;
  // Channel gain and pan have already been applied per channel, on the way into
  // the mix (renderChannel). What is left here is the master.
  const float left_gain = master_gain_;
  const float right_gain = master_gain_;
  const int channels = output.numChannels();
  for (int frame = 0; frame < context.num_frames; ++frame) {
    const float left = output.channel(0)[frame] * left_gain;
    output.channel(0)[frame] = left;
    peak_left = std::max(peak_left, std::abs(left));
    sum_left += static_cast<double>(left) * static_cast<double>(left);
    if (channels > 1) {
      const float right = output.channel(1)[frame] * right_gain;
      output.channel(1)[frame] = right;
      peak_right = std::max(peak_right, std::abs(right));
      sum_right += static_cast<double>(right) * static_cast<double>(right);
    }
  }
  if (channels <= 1) {
    peak_right = peak_left;
    sum_right = sum_left;
  }
  peak_left_ = peak_left;
  peak_right_ = peak_right;

  if (context.num_frames > 0) {
    rms_left_ = static_cast<float>(std::sqrt(sum_left / context.num_frames));
    rms_right_ = static_cast<float>(std::sqrt(sum_right / context.num_frames));
  }

  const uint64_t render_nanos = rt::monotonicNanos() - started_ns;
  ++callback_count_;
  publishSnapshot(context, render_nanos);
  // Released rather than left set, so the offline driver's caller — an ordinary
  // thread that will go on to make main-thread calls — is not stuck holding the
  // audio role and tripping the opposite assertion.
  plugin::ThreadCheck::leaveAudioThread();
}

void Engine::processChunk(const AudioBufferView& output, int offset, int num_frames,
                          const Schedule* schedule, int64_t chunk_start,
                          const plugin::EventList* block_events) noexcept OB_NONBLOCKING {
  if (num_frames <= 0) {
    return;
  }

  // Consumed once for the whole chunk and then broadcast to every channel: a
  // loop seam releases the entire rack, not whichever channel happened to be
  // rendered first.
  const bool release_all = pending_all_notes_off_;
  pending_all_notes_off_ = false;

  // Tempo is the *host's* clock, not any channel's: applied once for the chunk,
  // before anything renders and before the transport advances, which is exactly
  // where the single-instrument engine applied it.
  if (schedule != nullptr) {
    const int32_t event_count = schedule->eventCount();
    const ScheduleEvent* schedule_events = schedule->events();
    const int64_t chunk_end = chunk_start + num_frames;
    for (int32_t cursor = schedule->lowerBound(chunk_start);
         cursor < event_count && schedule_events[cursor].frame < chunk_end; ++cursor) {
      if (static_cast<EventType>(schedule_events[cursor].type) == EventType::TempoChange) {
        transport_.setTempo(static_cast<double>(schedule_events[cursor].value));
      }
    }
  }

  int32_t voices = 0;
  for (int index = 0; index < MaxRackChannels; ++index) {
    Channel& channel = *channels_[static_cast<size_t>(index)];
    if (!channel.active.load(std::memory_order_acquire)) continue;
    renderChannel(channel, static_cast<InstrumentId>(index), output, offset, num_frames, schedule,
                  chunk_start, block_events, release_all, channelInstrument(index));
    voices += channelInstrument(index).activeVoiceCount();
  }
  renderChannel(*preview_channel_, 0, output, offset, num_frames, nullptr, chunk_start,
                block_events, release_all, preview_channel_->instrument, true);
  voices += preview_channel_->instrument.activeVoiceCount();
  renderMetronome(output, offset, num_frames, chunk_start);
  active_voices_ = voices;
}

// One channel. Its events are the schedule events addressed to it, plus the
// block's commands when it is the audition channel — a manual note belongs to
// the channel the user has selected, not to all of them at once. Renders into
// the shared scratch buffer and mixes the result into `output`, so a channel
// never sees, and cannot overwrite, what the channels before it produced.
void Engine::renderChannel(Channel& channel, InstrumentId index, const AudioBufferView& output,
                           int offset, int num_frames, const Schedule* schedule,
                           int64_t chunk_start, const plugin::EventList* block_events,
                           bool release_all, plugin::PluginInstance& instrument,
                           bool preview_voice) noexcept OB_NONBLOCKING {
  plugin::EventList events = chunk_events_.list();

  if (channel.reset_requested.exchange(false, std::memory_order_acq_rel)) {
    // Only the moved/removed channel is released. This keeps a newly added
    // second song from interrupting the first song that is already sounding.
    events.push(plugin::PluginEvent::allNotesOff(0));
  }
  if (!channel.one_shot.load(std::memory_order_acquire)) {
    channel.deferred_audio_start = false;
  }

  // A loop wrap that landed on the previous block boundary releases here, before
  // anything else, so it still precedes every note this chunk starts.
  if (release_all) {
    events.push(plugin::PluginEvent::allNotesOff(0));
  }

  // Commands first, at frame 0 — they were drained before the block rendered,
  // and the stable sort below keeps them ahead of any schedule event at 0.
  // Transport-wide releases (stop, seek) are broadcast to every channel;
  // auditioned notes and parameter edits belong to the selected channel only,
  // or every lane would sound whenever the user pressed a key.
  const bool is_audition =
      static_cast<int>(index) == audition_channel_.load(std::memory_order_acquire);
  if (block_events != nullptr) {
    for (uint32_t i = 0; i < block_events->size(); ++i) {
      const plugin::PluginEvent& event = (*block_events)[i];
      const bool is_broadcast_release =
          event.type == static_cast<uint16_t>(plugin::EventType::NoteOff) &&
          event.key == plugin::AnyKey;
      const bool is_preview = (event.flags & plugin::EventFlagDontRecord) != 0;
      if (is_broadcast_release || (is_preview ? preview_voice : (!preview_voice && is_audition))) {
        events.push(event);
      }
    }
  }

  if (!preview_voice && schedule != nullptr) {
    const int32_t event_count = schedule->eventCount();
    const ScheduleEvent* schedule_events = schedule->events();
    const int64_t chunk_end = chunk_start + num_frames;
    const bool one_shot = channel.one_shot.load(std::memory_order_acquire);
    const bool sample_ready = !one_shot || channel.sample_ready.load(std::memory_order_acquire);
    bool scheduled_audio_start = false;
    for (int32_t cursor = schedule->lowerBound(chunk_start);
         cursor < event_count && schedule_events[cursor].frame < chunk_end; ++cursor) {
      const ScheduleEvent& event = schedule_events[cursor];
      // The whole point of the rack: an event belongs to exactly one channel.
      if (event.instrument != index) continue;
      const EventType type = static_cast<EventType>(event.type);
      if (one_shot && !sample_ready) {
        if (type == EventType::AudioStart) {
          // The worker may finish decoding after the one-shot's timeline event
          // has passed. Remember it and start from frame zero when ready.
          channel.deferred_audio_start = true;
        }
        continue;
      }
      const auto time = static_cast<uint32_t>(event.frame - chunk_start);
      switch (type) {
        case EventType::NoteOn:
          events.push(
              plugin::PluginEvent::noteOn(time, event.note, static_cast<double>(event.value)));
          break;
        case EventType::AudioStart:
          // Audio clips are one-shot samples; MIDI C3 is the sampler's neutral
          // rate and the voice ends when the decoded source reaches EOF.
          events.push(plugin::PluginEvent::noteOn(time, Sampler::RootNote,
                                                  static_cast<double>(event.value)));
          scheduled_audio_start = true;
          break;
        case EventType::NoteOff:
          events.push(plugin::PluginEvent::noteOff(time, event.note));
          break;
        case EventType::TempoChange:
          break;  // host clock, applied once per chunk in processChunk
        case EventType::ParamValue:
          events.push(plugin::PluginEvent::paramValue(time, event.reserved,
                                                      static_cast<double>(event.value)));
          break;
        case EventType::ParamModulation:
          events.push(plugin::PluginEvent::paramModulation(time, event.reserved,
                                                           static_cast<double>(event.value)));
          break;
      }
    }
    if (one_shot && sample_ready && channel.deferred_audio_start && !scheduled_audio_start) {
      events.push(plugin::PluginEvent::noteOn(0, Sampler::RootNote, 1.0));
      channel.deferred_audio_start = false;
    } else if (scheduled_audio_start) {
      channel.deferred_audio_start = false;
    }
  }

  events.sortByTime();
  if (events.overflowCount() > 0) {
    rt_log_.log(rt::LogLevel::Warn, rt::RtMessage::EventListFull,
                static_cast<int64_t>(events.overflowCount()),
                static_cast<int64_t>(events.capacity()));
  }

  // The channel renders into scratch rather than straight into the master, so
  // its gain and pan can be applied on the way in and so each channel starts
  // from silence instead of from the previous channel's output. Stack storage
  // for the plane pointers, no allocation: the scratch itself was sized at
  // initialise() for the device's largest block.
  const int channels = std::min(output.numChannels(), MaxChannels);
  const auto stride = static_cast<size_t>(config_.block_frames);
  float* slice[MaxChannels] = {nullptr, nullptr};
  for (int plane = 0; plane < channels; ++plane) {
    slice[plane] = channel_scratch_.data() + (static_cast<size_t>(plane) * stride);
  }
  const AudioBufferView port(slice, channels, num_frames);
  port.clear();

  plugin::ProcessBlock block;
  block.frames = static_cast<uint32_t>(num_frames);
  block.audio_outputs = &port;
  block.audio_output_count = 1;
  block.in_events = events.view();
  block.steady_time_frames = static_cast<int64_t>(callback_count_);

  plugin::TransportInfo& transport = block.transport;
  transport.is_valid = true;
  transport.is_playing = transport_.playing();
  transport.is_loop_active = transport_.loopEnabled();
  transport.tempo_bpm = transport_.tempo();
  transport.position_frames = chunk_start;
  transport.position_beats = transport_.timeMap().framesToBeats(chunk_start);
  transport.position_seconds = transport_.timeMap().framesToSeconds(chunk_start);
  transport.loop_start_beats = transport_.loopStartBeats();
  transport.loop_end_beats = transport_.loopEndBeats();

  const plugin::ProcessStatus status = instrument.process(block);
  if (status == plugin::ProcessStatus::Error) {
    rt_log_.log(rt::LogLevel::Error, rt::RtMessage::InstrumentProcessFailed,
                static_cast<int64_t>(index), 0);
  }

  // Mix into the master with this channel's level. Muting is a gain of zero
  // taken here rather than a skipped render, so a muted channel's voices still
  // advance and unmuting does not resurrect a note from where it left off.
  const float gain = channel.muted.load(std::memory_order_acquire)
                         ? 0.0F
                         : channel.gain.load(std::memory_order_acquire);
  if (gain == 0.0F) return;
  // Constant-power balance: pan == 0 is centred, +1 hard right, -1 hard left.
  const float pan = channel.pan.load(std::memory_order_acquire);
  const float left_gain = gain * (pan > 0.0F ? 1.0F - pan : 1.0F);
  const float right_gain = gain * (pan < 0.0F ? 1.0F + pan : 1.0F);

  float* out_left = output.channel(0) + offset;
  const float* in_left = port.channel(0);
  if (channels > 1) {
    float* out_right = output.channel(1) + offset;
    const float* in_right = port.channel(1);
    for (int frame = 0; frame < num_frames; ++frame) {
      out_left[frame] += in_left[frame] * left_gain;
      out_right[frame] += in_right[frame] * right_gain;
    }
  } else {
    for (int frame = 0; frame < num_frames; ++frame) {
      out_left[frame] += in_left[frame] * left_gain;
    }
  }
}

void Engine::renderMetronome(const AudioBufferView& output, int offset, int num_frames,
                             int64_t chunk_start) noexcept OB_NONBLOCKING {
  if (!metronome_enabled_ || !transport_.playing() || output.numChannels() <= 0) return;

  const double sample_rate = config_.sample_rate;
  const double frames_per_beat = transport_.timeMap().framesPerBeat();
  constexpr int ClickFrames = 720;
  constexpr float NormalLevel = 0.22F;
  constexpr float AccentLevel = 0.34F;
  constexpr double NormalFrequency = 1200.0;
  constexpr double AccentFrequency = 1800.0;
  constexpr double Pi = 3.14159265358979323846;

  for (int frame = 0; frame < num_frames; ++frame) {
    const int64_t position = chunk_start + frame;
    const int64_t beat_number =
        static_cast<int64_t>(std::floor(static_cast<double>(position) / frames_per_beat));
    const int64_t beat_start =
        static_cast<int64_t>(std::llround(static_cast<double>(beat_number) * frames_per_beat));
    const int64_t since_beat = position - beat_start;
    if (since_beat < 0 || since_beat >= ClickFrames) continue;

    const bool accent = (beat_number % 4) == 0;
    const double frequency = accent ? AccentFrequency : NormalFrequency;
    const float level = accent ? AccentLevel : NormalLevel;
    const float envelope = std::exp(-static_cast<float>(since_beat) / 180.0F);
    const float sample = level * envelope *
                         static_cast<float>(std::sin(
                             2.0 * Pi * frequency * static_cast<double>(since_beat) / sample_rate));
    output.channel(0)[offset + frame] += sample;
    if (output.numChannels() > 1) output.channel(1)[offset + frame] += sample;
  }
}

void Engine::runSchedule(const AudioBufferView& output, int block_offset, int num_frames,
                         const plugin::EventList& block_events) noexcept OB_NONBLOCKING {
  const Schedule* schedule = schedule_.acquire();
  int64_t remaining = num_frames;
  int offset = block_offset;
  int wrap_guard = 0;
  bool first_chunk = true;

  while (remaining > 0) {
    const int64_t chunk = transport_.framesUntilLoopWrap(remaining);
    if (chunk <= 0) {
      // Loop wrap: release sounding voices so nothing hangs across the seam,
      // then jump back to the loop start sample-accurately. The release rides
      // into the next chunk as a wildcarded note-off at frame 0 — the same
      // instant, expressed in the model's vocabulary instead of a direct call.
      pending_all_notes_off_ = true;
      transport_.seekFrames(transport_.loopStartFrames());
      if (++wrap_guard > 8) {
        break;  // degenerate loop region; do not spin on the audio thread
      }
      continue;
    }
    wrap_guard = 0;

    processChunk(output, offset, static_cast<int>(chunk), schedule, transport_.positionFrames(),
                 first_chunk ? &block_events : nullptr);
    first_chunk = false;

    transport_.advance(chunk);
    // Wrap as soon as the loop end is reached rather than at the top of the
    // next block, so the reported position is never momentarily past the end.
    if (transport_.loopEnabled() && transport_.positionFrames() >= transport_.loopEndFrames()) {
      pending_all_notes_off_ = true;
      transport_.seekFrames(transport_.loopStartFrames());
    }
    offset += static_cast<int>(chunk);
    remaining -= chunk;
  }
}

void Engine::drainCommands(plugin::EventList& block_events) noexcept OB_NONBLOCKING {
  ob_command command{};
  int drained = 0;
  // Bounded: a runaway producer must not extend the block indefinitely.
  while (drained < 256 && commands_.tryPop(command)) {
    applyCommand(command, block_events);
    ++drained;
  }
}

void Engine::applyCommand(const ob_command& command,
                          plugin::EventList& block_events) noexcept OB_NONBLOCKING {
  last_command_generation_ = command.generation;
  switch (static_cast<ob_command_type>(command.type)) {
    case OB_CMD_TRANSPORT_PLAY:
      transport_.play();
      rt_log_.log(rt::LogLevel::Info, rt::RtMessage::TransportStateChanged, 1,
                  transport_.positionFrames());
      break;
    case OB_CMD_TRANSPORT_STOP:
      transport_.stop();
      block_events.push(plugin::PluginEvent::allNotesOff(0));
      rt_log_.log(rt::LogLevel::Info, rt::RtMessage::TransportStateChanged, 0,
                  transport_.positionFrames());
      break;
    case OB_CMD_TRANSPORT_SEEK_FRAMES:
      block_events.push(plugin::PluginEvent::allNotesOff(0));  // click-safe seek
      transport_.seekFrames(command.i64_a);
      break;
    case OB_CMD_TRANSPORT_SEEK_BEATS:
      block_events.push(plugin::PluginEvent::allNotesOff(0));
      transport_.seekBeats(command.f64_a);
      break;
    case OB_CMD_SET_TEMPO:
      transport_.setTempo(command.f64_a);
      break;
    case OB_CMD_SET_LOOP:
      transport_.setLoop(command.f64_a, command.f64_b, command.i64_a != 0);
      break;
    case OB_CMD_SET_METRONOME:
      metronome_enabled_ = command.i64_a != 0;
      break;
    case OB_CMD_NOTE_ON:
      block_events.push(
          plugin::PluginEvent::noteOn(0, static_cast<int16_t>(command.i64_a), command.f64_a));
      break;
    case OB_CMD_NOTE_OFF:
      block_events.push(plugin::PluginEvent::noteOff(0, static_cast<int16_t>(command.i64_a)));
      break;
    case OB_CMD_PREVIEW_NOTE_ON: {
      plugin::PluginEvent event =
          plugin::PluginEvent::noteOn(0, static_cast<int16_t>(command.i64_a), command.f64_a);
      event.flags = plugin::EventFlagDontRecord;
      block_events.push(event);
      break;
    }
    case OB_CMD_PREVIEW_NOTE_OFF: {
      plugin::PluginEvent event =
          plugin::PluginEvent::noteOff(0, static_cast<int16_t>(command.i64_a));
      event.flags = plugin::EventFlagDontRecord;
      block_events.push(event);
      break;
    }
    case OB_CMD_ALL_NOTES_OFF:
      block_events.push(plugin::PluginEvent::allNotesOff(0));
      break;
    case OB_CMD_SET_MASTER_GAIN:
      master_gain_ = std::clamp(static_cast<float>(command.f64_a), 0.0F, 2.0F);
      break;
    case OB_CMD_SET_INSTRUMENT_GAIN:
      channels_[static_cast<size_t>(audition_channel_.load(std::memory_order_acquire))]->gain.store(
          std::clamp(static_cast<float>(command.f64_a), 0.0F, 2.0F), std::memory_order_release);
      break;
    case OB_CMD_SET_INSTRUMENT_PAN:
      channels_[static_cast<size_t>(audition_channel_.load(std::memory_order_acquire))]->pan.store(
          std::clamp(static_cast<float>(command.f64_a), -1.0F, 1.0F), std::memory_order_release);
      break;
    case OB_CMD_PLUGIN_PARAM_BEGIN:
      block_events.push(
          plugin::PluginEvent::paramGesture(0, static_cast<uint32_t>(command.i64_a), true));
      break;
    case OB_CMD_PLUGIN_PARAM_VALUE:
      block_events.push(plugin::PluginEvent::paramValue(0, static_cast<uint32_t>(command.i64_a),
                                                        command.f64_a, plugin::EventFlagIsLive));
      break;
    case OB_CMD_PLUGIN_PARAM_END:
      block_events.push(
          plugin::PluginEvent::paramGesture(0, static_cast<uint32_t>(command.i64_a), false));
      break;
    case OB_CMD_NONE:
      break;
  }
}

void Engine::publishSnapshot(const ProcessContext& context,
                             uint64_t render_nanos) noexcept OB_NONBLOCKING {
  // A zero-frame context is the priming publish from initialise(): the UI must
  // find a valid snapshot (tempo, rate, latency) before the first callback runs.
  const int frames = context.num_frames > 0 ? context.num_frames : config_.block_frames;
  const double budget_nanos = (static_cast<double>(frames) / config_.sample_rate) * 1.0e9;
  const auto load = static_cast<float>(static_cast<double>(render_nanos) / budget_nanos);
  // One-pole smoothing so the UI shows a usable number rather than block noise.
  cpu_load_ = (cpu_load_ * 0.9F) + (load * 0.1F);

  // An xrun is a *device* underrun: the callback missed a deadline the hardware
  // was holding it to. An offline render has no device and no deadline — it runs
  // as fast as the machine allows — so comparing its wall-clock render time
  // against a real-time budget measures the scheduler, not the engine. On a
  // shared CI runner a render thread can lose 3 ms to descheduling with nothing
  // wrong, which is exactly how this counter produced an intermittent failure in
  // the Release stress test. FR-ENG-06 makes offline share the *processing*
  // path; it does not give it a deadline to miss.
  const bool has_deadline = !config_.use_null_device;
  if (has_deadline && render_nanos > 0 && static_cast<double>(render_nanos) > budget_nanos) {
    const uint64_t total = xruns_.fetch_add(1, std::memory_order_relaxed) + 1;
    rt_log_.log(rt::LogLevel::Warn, rt::RtMessage::Xrun, static_cast<int64_t>(render_nanos),
                static_cast<int64_t>(budget_nanos));
    ob_event event{};
    event.type = OB_EVT_XRUN;
    event.i64_a = static_cast<int64_t>(total);
    events_.tryPush(event);
  }

  const Schedule* schedule = schedule_.acquire();
  const MusicalPosition musical = transport_.musicalPosition();

  ob_snapshot snapshot{};
  snapshot.struct_version = SnapshotVersion;
  snapshot.struct_size = static_cast<uint32_t>(sizeof(ob_snapshot));
  snapshot.playing = transport_.playing() ? 1U : 0U;
  snapshot.loop_enabled = transport_.loopEnabled() ? 1U : 0U;
  snapshot.position_frames = transport_.positionFrames();
  snapshot.host_time_ns = context.host_time_ns != 0 ? context.host_time_ns : rt::monotonicNanos();
  snapshot.callback_count = callback_count_;
  snapshot.xrun_count = xruns_.load(std::memory_order_relaxed);
  snapshot.dropped_log_records = rt_log_.droppedCount();
  snapshot.last_command_generation = last_command_generation_;
  snapshot.position_beats = transport_.timeMap().framesToBeats(transport_.positionFrames());
  snapshot.position_seconds = transport_.timeMap().framesToSeconds(transport_.positionFrames());
  snapshot.tempo_bpm = transport_.tempo();
  snapshot.loop_start_beats = transport_.loopStartBeats();
  snapshot.loop_end_beats = transport_.loopEndBeats();
  snapshot.sample_rate = config_.sample_rate;
  snapshot.bar = musical.bar;
  snapshot.beat = musical.beat;
  snapshot.tick = musical.tick;
  snapshot.block_frames = frames;
  snapshot.active_voices = active_voices_;
  // Latency is cached off the audio thread (device queries are virtual calls
  // into the backend and are not RT-safe); it only changes when the device does.
  snapshot.latency_frames_output = latency_frames_output_;
  snapshot.latency_frames_roundtrip = latency_frames_roundtrip_;
  snapshot.schedule_event_count = schedule != nullptr ? schedule->eventCount() : 0;
  snapshot.peak_left = peak_left_;
  snapshot.peak_right = peak_right_;
  snapshot.rms_left = rms_left_;
  snapshot.rms_right = rms_right_;
  snapshot.cpu_load = cpu_load_;
  snapshot.master_gain = master_gain_;
  snapshot_.write(snapshot);
}

// --------------------------------------------------------------------------
// UI thread
// --------------------------------------------------------------------------

bool Engine::postCommand(const ob_command& command) noexcept {
  if (commands_.tryPush(command)) {
    return true;
  }
  rt_log_.log(rt::LogLevel::Warn, rt::RtMessage::CommandQueueFull, command.type, 0);
  return false;
}

void Engine::readSnapshot(ob_snapshot& out) const noexcept {
  snapshot_.read(out);
}

bool Engine::pollEvent(ob_event& out) noexcept {
  return events_.tryPop(out);
}

bool Engine::pushEvent(const ob_event& event) noexcept {
  return events_.tryPush(event);
}

// --------------------------------------------------------------------------
// Worker side
// --------------------------------------------------------------------------

// One 64-bit fingerprint per channel over the events addressed to it, compared
// against the schedule published before this one. Frames are part of the
// fingerprint, so a tempo change — which moves every event — reads as a change
// on every channel, which is what it is.
void Engine::releaseChannelsWhoseEventsChanged(const Schedule& schedule) {
  std::array<uint64_t, MaxRackChannels> hash{};
  for (auto& value : hash) value = 0xcbf29ce484222325ULL;  // FNV-1a offset basis

  const int32_t count = schedule.eventCount();
  const ScheduleEvent* events = schedule.events();
  for (int32_t index = 0; index < count; ++index) {
    const ScheduleEvent& event = events[index];
    if (event.instrument >= static_cast<InstrumentId>(MaxRackChannels)) continue;
    uint64_t& value = hash[static_cast<size_t>(event.instrument)];
    const auto mix = [&value](uint64_t word) {
      value = (value ^ word) * 0x100000001b3ULL;  // FNV-1a prime
    };
    mix(static_cast<uint64_t>(event.frame));
    mix((static_cast<uint64_t>(event.type) << 16U) |
        static_cast<uint64_t>(static_cast<uint16_t>(event.note)));
    uint32_t bits = 0;
    std::memcpy(&bits, &event.value, sizeof(bits));
    mix((static_cast<uint64_t>(bits) << 32U) | event.reserved);
  }

  // The first schedule of a session replaces nothing, so it orphans nothing.
  if (has_published_schedule_) {
    for (size_t channel = 0; channel < hash.size(); ++channel) {
      if (hash[channel] != published_channel_hash_[channel]) {
        requestChannelReset(static_cast<int>(channel));
      }
    }
  }
  published_channel_hash_ = hash;
  has_published_schedule_ = true;
}

void Engine::publishSchedule(std::unique_ptr<Schedule> schedule) {
  const uint64_t generation = schedule->generation();
  const int32_t count = schedule->eventCount();
  // Publishing a schedule is independent from voice resets. Adding a second
  // audio clip must not cut off clips that are already playing — and neither
  // must painting a step on one channel silence the melody sounding on
  // another, which is what a blanket all-notes-off on every publish did.
  //
  // A voice can only be orphaned by an edit that changed *its own* channel's
  // events, so that is the only channel released. The comparison is one linear
  // pass over the new schedule against the fingerprints of the last one: an
  // edit to a 64-lane arrangement resets the lane that was edited and leaves
  // the other 63 ringing.
  releaseChannelsWhoseEventsChanged(*schedule);
  schedule_.publish(std::move(schedule));
  ob_event event{};
  event.type = OB_EVT_SCHEDULE_PUBLISHED;
  event.i64_a = static_cast<int64_t>(generation);
  event.f64_a = static_cast<double>(count);
  events_.tryPush(event);
}

bool Engine::loadSample(const std::string& path, std::string& error) {
  // Clicking the same browser row again — or clicking back to a sample that is
  // still in the preview voice — must not pay for another file read and decode.
  // The sampler still holds it, so all that is owed is the completion event the
  // UI waits on before it starts the audition.
  if (!path.empty() && path == preview_loaded_path_) {
    ob_event event{};
    event.type = OB_EVT_SAMPLE_LOADED;
    event.i64_a = preview_loaded_frames_;
    copyText(event.text, sizeof(event.text), preview_loaded_name_);
    events_.tryPush(event);
    return true;
  }

  // Browser previews use a dedicated voice so loading a preview can never
  // replace a song or an arrangement channel.
  std::string name;
  int64_t frames = 0;
  if (!loadSampleInto(preview_channel_->instrument.sampler(), -1, path, error, &name, &frames)) {
    preview_loaded_path_.clear();
    return false;
  }
  preview_loaded_path_ = path;
  preview_loaded_name_ = std::move(name);
  preview_loaded_frames_ = frames;
  return true;
}

bool Engine::loadChannelSample(int index, const std::string& path, std::string& error) {
  if (index < 0 || index >= MaxRackChannels) {
    error = "The channel index is out of range.";
    return false;
  }
  return loadSampleInto(channels_[static_cast<size_t>(index)]->instrument.sampler(), index, path,
                        error);
}

bool Engine::loadSampleInto(Sampler& target, int log_channel, const std::string& path,
                            std::string& error, std::string* out_name, int64_t* out_frames) {
  std::unique_ptr<SampleData> sample =
      path.empty() ? makeFallbackSample(config_.sample_rate) : loadAudioFile(path, error);
  if (sample == nullptr) {
    diagnostics_.log(LogLevel::Error, "sampler", error);
    ob_event failure{};
    failure.type = OB_EVT_ERROR;
    failure.code = OB_ERR_FILE_UNSUPPORTED;
    copyText(failure.text, sizeof(failure.text), error);
    events_.tryPush(failure);
    return false;
  }

  const std::string name = sample->name;
  const int64_t frames = sample->frames;
  target.setSample(std::move(sample));
  if (log_channel >= 0) {
    diagnostics_.logf(LogLevel::Info, "sampler", "channel %d loaded '%s' (%lld frames)",
                      log_channel, name.c_str(), static_cast<long long>(frames));
  } else {
    diagnostics_.logf(LogLevel::Info, "sampler", "preview loaded '%s' (%lld frames)", name.c_str(),
                      static_cast<long long>(frames));
  }

  ob_event event{};
  event.type = OB_EVT_SAMPLE_LOADED;
  event.i64_a = frames;
  copyText(event.text, sizeof(event.text), name);
  events_.tryPush(event);
  if (out_name != nullptr) *out_name = name;
  if (out_frames != nullptr) *out_frames = frames;
  return true;
}

void Engine::requestSampleLoad(const std::string& path) {
  {
    std::lock_guard<std::mutex> lock(work_mutex_);
    pending_sample_loads_.push_back(path);
  }
  work_signal_.notify_one();
}

void Engine::setChannels(std::vector<ChannelDesc> channels) {
  // Publish the loading state before the schedule that references these
  // channels. A newly added audio clip can therefore defer its AudioStart
  // instead of triggering the fallback/old sample while the worker decodes.
  const size_t count = std::min(channels.size(), static_cast<size_t>(MaxRackChannels));
  for (size_t index = 0; index < count; ++index) {
    Channel& channel = *channels_[index];
    const ChannelDesc& desc = channels[index];
    channel.one_shot.store(desc.one_shot, std::memory_order_release);
    if (desc.one_shot && samplePathHash(desc.sample_path) !=
                             channel.loaded_sample_hash.load(std::memory_order_acquire)) {
      channel.sample_ready.store(false, std::memory_order_release);
    }
  }
  {
    std::lock_guard<std::mutex> lock(work_mutex_);
    pending_channels_ = std::move(channels);
    has_pending_channels_ = true;
  }
  work_signal_.notify_one();
}

void Engine::requestChannelReset(int index) noexcept {
  if (index < 0 || index >= MaxRackChannels) return;
  channels_[static_cast<size_t>(index)]->reset_requested.store(true, std::memory_order_release);
}

void Engine::setAuditionChannel(int index) noexcept {
  if (index < 0 || index >= MaxRackChannels) return;
  audition_channel_.store(index, std::memory_order_release);
}

// Housekeeping thread. Levels are published immediately — they are atomics the
// audio thread re-reads every block — while a changed sample path costs a disk
// read, so it is done only where the path actually differs.
void Engine::applyChannelSync(std::vector<ChannelDesc> channels) {
  const size_t count = std::min(channels.size(), static_cast<size_t>(MaxRackChannels));
  for (size_t index = 0; index < count; ++index) {
    Channel& channel = *channels_[index];
    const ChannelDesc& desc = channels[index];
    channel.gain.store(std::clamp(desc.gain, 0.0F, 2.0F), std::memory_order_release);
    channel.pan.store(std::clamp(desc.pan, -1.0F, 1.0F), std::memory_order_release);
    channel.muted.store(desc.muted, std::memory_order_release);
    channel.one_shot.store(desc.one_shot, std::memory_order_release);
    const uint64_t requested_hash = samplePathHash(desc.sample_path);
    if (desc.sample_path != channel.loaded_path) {
      if (desc.one_shot) channel.sample_ready.store(false, std::memory_order_release);
      std::string error;
      // A channel with no sample yet (an empty lane, or a hosted plug-in) is
      // left silent rather than given the fallback tone: an empty lane that
      // beeped would be worse than one that does nothing.
      if (!desc.sample_path.empty() &&
          loadChannelSample(static_cast<int>(index), desc.sample_path, error)) {
        channel.loaded_path = desc.sample_path;
        channel.loaded_sample_hash.store(requested_hash, std::memory_order_release);
        channel.sample_ready.store(true, std::memory_order_release);
      } else if (desc.sample_path.empty()) {
        channel.loaded_path.clear();
        channel.loaded_sample_hash.store(0, std::memory_order_release);
        channel.sample_ready.store(true, std::memory_order_release);
      }
    } else if (desc.one_shot &&
               requested_hash == channel.loaded_sample_hash.load(std::memory_order_acquire)) {
      // The schedule may have been republished while this clip was being
      // edited, but its decoded sample is still valid.
      channel.sample_ready.store(true, std::memory_order_release);
    }
    channel.active.store(true, std::memory_order_release);
  }
  // Slots the rack no longer reaches fall silent. Slot 0 stays active even when
  // the project is empty so the audition path always has a voice.
  for (size_t index = std::max<size_t>(count, 1); index < MaxRackChannels; ++index) {
    channels_[index]->active.store(false, std::memory_order_release);
    channels_[index]->one_shot.store(false, std::memory_order_release);
    channels_[index]->sample_ready.store(true, std::memory_order_release);
  }
}

void Engine::applyPendingWorkForTests() {
  std::vector<std::string> pending;
  std::vector<ChannelDesc> channels;
  bool has_channels = false;
  {
    std::lock_guard<std::mutex> lock(work_mutex_);
    pending.swap(pending_sample_loads_);
    has_channels = has_pending_channels_;
    channels.swap(pending_channels_);
    has_pending_channels_ = false;
  }
  if (has_channels) applyChannelSync(std::move(channels));
  for (const std::string& path : pending) {
    std::string error;
    loadSample(path, error);
  }
}

void Engine::housekeepingLoop() {
  char formatted[256];
  while (housekeeping_active_.load(std::memory_order_acquire)) {
    std::vector<std::string> pending;
    std::vector<ChannelDesc> channels;
    bool has_channels = false;
    {
      std::unique_lock<std::mutex> lock(work_mutex_);
      work_signal_.wait_for(lock, std::chrono::milliseconds(20));
      pending.swap(pending_sample_loads_);
      has_channels = has_pending_channels_;
      channels.swap(pending_channels_);
      has_pending_channels_ = false;
    }

    if (has_channels) applyChannelSync(std::move(channels));
    for (const std::string& path : pending) {
      std::string error;
      loadSample(path, error);
    }

    // Drain the RT log and write it out with real formatting.
    rt::RtLogRecord record{};
    while (rt_log_.pop(record)) {
      rt::RtLog::format(record, formatted, sizeof(formatted));
      diagnostics_.log(static_cast<LogLevel>(record.level), "rt", formatted);
    }

    // Free everything the audio thread provably cannot reach any more.
    const bool rt_running = running_.load(std::memory_order_acquire);
    schedule_.collect(rt_running);
    for (auto& channel : channels_) {
      channel->instrument.sampler().collectRetiredSamples(rt_running);
    }
    preview_channel_->instrument.sampler().collectRetiredSamples(rt_running);
  }
}

void Engine::onDeviceNotification(audio_io::DeviceNotification notification,
                                  const std::string& detail) {
  ob_event event{};
  switch (notification) {
    case audio_io::DeviceNotification::DeviceLost:
      event.type = OB_EVT_DEVICE_LOST;
      diagnostics_.logf(LogLevel::Warn, "audio", "device lost: %s; fell back to the default device",
                        detail.c_str());
      break;
    case audio_io::DeviceNotification::DefaultDeviceChanged:
      event.type = OB_EVT_DEVICE_CHANGED;
      diagnostics_.logf(LogLevel::Info, "audio", "default output device changed to %s",
                        detail.c_str());
      break;
    case audio_io::DeviceNotification::FormatChanged:
      event.type = OB_EVT_DEVICE_CHANGED;
      diagnostics_.logf(LogLevel::Info, "audio", "device format changed on %s", detail.c_str());
      break;
  }
  copyText(event.text, sizeof(event.text), detail);
  events_.tryPush(event);

  if (device_ != nullptr) {
    const audio_io::StreamFormat granted = device_->format();
    if (granted.sample_rate != config_.sample_rate) {
      config_.sample_rate = granted.sample_rate;
      // Instruments reallocate off the audio thread, and reconfiguring one is
      // legal only while it is deactivated (DM-Q5) — so this is a full
      // deactivate/configure/activate cycle, not a poke at the DSP. The device
      // is stopped while reopening, so it cannot race with a render.
      plugin::ProcessSetup setup;
      setup.sample_rate = granted.sample_rate;
      setup.max_block_frames = static_cast<uint32_t>(granted.block_frames);
      setup.is_offline = config_.use_null_device;
      for (int index = 0; index < MaxRackChannels; ++index) {
        plugin::PluginInstance& voice = channelInstrument(index);
        voice.deactivate();
        if (!voice.configure(setup) || !voice.activate()) {
          diagnostics_.logf(LogLevel::Error, "plugin", "channel %d rejected the new device format",
                            index);
        }
      }
      preview_channel_->instrument.deactivate();
      if (!preview_channel_->instrument.configure(setup) ||
          !preview_channel_->instrument.activate()) {
        diagnostics_.log(LogLevel::Error, "plugin",
                         "sample preview rejected the new device format");
      }
    }
    config_.block_frames = granted.block_frames;
    // The scratch is sized for the device's block; a larger block would other-
    // wise have channels rendering past the end of it.
    channel_scratch_.assign(static_cast<size_t>(granted.block_frames) * MaxChannels, 0.0F);
    latency_frames_output_ = device_->outputLatencyFrames();
    latency_frames_roundtrip_ = device_->roundTripLatencyFrames();
  }
}

}  // namespace onebeat::core
