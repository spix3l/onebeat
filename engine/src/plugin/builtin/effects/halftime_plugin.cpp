#include "plugin/builtin/effects/halftime_plugin.h"

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
    // Down to an eighth and up to double: the range that stays musical. 0.5 is
    // the name of the plug-in and therefore the default.
    make(HalftimePlugin::ParamRate, "Rate", 0.125, 2.0, 0.5),
    make(HalftimePlugin::ParamResync, "Resync", 0.25, HalftimePlugin::MaxResyncSeconds, 2.0),
    make(HalftimePlugin::ParamRepitch, "Repitch", 0.0, 1.0, 0.0, ParamFlagIsStepped),
    make(HalftimePlugin::ParamMix, "Mix", 0.0, 1.0, 1.0),
};

}  // namespace

HalftimePlugin::HalftimePlugin(PluginHost* host) : EffectPlugin(host) {
  declareParams(Params, sizeof(Params) / sizeof(Params[0]));
}

bool HalftimePlugin::onConfigure(const ProcessSetup& setup) {
  if (setup.sample_rate <= 0.0) return false;
  sample_rate_ = setup.sample_rate;
  // The ring has to hold everything the read head might still be behind by: a
  // full resync interval at the slowest rate, plus a block of slack.
  capture_size_ = static_cast<size_t>(MaxResyncSeconds * setup.sample_rate) +
                  static_cast<size_t>(setup.max_block_frames) + 2U;
  for (auto& plane : capture_) plane.assign(capture_size_, 0.0F);
  max_block_frames_ = static_cast<int>(setup.max_block_frames);
  stretch_.prepare(Channels);
  stretch_scratch_.assign(static_cast<size_t>(Channels) * static_cast<size_t>(max_block_frames_),
                          0.0F);
  setTailFrames(static_cast<uint32_t>(MaxResyncSeconds * setup.sample_rate));
  clearTail();
  return true;
}

void HalftimePlugin::clearTail() noexcept OB_NONBLOCKING {
  for (auto& plane : capture_) {
    for (float& sample : plane) sample = 0.0F;
  }
  written_ = 0;
  read_position_ = 0.0;
  frames_since_resync_ = 0;
  resync_fade_ = 0;
  stretch_.reset();
}

float HalftimePlugin::readCapture(double position, int channel) const noexcept OB_NONBLOCKING {
  if (capture_size_ == 0) return 0.0F;
  const auto index = static_cast<int64_t>(std::floor(position));
  const auto fraction = static_cast<float>(position - static_cast<double>(index));
  const auto size = static_cast<int64_t>(capture_size_);
  // Absolute positions, wrapped only at the point of access, so a read head
  // that is 100,000 frames behind is still addressed by plain subtraction.
  const auto first = static_cast<size_t>(((index % size) + size) % size);
  const auto second = static_cast<size_t>((((index + 1) % size) + size) % size);
  const auto plane = static_cast<size_t>(channel < Channels ? channel : Channels - 1);
  const float a = capture_[plane][first];
  const float b = capture_[plane][second];
  return a + ((b - a) * fraction);
}

void HalftimePlugin::processAudio(const core::AudioBufferView& io, int start_frame,
                                  int num_frames) noexcept OB_NONBLOCKING {
  const double rate = value(ParamRate);
  const double resync_frames = value(ParamResync) * sample_rate_;
  const auto mix = static_cast<float>(value(ParamMix));
  const bool repitch = value(ParamRepitch) >= 0.5;
  const int out_channels = io.numChannels();
  if (capture_size_ == 0 || out_channels <= 0 || rate <= 0.0) return;
  if (max_block_frames_ <= 0) return;

  // Switching modes mid-flight leaves the stretcher's overlap tail describing
  // audio the other path has since walked away from. Rewinding it to the shared
  // read head is what makes the switch a crossfade rather than a glitch.
  if (repitch != last_repitch_) {
    last_repitch_ = repitch;
    if (!repitch) {
      stretch_.reset();
      stretch_.setReadPosition(read_position_);
    }
    resync_fade_ = ResyncFadeFrames;
  }

  for (int frame = 0; frame < num_frames; ++frame) {
    const int position = start_frame + frame;

    // Capture first: the read head may legitimately be reading the sample that
    // is being written this very frame, which is what a rate of 1 does.
    const auto slot = static_cast<size_t>(written_ % static_cast<int64_t>(capture_size_));
    std::array<float, Channels> dry{0.0F, 0.0F};
    for (int channel = 0; channel < Channels; ++channel) {
      const int source = channel < out_channels ? channel : out_channels - 1;
      dry[static_cast<size_t>(channel)] = io.channel(source)[position];
      capture_[static_cast<size_t>(channel)][slot] = dry[static_cast<size_t>(channel)];
    }
    ++written_;

    std::array<float, Channels> wet{0.0F, 0.0F};
    if (repitch) {
      // Straight resampled playback: the speed moves the pitch, which is the
      // tape/turntable half of what "halftime" means.
      for (int channel = 0; channel < Channels; ++channel) {
        wet[static_cast<size_t>(channel)] = readCapture(read_position_, channel);
      }
      read_position_ += rate;
    } else {
      // Pitch held. The stretcher owns the read head in this mode, so the
      // effect follows it rather than advancing its own.
      float* planes[Channels] = {stretch_scratch_.data(),
                                 stretch_scratch_.data() + static_cast<size_t>(max_block_frames_)};
      const CaptureReader reader{this};
      if (stretch_.render(reader, rate, planes, Channels, 1) == 1) {
        wet[0] = planes[0][0];
        wet[1] = planes[1][0];
      }
      read_position_ = stretch_.readPosition();
    }

    // A resync crossfades from where the read head was to where the write head
    // is. Fading rather than jumping is the difference between the effect's
    // characteristic edge and a click.
    if (resync_fade_ > 0) {
      const auto blend = static_cast<float>(resync_fade_) / static_cast<float>(ResyncFadeFrames);
      for (int channel = 0; channel < Channels; ++channel) {
        const auto index = static_cast<size_t>(channel);
        wet[index] = (wet[index] * (1.0F - blend)) + (dry[index] * blend);
      }
      --resync_fade_;
    }

    for (int channel = 0; channel < out_channels; ++channel) {
      const int plane = channel < Channels ? channel : Channels - 1;
      float& sample = io.channel(channel)[position];
      sample = (sample * (1.0F - mix)) + (wet[static_cast<size_t>(plane)] * mix);
    }

    ++frames_since_resync_;
    if (static_cast<double>(frames_since_resync_) >= resync_frames) {
      frames_since_resync_ = 0;
      resync_fade_ = ResyncFadeFrames;
      // Catch up to just behind the write head, leaving one fade's worth of
      // material so the crossfade has something on both sides.
      read_position_ = static_cast<double>(written_ - ResyncFadeFrames);
      if (!repitch) stretch_.setReadPosition(read_position_);
    }
    // A read head that has fallen further behind than the ring is deep would
    // read audio that has already been overwritten. Snapping is the honest
    // failure: it is what a shorter resync would have done anyway.
    const double behind = static_cast<double>(written_) - read_position_;
    if (behind >= static_cast<double>(capture_size_ - 2)) {
      read_position_ = static_cast<double>(written_) - static_cast<double>(capture_size_ - 2);
      if (!repitch) stretch_.setReadPosition(read_position_);
    }
  }
}

}  // namespace onebeat::plugin::builtin
