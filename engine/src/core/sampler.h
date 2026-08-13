// The minimal built-in sampler (OB-1-08) — the seed of FR-BIP-01.
//
// Scope discipline: pitch by playback-rate resampling, velocity to gain, fixed
// polyphony with stealing, anti-click fades. ADSR, filter, looping and multi
// format land in Stage 7; do not grow this file in the meantime.
//
// This is **only** the voice allocator. It has no notion of parameters, events,
// ports or activation states: those live in `plugin::builtin::SamplerPlugin`,
// which wraps this and presents it through the one interface every processor in
// OneBeat implements (OB-2-01). The engine never talks to this class directly.
// v0.1's `core::Instrument` was the minimal ancestor of that interface and has
// been retired into it — there is now exactly one processor abstraction.
#pragma once

#include <array>
#include <atomic>
#include <cstdint>
#include <memory>

#include "core/audio_buffer.h"
#include "core/rt/publisher.h"
#include "core/rt/rt.h"
#include "core/rt/rt_log.h"
#include "core/wav_loader.h"

namespace onebeat::core {

class Sampler final {
 public:
  static constexpr int MaxVoices = 32;
  static constexpr int16_t RootNote = 60;          // C3 plays the sample at its own pitch
  static constexpr double ReleaseSeconds = 0.008;  // note-off fade
  static constexpr double StealSeconds = 0.002;    // faster fade when stealing

  explicit Sampler(rt::RtLog* log = nullptr) : log_(log) {}

  void prepare(double sample_rate, int max_block_frames);
  void release();

  void reset() noexcept OB_NONBLOCKING;
  void noteOn(int16_t note, float velocity) noexcept OB_NONBLOCKING;
  void noteOff(int16_t note) noexcept OB_NONBLOCKING;
  void allNotesOff() noexcept OB_NONBLOCKING;
  void render(const AudioBufferView& output, int start_frame,
              int num_frames) noexcept OB_NONBLOCKING;
  int activeVoices() const noexcept OB_NONBLOCKING;

  // Non-RT thread. Takes ownership; the previous sample is retired, not freed.
  void setSample(std::unique_ptr<SampleData> sample);
  // Non-RT reclamation thread.
  void collectRetiredSamples(bool rt_running) { sample_.collect(rt_running); }
  // Audio thread, once per block (epoch discipline, see rt/publisher.h).
  void beginBlock() noexcept OB_NONBLOCKING { sample_.beginBlock(); }

 private:
  struct Voice {
    bool active = false;
    bool releasing = false;
    int16_t note = 0;
    float gain = 0.0F;
    double position = 0.0;  // in source frames
    double rate = 1.0;      // source frames per output frame
    float fade = 1.0F;      // 1 -> 0 during release
    float fade_step = 0.0F;
    uint64_t order = 0;         // start order, for oldest-first stealing
    int16_t pending_note = -1;  // queued retrigger after a steal fade
    float pending_velocity = 0.0F;
  };

  void startVoice(Voice& voice, int16_t note, float velocity) noexcept OB_NONBLOCKING;

  std::array<Voice, MaxVoices> voices_{};
  rt::NonRealtimeMutable<SampleData> sample_;
  rt::RtLog* log_ = nullptr;
  double sample_rate_ = 48000.0;
  float release_step_ = 0.0F;
  float steal_step_ = 0.0F;
  uint64_t order_counter_ = 0;
};

}  // namespace onebeat::core
