// `PluginInstance` — the one interface every processor in OneBeat implements
// (OB-2-01, D5, FR-PLG-04).
//
// Built-ins, CLAP plugins, VST3 plugins and Audio Units all arrive here. So will
// the WASM extensions in Stage 6 (FR-EXT-08: built-ins use only the public API,
// and the public API is a projection of this). Nothing above this line knows
// what format anything is.
//
// The shape is CLAP's, on purpose (D5). Where OneBeat adds something CLAP does
// not have, the comment says so explicitly and says why — those additions are
// the places a future CLAP version could make us refactor, so they are worth
// being able to enumerate.
//
// **Read docs/plugin-threading-contract.md before implementing this.** Every
// method below is annotated `[main-thread]` or `[audio-thread]`, mirrored from
// CLAP's own annotations, and the annotations are asserted at runtime in debug
// builds. They are not advisory.
#pragma once

#include <cstdint>

#include "core/audio_buffer.h"
#include "core/rt/rt.h"
#include "plugin/event.h"
#include "plugin/host.h"
#include "plugin/parameters.h"
#include "plugin/plugin_types.h"
#include "plugin/ports.h"
#include "plugin/state.h"

namespace onebeat::plugin {

// --------------------------------------------------------------------------
// Process-time inputs
// --------------------------------------------------------------------------

// Musical and wall-clock position for this block. Passed in the block rather
// than as an event, exactly as CLAP passes `clap_process.transport`: it is a
// *state*, not an occurrence. Occurrences (a loop wrap, a seek) are marked by a
// TransportDiscontinuity event at the frame they happen.
struct TransportInfo {
  bool is_valid = false;  // false when the host has no transport at all
  bool is_playing = false;
  bool is_recording = false;
  bool is_loop_active = false;

  double tempo_bpm = 120.0;
  double time_signature_numerator = 4.0;
  double time_signature_denominator = 4.0;

  // Position at the *start* of this block.
  double position_beats = 0.0;
  double position_seconds = 0.0;
  int64_t position_frames = 0;

  double loop_start_beats = 0.0;
  double loop_end_beats = 0.0;

  // Bar-relative position, so a plugin can align to the bar without redoing the
  // host's time-signature arithmetic.
  double bar_start_beats = 0.0;
  int32_t bar_number = 0;
};

enum class ProcessStatus : int32_t {
  // The plugin failed. The host stops calling process(), reports it, and (in
  // Stage 2) may restart the instance out of process.
  Error = 0,
  // Normal: keep calling me.
  Continue = 1,
  // Keep calling me only while my input is non-silent. The host may stop once
  // the input goes quiet — an economy that matters with hundreds of instances.
  ContinueIfNotQuiet = 2,
  // I am rendering a tail; ask tailFrames() for how much is left.
  Tail = 3,
  // I produced silence and have nothing pending. The host may skip me entirely
  // until it sends me an event or I call requestProcess().
  Sleep = 4,
};

// What one process() call operates on.
//
// Note the plural: audio ports are arrays, because FR-PLG-12 multi-out is a
// first-class case rather than a later bolt-on. A conventional stereo instrument
// simply has one output port.
struct ProcessBlock {
  uint32_t frames = 0;

  const core::AudioBufferView* audio_inputs = nullptr;
  uint32_t audio_input_count = 0;
  const core::AudioBufferView* audio_outputs = nullptr;
  uint32_t audio_output_count = 0;

  // Sorted by time, times relative to the start of this block.
  EventListView in_events;
  // Where the plugin writes NoteEnd, parameter changes it made itself, and
  // gestures. May be null when the host does not collect them.
  EventList* out_events = nullptr;

  TransportInfo transport;

  // Frames elapsed on the audio stream since it started, or -1 when unknown.
  // Monotonic across transport stops, unlike transport.position_frames — a
  // free-running LFO wants this one.
  int64_t steady_time_frames = -1;

