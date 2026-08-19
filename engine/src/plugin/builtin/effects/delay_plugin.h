// OneBeat Delay — a stereo feedback delay with damping and ping-pong.
//
// A delay line per channel, a one-pole lowpass in the feedback path so repeats
// darken as they fade, and a cross-feed switch that sends each channel's
// feedback into the other one. The delay time is read every sample from the
// (automatable) parameter and the read head interpolates, which is deliberate:
// automating the time then sounds like a tape delay being sped up rather than
// like a buffer being re-indexed.
#pragma once

#include <array>
#include <cstdint>
#include <vector>

#include "plugin/builtin/effects/effect_plugin.h"

namespace onebeat::plugin::builtin {

class DelayPlugin final : public EffectPlugin {
 public:
  enum : ParamId {
    ParamTime = EffectParamFirst,  // 2, seconds
    ParamFeedback = 3,
    ParamDamping = 4,
    ParamMix = 5,
    ParamPingPong = 6,
  };

  static constexpr const char* Identifier = "dev.onebeat.fx.delay";
  static constexpr double MaxDelaySeconds = 4.0;

  explicit DelayPlugin(PluginHost* host);

  PluginName name() const override { return PluginName("OneBeat Delay"); }

 protected:
  bool onConfigure(const ProcessSetup& setup) override;
  bool onActivate() override { return true; }
  void onDeactivate() override {}
  void processAudio(const core::AudioBufferView& io, int start_frame,
                    int num_frames) noexcept OB_NONBLOCKING override;
  void clearTail() noexcept OB_NONBLOCKING override;

 private:
  static constexpr int Channels = 2;

  std::array<std::vector<float>, Channels> lines_{};
  std::array<float, Channels> damping_state_{};
  size_t write_index_ = 0;
  // Smoothed towards the parameter each sample. Jumping the read head to a new
  // delay time produces a click; gliding to it produces the pitch bend a tape
  // delay makes, which is the sound people automate delay time *for*.
  double current_delay_frames_ = 0.0;
  double sample_rate_ = 48000.0;
};

}  // namespace onebeat::plugin::builtin
