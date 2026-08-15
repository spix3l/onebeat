// The engine: one process entry point, one schedule, one transport.
//
// Engine::process is the *only* place audio is produced. The CoreAudio backend
// and the offline render driver both call it, which is what makes FR-ENG-06
// ("offline render shares the real-time code path") true by construction rather
// than by convention.
#pragma once

#include <array>
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

// How many rack channels can sound at once. The schedule addresses instruments
// by a dense index (see model/flattener.h), and this is the size of the array
// that index selects — so it is also the hard ceiling on project instruments
// that produce audio. Every slot is configured and activated up front, which is
// what lets a channel be added mid-session without allocating on the RT path.
inline constexpr int MaxRackChannels = 64;

class Engine final : public audio_io::RenderCallback {
 public:
  explicit Engine(EngineConfig config);
  ~Engine() override;

  // What one rack channel should be, as the model sees it. The main thread
  // hands over a whole rack; the housekeeping thread reconciles it against what
  // is loaded (see setChannels).
  struct ChannelDesc {
    std::string sample_path;
    float gain = 1.0F;
    float pan = 0.0F;
    bool muted = false;
    // Arrangement audio clips are one-shot sources, not MIDI/sample-rack
    // instruments. This lets the loader and render path defer their start until
    // the file is ready without delaying ordinary note channels.
    bool one_shot = false;
  };

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
  bool loadChannelSample(int index, const std::string& path, std::string& error);
  void requestSampleLoad(const std::string& path);
  void applyPendingWorkForTests();

  // Replaces the whole rack, indexed by the schedule's dense instrument index.
  // Asynchronous by design: reconciling means reading WAVs off disk, which must
  // not happen on the caller's thread any more than on the audio thread. Slots
  // past `channels.size()` fall silent. A channel whose sample path is unchanged
  // keeps the sample it already has, so reordering the rack does not re-read
  // every file.
  void setChannels(std::vector<ChannelDesc> channels);
  // Requests a click-safe reset for one arrangement channel after a clip move,
  // delete, or mute edit. Unlike a global reset, adding another audio clip does
  // not interrupt clips that are already sounding.
  void requestChannelReset(int index) noexcept;
  // Which channel manual note commands (the audition path) sound on.
  void setAuditionChannel(int index) noexcept;

  // The engine holds its instrument as a `PluginInstance` and nothing else: a
  // hosted CLAP plugin (OB-2-07) drops in here with no change above this line.
  // Names the channel a hosted plug-in occupies, which is also slot 0 — the
  // audition voice — until something is hosted elsewhere.
  plugin::PluginInstance& instrument() { return channelInstrument(hosted_channel_); }
  const plugin::PluginInstance& instrument() const { return channelInstrument(hosted_channel_); }
  // On the audio thread's path (renderChannel), so it carries the RT contract:
  // a compare, a branch and an array index, and nothing else.
  plugin::PluginInstance& channelInstrument(int index) noexcept OB_NONBLOCKING;
  const plugin::PluginInstance& channelInstrument(int index) const noexcept OB_NONBLOCKING;
  // Replaces the v0.1 built-in instrument while the device is stopped around
  // the swap. Ownership stays with the engine so the audio thread only ever
  // observes a stable pointer.
  bool installHostedInstrument(std::unique_ptr<plugin::PluginInstance> instance,
                               std::string& error);
  bool restoreBuiltinInstrument(std::string& error);
  bool hasHostedInstrument() const noexcept { return hosted_instrument_ != nullptr; }
  bool createSandboxedInstrument(const std::string& bundle_path, const std::string& plugin_id,
                                 const std::string& helper_path, std::string& error);
  bool installMissingInstrument(const std::string& name, const std::vector<uint8_t>& state,
                                std::string& error);
  uint32_t hostedParamCount() const;
  bool hostedParamInfo(uint32_t index, plugin::ParamInfo& out) const;
  bool hostedParamValue(plugin::ParamId param, double& out) const;
  bool saveHostedState(std::vector<uint8_t>& out) const;
  std::string hostedError() const;
  bool loadHostedState(const std::vector<uint8_t>& bytes);
  bool hostedHasEditor() const;
  bool hostedHealthy() const;
  bool restartHostedInstrument();
  bool openHostedEditor();
  void closeHostedEditor();
  static constexpr uint32_t CommandQueueCapacity = 1024;
  // Sample loading has no place in a format-agnostic interface, so it stays on
  // the concrete built-in.
  Sampler& sampler() { return channels_[0]->instrument.sampler(); }
  Sampler& channelSampler(int index) {
    return channels_[static_cast<size_t>(index)]->instrument.sampler();
  }
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

