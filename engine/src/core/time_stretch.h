// Pitch-preserving time stretching (FR-AUD-03).
//
// WSOLA — waveform-similarity overlap-add. The idea in one paragraph: cut the
// source into overlapping grains, slide each grain to the position where it
// best matches what has already been written, and cross-fade it in. Advancing
// the read position slower than the write position makes the material longer;
// advancing it faster makes it shorter. Pitch is untouched either way, because
// every sample output is a sample that was input — nothing is resampled.
//
// The sliding is what separates WSOLA from plain overlap-add, and it is the
// whole of the quality difference: without it, grain boundaries land wherever
// the arithmetic puts them, waveforms meet out of phase, and the result has the
// hollow flanged sound that gives cheap stretching its reputation.
//
// What this is not: a phase vocoder. Transients smear a little at extreme
// ratios and dense polyphonic material fares worse than drums or a single
// voice. PRD §160 names `signalsmith-stretch` as the eventual upgrade; this is
// the in-repo stand-in, behind an interface narrow enough that swapping it is a
// file change rather than a design change.
//
// **Every allocation happens in prepare().** `render` runs on the audio thread.
#pragma once

#include <concepts>
#include <cstdint>
#include <vector>

#include "core/rt/rt.h"
#include "core/wav_loader.h"

namespace onebeat::core {

// What the stretcher needs from whatever it reads. Two things satisfy it:
// `SourceWindow` below, for a clip reading a decoded file, and the capture ring
// inside the halftime effect, for a live signal being replayed slowly.
//
// A template rather than a virtual interface because `read` is called several
// hundred times per output frame; a virtual call there is the difference
// between the stretcher being free and being audible in the CPU meter.
template <typename Reader>
concept StretchSource = requires(const Reader& reader, double offset, int channel) {
  { reader.read(offset, channel) } -> std::convertible_to<float>;
  { reader.sourceFrames() } -> std::convertible_to<int64_t>;
};

// A clip's view of a decoded file: which part of it, and in which direction.
//
// Trim and reverse live here together because they are the same kind of fact —
// a mapping from "how far into this clip" to "which frame of that file" — and
// because every reader downstream then gets both for free instead of
// implementing reverse twice.
struct SourceWindow {
  const SampleData* sample = nullptr;
  int64_t start = 0;   // first source frame of the window
  int64_t length = 0;  // frames in the window
  bool reversed = false;

  bool valid() const noexcept OB_NONBLOCKING { return sample != nullptr && length > 0; }
  int64_t sourceFrames() const noexcept OB_NONBLOCKING { return length; }

  // The file frame holding position `offset` frames into the window. Reversal
  // is a reflection about the window, not about the file, so reversing a
  // trimmed clip plays that trim backwards rather than jumping elsewhere.
  int64_t frameAt(int64_t offset) const noexcept OB_NONBLOCKING {
    const int64_t clamped = offset < 0 ? 0 : (offset >= length ? length - 1 : offset);
    return reversed ? start + (length - 1 - clamped) : start + clamped;
  }

  // Linearly interpolated read at a fractional position. Interpolating in
  // *window* space rather than file space is what keeps a reversed clip smooth:
  // the two frames either side of the read head are neighbours in playback
  // order, which after reflection they are not in the file.
  float read(double offset, int channel) const noexcept OB_NONBLOCKING {
    const auto index = static_cast<int64_t>(offset);
    const auto fraction = static_cast<float>(offset - static_cast<double>(index));
    const int channels = sample->channels;
    const int source_channel = channel < channels ? channel : channels - 1;
    const float a = sample->sampleAt(frameAt(index), source_channel);
    const float b = sample->sampleAt(frameAt(index + 1), source_channel);
    return a + ((b - a) * fraction);
  }
};

class TimeStretch {
 public:
  // ~5.3 ms at 48 kHz. Long enough that the correlation search has a waveform
  // to lock onto, short enough that a drum transient is not audibly doubled.
  static constexpr int SynthesisHop = 256;
  static constexpr int GrainFrames = SynthesisHop * 2;  // Hann window length
  // How far a grain may slide either way to find a better match. Half a hop
  // covers a full cycle down to about 90 Hz, which is where the ear stops
  // hearing phase cancellation as flanging and starts hearing it as level.
  static constexpr int SearchFrames = SynthesisHop / 2;
  static constexpr int MaxChannels = 2;

  // [main-thread] Allocates every buffer `render` will use.
  void prepare(int channels);
  // [audio-thread] Rewinds to the start without freeing anything.
  void reset() noexcept OB_NONBLOCKING;
  // [audio-thread] Whether the source has been consumed to its end.
  bool finished() const noexcept OB_NONBLOCKING { return finished_; }
  // [audio-thread] Where the read head sits, in source frames. The halftime
  // effect drives this directly on a resync; a clip never touches it.
  double readPosition() const noexcept OB_NONBLOCKING { return read_position_; }
  void setReadPosition(double position) noexcept OB_NONBLOCKING {
    read_position_ = position;
    finished_ = false;
  }

