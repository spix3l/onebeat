#include <cmath>
#include <vector>

#include "core/sampler.h"
#include "doctest.h"
#include "test_helpers.h"
#include "testing/offline_driver.h"

using onebeat::core::AudioBufferView;
using onebeat::core::Sampler;

namespace {

// A flat-topped sample: any discontinuity in the render is the sampler's doing,
// not the source material's.
std::unique_ptr<onebeat::core::SampleData> makePlateauSample(double sample_rate) {
  auto data = std::make_unique<onebeat::core::SampleData>();
  data->channels = 1;
  data->sample_rate = sample_rate;
  data->frames = static_cast<int64_t>(sample_rate);  // one second
  data->name = "plateau";
  data->samples.assign(static_cast<size_t>(data->frames), 0.5F);
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

}  // namespace

TEST_SUITE("unit") {
  TEST_CASE("A note-on plays the sample, scaled by velocity") {
    Sampler sampler;
    sampler.prepare(48000.0, 512);
    sampler.setSample(makePlateauSample(48000.0));
    sampler.collectRetiredSamples(false);

    Scratch scratch(512);
    sampler.noteOn(Sampler::RootNote, 1.0F);
    sampler.render(scratch.view(), 0, 512);
    CHECK(scratch.storage[10] == doctest::Approx(0.5F));

    scratch.clear();
    sampler.allNotesOff();
    sampler.render(scratch.view(), 0, 512);  // let the release finish

    scratch.clear();
    sampler.noteOn(Sampler::RootNote, 0.5F);
    sampler.render(scratch.view(), 0, 512);
    CHECK(scratch.storage[10] == doctest::Approx(0.25F));
  }

  TEST_CASE("Pitch follows the note number by playback rate") {
    Sampler sampler;
    sampler.prepare(48000.0, 512);
    sampler.setSample(makePlateauSample(48000.0));

    Scratch scratch(512);
    // An octave up consumes source frames twice as fast, so the sample runs out
    // in half the time. Use a short sample to observe it.
    auto shortSample = std::make_unique<onebeat::core::SampleData>();
    shortSample->channels = 1;
    shortSample->sample_rate = 48000.0;
    shortSample->frames = 200;
    shortSample->samples.assign(200, 0.5F);
    sampler.setSample(std::move(shortSample));

    sampler.noteOn(static_cast<int16_t>(Sampler::RootNote + 12), 1.0F);
    sampler.render(scratch.view(), 0, 512);
    CHECK(sampler.activeVoices() == 0);  // finished inside the block
    CHECK(scratch.storage[99] == doctest::Approx(0.5F));
    CHECK(scratch.storage[120] == doctest::Approx(0.0F));
  }

  TEST_CASE("Note-off fades out instead of cutting: no sample-to-sample jump") {
    Sampler sampler;
    sampler.prepare(48000.0, 512);
    sampler.setSample(makePlateauSample(48000.0));

    Scratch scratch(1024);
    sampler.noteOn(Sampler::RootNote, 1.0F);
    sampler.render(scratch.view(), 0, 64);
    sampler.noteOff(Sampler::RootNote);
    sampler.render(scratch.view(), 64, 960);

    float worst = 0.0F;
    for (int frame = 1; frame < 1024; ++frame) {
      worst = std::max(worst, std::abs(scratch.storage[static_cast<size_t>(frame)] -
                                       scratch.storage[static_cast<size_t>(frame - 1)]));
    }
    // A hard cut would be 0.5; an 8 ms fade at 48 kHz steps by ~0.0013.
    CHECK(worst < 0.01F);
  }

  TEST_CASE("Voice stealing is bounded, click-free, and keeps polyphony at the limit") {
    Sampler sampler;
    sampler.prepare(48000.0, 512);
    sampler.setSample(makePlateauSample(48000.0));

    Scratch scratch(512);
    for (int index = 0; index < Sampler::MaxVoices; ++index) {
      sampler.noteOn(static_cast<int16_t>(40 + index), 0.02F);
    }
    CHECK(sampler.activeVoices() == Sampler::MaxVoices);

    sampler.render(scratch.view(), 0, 256);
    sampler.noteOn(90, 0.02F);  // one too many: steals the oldest
    sampler.render(scratch.view(), 256, 256);
    CHECK(sampler.activeVoices() <= Sampler::MaxVoices);

    float worst = 0.0F;
    for (int frame = 1; frame < 512; ++frame) {
      worst = std::max(worst, std::abs(scratch.storage[static_cast<size_t>(frame)] -
                                       scratch.storage[static_cast<size_t>(frame - 1)]));
    }
    CHECK(worst < 0.05F);
  }

  TEST_CASE("32 simultaneous voices render without dropouts at a 128-frame block") {
    Sampler sampler;
    sampler.prepare(48000.0, 128);
    sampler.setSample(makePlateauSample(48000.0));

    Scratch scratch(128);
    for (int index = 0; index < Sampler::MaxVoices; ++index) {
      sampler.noteOn(static_cast<int16_t>(48 + (index % 24)), 0.03F);
    }
    for (int block = 0; block < 100; ++block) {
      scratch.clear();
      sampler.render(scratch.view(), 0, 128);
    }
    CHECK(sampler.activeVoices() == Sampler::MaxVoices);
  }

}  // TEST_SUITE