  // One rack channel: its own voice, its own sample, its own level. Slots are
  // constructed once and never reallocated, so the audio thread's view of a
  // channel is stable for the life of the engine and only the atomics below
  // change under it.
  struct Channel {
    Channel(plugin::PluginHost* host, rt::RtLog* log) : instrument(host, log) {}

    plugin::builtin::SamplerPlugin instrument;
    std::atomic<float> gain{1.0F};
    std::atomic<float> pan{0.0F};
    std::atomic<bool> muted{false};
    std::atomic<bool> one_shot{false};
    std::atomic<bool> sample_ready{true};
    std::atomic<uint64_t> loaded_sample_hash{0};
    std::atomic<bool> reset_requested{false};
    // Audio-thread-only: an AudioStart that arrived before its file finished
    // loading is replayed once the worker marks the channel ready.
    bool deferred_audio_start = false;
    // Whether this slot is part of the rack at all. Slot 0 starts active so an
    // engine with no project still sounds — that is the audition path every
    // test and the v0.1 single-sampler behaviour rely on.
    std::atomic<bool> active{false};
    // Housekeeping thread only: what `instrument`'s sampler currently holds, so
    // reconciliation can tell a re-order from a genuine sample change.
    std::string loaded_path;
  };

  // Renders one channel into the scratch buffer and mixes it into `output` at
  // `offset` with that channel's gain and constant-power pan.
  void renderChannel(Channel& channel, InstrumentId index, const AudioBufferView& output,
                     int offset, int num_frames, const Schedule* schedule, int64_t chunk_start,
                     const plugin::EventList* block_events,
                     bool release_all, plugin::PluginInstance& instrument,
                     bool preview_voice = false) noexcept OB_NONBLOCKING;
  void applyChannelSync(std::vector<ChannelDesc> channels);

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
  bool loadSampleInto(Sampler& target, int log_channel, const std::string& path,
                      std::string& error);

  EngineConfig config_;
  Diagnostics diagnostics_;
  rt::RtLog rt_log_;

  std::unique_ptr<audio_io::AudioDevice> device_;
  Transport transport_;
  HostBridge host_bridge_;
  // The rack. Slot 0 doubles as the v0.1 single instrument: `sampler()` and
  // `instrument()` below still name it, so the audition path and every caller
  // that predates the rack keep working unchanged.
  std::array<std::unique_ptr<Channel>, MaxRackChannels> channels_;
  // Independent from the rack because slot 0 may host the default piano.
  std::unique_ptr<Channel> preview_channel_;
  // A hosted CLAP plug-in still replaces exactly one channel's voice. Per-channel
  // hosting is a Stage 7 concern; what matters here is that the *built-in*
  // sampler is per-channel, which is what the rack is made of today.
  std::unique_ptr<plugin::PluginInstance> hosted_instrument_;
  int hosted_channel_ = 0;
  std::atomic<int> audition_channel_{0};
  rt::NonRealtimeMutable<Schedule> schedule_;

  // One channel's render target, mixed into the master and reused across
  // channels. Sized at initialise() for the device's largest block; the audio
  // thread never resizes it.
  std::vector<float> channel_scratch_;

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
  // Replacing a schedule while playing must reconcile voices from the old
  // arrangement. The audio thread consumes this flag at the next block and
  // releases those voices before rendering the new schedule.
  // Schedule publication itself is intentionally not a global voice reset:
  // adding a second clip must leave already-playing clips uninterrupted.


  std::thread housekeeping_;
  std::mutex work_mutex_;
  std::condition_variable work_signal_;
  std::vector<std::string> pending_sample_loads_;
  // The rack the model last asked for. Only the newest matters — a burst of
  // edits should reconcile once, not once per edit — so this is a slot, not a
  // queue.
  std::vector<ChannelDesc> pending_channels_;
  bool has_pending_channels_ = false;
};

}  // namespace onebeat::core
