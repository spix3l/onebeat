// The engine: one process entry point, one schedule, one transport.
//
// Engine::process is the *only* place audio is produced. The CoreAudio backend
// and the offline render driver both call it, which is what makes FR-ENG-06
// ("offline render shares the real-time code path") true by construction rather
// than by convention.
#pragma once

#include <atomic>
#include <condition_variable>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

#include "abi/onebeat_abi.h"
#include "audio_io/audio_device.h"
#include "core/audio_buffer.h"
#include "core/diagnostics.h"
#include "core/rt/mpsc_ring.h"
#include "core/rt/publisher.h"
#include "core/rt/rt.h"
#include "core/rt/rt_log.h"
#include "core/rt/spsc_ring.h"
#include "core/sampler.h"
#include "core/schedule.h"
#include "core/transport.h"

namespace onebeat::core {

struct EngineConfig {
  double sample_rate = 48000.0;
  int block_frames = 512;
  bool use_null_device = false;
  bool free_running_null_device = true;
  std::string log_directory;
};

// What one call to process() operates on. Deliberately tiny and POD-ish: it is
// constructed on the audio thread every block.
struct ProcessContext {
  AudioBufferView output;
  int num_frames = 0;
  uint64_t host_time_ns = 0;
  uint64_t stream_time_frames = 0;
};

// Seqlock-published snapshot (ADR-002 §4).
//
// The audio thread is the only writer; readers retry while the sequence number
// is odd or changed under them. The payload is held as an array of atomics
// rather than a plain struct so that the read/write race the seqlock makes safe
// is also *legal*, which keeps TSan quiet without suppressions.
class SnapshotSlot {
 public:
  void write(const ob_snapshot& snapshot) noexcept OB_NONBLOCKING;
  bool read(ob_snapshot& out) const noexcept OB_NONBLOCKING;

 private:
  static constexpr size_t WordCount = sizeof(ob_snapshot) / sizeof(uint64_t);
  static_assert(sizeof(ob_snapshot) % sizeof(uint64_t) == 0,
                "ob_snapshot must be a whole number of 64-bit words");

  alignas(64) std::atomic<uint32_t> sequence_{0};
  std::atomic<uint64_t> words_[WordCount]{};
};

class Engine final : public audio_io::RenderCallback {
 public:
  explicit Engine(EngineConfig config);
  ~Engine() override;

  Engine(const Engine&) = delete;
  Engine& operator=(const Engine&) = delete;

  // Main thread. Opens the device (or the null backend) and prepares everything
  // the audio thread will need. No allocation happens after this returns.
  bool initialise(std::string& error);
  bool start(std::string& error);
  void stop();
  bool isRunning() const;

  // --- audio thread -------------------------------------------------------
  void renderAudio(const audio_io::RenderBlock& block) noexcept OB_NONBLOCKING override;
  // The single render entry point, shared with the offline driver.
  void process(const ProcessContext& context) noexcept OB_NONBLOCKING;

  // --- UI thread ----------------------------------------------------------
  bool postCommand(const ob_command& command) noexcept;
  void readSnapshot(ob_snapshot& out) const noexcept;
  bool pollEvent(ob_event& out) noexcept;
  bool pushEvent(const ob_event& event) noexcept;

  // --- worker / test threads ---------------------------------------------
  void publishSchedule(std::unique_ptr<Schedule> schedule);
  uint64_t scheduleGeneration() const { return schedule_.generation(); }
  bool loadSample(const std::string& path, std::string& error);
  void requestSampleLoad(const std::string& path);
  void applyPendingWorkForTests();

  Sampler& sampler() { return sampler_; }
  Transport& transportForTests() { return transport_; }
  Diagnostics& diagnostics() { return diagnostics_; }
  rt::RtLog& rtLog() { return rt_log_; }
  audio_io::AudioDevice* device() { return device_.get(); }
  const EngineConfig& config() const { return config_; }
  std::string deviceName() const;

 private:
  void drainCommands() noexcept OB_NONBLOCKING;
  void applyCommand(const ob_command& command) noexcept OB_NONBLOCKING;
  void renderRange(const AudioBufferView& output, int start_frame,
                   int num_frames) noexcept OB_NONBLOCKING;
  void runSchedule(const AudioBufferView& output, int block_offset,
                   int num_frames) noexcept OB_NONBLOCKING;
  void applyScheduleEvent(const ScheduleEvent& event) noexcept OB_NONBLOCKING;
  void publishSnapshot(const ProcessContext& context,
                       uint64_t render_nanos) noexcept OB_NONBLOCKING;
  void housekeepingLoop();
  void onDeviceNotification(audio_io::DeviceNotification notification, const std::string& detail);

  EngineConfig config_;
  Diagnostics diagnostics_;
  rt::RtLog rt_log_;

  std::unique_ptr<audio_io::AudioDevice> device_;
  Transport transport_;
  Sampler sampler_{&rt_log_};
  rt::NonRealtimeMutable<Schedule> schedule_;

  rt::SpscRing<ob_command, 1024> commands_;
  rt::MpscRing<ob_event, 256> events_;
  SnapshotSlot snapshot_;

  // Audio-thread-owned state (no synchronisation, single writer).
  float master_gain_ = 1.0F;
  float peak_left_ = 0.0F;
  float peak_right_ = 0.0F;
  float rms_left_ = 0.0F;
  float rms_right_ = 0.0F;
  float cpu_load_ = 0.0F;
  int32_t latency_frames_output_ = 0;
  int32_t latency_frames_roundtrip_ = 0;
  uint64_t callback_count_ = 0;
  uint64_t last_command_generation_ = 0;

  std::atomic<uint64_t> xruns_{0};
  std::atomic<bool> running_{false};
  std::atomic<bool> housekeeping_active_{false};

  std::thread housekeeping_;
  std::mutex work_mutex_;
  std::condition_variable work_signal_;
  std::vector<std::string> pending_sample_loads_;
};

}  // namespace onebeat::core
