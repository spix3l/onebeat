// OneBeat Reverb — a Schroeder/Moorer comb-and-allpass reverberator.
//
// Eight parallel comb filters per channel feed four series allpasses, the
// classic "Freeverb" topology. It is not the most sophisticated reverb in
// existence and it is not trying to be: it is small, it allocates nothing on
// the audio thread, its parameters map onto things a musician already
// understands, and it sounds like a room. The comb delay lengths are mutually
// prime so their echo trains do not line up into a ringing pitch, and the right
// channel is offset from the left by a fixed stereo spread.
#pragma once

#include <array>
#include <cstdint>
#include <vector>

#include "plugin/builtin/effects/effect_plugin.h"

namespace onebeat::plugin::builtin {

class ReverbPlugin final : public EffectPlugin {
 public:
  // Frozen: projects automate these by number.
  enum : ParamId {
    ParamSize = EffectParamFirst,  // 2
    ParamDamping = 3,
    ParamWidth = 4,
    ParamMix = 5,
    ParamPreDelay = 6,
  };

  static constexpr const char* Identifier = "dev.onebeat.fx.reverb";

  explicit ReverbPlugin(PluginHost* host);

  PluginName name() const override { return PluginName("OneBeat Reverb"); }

 protected:
  bool onConfigure(const ProcessSetup& setup) override;
  bool onActivate() override { return true; }
  void onDeactivate() override {}
  void processAudio(const core::AudioBufferView& io, int start_frame,
                    int num_frames) noexcept OB_NONBLOCKING override;
  void clearTail() noexcept OB_NONBLOCKING override;

 private:
  static constexpr int CombCount = 8;
  static constexpr int AllpassCount = 4;
  static constexpr int Channels = 2;

  // A delay line with a one-pole lowpass in its feedback path. The lowpass is
  // what makes the tail darken as it decays, which is what real rooms do and
  // what an undamped comb bank conspicuously does not.
  struct Comb {
    std::vector<float> buffer;
    size_t index = 0;
    float store = 0.0F;

    float process(float input, float feedback, float damping) noexcept OB_NONBLOCKING {
      const float output = buffer[index];
      store = (output * (1.0F - damping)) + (store * damping);
      buffer[index] = input + (store * feedback);
      if (++index >= buffer.size()) index = 0;
      return output;
    }
  };

  struct Allpass {
    std::vector<float> buffer;
    size_t index = 0;

    float process(float input) noexcept OB_NONBLOCKING {
      const float buffered = buffer[index];
      const float output = buffered - input;
      // 0.5 throughout: the classic value, and the one that keeps the allpass
      // chain flat while it smears the comb bank's echo density.
      buffer[index] = input + (buffered * 0.5F);
      if (++index >= buffer.size()) index = 0;
      return output;
    }
  };

  std::array<std::array<Comb, CombCount>, Channels> combs_{};
  std::array<std::array<Allpass, AllpassCount>, Channels> allpasses_{};
  // Pre-delay: a plain delay line ahead of the reverberator. A few milliseconds
  // of it is what separates a source from the room it is in.
  std::array<std::vector<float>, Channels> predelay_{};
  size_t predelay_index_ = 0;
  double sample_rate_ = 48000.0;
};

}  // namespace onebeat::plugin::builtin
