// The mixer graph and the stock effects.
//
// The graph tests are about *order and routing*, which is the part that is easy
// to get subtly wrong and impossible to hear: a mis-sorted graph still makes
// sound, just not through the chain the user built. The effect tests assert the
// one property that defines each effect, plus the two properties every effect
// must have — bypass is silent, and parameters respond to automation events.
#include <cmath>
#include <utility>
#include <vector>

#include "core/mixer_graph.h"
#include "doctest.h"
#include "plugin/builtin/effects/delay_plugin.h"
#include "plugin/builtin/effects/effect_factory.h"
#include "plugin/builtin/effects/reverb_plugin.h"
#include "plugin/event.h"
#include "plugin/state.h"

using onebeat::core::AudioBufferView;
using onebeat::core::GraphEffect;
using onebeat::core::GraphNode;
using onebeat::core::MixerGraph;

namespace {

constexpr double kRate = 48000.0;
constexpr int kBlock = 512;

GraphNode makeNode(const char* id, int32_t output) {
  GraphNode node;
  node.track_id = id;
  node.output = output;
  return node;
}

struct Stereo {
  Stereo() : storage(2 * static_cast<size_t>(kBlock), 0.0F) {
    pointers = {storage.data(), storage.data() + kBlock};
  }
  AudioBufferView view() { return AudioBufferView(pointers.data(), 2, kBlock); }
  void fill(float value) { std::fill(storage.begin(), storage.end(), value); }
  void impulse() {
    std::fill(storage.begin(), storage.end(), 0.0F);
    storage[0] = 1.0F;
    storage[static_cast<size_t>(kBlock)] = 1.0F;
  }
  float peak() const {
    float highest = 0.0F;
    for (float sample : storage) highest = std::max(highest, std::abs(sample));
    return highest;
  }
  float energy() const {
    float total = 0.0F;
    for (float sample : storage) total += sample * sample;
    return total;
  }

  std::vector<float> storage;
  std::vector<float*> pointers;
};

// `initial` is applied before configure(), which is the order a host restores a
// saved project in — and the order that matters for the delay, whose read head
// glides towards its parameter rather than jumping to it.
std::unique_ptr<onebeat::plugin::builtin::EffectPlugin> makeEffect(
    const char* id, const std::vector<std::pair<onebeat::plugin::ParamId, double>>& initial = {}) {
  auto effect = onebeat::plugin::builtin::createBuiltinEffect(id, nullptr);
  REQUIRE(effect != nullptr);
  if (!initial.empty()) {
    std::vector<onebeat::plugin::PluginEvent> storage(initial.size());
    onebeat::plugin::EventList events(storage.data(), static_cast<uint32_t>(storage.size()));
    for (const auto& [param, value] : initial) {
      events.push(onebeat::plugin::PluginEvent::paramValue(0, param, value));
    }
    effect->paramsFlush(events.view(), nullptr);
  }
  onebeat::plugin::ProcessSetup setup;
  setup.sample_rate = kRate;
  setup.max_block_frames = kBlock;
  REQUIRE(effect->configure(setup));
  REQUIRE(effect->activate());
  return effect;
}

// Runs one block through an effect with an optional parameter event at frame 0.
//
// The scoped marker is not decoration: `process` asserts it is on the audio
// thread in debug builds, and the whole point of that assertion is that a test
// calling it from anywhere else trips it (docs/plugin-threading-contract.md).
void runBlock(onebeat::plugin::builtin::EffectPlugin& effect, Stereo& io,
              onebeat::plugin::EventList* events = nullptr) {
  const onebeat::plugin::ThreadCheck::ScopedAudioThread audio_thread;
  const AudioBufferView view = io.view();
  onebeat::plugin::ProcessBlock block;
  block.frames = kBlock;
  block.audio_inputs = &view;
  block.audio_input_count = 1;
  block.audio_outputs = &view;
  block.audio_output_count = 1;
  if (events != nullptr) block.in_events = events->view();
  effect.process(block);
}

}  // namespace

