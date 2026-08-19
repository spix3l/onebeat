#include "plugin/builtin/effects/delay_plugin.h"

#include <cmath>

namespace onebeat::plugin::builtin {
namespace {

ParamInfo make(ParamId id, const char* label, double min, double max, double fallback,
               uint32_t extra = 0) noexcept {
  ParamInfo value;
  value.id = id;
  value.name.assign(label);
  value.module.assign("/");
  value.min_value = min;
  value.max_value = max;
  value.default_value = fallback;
  value.flags = ParamFlagIsAutomatable | ParamFlagIsModulatable | extra;
  return value;
}

const ParamInfo Params[] = {
    make(DelayPlugin::ParamTime, "Time", 0.001, DelayPlugin::MaxDelaySeconds, 0.375),
    make(DelayPlugin::ParamFeedback, "Feedback", 0.0, 0.98, 0.4),
    make(DelayPlugin::ParamDamping, "Damping", 0.0, 1.0, 0.3),
    make(DelayPlugin::ParamMix, "Mix", 0.0, 1.0, 0.3),
    make(DelayPlugin::ParamPingPong, "Ping-pong", 0.0, 1.0, 0.0, ParamFlagIsStepped),
};

// How fast the read head glides to a new delay time, as a fraction of the gap
// per sample. Slow enough to be a pitch bend rather than a jump.
constexpr double GlideRate = 0.0002;

}  // namespace

DelayPlugin::DelayPlugin(PluginHost* host) : EffectPlugin(host) {
  declareParams(Params, sizeof(Params) / sizeof(Params[0]));
}

bool DelayPlugin::onConfigure(const ProcessSetup& setup) {
  if (setup.sample_rate <= 0.0) return false;
  sample_rate_ = setup.sample_rate;
  const auto frames = static_cast<size_t>(MaxDelaySeconds * setup.sample_rate) + 2U;
  for (auto& line : lines_) line.assign(frames, 0.0F);
  // At maximum feedback the repeats take many seconds to fall below audibility.
  setTailFrames(static_cast<uint32_t>(setup.sample_rate * 8.0));
  clearTail();
  current_delay_frames_ = value(ParamTime) * sample_rate_;
  return true;
}

void DelayPlugin::clearTail() noexcept OB_NONBLOCKING {
  for (auto& line : lines_) {
    for (float& sample : line) sample = 0.0F;
  }
  for (float& state : damping_state_) state = 0.0F;
  write_index_ = 0;
}

void DelayPlugin::processAudio(const core::AudioBufferView& io, int start_frame,
                               int num_frames) noexcept OB_NONBLOCKING {
  const double target_frames = value(ParamTime) * sample_rate_;
  const auto feedback = static_cast<float>(value(ParamFeedback));
  const auto damping = static_cast<float>(value(ParamDamping));
  const auto mix = static_cast<float>(value(ParamMix));
  const bool ping_pong = value(ParamPingPong) >= 0.5;

  const size_t size = lines_[0].size();
  const int out_channels = io.numChannels();
  if (size == 0 || out_channels <= 0) return;

  for (int frame = 0; frame < num_frames; ++frame) {
    const int position = start_frame + frame;

    current_delay_frames_ += (target_frames - current_delay_frames_) * GlideRate;
    double delay = current_delay_frames_;
    if (delay < 1.0) delay = 1.0;
    if (delay > static_cast<double>(size - 2)) delay = static_cast<double>(size - 2);

    // Fractional read head, interpolated. An integer one quantises the delay
    // time to whole samples, which is audible as zipper noise while it glides.
    const double read = static_cast<double>(write_index_ + size) - delay;
    const auto read_index = static_cast<size_t>(read) % size;
    const size_t next_index = (read_index + 1) % size;
    const auto fraction = static_cast<float>(read - std::floor(read));

    std::array<float, Channels> delayed{0.0F, 0.0F};
    for (int channel = 0; channel < Channels; ++channel) {
      const auto index = static_cast<size_t>(channel);
      const float a = lines_[index][read_index];
      const float b = lines_[index][next_index];
      delayed[index] = a + ((b - a) * fraction);
    }

    for (int channel = 0; channel < Channels; ++channel) {
      const auto index = static_cast<size_t>(channel);
      const int source_channel = channel < out_channels ? channel : out_channels - 1;
      const float dry = io.channel(source_channel)[position];

      // Ping-pong feeds each channel's repeat into the *other* line, so
      // successive echoes alternate sides.
      const float fed = ping_pong ? delayed[index == 0 ? 1 : 0] : delayed[index];
      // One-pole lowpass in the feedback path: each pass through the loop is a
      // little darker than the last, which is what stops a long feedback from
      // turning into a hiss build-up.
      damping_state_[index] = (fed * (1.0F - damping)) + (damping_state_[index] * damping);
      lines_[index][write_index_] = dry + (damping_state_[index] * feedback);
    }

    for (int channel = 0; channel < out_channels; ++channel) {
      const int line = channel < Channels ? channel : Channels - 1;
      float& sample = io.channel(channel)[position];
      sample = (sample * (1.0F - mix)) + (delayed[static_cast<size_t>(line)] * mix);
    }
    write_index_ = (write_index_ + 1) % size;
  }
}

}  // namespace onebeat::plugin::builtin
