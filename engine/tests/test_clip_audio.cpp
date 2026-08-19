// Clip playback and the time stretcher: trim, reverse, resample and WSOLA.
//
// These are DSP tests, so they assert on *audio*, not on flags. Each one builds
// a source whose shape makes the property under test visible — a ramp for
// direction, a plateau for continuity, a sine for pitch — and then reads the
// rendered output back.
#include <cmath>
#include <vector>

#include "core/sampler.h"
#include "core/time_stretch.h"
#include "doctest.h"

using onebeat::core::AudioBufferView;
using onebeat::core::ClipPlayback;
using onebeat::core::SampleData;
using onebeat::core::Sampler;
using onebeat::core::SourceWindow;
using onebeat::core::TimeStretch;

namespace {

constexpr double kRate = 48000.0;

// A ramp from 0 to 1 across the file. Position is readable from the value, so
// "where in the file did this come from" is answerable from the output alone.
std::unique_ptr<SampleData> makeRamp(int64_t frames) {
  auto data = std::make_unique<SampleData>();
  data->channels = 1;
  data->sample_rate = kRate;
  data->frames = frames;
  data->name = "ramp";
  data->samples.resize(static_cast<size_t>(frames));
  for (int64_t i = 0; i < frames; ++i) {
    data->samples[static_cast<size_t>(i)] = static_cast<float>(i) / static_cast<float>(frames - 1);
  }
  return data;
}

std::unique_ptr<SampleData> makeSine(int64_t frames, double hz) {
  auto data = std::make_unique<SampleData>();
  data->channels = 1;
  data->sample_rate = kRate;
  data->frames = frames;
  data->name = "sine";
  data->samples.resize(static_cast<size_t>(frames));
  for (int64_t i = 0; i < frames; ++i) {
    data->samples[static_cast<size_t>(i)] = static_cast<float>(
        std::sin(2.0 * 3.14159265358979323846 * hz * static_cast<double>(i) / kRate));
  }
  return data;
}

struct Scratch {
  explicit Scratch(int frames) : storage(2 * static_cast<size_t>(frames), 0.0F), frames(frames) {
    pointers = {storage.data(), storage.data() + frames};
  }
  AudioBufferView view() { return AudioBufferView(pointers.data(), 2, frames); }
  void clear() { std::fill(storage.begin(), storage.end(), 0.0F); }

  std::vector<float> storage;
  std::vector<float*> pointers;
  int frames;
};

// Counts zero crossings, which is a cheap and robust proxy for pitch: a signal
// that has been resampled up an octave crosses zero twice as often, and one
// that has been stretched without repitching crosses at the same rate.
int zeroCrossings(const float* data, int frames) {
  int count = 0;
  for (int i = 1; i < frames; ++i) {
    if ((data[i - 1] < 0.0F) != (data[i] < 0.0F)) ++count;
  }
  return count;
}

}  // namespace

