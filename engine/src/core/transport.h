// The engine clock (OB-1-09).
//
// Position in samples is canonical; musical time is derived through TimeMap.
// Every mutation is applied at a block boundary by the audio thread, so this
// object is owned by the audio thread and never locked.
#pragma once

#include <cstdint>

#include "core/rt/rt.h"
#include "core/time_map.h"

namespace onebeat::core {

class Transport {
 public:
  void prepare(double sample_rate, double tempo_bpm) noexcept OB_NONBLOCKING {
    time_map_ = TimeMap(sample_rate, tempo_bpm);
    position_frames_ = 0;
    playing_ = false;
  }

  bool playing() const noexcept OB_NONBLOCKING { return playing_; }
  int64_t positionFrames() const noexcept OB_NONBLOCKING { return position_frames_; }
  const TimeMap& timeMap() const noexcept OB_NONBLOCKING { return time_map_; }
  double tempo() const noexcept OB_NONBLOCKING { return time_map_.tempo(); }

  bool loopEnabled() const noexcept OB_NONBLOCKING { return loop_enabled_; }
  double loopStartBeats() const noexcept OB_NONBLOCKING { return loop_start_beats_; }
  double loopEndBeats() const noexcept OB_NONBLOCKING { return loop_end_beats_; }
  int64_t loopStartFrames() const noexcept OB_NONBLOCKING {
    return time_map_.beatsToFrames(loop_start_beats_);
  }
  int64_t loopEndFrames() const noexcept OB_NONBLOCKING {
    return time_map_.beatsToFrames(loop_end_beats_);
  }

  void play() noexcept OB_NONBLOCKING { playing_ = true; }
  void stop() noexcept OB_NONBLOCKING { playing_ = false; }

  void seekFrames(int64_t frames) noexcept OB_NONBLOCKING {
    position_frames_ = frames < 0 ? 0 : frames;
  }
  void seekBeats(double beats) noexcept OB_NONBLOCKING {
    seekFrames(time_map_.beatsToFrames(beats < 0.0 ? 0.0 : beats));
  }

  // Musical position is preserved across a tempo change: we read the current
  // beat under the old tempo and re-anchor the sample position under the new
  // one, so playback continues from the same musical place without a jump.
  void setTempo(double bpm) noexcept OB_NONBLOCKING {
    const double beats = time_map_.framesToBeats(position_frames_);
    time_map_.setTempo(bpm);
    position_frames_ = time_map_.beatsToFrames(beats);
  }

  void setSampleRate(double sample_rate) noexcept OB_NONBLOCKING {
    const double beats = time_map_.framesToBeats(position_frames_);
    time_map_.setSampleRate(sample_rate);
    position_frames_ = time_map_.beatsToFrames(beats);
  }

  void setLoop(double start_beats, double end_beats, bool enabled) noexcept OB_NONBLOCKING {
    if (end_beats > start_beats && start_beats >= 0.0) {
      loop_start_beats_ = start_beats;
      loop_end_beats_ = end_beats;
    }
    loop_enabled_ = enabled;
  }

  void advance(int64_t frames) noexcept OB_NONBLOCKING { position_frames_ += frames; }

  // How many frames may be consumed from `position_frames_` before the loop end
  // is reached, capped at `frames`. Returns `frames` when not looping.
  int64_t framesUntilLoopWrap(int64_t frames) const noexcept OB_NONBLOCKING {
    if (!loop_enabled_) {
      return frames;
    }
    const int64_t end = loopEndFrames();
    if (position_frames_ >= end) {
      return 0;
    }
    const int64_t remaining = end - position_frames_;
    return remaining < frames ? remaining : frames;
  }

  MusicalPosition musicalPosition() const noexcept OB_NONBLOCKING {
    return time_map_.musicalPosition(position_frames_);
  }

 private:
  TimeMap time_map_{48000.0, 120.0};
  int64_t position_frames_ = 0;
  double loop_start_beats_ = 0.0;
  double loop_end_beats_ = 16.0;
  bool playing_ = false;
  bool loop_enabled_ = true;
};

}  // namespace onebeat::core
