// The shared seat for OneBeat's built-in effects (FR-BIP, EPIC-7).
//
// Four things are the same for every effect and none of them is interesting:
// a stereo in-place port pair, a parameter table, the event loop that turns
// ParamValue and ParamModulation into `ModulatedValue`s, and a bypass. This
// class owns all four so that a concrete effect is only its DSP.
//
// **Bypass is a parameter, not a host trick.** `ParamFlagIsBypass` tells the
// host to bind its own control to it, which means the mixer's bypass button and
// an automation curve drive exactly the same thing — and a bypass that can be
// automated is the difference between a mix control and a debugging switch.
//
// These are built-ins hosted through `PluginInstance`, exactly like a CLAP
// effect will be. There is no privileged path: when Stage 6 moves the built-ins
// onto the public API (FR-EXT-08), this is the class that gets ported and the
// mixer above it does not change.
#pragma once

#include <array>
#include <cstdint>

#include "core/audio_buffer.h"
#include "core/rt/rt.h"
#include "plugin/plugin_instance.h"

namespace onebeat::plugin::builtin {

// Every built-in effect reserves this ID for its bypass so the mixer can drive
// bypass generically, without asking each plug-in which parameter it is.
inline constexpr ParamId EffectParamBypass = 1;
// Concrete effects number their own parameters from here upwards.
inline constexpr ParamId EffectParamFirst = 2;

// The most parameters any built-in effect declares. A fixed array rather than a
// vector because `paramsFlush` and the event loop read it on the audio thread.
inline constexpr size_t MaxEffectParams = 12;

class EffectPlugin : public PluginInstance {
 public:
  static constexpr PortId MainPort = 0;

  // --- parameters ---
  uint32_t paramCount() const override { return static_cast<uint32_t>(param_count_); }
  bool paramInfo(uint32_t index, ParamInfo& out) const override;
  bool paramValue(ParamId param, double& out) const override;
  bool paramValueToText(ParamId param, double value, char* out, size_t out_size) const override;
  bool paramTextToValue(ParamId param, const char* text, double& out) const override;
  void paramsFlush(const EventListView& in, EventList* out) override;

  // --- ports: one stereo pair, processed in place ---
  uint32_t audioPortCount(PortDirection direction) const override;
  bool audioPortInfo(PortDirection direction, uint32_t index, AudioPortInfo& out) const override;

  // --- state ---
  bool saveState(StateWriter& writer) const override;
  bool loadState(StateReader& reader) override;

  // --- processing ---
  void reset() noexcept OB_NONBLOCKING override;
  ProcessStatus process(const ProcessBlock& block) noexcept OB_NONBLOCKING override;

  bool bypassed() const noexcept OB_NONBLOCKING { return values_[0].effective(params_[0]) >= 0.5; }

  // How long this effect keeps sounding after its input stops, in frames. The
  // offline renderer uses it so an export does not clip a reverb tail off.
  // Public, like the base class's: narrowing an override's visibility means a
  // caller holding a `PluginInstance&` can reach it and one holding the
  // concrete type cannot, which is the wrong way round.
  uint32_t tailFrames() const noexcept OB_NONBLOCKING override { return tail_frames_; }

 protected:
  explicit EffectPlugin(PluginHost* host) : PluginInstance(host) {}

  // Called once from the subclass's constructor. `bypass` is added here rather
  // than by every subclass, so no effect can ship without one.
  void declareParams(const ParamInfo* params, size_t count);

  // The value the DSP should use this block: base plus modulation, clamped.
  // Addressed by ParamId so a subclass reads `value(ParamMix)` and never has to
  // know where in the table that landed.
  double value(ParamId param) const noexcept OB_NONBLOCKING;

  // [audio-thread] The DSP. `io` is the track bus, read and written in place;
  // the base class has already handled bypass, so reaching here means the
  // effect is live.
  virtual void processAudio(const core::AudioBufferView& io, int start_frame,
                            int num_frames) noexcept OB_NONBLOCKING = 0;
  // [audio-thread] Drop every tail and delay line without freeing them.
  virtual void clearTail() noexcept OB_NONBLOCKING = 0;

  void setTailFrames(uint32_t frames) noexcept OB_NONBLOCKING { tail_frames_ = frames; }

  size_t indexOf(ParamId param) const noexcept OB_NONBLOCKING;

 private:
  void applyEvent(const PluginEvent& event) noexcept OB_NONBLOCKING;

  std::array<ParamInfo, MaxEffectParams> params_{};
  std::array<ModulatedValue, MaxEffectParams> values_{};
  size_t param_count_ = 0;
  uint32_t tail_frames_ = 0;
};

}  // namespace onebeat::plugin::builtin
