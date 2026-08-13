// The plugin model's lifecycle, parameters, ports and state (OB-2-01).
//
// Driven through the built-in sampler, which is the first implementation of the
// interface and the one every other implementation will be compared against.
#include <algorithm>
#include <array>
#include <cmath>
#include <cstring>
#include <string>
#include <vector>

#include "core/audio_buffer.h"
#include "doctest.h"
#include "plugin/builtin/sampler_plugin.h"
#include "plugin/host.h"
#include "test_helpers.h"
#include "testing/offline_driver.h"

using onebeat::core::AudioBufferPool;
using onebeat::core::AudioBufferView;
using onebeat::plugin::EventList;
using onebeat::plugin::MemoryStateReader;
using onebeat::plugin::MemoryStateWriter;
using onebeat::plugin::NullPluginHost;
using onebeat::plugin::ParamFlagIsAutomatable;
using onebeat::plugin::ParamFlagIsModulatable;
using onebeat::plugin::ParamInfo;
using onebeat::plugin::PluginEvent;
using onebeat::plugin::PluginInstance;
using onebeat::plugin::PortDirection;
using onebeat::plugin::ProcessBlock;
using onebeat::plugin::ProcessSetup;
using onebeat::plugin::ProcessStatus;
using onebeat::plugin::ThreadCheck;
using onebeat::plugin::builtin::SamplerPlugin;

namespace {

// A configured, activated sampler plus the buffers to run it. Everything a
// process() call needs and nothing it does not.
struct Rig {
  static constexpr int Frames = 256;

  NullPluginHost host;
  SamplerPlugin instrument{&host, nullptr};
  AudioBufferPool pool;
  std::array<PluginEvent, 64> event_storage{};

  Rig() {
    ProcessSetup setup;
    setup.sample_rate = 48000.0;
    setup.max_block_frames = Frames;
    REQUIRE(instrument.configure(setup));
    REQUIRE(instrument.activate());
    pool.resize(2, Frames);
  }

  // Renders one block with the given events and returns the peak of the output.
  float render(const std::vector<PluginEvent>& events, int frames = Frames) {
    const ThreadCheck::ScopedAudioThread audio_thread;
    EventList list(event_storage.data(), static_cast<uint32_t>(event_storage.size()));
    for (const PluginEvent& event : events) {
      list.push(event);
    }
    list.sortByTime();

    const AudioBufferView view = pool.view(frames);
    view.clear();

    ProcessBlock block;
    block.frames = static_cast<uint32_t>(frames);
    block.audio_outputs = &view;
    block.audio_output_count = 1;
    block.in_events = list.view();
    instrument.process(block);

    float peak = 0.0F;
    for (int frame = 0; frame < frames; ++frame) {
      peak = std::max(peak, std::abs(view.channel(0)[frame]));
    }
    return peak;
  }
};

// Produced by the v0.1 engine, before the sampler moved behind PluginInstance,
// and re-derived identically afterwards. FNV-1a over the raw sample bits.
constexpr uint64_t GoldenRenderChecksum = 4469794906267174019ULL;

}  // namespace

