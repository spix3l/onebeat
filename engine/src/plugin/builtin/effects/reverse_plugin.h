// OneBeat Reverse — captures a window of audio and plays it back backwards.
//
// The effect works in alternating windows. While window N is being captured,
// window N-1 is played back from its end towards its start; when the capture
// fills, the two swap. That one-window delay is inherent and is not a bug to be
// engineered away: you cannot play something backwards before you have heard
// all of it. It is reported through `latencyFrames` so the host can say so.
//
// The window length is the whole of the sound design. Short windows stutter and
// granulate; long windows swallow a bar and hand it back inside out. Both are
// wanted, so the parameter spans both and is automatable.
#pragma once

#include <array>
#include <cstdint>
#include <vector>

#include "plugin/builtin/effects/effect_plugin.h"

namespace onebeat::plugin::builtin {

class ReversePlugin final : public EffectPlugin {
 public:
  enum : ParamId {
    ParamWindow = EffectParamFirst,  // 2, seconds
    ParamCrossfade = 3,
    ParamMix = 4,
  };

  static constexpr const char* Identifier = "dev.onebeat.fx.reverse";
  static constexpr double MaxWindowSeconds = 4.0;

  explicit ReversePlugin(PluginHost* host);

  PluginName name() const override { return PluginName("OneBeat Reverse"); }

  // One window of delay, by construction. Saying so is what lets the mixer
  // compensate instead of the user wondering why the track drifted.
  uint32_t latencyFrames() const override { return latency_frames_; }

 protected:
  bool onConfigure(const ProcessSetup& setup) override;
  bool onActivate() override { return true; }
  void onDeactivate() override {}
  void processAudio(const core::AudioBufferView& io, int start_frame,
                    int num_frames) noexcept OB_NONBLOCKING override;
  void clearTail() noexcept OB_NONBLOCKING override;

 private:
  static constexpr int Channels = 2;

  // Two buffers, swapped at each window boundary: one being filled, one being
  // played backwards. A single buffer cannot do both — the read head would
  // overwrite what it is about to reach.
  std::array<std::array<std::vector<float>, Channels>, 2> buffers_{};
  size_t capture_buffer_ = 0;
  int64_t position_ = 0;       // frames into the current window
  int64_t window_frames_ = 0;  // resolved at each boundary, never mid-window
  bool has_played_once_ = false;
  uint32_t latency_frames_ = 0;
  double sample_rate_ = 48000.0;
};

}  // namespace onebeat::plugin::builtin
