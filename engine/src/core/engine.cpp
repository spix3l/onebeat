#include "core/engine.h"

#include <algorithm>
#include <cstring>

#include "core/wav_loader.h"

namespace onebeat::core {
namespace {

constexpr int SnapshotVersion = OB_SNAPSHOT_VERSION;

void copyText(char* destination, size_t capacity, const std::string& source) {
  const size_t length = std::min(source.size(), capacity - 1);
  std::memcpy(destination, source.data(), length);
  destination[length] = '\0';
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

Engine::Engine(EngineConfig config) : config_(std::move(config)) {}

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
  if (!instrument_.configure(setup) || !instrument_.activate()) {
    error = "The built-in instrument could not be configured for this device format.";
    diagnostics_.log(LogLevel::Error, "plugin", error);
    return false;
  }

  // Sized for the worst honest case rather than the typical one: the command
  // ring holds 1024 entries, and a block can in principle carry a schedule event
  // on every frame. Overflow is counted and logged, never grown.
  command_events_.reserve(CommandQueueCapacity);
  chunk_events_.reserve(CommandQueueCapacity +
                        static_cast<uint32_t>(granted.block_frames) * 2U);

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
  instrument_.beginAudioBlock();

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
  const int channels = output.numChannels();
  for (int frame = 0; frame < context.num_frames; ++frame) {
    const float left = output.channel(0)[frame] * master_gain_;
    output.channel(0)[frame] = left;
    peak_left = std::max(peak_left, std::abs(left));
    sum_left += static_cast<double>(left) * static_cast<double>(left);
    if (channels > 1) {
      const float right = output.channel(1)[frame] * master_gain_;
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

  plugin::EventList events = chunk_events_.list();

  // A loop wrap that landed on the previous block boundary releases here, before
  // anything else, so it still precedes every note this chunk starts.
  if (pending_all_notes_off_) {
    events.push(plugin::PluginEvent::allNotesOff(0));
    pending_all_notes_off_ = false;
  }

  // Commands first, at frame 0 — they were drained before the block rendered,
  // and the stable sort below keeps them ahead of any schedule event at 0.
  if (block_events != nullptr) {
    for (uint32_t index = 0; index < block_events->size(); ++index) {
      events.push((*block_events)[index]);
    }
  }

  if (schedule != nullptr) {
    const int32_t event_count = schedule->eventCount();
    const ScheduleEvent* schedule_events = schedule->events();
    const int64_t chunk_end = chunk_start + num_frames;
    for (int32_t index = schedule->lowerBound(chunk_start);
         index < event_count && schedule_events[index].frame < chunk_end; ++index) {
      const ScheduleEvent& event = schedule_events[index];
      const auto time = static_cast<uint32_t>(event.frame - chunk_start);
      switch (static_cast<EventType>(event.type)) {
        case EventType::NoteOn:
          events.push(
              plugin::PluginEvent::noteOn(time, event.note, static_cast<double>(event.value)));
          break;
        case EventType::NoteOff:
          events.push(plugin::PluginEvent::noteOff(time, event.note));
          break;
        case EventType::TempoChange:
          // Tempo is the *host's* clock, not the instrument's: it never reaches
          // process(). Applied here, before the chunk renders and before the
          // transport advances, which is exactly where v0.1 applied it.
          transport_.setTempo(static_cast<double>(event.value));
          break;
      }
    }
  }

  events.sortByTime();
  if (events.overflowCount() > 0) {
    rt_log_.log(rt::LogLevel::Warn, rt::RtMessage::EventListFull,
                static_cast<int64_t>(events.overflowCount()),
                static_cast<int64_t>(events.capacity()));
  }

  // A window onto the output at `offset`. Stack storage, no allocation: the
  // instrument's ports are addressed from frame 0 of what it is given, so the
  // host does the offsetting rather than every plugin having to.
  float* slice[MaxChannels] = {nullptr, nullptr};
  const int channels = std::min(output.numChannels(), MaxChannels);
  for (int channel = 0; channel < channels; ++channel) {
    slice[channel] = output.channel(channel) + offset;
  }
  const AudioBufferView port(slice, channels, num_frames);

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

  const plugin::ProcessStatus status = instrument_.process(block);
  if (status == plugin::ProcessStatus::Error) {
    rt_log_.log(rt::LogLevel::Error, rt::RtMessage::InstrumentProcessFailed, 0, 0);
  }
  active_voices_ = instrument_.activeVoiceCount();
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
    case OB_CMD_NOTE_ON:
      block_events.push(
          plugin::PluginEvent::noteOn(0, static_cast<int16_t>(command.i64_a), command.f64_a));
      break;
    case OB_CMD_NOTE_OFF:
      block_events.push(plugin::PluginEvent::noteOff(0, static_cast<int16_t>(command.i64_a)));
      break;
    case OB_CMD_ALL_NOTES_OFF:
      block_events.push(plugin::PluginEvent::allNotesOff(0));
      break;
    case OB_CMD_SET_MASTER_GAIN:
      master_gain_ = std::clamp(static_cast<float>(command.f64_a), 0.0F, 2.0F);
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

  if (render_nanos > 0 && static_cast<double>(render_nanos) > budget_nanos) {
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

void Engine::publishSchedule(std::unique_ptr<Schedule> schedule) {
  const uint64_t generation = schedule->generation();
  const int32_t count = schedule->eventCount();
  schedule_.publish(std::move(schedule));
  ob_event event{};
  event.type = OB_EVT_SCHEDULE_PUBLISHED;
  event.i64_a = static_cast<int64_t>(generation);
  event.f64_a = static_cast<double>(count);
  events_.tryPush(event);
}

bool Engine::loadSample(const std::string& path, std::string& error) {
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
  instrument_.sampler().setSample(std::move(sample));
  diagnostics_.logf(LogLevel::Info, "sampler", "loaded '%s' (%lld frames)", name.c_str(),
                    static_cast<long long>(frames));

  ob_event event{};
  event.type = OB_EVT_SAMPLE_LOADED;
  event.i64_a = frames;
  copyText(event.text, sizeof(event.text), name);
  events_.tryPush(event);
  return true;
}

void Engine::requestSampleLoad(const std::string& path) {
  {
    std::lock_guard<std::mutex> lock(work_mutex_);
    pending_sample_loads_.push_back(path);
  }
  work_signal_.notify_one();
}

void Engine::applyPendingWorkForTests() {
  std::vector<std::string> pending;
  {
    std::lock_guard<std::mutex> lock(work_mutex_);
    pending.swap(pending_sample_loads_);
  }
  for (const std::string& path : pending) {
    std::string error;
    loadSample(path, error);
  }
}

void Engine::housekeepingLoop() {
  char formatted[256];
  while (housekeeping_active_.load(std::memory_order_acquire)) {
    std::vector<std::string> pending;
    {
      std::unique_lock<std::mutex> lock(work_mutex_);
      work_signal_.wait_for(lock, std::chrono::milliseconds(20));
      pending.swap(pending_sample_loads_);
    }

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
    instrument_.sampler().collectRetiredSamples(rt_running);
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
      instrument_.deactivate();
      if (!instrument_.configure(setup) || !instrument_.activate()) {
        diagnostics_.log(LogLevel::Error, "plugin",
                         "the built-in instrument rejected the new device format");
      }
    }
    config_.block_frames = granted.block_frames;
    latency_frames_output_ = device_->outputLatencyFrames();
    latency_frames_roundtrip_ = device_->roundTripLatencyFrames();
  }
}

}  // namespace onebeat::core
