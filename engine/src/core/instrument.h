// The engine's internal instrument interface — event in, audio out.
//
// This is the first, minimal version of the format-agnostic processor interface
// that Stage 2 grows into the CLAP-shaped plugin model (OB-2-01). Keep it
// format-neutral: nothing here may assume a built-in, a plugin, or a format.
#pragma once

#include <cstdint>

#include "core/audio_buffer.h"
#include "core/rt/rt.h"

namespace onebeat::core {

class Instrument {
 public:
  virtual ~Instrument() = default;

  // Non-RT thread, called before the device starts and on format changes. This
  // is where every allocation an instrument will ever need must happen.
  virtual void prepare(double sample_rate, int max_block_frames) = 0;
  virtual void release() = 0;

  // Audio thread only, all of it allocation- and lock-free.
  virtual void reset() noexcept OB_NONBLOCKING = 0;
  virtual void noteOn(int16_t note, float velocity) noexcept OB_NONBLOCKING = 0;
  virtual void noteOff(int16_t note) noexcept OB_NONBLOCKING = 0;
  virtual void allNotesOff() noexcept OB_NONBLOCKING = 0;

  // Adds into `output` over [start_frame, start_frame + num_frames). Additive,
  // so the engine can render several instruments into one bus; the engine
  // clears the bus once per block.
  virtual void render(const AudioBufferView& output, int start_frame,
                      int num_frames) noexcept OB_NONBLOCKING = 0;

  virtual int activeVoices() const noexcept OB_NONBLOCKING = 0;
};

}  // namespace onebeat::core