  const core::AudioBufferView& output(uint32_t port) const noexcept OB_NONBLOCKING {
    return audio_outputs[port];
  }
};

// --------------------------------------------------------------------------
// The interface
// --------------------------------------------------------------------------

class PluginInstance {
 public:
  // The activation state machine, made explicit so that "port reconfiguration
  // is legal only while deactivated" (DM-Q5) is a checkable statement rather
  // than a paragraph in a document.
  //
  //   Created ──configure──> Configured ──activate──> Active
  //      ^                        ^                     │
  //      └──────────────── deactivate ──────────────────┘
  //
  // Processing is a sub-state of Active, entered and left on the audio thread:
  //   Active ──startProcessing──> Processing ──stopProcessing──> Active
  enum class State : uint8_t {
    Created = 0,
    Configured = 1,
    Active = 2,
    Processing = 3,
  };

  virtual ~PluginInstance() = default;

  // --- identity ------------------------------------------------------------

  // [main-thread]
  virtual PluginName name() const = 0;

  State state() const noexcept OB_NONBLOCKING { return state_; }
  bool isActive() const noexcept OB_NONBLOCKING {
    return state_ == State::Active || state_ == State::Processing;
  }

  // --- lifecycle -----------------------------------------------------------

  // [main-thread, deactivated] Fix the stream format and allocate everything
  // this instance will ever need. Every allocation a plugin performs must happen
  // here or in a main-thread call reachable from here — never in process().
  bool configure(const ProcessSetup& setup) {
    OB_ASSERT_MAIN_THREAD();
    if (isActive()) {
      return false;  // the caller must deactivate first; this is DM-Q5's rule
    }
    if (!onConfigure(setup)) {
      return false;
    }
    setup_ = setup;
    state_ = State::Configured;
    return true;
  }

  // [main-thread] After this returns true the plugin is ready to be processed
  // and its port layout is frozen until deactivate().
  bool activate() {
    OB_ASSERT_MAIN_THREAD();
    if (state_ != State::Configured) {
      return false;
    }
    if (!onActivate()) {
      return false;
    }
    state_ = State::Active;
    return true;
  }

  // [main-thread] Legal only when not processing. Returns the instance to
  // Configured, where ports and the stream format may be changed again.
  void deactivate() {
    OB_ASSERT_MAIN_THREAD();
    if (state_ == State::Processing) {
      return;  // the audio thread must call stopProcessing() first
    }
    if (state_ != State::Active) {
      return;
    }
    onDeactivate();
    state_ = State::Configured;
  }

  // [audio-thread] Bracket a run of process() calls. Separate from activate()
  // because activation allocates and this must not: the transport starting must
  // never take a lock.
  bool startProcessing() noexcept OB_NONBLOCKING {
    OB_ASSERT_AUDIO_THREAD();
    if (state_ != State::Active) {
      return false;
    }
    if (!onStartProcessing()) {
      return false;
    }
    state_ = State::Processing;
    return true;
  }

  // [audio-thread]
  void stopProcessing() noexcept OB_NONBLOCKING {
    OB_ASSERT_AUDIO_THREAD();
    if (state_ != State::Processing) {
      return;
    }
    onStopProcessing();
    state_ = State::Active;
  }

  // [audio-thread] Discard all sounding state without a fade — the transport
  // jumped, or the host is splicing. Buffers keep their allocation.
  virtual void reset() noexcept OB_NONBLOCKING = 0;

  // [audio-thread] Render one block. The only method in this file that is
  // allowed to be expensive, and the only one that must be allocation-, lock-
  // and exception-free all the way down.
  //
  // The host may call this more than once per audio callback, with a different
  // transport each time — OneBeat splits a callback at loop seams so a wrap is
  // sample-accurate. A plugin must not assume one call per callback, and must
  // not assume `frames` equals the configured maximum.
  virtual ProcessStatus process(const ProcessBlock& block) noexcept OB_NONBLOCKING = 0;

  // [audio-thread] **OneBeat extension, not CLAP.** Called exactly once per
  // audio callback, before any process() call for that callback, so that
  // instances holding RCU-published data (rt/publisher.h) can tick their
  // reclamation epoch. CLAP has no equivalent because CLAP plugins do not share
  // OneBeat's reclamation scheme; a hosted CLAP plugin simply ignores it.
  virtual void beginAudioBlock() noexcept OB_NONBLOCKING {}

