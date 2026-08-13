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
#include "plugin/builtin/sampler_plugin.h"
#include "plugin/event.h"
#include "plugin/host.h"
#include "plugin/plugin_instance.h"

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

  // The engine holds its instrument as a `PluginInstance` and nothing else: a
  // hosted CLAP plugin (OB-2-07) drops in here with no change above this line.
  plugin::PluginInstance& instrument() { return instrument_; }
  static constexpr uint32_t CommandQueueCapacity = 1024;
  // Sample loading has no place in a format-agnostic interface, so it stays on
  // the concrete built-in.
  Sampler& sampler() { return instrument_.sampler(); }
  Transport& transportForTests() { return transport_; }
  Diagnostics& diagnostics() { return diagnostics_; }
  rt::RtLog& rtLog() { return rt_log_; }
  audio_io::AudioDevice* device() { return device_.get(); }
  const EngineConfig& config() const { return config_; }
  std::string deviceName() const;

 private:
  // What the instrument may ask of the engine. Stage 2's implementation is
  // deliberately conservative — it records and logs rather than acting — because
  // honouring a restart request needs the graph rebuild that arrives with
  // OB-2-05/OB-2-07. The seat exists now so those tickets add behaviour, not
  // structure.
  class HostBridge final : public plugin::PluginHost {
   public:
    void requestRestart() noexcept override { restart_requested_.store(true); }
    void requestProcess() noexcept override { process_requested_.store(true); }
    void requestCallback() noexcept override { callback_requested_.store(true); }
    void paramsRescan(uint32_t flags) noexcept override { params_rescan_.fetch_or(flags); }
    void paramsClear(plugin::ParamId /*param*/, uint32_t /*flags*/) noexcept override {}
    void audioPortsRescan(uint32_t flags) noexcept override { ports_rescan_.fetch_or(flags); }
    void notePortsRescan(uint32_t flags) noexcept override { ports_rescan_.fetch_or(flags); }
    void latencyChanged() noexcept override { latency_dirty_.store(true); }
    void tailChanged() noexcept override {}
    // OneBeat has no worker pool until the graph lands in Stage 4 (FR-ENG-05).
    // Declining is always legal; the plugin does the work itself.
    bool requestThreadPoolExec(uint32_t /*num_tasks*/) noexcept OB_NONBLOCKING override {
      return false;
    }

    bool takeCallbackRequest() noexcept { return callback_requested_.exchange(false); }
    bool restartRequested() const noexcept { return restart_requested_.load(); }

   private:
    std::atomic<bool> restart_requested_{false};
    std::atomic<bool> process_requested_{false};
    std::atomic<bool> callback_requested_{false};
    std::atomic<bool> latency_dirty_{false};
    std::atomic<uint32_t> params_rescan_{0};
    std::atomic<uint32_t> ports_rescan_{0};
  };

  void drainCommands(plugin::EventList& block_events) noexcept OB_NONBLOCKING;
  void applyCommand(const ob_command& command,
                    plugin::EventList& block_events) noexcept OB_NONBLOCKING;
  void runSchedule(const AudioBufferView& output, int block_offset, int num_frames,
                   const plugin::EventList& block_events) noexcept OB_NONBLOCKING;
  // One process() call: builds the instrument's event list for [chunk_start,
  // chunk_start + num_frames) and hands it a view of the output at `offset`.
  void processChunk(const AudioBufferView& output, int offset, int num_frames,
                    const Schedule* schedule, int64_t chunk_start,
                    const plugin::EventList* block_events) noexcept OB_NONBLOCKING;
  void publishSnapshot(const ProcessContext& context,
                       uint64_t render_nanos) noexcept OB_NONBLOCKING;
  void housekeepingLoop();
  void onDeviceNotification(audio_io::DeviceNotification notification, const std::string& detail);

  EngineConfig config_;
  Diagnostics diagnostics_;
  rt::RtLog rt_log_;

  std::unique_ptr<audio_io::AudioDevice> device_;
  Transport transport_;
  HostBridge host_bridge_;
  plugin::builtin::SamplerPlugin instrument_{&host_bridge_, &rt_log_};
  rt::NonRealtimeMutable<Schedule> schedule_;

  // Both reserved at initialise() time and never resized afterwards: pushing an
  // event on the audio thread must never allocate (OB-2-01 AC 3).
  plugin::EventBuffer command_events_;  // commands drained this block, all at time 0
  plugin::EventBuffer chunk_events_;    // commands + schedule events for one process() call

  rt::SpscRing<ob_command, CommandQueueCapacity> commands_;
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
  int32_t active_voices_ = 0;
  // A loop wrap at the very end of a block has no following chunk to carry its
  // note-off into, so it rides to the next block. Audibly identical: voices only
  // advance their fade while rendering, and nothing renders in between.
  bool pending_all_notes_off_ = false;

  std::atomic<uint64_t> xruns_{0};
  std::atomic<bool> running_{false};
  std::atomic<bool> housekeeping_active_{false};

  std::thread housekeeping_;
  std::mutex work_mutex_;
  std::condition_variable work_signal_;
  std::vector<std::string> pending_sample_loads_;
};

}  // namespace onebeat::core
