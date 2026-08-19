#include "core/time_stretch.h"

#include <cmath>

namespace onebeat::core {
namespace {

constexpr double Pi = 3.14159265358979323846;

}  // namespace

void TimeStretch::prepare(int channels) {
  channels_ = channels < 1 ? 1 : (channels > MaxChannels ? MaxChannels : channels);
  tail_.assign(static_cast<size_t>(channels_) * static_cast<size_t>(SynthesisHop), 0.0F);
  // A full grain of headroom per channel, so one produceHop always fits and a
  // caller asking for a single frame still gets served.
  ready_.assign(static_cast<size_t>(channels_) * static_cast<size_t>(GrainFrames), 0.0F);
  window_shape_.resize(GrainFrames);
  for (int i = 0; i < GrainFrames; ++i) {
    // Hann. Two of these overlapped at half their length sum to exactly 1, so
    // the cross-fade holds level rather than pumping.
    const double phase = 2.0 * Pi * static_cast<double>(i) / static_cast<double>(GrainFrames - 1);
    window_shape_[static_cast<size_t>(i)] = static_cast<float>(0.5 - (0.5 * std::cos(phase)));
  }
  prepared_ = true;
  reset();
}

void TimeStretch::reset() noexcept OB_NONBLOCKING {
  read_position_ = 0.0;
  ready_frames_ = 0;
  ready_read_ = 0;
  finished_ = false;
  for (float& value : tail_) value = 0.0F;
}

}  // namespace onebeat::core
