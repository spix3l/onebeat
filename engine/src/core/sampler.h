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
#include <vector>

#include "core/audio_buffer.h"
#include "core/rt/publisher.h"
#include "core/rt/rt.h"
#include "core/rt/rt_log.h"
#include "core/time_stretch.h"
#include "core/wav_loader.h"

namespace onebeat::core {

// How an arrangement audio clip plays its file: which part, how fast, which way
// round, and whether speed is allowed to move the pitch.
//
// One of these per sampler rather than per voice, because a one-shot channel
// carries exactly one clip (model/flattener.h gives every audio clip a channel
// of its own). A rack channel playing notes leaves `enabled` false and is
// unaffected by every field below it.
struct ClipPlayback {
  bool enabled = false;
  int64_t start_frame = 0;    // trim-in, in source frames
  int64_t length_frames = 0;  // 0 == to the end of the file
  bool reversed = false;
  // Source frames consumed per output frame. 1.0 plays the file at its own
  // speed; the flattener derives anything else from the clip's length.
  double rate = 1.0;
  // Whether `rate` moves the pitch with the speed (false, the turntable) or
  // holds it (true, via TimeStretch). Ignored when `rate` is 1.
  bool pitch_preserving = false;
};

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
  // Audio thread. Applies from the *next* voice start, never mid-voice: a clip
  // that is already sounding must not jump when the model behind it is edited.
  void setClipPlayback(const ClipPlayback& playback) noexcept OB_NONBLOCKING { clip_ = playback; }
  const ClipPlayback& clipPlayback() const noexcept OB_NONBLOCKING { return clip_; }
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
    // The window this voice reads, resolved at start. A note voice gets the
    // whole file forwards; a clip voice gets its trim, its direction and — when
    // `stretching` — the overlap-add path instead of the resampler.
    SourceWindow window;
    bool stretching = false;
  };

  void startVoice(Voice& voice, int16_t note, float velocity) noexcept OB_NONBLOCKING;
  void renderStretchedVoice(Voice& voice, const AudioBufferView& output, int start_frame,
                            int num_frames) noexcept OB_NONBLOCKING;

  std::array<Voice, MaxVoices> voices_{};
  rt::NonRealtimeMutable<SampleData> sample_;
  ClipPlayback clip_;
  // One stretcher, not one per voice: only a clip voice ever stretches and a
  // clip channel has one of those. 32 of these would cost a quarter of a
  // megabyte per channel to serve a case that cannot arise.
  TimeStretch stretch_;
  // Scratch for the stretcher's channel pointers, so render() hands it planes
  // without touching the output buffer's own offsets. Sized in prepare().
  std::vector<float> stretch_scratch_;
  int max_block_frames_ = 0;
  rt::RtLog* log_ = nullptr;
  double sample_rate_ = 48000.0;
  float release_step_ = 0.0F;
  float steal_step_ = 0.0F;
  uint64_t order_counter_ = 0;
};

}  // namespace onebeat::core
