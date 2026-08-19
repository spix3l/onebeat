// Voice allocation in the stock instruments.
//
// The regression these guard: a chord is several note-ons at the *same frame*,
// all applied before a single sample is rendered. A voice claimed at that frame
// is at the very bottom of its envelope, so an allocator that steals "the
// quietest voice" hands each note of the chord the voice the note before it
// just took. Once the voices fill up — a bar or two into a sustained part —
// only the last note-on at each frame survives, and because the flattener emits
// same-frame note-ons in ascending key order that is the top of every chord and
// nothing underneath it.
#include <array>

#include "doctest.h"
#include "stock_plugins/guitar/guitar_engine.h"
#include "stock_plugins/piano/piano_engine.h"
#include "stock_plugins/synth/synth_engine.h"

namespace {

constexpr double SampleRate = 48000.0;
constexpr uint32_t RenderFrames = 256;

// Renders through a scratch stereo buffer, which is what advances voice age.
template <typename Engine>
void renderSome(Engine& engine, uint32_t blocks = 1) {
  std::array<float, RenderFrames> left{};
  std::array<float, RenderFrames> right{};
  std::array<float*, 2> planes{left.data(), right.data()};
  for (uint32_t block = 0; block < blocks; ++block) {
    left.fill(0.0F);
    right.fill(0.0F);
    engine.render(planes.data(), 2, 0, RenderFrames);
  }
}

// Holds every voice down with keys well away from the chord under test, so the
// next note-on has nothing free and has to steal.
template <typename Engine>
void fillVoices(Engine& engine) {
  for (uint32_t voice = 0; voice < Engine::VoiceCount; ++voice) {
    engine.noteOn(-1, 0, static_cast<int>(20 + voice), 0.8);
  }
  renderSome(engine);
}

}  // namespace

TEST_SUITE("unit") {
  TEST_CASE_TEMPLATE("A chord sounds every one of its notes once the voices are full", Engine,
                     onebeat::stock::piano::PianoEngine, onebeat::stock::synth::SynthEngine,
                     onebeat::stock::guitar::GuitarEngine) {
    Engine engine;
    engine.setSampleRate(SampleRate);
    fillVoices(engine);

    // The chord: three note-ons at one frame, no render between them.
    engine.noteOn(-1, 0, 60, 0.9);
    engine.noteOn(-1, 0, 64, 0.9);
    engine.noteOn(-1, 0, 67, 0.9);

    CHECK(engine.keySounding(60));
    CHECK(engine.keySounding(64));
    CHECK(engine.keySounding(67));
  }

  TEST_CASE_TEMPLATE("Stealing still recycles voices that have been heard", Engine,
                     onebeat::stock::piano::PianoEngine, onebeat::stock::synth::SynthEngine,
                     onebeat::stock::guitar::GuitarEngine) {
    // The guard must not turn into "never steal": a held part that runs past
    // the voice count has to keep sounding the notes arriving now.
    Engine engine;
    engine.setSampleRate(SampleRate);
    fillVoices(engine);

    for (int note = 0; note < 8; ++note) {
      engine.noteOn(-1, 0, 60 + note, 0.9);
      renderSome(engine);
      CHECK(engine.keySounding(60 + note));
    }
  }
}
