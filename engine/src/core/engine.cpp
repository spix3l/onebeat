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

  transport_.prepare(granted.sample_rate, 120.0);
  sampler_.prepare(granted.sample_rate, granted.block_frames);

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
  const uint64_t started_ns = rt::monotonicNanos();

  // Exactly one epoch tick per block on every publisher the audio thread reads:
  // reclamation correctness depends on it (rt/publisher.h).
  schedule_.beginBlock();
  sampler_.beginBlock();

  drainCommands();

  const AudioBufferView& output = context.output;
  output.clear();

  if (transport_.playing()) {
    runSchedule(output, 0, context.num_frames);
  } else {
    renderRange(output, 0, context.num_frames);
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
}

void Engine::renderRange(const AudioBufferView& output, int start_frame,
                         int num_frames) noexcept OB_NONBLOCKING {
  if (num_frames <= 0) {
    return;
  }
  sampler_.render(output, start_frame, num_frames);
}

void Engine::runSchedule(const AudioBufferView& output, int block_offset,
                         int num_frames) noexcept OB_NONBLOCKING {
  const Schedule* schedule = schedule_.acquire();
  int64_t remaining = num_frames;
  int offset = block_offset;
  int wrap_guard = 0;

  while (remaining > 0) {
    const int64_t chunk = transport_.framesUntilLoopWrap(remaining);
    if (chunk <= 0) {
      // Loop wrap: release sounding voices so nothing hangs across the seam,
      // then jump back to the loop start sample-accurately.
      sampler_.allNotesOff();
      transport_.seekFrames(transport_.loopStartFrames());
      if (++wrap_guard > 8) {
        break;  // degenerate loop region; do not spin on the audio thread
      }
      continue;
    }
    wrap_guard = 0;

    const int64_t chunk_start = transport_.positionFrames();
    int64_t consumed = 0;
    int32_t index = schedule != nullptr ? schedule->lowerBound(chunk_start) : 0;
    const int32_t event_count = schedule != nullptr ? schedule->eventCount() : 0;
    const ScheduleEvent* events = schedule != nullptr ? schedule->events() : nullptr;

    while (consumed < chunk) {
      const int64_t position = chunk_start + consumed;
      int64_t next_event_frame = chunk_start + chunk;
      if (index < event_count && events[index].frame < chunk_start + chunk) {
        next_event_frame = std::max(events[index].frame, position);
      }
      const int64_t sub_frames = next_event_frame - position;
      if (sub_frames > 0) {
        renderRange(output, offset + static_cast<int>(consumed), static_cast<int>(sub_frames));
        consumed += sub_frames;
      }
      while (index < event_count && events[index].frame <= chunk_start + consumed &&
             events[index].frame < chunk_start + chunk) {
        applyScheduleEvent(events[index]);
        ++index;
      }
    }

    transport_.advance(chunk);
    // Wrap as soon as the loop end is reached rather than at the top of the
    // next block, so the reported position is never momentarily past the end.
    if (transport_.loopEnabled() && transport_.positionFrames() >= transport_.loopEndFrames()) {
      sampler_.allNotesOff();
      transport_.seekFrames(transport_.loopStartFrames());
    }
    offset += static_cast<int>(chunk);
    remaining -= chunk;
  }
}

void Engine::applyScheduleEvent(const ScheduleEvent& event) noexcept OB_NONBLOCKING {
  switch (static_cast<EventType>(event.type)) {
    case EventType::NoteOn:
      sampler_.noteOn(event.note, event.value);
      break;
    case EventType::NoteOff:
      sampler_.noteOff(event.note);
      break;
    case EventType::TempoChange:
      transport_.setTempo(static_cast<double>(event.value));
      break;
  }
}

void Engine::drainCommands() noexcept OB_NONBLOCKING {
  ob_command command{};
  int drained = 0;
  // Bounded: a runaway producer must not extend the block indefinitely.
  while (drained < 256 && commands_.tryPop(command)) {
    applyCommand(command);
    ++drained;
  }
}

void Engine::applyCommand(const ob_command& command) noexcept OB_NONBLOCKING {
  last_command_generation_ = command.generation;
  switch (static_cast<ob_command_type>(command.type)) {
    case OB_CMD_TRANSPORT_PLAY:
      transport_.play();
      rt_log_.log(rt::LogLevel::Info, rt::RtMessage::TransportStateChanged, 1,
                  transport_.positionFrames());
      break;
    case OB_CMD_TRANSPORT_STOP:
      transport_.stop();
      sampler_.allNotesOff();
      rt_log_.log(rt::LogLevel::Info, rt::RtMessage::TransportStateChanged, 0,
                  transport_.positionFrames());
      break;
    case OB_CMD_TRANSPORT_SEEK_FRAMES:
      sampler_.allNotesOff();  // click-safe seek
      transport_.seekFrames(command.i64_a);
      break;
    case OB_CMD_TRANSPORT_SEEK_BEATS:
      sampler_.allNotesOff();
      transport_.seekBeats(command.f64_a);
      break;
    case OB_CMD_SET_TEMPO:
      transport_.setTempo(command.f64_a);
      break;
    case OB_CMD_SET_LOOP:
      transport_.setLoop(command.f64_a, command.f64_b, command.i64_a != 0);
      break;
    case OB_CMD_NOTE_ON:
      sampler_.noteOn(static_cast<int16_t>(command.i64_a), static_cast<float>(command.f64_a));
      break;
    case OB_CMD_NOTE_OFF:
      sampler_.noteOff(static_cast<int16_t>(command.i64_a));
      break;
    case OB_CMD_ALL_NOTES_OFF:
      sampler_.allNotesOff();
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
  snapshot.active_voices = sampler_.activeVoices();
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
  sampler_.setSample(std::move(sample));
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
    sampler_.collectRetiredSamples(rt_running);
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
      // Instruments reallocate off the audio thread; the device is stopped
      // while reopening, so this cannot race with a render.
      sampler_.prepare(granted.sample_rate, granted.block_frames);
    }
    config_.block_frames = granted.block_frames;
    latency_frames_output_ = device_->outputLatencyFrames();
    latency_frames_roundtrip_ = device_->roundTripLatencyFrames();
  }
}

}  // namespace onebeat::core