  // [audio-thread] Writes `num_frames` of stretched audio into `out`, one
  // pointer per channel, and returns how many it actually produced — fewer than
  // asked for means the source ran out.
  //
  // `ratio` is source frames consumed per output frame: below 1 stretches,
  // above 1 compresses. Read every call rather than latched, so an automated
  // stretch is a continuous change rather than a retrigger.
  template <StretchSource Reader>
  int64_t render(const Reader& source, double ratio, float* const* out, int out_channels,
                 int64_t num_frames) noexcept OB_NONBLOCKING {
    if (!prepared_ || num_frames <= 0 || ratio <= 0.0) return 0;

    int64_t written = 0;
    while (written < num_frames) {
      if (ready_read_ >= ready_frames_) {
        ready_read_ = 0;
        ready_frames_ = 0;
        if (finished_) break;
        produceHop(source, ratio);
        if (ready_frames_ == 0) break;
      }
      const int64_t available = ready_frames_ - ready_read_;
      const int64_t take = available < (num_frames - written) ? available : (num_frames - written);
      for (int channel = 0; channel < out_channels; ++channel) {
        const int plane = channel < channels_ ? channel : channels_ - 1;
        const size_t base = planeBase(plane);
        float* destination = out[channel];
        for (int64_t i = 0; i < take; ++i) {
          destination[written + i] = ready_[base + static_cast<size_t>(ready_read_ + i)];
        }
      }
      ready_read_ += take;
      written += take;
    }
    return written;
  }

 private:
  size_t planeBase(int channel) const noexcept OB_NONBLOCKING {
    return static_cast<size_t>(channel) * static_cast<size_t>(GrainFrames);
  }
  size_t tailBase(int channel) const noexcept OB_NONBLOCKING {
    return static_cast<size_t>(channel) * static_cast<size_t>(SynthesisHop);
  }

  // How well the grain starting at `offset` continues the overlap tail. Plain
  // unnormalised cross-correlation, which is enough when every candidate is the
  // same length. Only the first channel: the search is looking for a phase
  // alignment, and on correlated stereo the left channel finds the same one the
  // sum does at half the cost.
  template <StretchSource Reader>
  float similarity(const Reader& source, int64_t offset) const noexcept OB_NONBLOCKING {
    float score = 0.0F;
    for (int i = 0; i < SynthesisHop; i += 2) {
      score += tail_[static_cast<size_t>(i)] * source.read(static_cast<double>(offset + i), 0);
    }
    return score;
  }

  // Appends one synthesis hop, choosing where to read from by waveform
  // similarity against what has already been written.
  template <StretchSource Reader>
  void produceHop(const Reader& source, double ratio) noexcept OB_NONBLOCKING {
    const auto nominal = static_cast<int64_t>(read_position_);
    const int64_t frames = source.sourceFrames();

    // At the very start there is no tail to match, so the nominal position
    // stands and the search is skipped.
    int64_t best = nominal;
    if (read_position_ > 0.0) {
      float best_score = similarity(source, nominal);
      for (int64_t offset = -SearchFrames; offset <= SearchFrames; offset += 4) {
        const int64_t candidate = nominal + offset;
        if (candidate < 0 || candidate + GrainFrames >= frames) continue;
        const float score = similarity(source, candidate);
        if (score > best_score) {
          best_score = score;
          best = candidate;
        }
      }
    }

    // Overlap-add: the first half of the grain fades in over the tail and
    // completes it; the second half becomes the new tail.
    for (int channel = 0; channel < channels_; ++channel) {
      const size_t ready_base = planeBase(channel);
      const size_t tail_base = tailBase(channel);
      for (int i = 0; i < SynthesisHop; ++i) {
        // Widened before the addition, not after: the two halves of the Hann
        // window are indexed a hop apart, and doing the arithmetic in `int`
        // first is the shape of an overflow even where this one cannot.
        const size_t offset = static_cast<size_t>(i);
        const float shape_in = window_shape_[offset];
        const float shape_out = window_shape_[offset + static_cast<size_t>(SynthesisHop)];
        const float grain_in = source.read(static_cast<double>(best + i), channel);
        const float grain_out = source.read(static_cast<double>(best + i + SynthesisHop), channel);
        ready_[ready_base + static_cast<size_t>(ready_frames_) + static_cast<size_t>(i)] =
            tail_[tail_base + static_cast<size_t>(i)] + (grain_in * shape_in);
        tail_[tail_base + static_cast<size_t>(i)] = grain_out * shape_out;
      }
    }
    ready_frames_ += SynthesisHop;

    // The read head advances by the *nominal* hop, not by wherever the search
    // landed. Accumulating the search offset would let a run of similar matches
    // drift the material off its own timeline.
    read_position_ += static_cast<double>(SynthesisHop) * ratio;
    if (frames > 0 && read_position_ + GrainFrames >= static_cast<double>(frames)) {
      finished_ = true;
    }
  }

  int channels_ = 0;
  bool prepared_ = false;
  bool finished_ = false;
  // Read head in source frames. Fractional because the ratio is.
  double read_position_ = 0.0;
  // The half-grain of output that is written but not yet complete: the next
  // grain fades in over it. Channel-major, `SynthesisHop` per channel.
  std::vector<float> tail_;
  // Finished output waiting to be handed out, channel-major.
  std::vector<float> ready_;
  int64_t ready_frames_ = 0;
  int64_t ready_read_ = 0;
  // Hann, computed once in prepare().
  std::vector<float> window_shape_;
};

}  // namespace onebeat::core