TEST_SUITE("unit") {
  // ------------------------------------------------------------------------
  // Lifecycle
  // ------------------------------------------------------------------------

  TEST_CASE("The activation state machine refuses illegal transitions") {
    NullPluginHost host;
    SamplerPlugin instrument(&host, nullptr);
    CHECK(instrument.state() == PluginInstance::State::Created);

    // activate() before configure() is not a thing: there is no stream format
    // to activate against.
    CHECK_FALSE(instrument.activate());

    ProcessSetup setup;
    setup.max_block_frames = 128;
    CHECK(instrument.configure(setup));
    CHECK(instrument.state() == PluginInstance::State::Configured);
    CHECK_FALSE(instrument.isActive());

    CHECK(instrument.activate());
    CHECK(instrument.state() == PluginInstance::State::Active);
    CHECK(instrument.isActive());

    // DM-Q5's rule, made checkable: the stream format and the port layout are
    // frozen while active. Reconfiguring means deactivating first.
    CHECK_FALSE(instrument.configure(setup));

    instrument.deactivate();
    CHECK(instrument.state() == PluginInstance::State::Configured);
    CHECK(instrument.configure(setup));  // now legal again
  }

  TEST_CASE("A nonsensical setup is rejected rather than half-applied") {
    NullPluginHost host;
    SamplerPlugin instrument(&host, nullptr);
    ProcessSetup setup;
    setup.sample_rate = 0.0;
    CHECK_FALSE(instrument.configure(setup));
    CHECK(instrument.state() == PluginInstance::State::Created);

    setup.sample_rate = 48000.0;
    setup.max_block_frames = 0;
    CHECK_FALSE(instrument.configure(setup));
    CHECK(instrument.state() == PluginInstance::State::Created);
  }

  TEST_CASE("Processing is a sub-state entered from the audio thread") {
    Rig rig;
    const ThreadCheck::ScopedAudioThread audio_thread;
    CHECK(rig.instrument.startProcessing());
    CHECK(rig.instrument.state() == PluginInstance::State::Processing);
    rig.instrument.stopProcessing();
    CHECK(rig.instrument.state() == PluginInstance::State::Active);
  }

  // ------------------------------------------------------------------------
  // Ports
  // ------------------------------------------------------------------------

  TEST_CASE("The sampler reports one main stereo output and one note input") {
    Rig rig;
    CHECK(rig.instrument.audioPortCount(PortDirection::Output) == 1);
    CHECK(rig.instrument.audioPortCount(PortDirection::Input) == 0);

    onebeat::plugin::AudioPortInfo audio{};
    REQUIRE(rig.instrument.audioPortInfo(PortDirection::Output, 0, audio));
    CHECK(audio.id == SamplerPlugin::MainOutputPort);
    CHECK(audio.channel_count == 2);
    CHECK(audio.layout == onebeat::plugin::ChannelLayout::Stereo);
    CHECK(audio.is_main);
    CHECK(std::string(audio.name.text()) == "Main");
    CHECK_FALSE(rig.instrument.audioPortInfo(PortDirection::Output, 1, audio));

    CHECK(rig.instrument.notePortCount(PortDirection::Input) == 1);
    onebeat::plugin::NotePortInfo notes{};
    REQUIRE(rig.instrument.notePortInfo(PortDirection::Input, 0, notes));
    // CLAP dialect preferred: it is the only one that carries a note id, and
    // therefore the only one per-note expression survives (D5).
    CHECK(notes.preferred_dialect == onebeat::plugin::NoteDialectClap);
    CHECK((notes.supported_dialects & onebeat::plugin::NoteDialectMidi) != 0U);
  }

  // ------------------------------------------------------------------------
  // Parameters
  // ------------------------------------------------------------------------

  TEST_CASE("Parameters are enumerable, and their ids are stable") {
    Rig rig;
    REQUIRE(rig.instrument.paramCount() == 2);

    ParamInfo info{};
    REQUIRE(rig.instrument.paramInfo(0, info));
    CHECK(info.id == SamplerPlugin::ParamGain);
    CHECK(info.default_value == doctest::Approx(1.0));
    CHECK(info.has(ParamFlagIsAutomatable));
    CHECK(info.has(ParamFlagIsModulatable));

    REQUIRE(rig.instrument.paramInfo(1, info));
    CHECK(info.id == SamplerPlugin::ParamTranspose);
    CHECK(info.min_value == doctest::Approx(-24.0));
    CHECK(info.max_value == doctest::Approx(24.0));

    CHECK_FALSE(rig.instrument.paramInfo(2, info));
  }

  TEST_CASE("Value and text convert both ways") {
    Rig rig;
    std::array<char, 64> text{};

    REQUIRE(rig.instrument.paramValueToText(SamplerPlugin::ParamGain, 1.0, text.data(),
                                            text.size()));
    CHECK(std::string(text.data()) == "0.0 dB");
    REQUIRE(rig.instrument.paramValueToText(SamplerPlugin::ParamGain, 0.5, text.data(),
                                            text.size()));
    CHECK(std::string(text.data()) == "-6.0 dB");

    double parsed = 0.0;
    REQUIRE(rig.instrument.paramTextToValue(SamplerPlugin::ParamGain, "-6.0 dB", parsed));
    CHECK(parsed == doctest::Approx(0.5).epsilon(0.001));

    REQUIRE(rig.instrument.paramValueToText(SamplerPlugin::ParamTranspose, -7.0, text.data(),
                                            text.size()));
    CHECK(std::string(text.data()) == "-7 st");
    REQUIRE(rig.instrument.paramTextToValue(SamplerPlugin::ParamTranspose, "5", parsed));
    CHECK(parsed == doctest::Approx(5.0));

    // Nonsense in, refusal out — not a silent zero.
    CHECK_FALSE(rig.instrument.paramTextToValue(SamplerPlugin::ParamGain, "loud", parsed));
    CHECK_FALSE(rig.instrument.paramValueToText(9999, 1.0, text.data(), text.size()));
  }

  TEST_CASE("Out-of-range parameter values are clamped, not wrapped") {
    Rig rig;
    rig.render({PluginEvent::paramValue(0, SamplerPlugin::ParamTranspose, 500.0)});
    double value = 0.0;
    REQUIRE(rig.instrument.paramValue(SamplerPlugin::ParamTranspose, value));
    CHECK(value == doctest::Approx(24.0));
  }

  TEST_CASE("Parameter changes arrive while the transport is stopped, via flush") {
    Rig rig;
    std::array<PluginEvent, 2> storage{};
    EventList list(storage.data(), static_cast<uint32_t>(storage.size()));
    list.push(PluginEvent::paramValue(0, SamplerPlugin::ParamGain, 0.25));
    rig.instrument.paramsFlush(list.view(), nullptr);

    double value = 0.0;
    REQUIRE(rig.instrument.paramValue(SamplerPlugin::ParamGain, value));
    CHECK(value == doctest::Approx(0.25));
  }

  TEST_CASE("Modulation is a non-destructive offset — the base value is untouched") {
    Rig rig;

    // Set the base to full, then modulate it down. The audible result changes;
    // the value the user sees and the project would save does not. Collapsing
    // these two is precisely the bug D5 exists to prevent.
    const float unmodulated =
        rig.render({PluginEvent::paramValue(0, SamplerPlugin::ParamGain, 1.0),
                    PluginEvent::noteOn(0, 60, 1.0)});

    double base_before = 0.0;
    REQUIRE(rig.instrument.paramValue(SamplerPlugin::ParamGain, base_before));
    CHECK(base_before == doctest::Approx(1.0));

    Rig modulated_rig;
    const float modulated = modulated_rig.render(
        {PluginEvent::paramValue(0, SamplerPlugin::ParamGain, 1.0),
         PluginEvent::paramModulation(0, SamplerPlugin::ParamGain, -0.5),
         PluginEvent::noteOn(0, 60, 1.0)});

    double base_after = 0.0;
    REQUIRE(modulated_rig.instrument.paramValue(SamplerPlugin::ParamGain, base_after));
    CHECK(base_after == doctest::Approx(1.0));  // unchanged by the modulation

    CHECK(unmodulated > 0.0F);
    CHECK(modulated == doctest::Approx(unmodulated * 0.5F).epsilon(0.02));
  }

  TEST_CASE("A parameter at its default changes nothing about the render") {
    // The guarantee behind the byte-identical regression: adding parameters to
    // the sampler must not perturb its output while they sit at their defaults.
    Rig plain;
    Rig explicit_defaults;
    const float without = plain.render({PluginEvent::noteOn(0, 60, 1.0)});
    const float with = explicit_defaults.render(
        {PluginEvent::paramValue(0, SamplerPlugin::ParamGain, 1.0),
         PluginEvent::paramValue(0, SamplerPlugin::ParamTranspose, 0.0),
         PluginEvent::noteOn(0, 60, 1.0)});
    CHECK(without == with);  // exactly, not approximately
  }

  // ------------------------------------------------------------------------
  // Events reaching the DSP
  // ------------------------------------------------------------------------

  TEST_CASE("Events are applied at their frame, not at the block boundary") {
    Rig rig;
    // A note starting three quarters of the way through the block produces
    // audio only in that last quarter.
    rig.render({PluginEvent::noteOn(192, 60, 1.0)});

    const AudioBufferView view = rig.pool.view(Rig::Frames);
    float early = 0.0F;
    for (int frame = 0; frame < 192; ++frame) {
      early = std::max(early, std::abs(view.channel(0)[frame]));
    }
    float late = 0.0F;
    for (int frame = 192; frame < Rig::Frames; ++frame) {
      late = std::max(late, std::abs(view.channel(0)[frame]));
    }
    CHECK(early == 0.0F);
    CHECK(late > 0.0F);
  }

  TEST_CASE("A wildcarded note-off releases every voice") {
    Rig rig;
    rig.render({PluginEvent::noteOn(0, 60, 1.0), PluginEvent::noteOn(0, 64, 1.0),
                PluginEvent::noteOn(0, 67, 1.0)});
    CHECK(rig.instrument.activeVoiceCount() == 3);

    // Long enough for the 8 ms release to complete at 48 kHz.
    for (int block = 0; block < 4; ++block) {
      rig.render(block == 0 ? std::vector<PluginEvent>{PluginEvent::allNotesOff(0)}
                            : std::vector<PluginEvent>{});
    }
    CHECK(rig.instrument.activeVoiceCount() == 0);
  }

  TEST_CASE("Transpose shifts the note the DSP actually plays") {
    Rig low;
    Rig high;
    low.render({PluginEvent::noteOn(0, 60, 1.0)});
    high.render({PluginEvent::paramValue(0, SamplerPlugin::ParamTranspose, 12.0),
                 PluginEvent::noteOn(0, 60, 1.0)});
    // An octave up reads the sample twice as fast, so the two renders differ.
    const AudioBufferView low_view = low.pool.view(Rig::Frames);
    const AudioBufferView high_view = high.pool.view(Rig::Frames);
    bool differs = false;
    for (int frame = 0; frame < Rig::Frames; ++frame) {
      if (low_view.channel(0)[frame] != high_view.channel(0)[frame]) {
        differs = true;
        break;
      }
    }
    CHECK(differs);
  }

  TEST_CASE("The instrument reports Sleep when it has nothing to render") {
    Rig rig;
    const ThreadCheck::ScopedAudioThread audio_thread;
    const AudioBufferView view = rig.pool.view(Rig::Frames);
    ProcessBlock block;
    block.frames = Rig::Frames;
    block.audio_outputs = &view;
    block.audio_output_count = 1;
    CHECK(rig.instrument.process(block) == ProcessStatus::Sleep);

    // And Error when it is handed no output port at all, rather than writing
    // through a null pointer.
    ProcessBlock portless;
    portless.frames = Rig::Frames;
    CHECK(rig.instrument.process(portless) == ProcessStatus::Error);
  }

  // ------------------------------------------------------------------------
  // State
  // ------------------------------------------------------------------------

  TEST_CASE("State round-trips through an opaque chunk") {
    Rig source;
    source.render({PluginEvent::paramValue(0, SamplerPlugin::ParamGain, 0.4),
                   PluginEvent::paramValue(0, SamplerPlugin::ParamTranspose, -5.0)});

    MemoryStateWriter writer;
    REQUIRE(source.instrument.saveState(writer));
    CHECK_FALSE(writer.bytes().empty());

    Rig target;
    MemoryStateReader reader(writer.bytes());
    REQUIRE(target.instrument.loadState(reader));

    double gain = 0.0;
    double transpose = 0.0;
    REQUIRE(target.instrument.paramValue(SamplerPlugin::ParamGain, gain));
    REQUIRE(target.instrument.paramValue(SamplerPlugin::ParamTranspose, transpose));
    CHECK(gain == doctest::Approx(0.4));
    CHECK(transpose == doctest::Approx(-5.0));
  }

  TEST_CASE("A truncated or foreign state chunk is refused, not half-applied") {
    Rig rig;
    MemoryStateWriter writer;
    REQUIRE(rig.instrument.saveState(writer));

    std::vector<uint8_t> truncated = writer.bytes();
    truncated.resize(truncated.size() / 2);
    MemoryStateReader short_reader(truncated);
    CHECK_FALSE(rig.instrument.loadState(short_reader));

    std::vector<uint8_t> foreign = writer.bytes();
    foreign[0] ^= 0xFFU;  // wrong magic
    MemoryStateReader foreign_reader(foreign);
    CHECK_FALSE(rig.instrument.loadState(foreign_reader));

    // The refusals left the instrument's own values alone.
    double gain = 0.0;
    REQUIRE(rig.instrument.paramValue(SamplerPlugin::ParamGain, gain));
    CHECK(gain == doctest::Approx(1.0));
  }

  TEST_CASE("Modulation is transient and never persisted") {
    Rig source;
    source.render({PluginEvent::paramValue(0, SamplerPlugin::ParamGain, 1.0),
                   PluginEvent::paramModulation(0, SamplerPlugin::ParamGain, -0.75)});

    MemoryStateWriter writer;
    REQUIRE(source.instrument.saveState(writer));

    Rig target;
    MemoryStateReader reader(writer.bytes());
    REQUIRE(target.instrument.loadState(reader));

    // The reloaded instrument renders at the base gain: a project must not
    // reopen carrying an offset nobody applied.
    const float reloaded = target.render({PluginEvent::noteOn(0, 60, 1.0)});
    Rig reference;
    const float expected = reference.render({PluginEvent::noteOn(0, 60, 1.0)});
    CHECK(reloaded == expected);
  }

  // ------------------------------------------------------------------------
  // Host cooperation
  // ------------------------------------------------------------------------

  TEST_CASE("The host may decline a thread-pool request and the plugin copes") {
    NullPluginHost host;
    // OneBeat has no worker pool before Stage 4, so it declines — which is
    // always legal, and the plugin must then do the work inline.
    CHECK_FALSE(host.requestThreadPoolExec(8));
  }
}  // TEST_SUITE

