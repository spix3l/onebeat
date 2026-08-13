// The built-in sampler, seated behind PluginInstance (OB-2-01 scope §7).
//
// This is the proof that the model is not shaped around third-party plugins:
// OneBeat's own instrument goes through exactly the same interface a hosted CLAP
// plugin will, with no privileged side channel. It is also the precursor to
// FR-EXT-08 — when the built-ins move onto the public WASM API in Stage 6, this
// is the class that gets ported, and the engine above it does not change.
//
// `core::Sampler` keeps the DSP. The split is deliberate: the DSP is a voice
// allocator that knows nothing about parameters, events or activation states,
// and this class is the adapter that gives it a format-agnostic face.
#pragma once

#include <cstdint>

#include "core/sampler.h"
#include "plugin/plugin_instance.h"

namespace onebeat::plugin::builtin {

class SamplerPlugin final : public PluginInstance {
 public:
  // Parameter IDs are frozen: projects saved by v0.2 automate them by number.
  // Adding a parameter means adding an ID, never renumbering these.
  enum : ParamId {
    ParamGain = 1,
    ParamTranspose = 2,
  };

  static constexpr PortId MainOutputPort = 0;
  static constexpr PortId NoteInputPort = 0;

  SamplerPlugin(PluginHost* host, rt::RtLog* log);

  // --- identity ---
  PluginName name() const override { return PluginName("OneBeat Sampler"); }

  // --- processing ---
  void reset() noexcept OB_NONBLOCKING override;
  ProcessStatus process(const ProcessBlock& block) noexcept OB_NONBLOCKING override;
  void beginAudioBlock() noexcept OB_NONBLOCKING override { sampler_.beginBlock(); }
  int32_t activeVoiceCount() const noexcept OB_NONBLOCKING override {
    return static_cast<int32_t>(sampler_.activeVoices());
  }
  // Voices fade over ReleaseSeconds; the offline renderer needs to know that so
  // an export does not truncate the last note's tail.
  uint32_t tailFrames() const noexcept OB_NONBLOCKING override { return tail_frames_; }

  // --- parameters ---
  uint32_t paramCount() const override { return ParameterCount; }
  bool paramInfo(uint32_t index, ParamInfo& out) const override;
  bool paramValue(ParamId param, double& out) const override;
  bool paramValueToText(ParamId param, double value, char* out, size_t out_size) const override;
  bool paramTextToValue(ParamId param, const char* text, double& out) const override;
  void paramsFlush(const EventListView& in, EventList* out) override;

  // --- ports ---
  uint32_t audioPortCount(PortDirection direction) const override;
  bool audioPortInfo(PortDirection direction, uint32_t index, AudioPortInfo& out) const override;
  uint32_t notePortCount(PortDirection direction) const override;
  bool notePortInfo(PortDirection direction, uint32_t index, NotePortInfo& out) const override;

  // --- state ---
  bool saveState(StateWriter& writer) const override;
  bool loadState(StateReader& reader) override;

  // --- the DSP underneath -------------------------------------------------
  // Sample loading is a main-thread concern with its own RCU publication, so it
  // stays on the concrete sampler rather than being forced through the
  // format-agnostic interface, which has no notion of "a sample".
  core::Sampler& sampler() noexcept { return sampler_; }
  const core::Sampler& sampler() const noexcept { return sampler_; }

 protected:
  bool onConfigure(const ProcessSetup& setup) override;
  bool onActivate() override;
  void onDeactivate() override;

 private:
  static constexpr uint32_t ParameterCount = 2;

  // Base values are what the user set and what saveState() writes; modulation is
  // a per-block, non-destructive offset that is never written back. Keeping them
  // in separate fields is what makes that guarantee structural rather than a
  // convention someone has to remember (D5).
  ModulatedValue gain_{1.0, 0.0};
  ModulatedValue transpose_{0.0, 0.0};

  void applyEvent(const PluginEvent& event) noexcept OB_NONBLOCKING;

  core::Sampler sampler_;
  uint32_t tail_frames_ = 0;
};

}  // namespace onebeat::plugin::builtin
