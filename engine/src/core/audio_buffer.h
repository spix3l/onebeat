// Pre-allocated, non-owning-view audio buffers. All allocation happens at
// prepare() time on a non-RT thread; the audio thread only ever gets views.
#pragma once

#include <algorithm>
#include <cstddef>
#include <vector>

#include "core/rt/rt.h"

namespace onebeat::core {

inline constexpr int MaxChannels = 2;  // v0.1 is stereo master only

// A borrowed, planar, non-owning view onto float32 channel buffers.
class AudioBufferView {
 public:
  AudioBufferView() = default;
  AudioBufferView(float* const* channels, int num_channels, int num_frames) noexcept
      : channels_(channels), num_channels_(num_channels), num_frames_(num_frames) {}

  float* channel(int index) const noexcept OB_NONBLOCKING { return channels_[index]; }
  int numChannels() const noexcept OB_NONBLOCKING { return num_channels_; }
  int numFrames() const noexcept OB_NONBLOCKING { return num_frames_; }

  void clear() const noexcept OB_NONBLOCKING {
    for (int channel = 0; channel < num_channels_; ++channel) {
      float* data = channels_[channel];
      for (int frame = 0; frame < num_frames_; ++frame) {
        data[frame] = 0.0F;
      }
    }
  }

 private:
  float* const* channels_ = nullptr;
  int num_channels_ = 0;
  int num_frames_ = 0;
};

// Owns storage; hands out views. Resized only on a non-RT thread.
class AudioBufferPool {
 public:
  // Non-RT thread only (engine prepare / device format change).
  void resize(int num_channels, int max_frames) {
    storage_.assign(static_cast<size_t>(num_channels) * static_cast<size_t>(max_frames), 0.0F);
    pointers_.resize(static_cast<size_t>(num_channels));
    for (int channel = 0; channel < num_channels; ++channel) {
      pointers_[static_cast<size_t>(channel)] =
          storage_.data() + static_cast<size_t>(channel) * static_cast<size_t>(max_frames);
    }
    num_channels_ = num_channels;
    max_frames_ = max_frames;
  }

  // Audio thread. No allocation: frames must be <= the prepared maximum.
  AudioBufferView view(int num_frames) noexcept OB_NONBLOCKING {
    return AudioBufferView(pointers_.data(), num_channels_, std::min(num_frames, max_frames_));
  }

  int maxFrames() const noexcept { return max_frames_; }
  int numChannels() const noexcept { return num_channels_; }

 private:
  std::vector<float> storage_;
  std::vector<float*> pointers_;
  int num_channels_ = 0;
  int max_frames_ = 0;
};

}  // namespace onebeat::core