TEST_SUITE("engine") {
  TEST_CASE("The engine drives its instrument through the format-agnostic interface") {
    auto engine = onebeat::tests::makeOfflineEngine();
    REQUIRE(engine != nullptr);

    // The engine holds a PluginInstance, not a Sampler: this is the seam a
    // hosted CLAP plugin (OB-2-07) slots into with nothing above it changing.
    PluginInstance& instrument = engine->instrument();
    CHECK(instrument.isActive());
    CHECK(std::string(instrument.name().text()) == "OneBeat Sampler");
    CHECK(instrument.audioPortCount(PortDirection::Output) == 1);
    CHECK(instrument.tailFrames() > 0);  // the release fade, for offline tails
  }

  TEST_CASE("A dense event stream stays sample-accurate across blocks") {
    // An event on almost every frame, which is also what makes this the shape
    // the RTSan stress case exercises: the block is split as many times as
    // there are events, and none of that may allocate.
    auto engine = onebeat::tests::makeOfflineEngine();
    REQUIRE(engine != nullptr);

    onebeat::core::ScheduleBuilder builder;
    constexpr int Notes = 400;
    for (int index = 0; index < Notes; ++index) {
      builder.addNote(onebeat::core::DefaultInstrument, static_cast<int16_t>(48 + (index % 24)),
                      1.0F, static_cast<int64_t>(index) * 37, 30);
    }
    builder.setLengthFrames(static_cast<int64_t>(Notes) * 37);
    engine->publishSchedule(builder.build(48000.0, 1));
    engine->postCommand(onebeat::tests::command(OB_CMD_SET_LOOP, 0, 0.0, 64.0));
    engine->postCommand(onebeat::tests::command(OB_CMD_TRANSPORT_PLAY));

    const auto result = onebeat::testing::renderOffline(*engine, static_cast<int64_t>(Notes) * 37, 128);
    CHECK(result.peak() > 0.05F);

    ob_snapshot snapshot{};
    engine->readSnapshot(snapshot);
    CHECK(snapshot.dropped_log_records == 0);  // no event-list overflow was logged
  }

  TEST_CASE("A render is byte-identical to the pre-plugin-model engine") {
    // The OB-2-01 regression guard. The checksum below was produced by the
    // v0.1 engine — the one that called Sampler::noteOn() directly — and
    // verified identical after the sampler moved behind PluginInstance. If this
    // fails, the event path changed the audio, which OB-2-01 forbids.
    auto engine = onebeat::tests::makeOfflineEngine();
    REQUIRE(engine != nullptr);
    engine->publishSchedule(onebeat::testing::makeGridSchedule(8, 60, 48000.0, 0.5, 120.0));
    engine->postCommand(onebeat::tests::command(OB_CMD_SET_LOOP, 1, 0.0, 4.0));
    engine->postCommand(onebeat::tests::command(OB_CMD_TRANSPORT_PLAY));
    const auto result = onebeat::testing::renderOffline(*engine, 96000, 128);

    // A checksum over the raw sample bits: sensitive to a single ULP, which is
    // the point. Approximate comparison would not catch a re-ordered event.
    uint64_t checksum = 1469598103934665603ULL;
    for (const std::vector<float>* channel : {&result.left, &result.right}) {
      for (const float sample : *channel) {
        uint32_t bits = 0;
        std::memcpy(&bits, &sample, sizeof(bits));
        checksum = (checksum ^ bits) * 1099511628211ULL;
      }
    }
    CHECK(checksum == GoldenRenderChecksum);
  }
}  // TEST_SUITE
