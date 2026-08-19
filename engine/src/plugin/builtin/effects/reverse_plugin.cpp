#include "plugin/builtin/effects/reverse_plugin.h"

#include <cmath>

namespace onebeat::plugin::builtin {
namespace {

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
    // From a granular 50 ms up to a bar and a half at 120 bpm.
    make(ReversePlugin::ParamWindow, "Window", 0.05, ReversePlugin::MaxWindowSeconds, 0.5),
    make(ReversePlugin::ParamCrossfade, "Crossfade", 0.0, 1.0, 0.15),
    make(ReversePlugin::ParamMix, "Mix", 0.0, 1.0, 1.0),
};

// The crossfade parameter is a fraction of the window, capped so the fades at
// the two ends can never overlap each other.
constexpr double MaxCrossfadeFraction = 0.5;

}  // namespace

ReversePlugin::ReversePlugin(PluginHost* host) : EffectPlugin(host) {
  declareParams(Params, sizeof(Params) / sizeof(Params[0]));
}

bool ReversePlugin::onConfigure(const ProcessSetup& setup) {
  if (setup.sample_rate <= 0.0) return false;
  sample_rate_ = setup.sample_rate;
  const auto frames = static_cast<size_t>(MaxWindowSeconds * setup.sample_rate) + 2U;
  for (auto& buffer : buffers_) {
    for (auto& plane : buffer) plane.assign(frames, 0.0F);
  }
  window_frames_ = static_cast<int64_t>(value(ParamWindow) * setup.sample_rate);
  latency_frames_ = static_cast<uint32_t>(window_frames_);
  setTailFrames(static_cast<uint32_t>(MaxWindowSeconds * setup.sample_rate));
  clearTail();
  return true;
}

void ReversePlugin::clearTail() noexcept OB_NONBLOCKING {
  for (auto& buffer : buffers_) {
    for (auto& plane : buffer) {
      for (float& sample : plane) sample = 0.0F;
    }
  }
  capture_buffer_ = 0;
  position_ = 0;
  has_played_once_ = false;
}

void ReversePlugin::processAudio(const core::AudioBufferView& io, int start_frame,
                                 int num_frames) noexcept OB_NONBLOCKING {
  const auto mix = static_cast<float>(value(ParamMix));
  const double crossfade_fraction = value(ParamCrossfade) * MaxCrossfadeFraction;
  const int out_channels = io.numChannels();
  const size_t capacity = buffers_[0][0].size();
  if (out_channels <= 0 || capacity == 0) return;

  if (window_frames_ <= 0) {
    window_frames_ = static_cast<int64_t>(value(ParamWindow) * sample_rate_);
  }

  for (int frame = 0; frame < num_frames; ++frame) {
    const int position = start_frame + frame;
    const size_t playback_buffer = 1U - capture_buffer_;

    // Capture into this window, and read the *other* one backwards.
    const auto write_slot = static_cast<size_t>(position_);
    const int64_t read_offset = window_frames_ - 1 - position_;
    const auto read_slot = static_cast<size_t>(read_offset < 0 ? 0 : read_offset);

    // Fade the two ends of the reversed window into silence. The join between
    // one window and the next is a discontinuity in the waveform no matter what
    // is on either side of it, and a fade is the only thing that hides it.
    float envelope = 1.0F;
    const auto fade_frames =
        static_cast<int64_t>(static_cast<double>(window_frames_) * crossfade_fraction);
    if (fade_frames > 0) {
      const int64_t from_start = position_;
      const int64_t from_end = window_frames_ - 1 - position_;
      const int64_t nearest = from_start < from_end ? from_start : from_end;
      if (nearest < fade_frames) {
        envelope =
            static_cast<float>(static_cast<double>(nearest) / static_cast<double>(fade_frames));
      }
    }

    for (int channel = 0; channel < Channels; ++channel) {
      const auto plane = static_cast<size_t>(channel);
      const int source = channel < out_channels ? channel : out_channels - 1;
      if (write_slot < capacity) {
        buffers_[capture_buffer_][plane][write_slot] = io.channel(source)[position];
      }
    }

    for (int channel = 0; channel < out_channels; ++channel) {
      const auto plane = static_cast<size_t>(channel < Channels ? channel : Channels - 1);
      // Before the first window has filled there is nothing to play backwards.
      // Silence is the honest output; anything else would be the dry signal
      // pretending to be reversed.
      const float wet = has_played_once_ && read_slot < capacity
                            ? buffers_[playback_buffer][plane][read_slot] * envelope
                            : 0.0F;
      float& sample = io.channel(channel)[position];
      sample = (sample * (1.0F - mix)) + (wet * mix);
    }

    ++position_;
    if (position_ >= window_frames_) {
      position_ = 0;
      capture_buffer_ = playback_buffer;
      has_played_once_ = true;
      // The window length is re-read only here. Changing it mid-window would
      // leave the read head pointing past the end of what was captured.
      const auto next = static_cast<int64_t>(value(ParamWindow) * sample_rate_);
      window_frames_ = next > 0 && static_cast<size_t>(next) < capacity ? next : window_frames_;
      latency_frames_ = static_cast<uint32_t>(window_frames_);
    }
  }
}

}  // namespace onebeat::plugin::builtin