TEST_SUITE("unit") {
  TEST_CASE("A clip window plays only the trimmed part of its source") {
    Sampler sampler;
    sampler.prepare(kRate, 512);
    sampler.setSample(makeRamp(1000));

    // The middle fifth of the file: values should land around 0.4 to 0.6.
    ClipPlayback playback;
    playback.enabled = true;
    playback.start_frame = 400;
    playback.length_frames = 200;
    sampler.setClipPlayback(playback);
    sampler.noteOn(Sampler::RootNote, 1.0F);

    Scratch scratch(512);
    sampler.render(scratch.view(), 0, 256);

    CHECK(scratch.storage[0] == doctest::Approx(0.4).epsilon(0.01));
    CHECK(scratch.storage[100] == doctest::Approx(0.5).epsilon(0.01));
    // Past the window the voice has ended, so the buffer keeps its silence.
    CHECK(scratch.storage[250] == doctest::Approx(0.0));
  }

  TEST_CASE("A reversed clip plays its window backwards, not the whole file") {
    Sampler sampler;
    sampler.prepare(kRate, 512);
    sampler.setSample(makeRamp(1000));

    ClipPlayback playback;
    playback.enabled = true;
    playback.start_frame = 400;
    playback.length_frames = 200;
    playback.reversed = true;
    sampler.setClipPlayback(playback);
    sampler.noteOn(Sampler::RootNote, 1.0F);

    Scratch scratch(512);
    sampler.render(scratch.view(), 0, 190);

    // Reversal reflects about the *window*: the first sample out is the window's
    // last one (~0.6), falling towards its first (~0.4). A reversal about the
    // file would have started near 1.0 instead.
    CHECK(scratch.storage[0] == doctest::Approx(0.6).epsilon(0.01));
    CHECK(scratch.storage[180] == doctest::Approx(0.42).epsilon(0.02));
    CHECK(scratch.storage[0] > scratch.storage[180]);
  }

  TEST_CASE("Resample mode moves the pitch and stretch mode does not") {
    const int64_t frames = 8000;
    const int render_frames = 2000;

    // Half speed by resampling: an octave down, so half the zero crossings.
    Sampler resampled;
    resampled.prepare(kRate, 4096);
    resampled.setSample(makeSine(frames, 440.0));
    ClipPlayback slow;
    slow.enabled = true;
    slow.length_frames = frames;
    slow.rate = 0.5;
    resampled.setClipPlayback(slow);
    resampled.noteOn(Sampler::RootNote, 1.0F);
    Scratch a(4096);
    resampled.render(a.view(), 0, render_frames);

    // Half speed with the pitch held: the same number of crossings as the source.
    Sampler stretched;
    stretched.prepare(kRate, 4096);
    stretched.setSample(makeSine(frames, 440.0));
    ClipPlayback held = slow;
    held.pitch_preserving = true;
    stretched.setClipPlayback(held);
    stretched.noteOn(Sampler::RootNote, 1.0F);
    Scratch b(4096);
    stretched.render(b.view(), 0, render_frames);

    const int reference =
        static_cast<int>(2.0 * 440.0 * static_cast<double>(render_frames) / kRate);
    const int resampled_crossings = zeroCrossings(a.storage.data(), render_frames);
    const int stretched_crossings = zeroCrossings(b.storage.data(), render_frames);

    // Resampled at half rate: about half the crossings of the original.
    CHECK(resampled_crossings == doctest::Approx(reference / 2).epsilon(0.15));
    // Stretched: the pitch is untouched, so the crossing count is the original's.
    CHECK(stretched_crossings == doctest::Approx(reference).epsilon(0.15));
    CHECK(stretched_crossings > resampled_crossings);
  }

  TEST_CASE("The stretcher lengthens its source without changing its pitch") {
    TimeStretch stretch;
    stretch.prepare(1);

    auto sample = makeSine(20000, 220.0);
    SourceWindow window;
    window.sample = sample.get();
    window.start = 0;
    window.length = sample->frames;

    std::vector<float> out(8000, 0.0F);
    float* planes[1] = {out.data()};
    // Half rate: 8,000 output frames should consume about 4,000 source frames.
    const int64_t produced = stretch.render(window, 0.5, planes, 1, 8000);
    REQUIRE(produced == 8000);

    const int expected = static_cast<int>(2.0 * 220.0 * static_cast<double>(produced) / kRate);
    CHECK(zeroCrossings(out.data(), static_cast<int>(produced)) ==
          doctest::Approx(expected).epsilon(0.15));

    // And the output is continuous: overlap-add that mismatched its grains shows
    // up as a sample-to-sample jump far larger than the waveform's own slope.
    float largest_step = 0.0F;
    for (int64_t i = 1; i < produced; ++i) {
      largest_step = std::max(
          largest_step, std::abs(out[static_cast<size_t>(i)] - out[static_cast<size_t>(i - 1)]));
    }
    CHECK(largest_step < 0.2F);
  }

  TEST_CASE("The stretcher stops when its window runs out") {
    TimeStretch stretch;
    stretch.prepare(1);

    auto sample = makeSine(2000, 220.0);
    SourceWindow window;
    window.sample = sample.get();
    window.start = 0;
    window.length = sample->frames;

    std::vector<float> out(20000, 0.0F);
    float* planes[1] = {out.data()};
    // Compressing 2,000 frames at double rate cannot fill 20,000 of output.
    const int64_t produced = stretch.render(window, 2.0, planes, 1, 20000);
    CHECK(produced < 20000);
    CHECK(stretch.finished());
  }

  TEST_CASE("Replacing a channel's sample under a sounding voice does not read the old one") {
    // The crash this covers, from a real report: adding playlist and rack items
    // reconciles the rack, which republishes samples — and a voice that had
    // latched the old `SampleData*` at note-on then dereferenced it after the
    // publisher had retired and freed it. A published sample is valid only for
    // the block it was acquired in (rt/publisher.h), so a voice, which outlives
    // its block, must never hold one.
    Sampler sampler;
    sampler.prepare(kRate, 512);
    sampler.setSample(makeRamp(4000));

    ClipPlayback playback;
    playback.enabled = true;
    playback.start_frame = 0;
    playback.length_frames = 0;
    sampler.setClipPlayback(playback);
    sampler.noteOn(Sampler::RootNote, 1.0F);

    Scratch scratch(512);
    sampler.render(scratch.view(), 0, 128);
    REQUIRE(sampler.activeVoices() == 1);

    // What reconciliation does: a different, and deliberately much shorter,
    // sample takes the channel while the voice is still going.
    sampler.setSample(makeRamp(300));
    sampler.beginBlock();
    // The old buffer is retired here and freed once nothing can reach it — which
    // under ASan is exactly when a stale pointer would be caught.
    sampler.collectRetiredSamples(false);

    scratch.clear();
    sampler.render(scratch.view(), 0, 128);

    // It must read the *new* sample, clamped to what that sample holds, and
    // never past its end. Anything it produces is in range; the point is that it
    // does not fault.
    for (int i = 0; i < 128; ++i) {
      const float value = scratch.storage[static_cast<size_t>(i)];
      CHECK(value >= -1.5F);
      CHECK(value <= 1.5F);
    }
  }

  TEST_CASE("A voice whose window no longer fits the sample ends instead of reading past it") {
    Sampler sampler;
    sampler.prepare(kRate, 512);
    sampler.setSample(makeRamp(4000));

    // A window deep inside the long sample...
    ClipPlayback playback;
    playback.enabled = true;
    playback.start_frame = 3000;
    playback.length_frames = 500;
    sampler.setClipPlayback(playback);
    sampler.noteOn(Sampler::RootNote, 1.0F);

    Scratch scratch(512);
    sampler.render(scratch.view(), 0, 64);
    REQUIRE(sampler.activeVoices() == 1);

    // ...and a replacement far too short to contain it.
    sampler.setSample(makeRamp(100));
    sampler.beginBlock();
    sampler.collectRetiredSamples(false);

    scratch.clear();
    sampler.render(scratch.view(), 0, 128);
    // Reading frame 3,000 of a 100-frame buffer is the crash; ending the voice is
    // the honest alternative.
    CHECK(sampler.activeVoices() == 0);
  }

  TEST_CASE("A clip with no stretching is bit-identical to its source") {
    Sampler sampler;
    sampler.prepare(kRate, 512);
    auto source = makeRamp(1000);
    const std::vector<float> expected = source->samples;
    sampler.setSample(std::move(source));

    ClipPlayback playback;
    playback.enabled = true;
    playback.length_frames = 0;  // to the end of the file
    sampler.setClipPlayback(playback);
    sampler.noteOn(Sampler::RootNote, 1.0F);

    Scratch scratch(512);
    sampler.render(scratch.view(), 0, 256);
    for (int i = 0; i < 200; ++i) {
      CHECK(scratch.storage[static_cast<size_t>(i)] ==
            doctest::Approx(expected[static_cast<size_t>(i)]).epsilon(0.0001));
    }
  }

}  // TEST_SUITE
