#include "plugin/builtin/effects/reverb_plugin.h"

#include <cmath>

namespace onebeat::plugin::builtin {
namespace {

// Freeverb's tuning, in frames at 44.1 kHz, scaled to the real rate in
// onConfigure. Mutually prime so the comb echo trains never align into a pitch.
constexpr int CombTuning[] = {1116, 1188, 1277, 1356, 1422, 1491, 1557, 1617};
constexpr int AllpassTuning[] = {556, 441, 341, 225};
// The right channel's delays are this many frames longer than the left's. Small
// enough to read as width rather than as two different rooms.
constexpr int StereoSpread = 23;
constexpr double TuningRate = 44100.0;
constexpr double MaxPreDelaySeconds = 0.2;

ParamInfo make(ParamId id, const char* label, double min, double max, double fallback) noexcept {
  ParamInfo value;
  value.id = id;
  value.name.assign(label);
  value.module.assign("/");
  value.min_value = min;
  value.max_value = max;
  value.default_value = fallback;
  value.flags = ParamFlagIsAutomatable | ParamFlagIsModulatable;
  return value;
}

const ParamInfo Params[] = {
    make(ReverbPlugin::ParamSize, "Size", 0.0, 1.0, 0.5),
    make(ReverbPlugin::ParamDamping, "Damping", 0.0, 1.0, 0.5),
    make(ReverbPlugin::ParamWidth, "Width", 0.0, 1.0, 1.0),
    make(ReverbPlugin::ParamMix, "Mix", 0.0, 1.0, 0.3),
    make(ReverbPlugin::ParamPreDelay, "Pre-delay", 0.0, 1.0, 0.0),
};

}  // namespace

ReverbPlugin::ReverbPlugin(PluginHost* host) : EffectPlugin(host) {
  declareParams(Params, sizeof(Params) / sizeof(Params[0]));
}

bool ReverbPlugin::onConfigure(const ProcessSetup& setup) {
  if (setup.sample_rate <= 0.0) return false;
  sample_rate_ = setup.sample_rate;
  const double scale = setup.sample_rate / TuningRate;

  // Every allocation the instance will ever perform happens here.
  for (int channel = 0; channel < Channels; ++channel) {
    const int spread = channel * StereoSpread;
    for (int i = 0; i < CombCount; ++i) {
      const auto frames = static_cast<size_t>((CombTuning[i] * scale) + spread);
      combs_[static_cast<size_t>(channel)][static_cast<size_t>(i)].buffer.assign(
          frames > 1 ? frames : 2, 0.0F);
    }
    for (int i = 0; i < AllpassCount; ++i) {
      const auto frames = static_cast<size_t>((AllpassTuning[i] * scale) + spread);
      allpasses_[static_cast<size_t>(channel)][static_cast<size_t>(i)].buffer.assign(
          frames > 1 ? frames : 2, 0.0F);
    }
    predelay_[static_cast<size_t>(channel)].assign(
        static_cast<size_t>(MaxPreDelaySeconds * setup.sample_rate) + 1U, 0.0F);
  }

  // A generous tail: at maximum size the comb feedback decays over several
  // seconds, and an export that stops before it does is an export with a click
  // at the end.
  setTailFrames(static_cast<uint32_t>(setup.sample_rate * 6.0));
  clearTail();
  return true;
}

void ReverbPlugin::clearTail() noexcept OB_NONBLOCKING {
  for (auto& channel : combs_) {
    for (Comb& comb : channel) {
      for (float& sample : comb.buffer) sample = 0.0F;
      comb.index = 0;
      comb.store = 0.0F;
    }
  }
  for (auto& channel : allpasses_) {
    for (Allpass& allpass : channel) {
      for (float& sample : allpass.buffer) sample = 0.0F;
      allpass.index = 0;
    }
  }
  for (auto& line : predelay_) {
    for (float& sample : line) sample = 0.0F;
  }
  predelay_index_ = 0;
}

void ReverbPlugin::processAudio(const core::AudioBufferView& io, int start_frame,
                                int num_frames) noexcept OB_NONBLOCKING {
  const auto size = static_cast<float>(value(ParamSize));
  const auto damping = static_cast<float>(value(ParamDamping));
  const auto width = static_cast<float>(value(ParamWidth));
  const auto mix = static_cast<float>(value(ParamMix));
  const double predelay_seconds = value(ParamPreDelay) * MaxPreDelaySeconds;

  // Room size maps onto comb feedback. Capped below 1 so the tail always
  // decays: a feedback of exactly 1 is an oscillator, not a reverb.
  const float feedback = 0.7F + (size * 0.28F);
  const auto predelay_frames = static_cast<size_t>(predelay_seconds * sample_rate_);
  const size_t predelay_size = predelay_[0].size();

  const int out_channels = io.numChannels();
  if (out_channels <= 0 || predelay_size == 0) return;

  for (int frame = 0; frame < num_frames; ++frame) {
    const int position = start_frame + frame;
    // Mono sum into the reverberator: two independent reverbs on a correlated
    // stereo source sound like two rooms, not one wide one. Width is applied on
    // the way out instead, where it belongs.
    float input = 0.0F;
    for (int channel = 0; channel < out_channels; ++channel) {
      input += io.channel(channel)[position];
    }
    input /= static_cast<float>(out_channels);

    const size_t write = predelay_index_;
    const size_t read = (write + predelay_size - (predelay_frames % predelay_size)) % predelay_size;

    std::array<float, Channels> wet{0.0F, 0.0F};
    for (int channel = 0; channel < Channels; ++channel) {
      const auto index = static_cast<size_t>(channel);
      // Write before read. At a pre-delay of zero the two indices are the same
      // slot, and reading first would hand the reverberator whatever that slot
      // held a whole ring ago — a fixed 200 ms of latency that no parameter
      // asked for and nothing on screen would explain.
      predelay_[index][write] = input;
      const float delayed = predelay_[index][read];

      float accumulated = 0.0F;
      // Parallel combs build the echo density...
      for (Comb& comb : combs_[index]) {
        accumulated += comb.process(delayed * 0.015F, feedback, damping);
      }
      // ...and series allpasses smear it into something that stops sounding
      // like a row of discrete echoes.
      for (Allpass& allpass : allpasses_[index]) {
        accumulated = allpass.process(accumulated);
      }
      wet[index] = accumulated;
    }
    predelay_index_ = (predelay_index_ + 1) % predelay_size;

    // Width as a mid/side blend: at 0 the two channels collapse to mono, at 1
    // they stay as the comb bank's stereo spread made them.
    const float mid = (wet[0] + wet[1]) * 0.5F;
    const float left = mid + ((wet[0] - mid) * width);
    const float right = mid + ((wet[1] - mid) * width);

    for (int channel = 0; channel < out_channels; ++channel) {
      const float wet_sample = channel == 0 ? left : right;
      float& sample = io.channel(channel)[position];
      sample = (sample * (1.0F - mix)) + (wet_sample * mix);
    }
  }
}

}  // namespace onebeat::plugin::builtin
