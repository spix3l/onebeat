// Samples <-> musical time, in one place (OB-1-09 §3).
//
// v0.1 has a single constant-tempo segment, but the interface is already a
// *function of position*, not a constant: Stage 3's tempo track (FR-SEQ-11)
// adds segments to `segments_` and every caller keeps working.
#pragma once

#include <cmath>
#include <cstdint>

#include "core/rt/rt.h"

namespace onebeat::core {

inline constexpr int TicksPerBeat = 960;  // PPQN
inline constexpr int BeatsPerBar = 4;     // 4/4 in v0.1; meter map arrives with FR-SEQ-11
inline constexpr double MinTempoBpm = 20.0;
inline constexpr double MaxTempoBpm = 999.0;

struct MusicalPosition {
  int32_t bar = 1;   // 1-based
  int32_t beat = 1;  // 1-based
  int32_t tick = 0;  // 0..TicksPerBeat-1
};

class TimeMap {
 public:
  TimeMap() noexcept OB_NONBLOCKING = default;
  TimeMap(double sample_rate, double tempo_bpm) noexcept OB_NONBLOCKING
      : sample_rate_(sample_rate),
        tempo_bpm_(clampTempo(tempo_bpm)) {}

  // Everything lands inside 20..999, including NaN and zero: a tempo field is
  // user-editable and must never be able to put the clock into a bad state.
  static double clampTempo(double bpm) noexcept OB_NONBLOCKING {
    if (!(bpm > MinTempoBpm)) {
      return MinTempoBpm;
    }
    return bpm > MaxTempoBpm ? MaxTempoBpm : bpm;
  }

  void setSampleRate(double sample_rate) noexcept OB_NONBLOCKING { sample_rate_ = sample_rate; }

  // Changing tempo keeps musical position continuous: the caller re-anchors by
  // asking for the current beat first, then converting it back to frames.
  void setTempo(double bpm) noexcept OB_NONBLOCKING { tempo_bpm_ = clampTempo(bpm); }

  double sampleRate() const noexcept OB_NONBLOCKING { return sample_rate_; }
  double tempo() const noexcept OB_NONBLOCKING { return tempo_bpm_; }

  double framesPerBeat() const noexcept OB_NONBLOCKING { return sample_rate_ * 60.0 / tempo_bpm_; }

  double framesToBeats(int64_t frames) const noexcept OB_NONBLOCKING {
    return static_cast<double>(frames) / framesPerBeat();
  }

  int64_t beatsToFrames(double beats) const noexcept OB_NONBLOCKING {
    return static_cast<int64_t>(std::llround(beats * framesPerBeat()));
  }

  double framesToSeconds(int64_t frames) const noexcept OB_NONBLOCKING {
    return static_cast<double>(frames) / sample_rate_;
  }

  MusicalPosition musicalPosition(int64_t frames) const noexcept OB_NONBLOCKING {
    const double beats = framesToBeats(frames);
    const double floored = std::floor(beats);
    auto whole_beats = static_cast<int64_t>(floored);
    if (whole_beats < 0) {
      whole_beats = 0;
    }
    MusicalPosition position;
    position.bar = static_cast<int32_t>(whole_beats / BeatsPerBar) + 1;
    position.beat = static_cast<int32_t>(whole_beats % BeatsPerBar) + 1;
    position.tick = static_cast<int32_t>((beats - floored) * TicksPerBeat);
    if (position.tick >= TicksPerBeat) {
      position.tick = TicksPerBeat - 1;
    }
    return position;
  }

 private:
  double sample_rate_ = 48000.0;
  double tempo_bpm_ = 120.0;
};

}  // namespace onebeat::core