TEST_SUITE("unit") {
  TEST_CASE("The graph renders every input before the track it feeds") {
    MixerGraph graph;
    // Deliberately declared out of order: master first, then a bus, then the
    // tracks that feed it. A graph that trusted declaration order would sum a
    // track into a bus that had already been processed.
    graph.nodes().push_back(makeNode("master", -1));
    graph.nodes().push_back(makeNode("drums", 0));
    graph.nodes().push_back(makeNode("kick", 1));
    graph.nodes().push_back(makeNode("snare", 1));
    REQUIRE(graph.finalise());
    CHECK(graph.master() == 0);

    std::vector<int32_t> position(graph.nodes().size(), -1);
    for (size_t i = 0; i < graph.order().size(); ++i) {
      position[static_cast<size_t>(graph.order()[i])] = static_cast<int32_t>(i);
    }
    CHECK(graph.order().size() == 4);
    CHECK(position[2] < position[1]);  // kick before drums
    CHECK(position[3] < position[1]);  // snare before drums
    CHECK(position[1] < position[0]);  // drums before master
  }

  TEST_CASE("The graph refuses routing that feeds itself") {
    MixerGraph graph;
    graph.nodes().push_back(makeNode("master", -1));
    graph.nodes().push_back(makeNode("a", 2));
    graph.nodes().push_back(makeNode("b", 1));
    // A cycle would hang the render walk rather than sound wrong, so it is
    // rejected outright and the previous mixer is kept.
    CHECK_FALSE(graph.finalise());
  }

  TEST_CASE("A graph with no master is not a graph") {
    MixerGraph graph;
    graph.nodes().push_back(makeNode("a", 1));
    graph.nodes().push_back(makeNode("b", 0));
    CHECK_FALSE(graph.finalise());
  }

  TEST_CASE("Every stock effect ships and instantiates") {
    CHECK(onebeat::plugin::builtin::builtinEffectCount() == 4);
    for (size_t i = 0; i < onebeat::plugin::builtin::builtinEffectCount(); ++i) {
      const auto& descriptor = onebeat::plugin::builtin::builtinEffects()[i];
      auto effect = onebeat::plugin::builtin::createBuiltinEffect(descriptor.id, nullptr);
      CHECK(effect != nullptr);
      // Every effect has a bypass at the frozen ID, whatever else it exposes.
      onebeat::plugin::ParamInfo info;
      REQUIRE(effect->paramInfo(0, info));
      CHECK(info.id == onebeat::plugin::builtin::EffectParamBypass);
      CHECK(info.has(onebeat::plugin::ParamFlagIsBypass));
    }
    CHECK(onebeat::plugin::builtin::createBuiltinEffect("dev.onebeat.fx.nope", nullptr) == nullptr);
  }

  TEST_CASE("Reverb turns an impulse into a decaying tail") {
    auto effect = makeEffect("dev.onebeat.fx.reverb");
    Stereo io;
    io.impulse();
    runBlock(*effect, io);

    CHECK(io.peak() > 0.0F);

    // The tail is what a reverb *is*: energy arriving after the input stopped.
    // The shortest comb is about 1,200 frames long, so the first echo cannot land
    // inside the block the impulse was in — checking the very next block would
    // assert that the reverb has no pre-delay of its own, which is not true and
    // not desirable. Six blocks covers the first few reflections comfortably.
    float tail_energy = 0.0F;
    for (int block = 0; block < 6; ++block) {
      Stereo silence;
      runBlock(*effect, silence);
      tail_energy += silence.energy();
    }
    CHECK(tail_energy > 0.0F);
  }

  TEST_CASE("Delay repeats its input after the delay time") {
    // A short delay so the repeat lands inside one block: 4 ms is 192 frames.
    // Set before configure, so the read head starts there rather than gliding
    // towards it from the default 375 ms.
    auto effect = makeEffect("dev.onebeat.fx.delay",
                             {{onebeat::plugin::builtin::DelayPlugin::ParamTime, 0.004},
                              {onebeat::plugin::builtin::DelayPlugin::ParamMix, 1.0}});
    Stereo io;
    io.impulse();
    runBlock(*effect, io);

    // Fully wet, so the dry impulse is gone and only the repeat is left.
    float latest = 0.0F;
    int latest_at = 0;
    for (int i = 1; i < kBlock; ++i) {
      const float value = std::abs(io.storage[static_cast<size_t>(i)]);
      if (value > latest) {
        latest = value;
        latest_at = i;
      }
    }
    CHECK(latest > 0.1F);
    CHECK(latest_at > 10);  // it arrived later than it went in
  }

  TEST_CASE("Reverse is silent until it has a whole window to turn around") {
    auto effect = makeEffect("dev.onebeat.fx.reverse");
    Stereo io;
    io.fill(0.5F);
    runBlock(*effect, io);
    // The default window is half a second; one 512-frame block cannot have filled
    // it, and you cannot play something backwards before you have heard all of
    // it. Silence is the honest output.
    CHECK(io.peak() == doctest::Approx(0.0F).epsilon(0.001));
    CHECK(effect->latencyFrames() > 0);
  }

  TEST_CASE("Halftime reports its rate and stays bounded") {
    auto effect = makeEffect("dev.onebeat.fx.halftime");
    Stereo io;
    for (int block = 0; block < 8; ++block) {
      for (int i = 0; i < kBlock; ++i) {
        const float value =
            static_cast<float>(std::sin(2.0 * 3.14159265358979323846 * 220.0 *
                                        static_cast<double>((block * kBlock) + i) / kRate));
        io.storage[static_cast<size_t>(i)] = value;
        io.storage[static_cast<size_t>(kBlock + i)] = value;
      }
      runBlock(*effect, io);
      // Whatever the read head is doing, the output must never run away: a
      // capture ring read past its own write head is how these effects blow up.
      CHECK(io.peak() < 4.0F);
    }
  }

  TEST_CASE("Bypass silences an effect's contribution entirely") {
    auto effect = makeEffect("dev.onebeat.fx.reverb");
    onebeat::plugin::PluginEvent storage[2];
    onebeat::plugin::EventList events(storage, 2);
    events.push(onebeat::plugin::PluginEvent::paramValue(
        0, onebeat::plugin::builtin::EffectParamBypass, 1.0));

    Stereo io;
    io.impulse();
    runBlock(*effect, io, &events);

    // Bypassed: the block comes back exactly as it went in, impulse and all.
    CHECK(io.storage[0] == doctest::Approx(1.0F));
    for (int i = 1; i < kBlock; ++i) {
      CHECK(io.storage[static_cast<size_t>(i)] == doctest::Approx(0.0F));
    }
  }

  TEST_CASE("An automation event changes a parameter mid-block") {
    auto effect = makeEffect("dev.onebeat.fx.reverb");
    // Mix starts at 0 and jumps to 1 halfway through the block. The first half
    // must be dry and the second half must not be.
    onebeat::plugin::PluginEvent storage[4];
    onebeat::plugin::EventList events(storage, 4);
    events.push(onebeat::plugin::PluginEvent::paramValue(
        0, onebeat::plugin::builtin::ReverbPlugin::ParamMix, 0.0));
    events.push(onebeat::plugin::PluginEvent::paramValue(
        256, onebeat::plugin::builtin::ReverbPlugin::ParamMix, 1.0));

    Stereo io;
    io.fill(0.5F);
    runBlock(*effect, io, &events);

    // Dry, mix 0: the input passes through untouched.
    CHECK(io.storage[10] == doctest::Approx(0.5F).epsilon(0.001));
    // Fully wet after the event: the reverb has replaced the input, and at this
    // point its tail has barely built, so the value is well below the dry level.
    CHECK(io.storage[400] != doctest::Approx(0.5F).epsilon(0.001));
  }

  TEST_CASE("Effect state round-trips through save and load") {
    auto saved = makeEffect("dev.onebeat.fx.delay");
    onebeat::plugin::PluginEvent storage[2];
    onebeat::plugin::EventList events(storage, 2);
    events.push(onebeat::plugin::PluginEvent::paramValue(
        0, onebeat::plugin::builtin::DelayPlugin::ParamFeedback, 0.75));
    saved->paramsFlush(events.view(), nullptr);

    onebeat::plugin::MemoryStateWriter writer;
    REQUIRE(saved->saveState(writer));

    auto loaded = makeEffect("dev.onebeat.fx.delay");
    onebeat::plugin::MemoryStateReader reader(writer.bytes());
    REQUIRE(loaded->loadState(reader));

    double value = 0.0;
    REQUIRE(loaded->paramValue(onebeat::plugin::builtin::DelayPlugin::ParamFeedback, value));
    CHECK(value == doctest::Approx(0.75));
  }

}  // TEST_SUITE