  // --- parameters ----------------------------------------------------------

  // [main-thread]
  virtual uint32_t paramCount() const = 0;
  virtual bool paramInfo(uint32_t index, ParamInfo& out) const = 0;
  virtual bool paramValue(ParamId param, double& out) const = 0;

  // [main-thread] Both directions of the display conversion. `valueToText` is
  // what the generic editor renders (OB-2-08); `textToValue` is what typing into
  // it produces. A plugin that implements neither gets a plain number.
  virtual bool paramValueToText(ParamId param, double value, char* out, size_t out_size) const = 0;
  virtual bool paramTextToValue(ParamId param, const char* text, double& out) const = 0;

  // [main-thread, while inactive] Deliver parameter changes when process() is
  // not running, and collect any the plugin wants to report back. Without this,
  // a knob turned while the transport is stopped does nothing — which is how
  // most "the plugin ignores my automation" bugs start.
  virtual void paramsFlush(const EventListView& in, EventList* out) {
    (void)in;
    (void)out;
  }

  // --- ports ---------------------------------------------------------------

  // [main-thread] Reading is always legal; the *values* are only stable while
  // active. A plugin changes them from Configured and tells the host via
  // PluginHost::audioPortsRescan().
  virtual uint32_t audioPortCount(PortDirection direction) const = 0;
  virtual bool audioPortInfo(PortDirection direction, uint32_t index, AudioPortInfo& out) const = 0;
  virtual uint32_t notePortCount(PortDirection direction) const {
    (void)direction;
    return 0;
  }
  virtual bool notePortInfo(PortDirection direction, uint32_t index, NotePortInfo& out) const {
    (void)direction;
    (void)index;
    (void)out;
    return false;
  }

  // --- state ---------------------------------------------------------------

  // [main-thread] Opaque to the host, always (FR-PLG-08, FR-PLG-10).
  virtual bool saveState(StateWriter& writer) const {
    (void)writer;
    return true;
  }
  virtual bool loadState(StateReader& reader) {
    (void)reader;
    return true;
  }

  // --- host cooperation ----------------------------------------------------

  // [main-thread] Runs in response to PluginHost::requestCallback().
  virtual void onMainThread() {}

  // [audio-thread] One unit of the work requested via
  // PluginHost::requestThreadPoolExec(). Called concurrently for distinct
  // indices, on host worker threads that are all real-time threads.
  virtual void threadPoolExec(uint32_t task_index) noexcept OB_NONBLOCKING { (void)task_index; }

  // [main-thread] Processing latency in frames, for FR-ENG-04 compensation.
  virtual uint32_t latencyFrames() const { return 0; }

  // [audio-thread] Release-tail length in frames; UINT32_MAX means infinite
  // (a feedback delay). The offline renderer uses it to decide how long to keep
  // rendering after the last note.
  virtual uint32_t tailFrames() const noexcept OB_NONBLOCKING { return 0; }

  // [audio-thread] **OneBeat extension, not CLAP.** How many voices are
  // sounding, for the performance readout. CLAP has no voice-count concept;
  // plugins that cannot answer return -1 and the UI shows nothing rather than a
  // confident zero.
  virtual int32_t activeVoiceCount() const noexcept OB_NONBLOCKING { return -1; }

 protected:
  explicit PluginInstance(PluginHost* host) : host_(host) {}

  PluginHost* host() const noexcept OB_NONBLOCKING { return host_; }
  const ProcessSetup& setup() const noexcept OB_NONBLOCKING { return setup_; }

  // Implemented by subclasses. The public wrappers above own the state machine
  // and the thread assertions so no implementation can forget either.
  virtual bool onConfigure(const ProcessSetup& setup) = 0;
  virtual bool onActivate() = 0;
  virtual void onDeactivate() = 0;
  virtual bool onStartProcessing() noexcept OB_NONBLOCKING { return true; }
  virtual void onStopProcessing() noexcept OB_NONBLOCKING {}

 private:
  PluginHost* host_ = nullptr;
  ProcessSetup setup_;
  State state_ = State::Created;
};

}  // namespace onebeat::plugin
