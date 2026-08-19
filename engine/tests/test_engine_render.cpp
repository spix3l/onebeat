#include <array>
#include <cmath>
#include <filesystem>
#include <memory>
#include <vector>

#include "core/sampler.h"
#include "core/wav_loader.h"
#include "doctest.h"
#include "test_helpers.h"
#include "testing/offline_driver.h"

using onebeat::testing::makeGridSchedule;
using onebeat::testing::renderOffline;
using onebeat::tests::command;
using onebeat::tests::makeOfflineEngine;

TEST_SUITE("engine") {
  TEST_CASE(
      "The offline driver renders through the same process path and stays silent when stopped") {
    auto engine = makeOfflineEngine();
    REQUIRE(engine != nullptr);
    const auto result = renderOffline(*engine, 4800, 128);
    CHECK(result.frames() == 4800);
    CHECK(result.isSilent());
  }

  TEST_CASE("Playing a scheduled note produces audio") {
    auto engine = makeOfflineEngine();
    REQUIRE(engine != nullptr);
    engine->publishSchedule(makeGridSchedule(4, 60, 48000.0, 1.0, 120.0));
    engine->postCommand(command(OB_CMD_SET_LOOP, 1, 0.0, 4.0));
    engine->postCommand(command(OB_CMD_TRANSPORT_PLAY));

    const auto result = renderOffline(*engine, 48000, 128);
    CHECK(result.peak() > 0.05F);
    CHECK(result.peak() <= 1.0F);
  }

  TEST_CASE("The metronome can be enabled and disabled without notes") {
    auto engine = makeOfflineEngine();
    REQUIRE(engine != nullptr);

    engine->postCommand(command(OB_CMD_SET_METRONOME, 1));
    engine->postCommand(command(OB_CMD_TRANSPORT_PLAY));
    const auto click = renderOffline(*engine, 128, 128);
    CHECK(click.peak() > 0.05F);

    engine->postCommand(command(OB_CMD_SET_METRONOME, 0));
    const auto silent = renderOffline(*engine, 128, 128);
    CHECK(silent.isSilent());
  }

  TEST_CASE("Renders are bit-exact across repeated runs") {
    auto first = makeOfflineEngine();
    REQUIRE(first != nullptr);
    first->publishSchedule(makeGridSchedule(8, 60, 48000.0, 0.5, 120.0));
    first->postCommand(command(OB_CMD_TRANSPORT_PLAY));
    const auto reference = renderOffline(*first, 96000, 128);

    for (int run = 0; run < 10; ++run) {
      auto engine = makeOfflineEngine();
      REQUIRE(engine != nullptr);
      engine->publishSchedule(makeGridSchedule(8, 60, 48000.0, 0.5, 120.0));
      engine->postCommand(command(OB_CMD_TRANSPORT_PLAY));
      const auto again = renderOffline(*engine, 96000, 128);
      CHECK(onebeat::testing::sameSamples(reference, again));
    }
  }

  TEST_CASE("A 4-bar loop at 120 BPM wraps at the exact sample with no hanging notes") {
    auto engine = makeOfflineEngine();
    REQUIRE(engine != nullptr);
    // 16 beats at 120 BPM and 48 kHz = 384000 frames.
    engine->publishSchedule(makeGridSchedule(16, 60, 48000.0, 1.0, 120.0));
    engine->postCommand(command(OB_CMD_SET_LOOP, 1, 0.0, 16.0));
    engine->postCommand(command(OB_CMD_TRANSPORT_PLAY));

    renderOffline(*engine, 384000 - 128, 128);
    ob_snapshot before{};
    engine->readSnapshot(before);
    CHECK(before.position_frames == 384000 - 128);

    renderOffline(*engine, 128, 128);
    ob_snapshot after{};
    engine->readSnapshot(after);
    // Exactly wrapped: position is back at the loop start, not past the end.
    CHECK(after.position_frames == 0);

    // Nothing hangs across the seam.
    renderOffline(*engine, 48000, 128);
    ob_snapshot later{};
    engine->readSnapshot(later);
    CHECK(later.active_voices <= 1);
  }

  TEST_CASE("Transport commands take effect at the next block boundary") {
    auto engine = makeOfflineEngine();
    REQUIRE(engine != nullptr);

    engine->postCommand(command(OB_CMD_SET_TEMPO, 0, 174.0));
    engine->postCommand(command(OB_CMD_TRANSPORT_PLAY));
    renderOffline(*engine, 128, 128);

    ob_snapshot snapshot{};
    engine->readSnapshot(snapshot);
    CHECK(snapshot.playing == 1U);
    CHECK(snapshot.tempo_bpm == doctest::Approx(174.0));
    CHECK(snapshot.position_frames == 128);

    engine->postCommand(command(OB_CMD_TRANSPORT_SEEK_FRAMES, 48000));
    renderOffline(*engine, 128, 128);
    engine->readSnapshot(snapshot);
    CHECK(snapshot.position_frames == 48000 + 128);

    engine->postCommand(command(OB_CMD_TRANSPORT_STOP));
    renderOffline(*engine, 128, 128);
    engine->readSnapshot(snapshot);
    CHECK(snapshot.playing == 0U);
    CHECK(snapshot.position_frames == 48000 + 128);  // stop does not rewind
  }

  TEST_CASE("A tempo change during playback does not glitch the output") {
    auto engine = makeOfflineEngine();
    REQUIRE(engine != nullptr);
    engine->publishSchedule(makeGridSchedule(16, 60, 48000.0, 0.5, 120.0));
    engine->postCommand(command(OB_CMD_TRANSPORT_PLAY));
    renderOffline(*engine, 24000, 128);

    engine->postCommand(command(OB_CMD_SET_TEMPO, 0, 90.0));
    const auto after = renderOffline(*engine, 24000, 128);
    CHECK(after.maxDelta() < 0.5F);  // no discontinuity from the tempo change

    ob_snapshot snapshot{};
    engine->readSnapshot(snapshot);
    CHECK(snapshot.tempo_bpm == doctest::Approx(90.0));
  }

  TEST_CASE("Manual note commands sound even when the transport is stopped") {
    auto engine = makeOfflineEngine();
    REQUIRE(engine != nullptr);
    engine->postCommand(command(OB_CMD_NOTE_ON, 60, 1.0));
    const auto result = renderOffline(*engine, 4800, 128);
    CHECK(result.peak() > 0.05F);
  }

  TEST_CASE("Master gain scales the output") {
    auto engine = makeOfflineEngine();
    REQUIRE(engine != nullptr);
    engine->postCommand(command(OB_CMD_NOTE_ON, 60, 1.0));
    const auto loud = renderOffline(*engine, 2400, 128);

    auto quiet_engine = makeOfflineEngine();
    REQUIRE(quiet_engine != nullptr);
    quiet_engine->postCommand(command(OB_CMD_SET_MASTER_GAIN, 0, 0.5));
    quiet_engine->postCommand(command(OB_CMD_NOTE_ON, 60, 1.0));
    const auto quiet = renderOffline(*quiet_engine, 2400, 128);

    CHECK(quiet.peak() == doctest::Approx(loud.peak() * 0.5F).epsilon(0.02));
  }

  TEST_CASE("The snapshot reports metering, latency and voice count") {
    auto engine = makeOfflineEngine();
    REQUIRE(engine != nullptr);
    engine->postCommand(command(OB_CMD_NOTE_ON, 60, 1.0));
    renderOffline(*engine, 1280, 128);

    ob_snapshot snapshot{};
    engine->readSnapshot(snapshot);
    CHECK(snapshot.struct_version == OB_SNAPSHOT_VERSION);
    CHECK(snapshot.struct_size == sizeof(ob_snapshot));
    CHECK(snapshot.sample_rate == doctest::Approx(48000.0));
    CHECK(snapshot.block_frames == 128);
    CHECK(snapshot.peak_left > 0.0F);
    CHECK(snapshot.rms_left > 0.0F);
    CHECK(snapshot.latency_frames_roundtrip > 0);
    CHECK(snapshot.callback_count == 10);
  }

  TEST_CASE("The event-capture plugin records what it was sent, at the right frame") {
    using onebeat::plugin::PluginEvent;
    using Kind = onebeat::testing::EventCapturePlugin::Captured::Kind;

    onebeat::testing::EventCapturePlugin instrument;
    REQUIRE(instrument.configure(onebeat::plugin::ProcessSetup{}));
    REQUIRE(instrument.activate());

    // process() is `[audio-thread]` and asserts it, so a test that drives it
    // says so rather than weakening the assertion.
    const onebeat::plugin::ThreadCheck::ScopedAudioThread audio_thread;

    std::array<PluginEvent, 4> storage{};
    onebeat::plugin::EventList events(storage.data(), static_cast<uint32_t>(storage.size()));
    events.push(PluginEvent::noteOn(0, 60, 1.0));
    events.push(PluginEvent::noteOff(64, 60));

    onebeat::plugin::ProcessBlock block;
    block.frames = 128;
    block.audio_output_count = 1;
    const onebeat::core::AudioBufferView silence;
    block.audio_outputs = &silence;
    block.in_events = events.view();
    instrument.process(block);
    // A second block, to prove the recorded frame is absolute across blocks.
    instrument.process(block);

    const auto captured = instrument.captured();
    REQUIRE(captured.size() == 4);
    CHECK(captured[0].kind == Kind::NoteOn);
    CHECK(captured[0].frame == 0);
    CHECK(captured[1].kind == Kind::NoteOff);
    CHECK(captured[1].frame == 64);
    CHECK(captured[2].frame == 128);
    CHECK(captured[3].frame == 128 + 64);
  }

  // The rack. Before these, the engine hosted one instrument and every lane
  // played whichever sample was loaded last — a kick and a hi-hat both sounding
  // like the clap that happened to be added most recently.
  TEST_CASE("Each channel plays its own sample, not the one loaded last") {
    // Two flat samples at different levels, so which channel produced the audio
    // is readable straight off the peak.
    const auto plateau = [](float level) {
      auto data = std::make_unique<onebeat::core::SampleData>();
      data->channels = 1;
      data->sample_rate = 48000.0;
      data->frames = 48000;
      data->name = "plateau";
      data->samples.assign(static_cast<size_t>(data->frames), level);
      return data;
    };

    // One note per channel, a beat apart, at the sampler's root note so neither
    // is resampled.
    const auto schedule = [](double sample_rate) {
      onebeat::core::ScheduleBuilder builder;
      const auto beat = static_cast<int64_t>(sample_rate / 2.0);  // 120 BPM
      builder.addNote(0, onebeat::core::Sampler::RootNote, 1.0F, 0, beat / 2);
      builder.addNote(1, onebeat::core::Sampler::RootNote, 1.0F, beat, beat / 2);
      return builder.setLengthFrames(beat * 2).build(sample_rate, 1);
    };

    auto engine = makeOfflineEngine();
    REQUIRE(engine != nullptr);

    // Two channels in the rack, then a distinguishable sample in each.
    std::vector<onebeat::core::Engine::ChannelDesc> rack(2);
    engine->setChannels(rack);
    engine->applyPendingWorkForTests();
    engine->channelSampler(0).setSample(plateau(0.5F));
    engine->channelSampler(1).setSample(plateau(0.25F));
    engine->channelSampler(0).collectRetiredSamples(false);
    engine->channelSampler(1).collectRetiredSamples(false);

    engine->publishSchedule(schedule(48000.0));
    engine->postCommand(command(OB_CMD_TRANSPORT_PLAY));

    // Frames 0..12000: only channel 0's note is sounding.
    const auto first = renderOffline(*engine, 12000, 128);
    CHECK(first.peak() == doctest::Approx(0.5F).epsilon(0.02));

    // Frames 12000..24000: the gap, which carries channel 0's release tail.
    // Rendered and discarded so the next window starts clean.
    renderOffline(*engine, 12000, 128);

    // Frames 24000..36000: only channel 1's note. If the channels shared one
    // sampler this would read 0.5 — the whole bug in one assertion.
    const auto second = renderOffline(*engine, 12000, 128);
    CHECK(second.peak() == doctest::Approx(0.25F).epsilon(0.02));
  }

  // Hosting used to take over whichever channel was selected, so loading a
  // plug-in on a new lane replaced the voice of the lane the user had been
  // working on: the hi-hat started playing the piano.
  TEST_CASE("A hosted plug-in takes its own channel, not the selected one") {
    const auto plateau = [](float level) {
      auto data = std::make_unique<onebeat::core::SampleData>();
      data->channels = 1;
      data->sample_rate = 48000.0;
      data->frames = 48000;
      data->name = "plateau";
      data->samples.assign(static_cast<size_t>(data->frames), level);
      return data;
    };

    auto engine = makeOfflineEngine();
    REQUIRE(engine != nullptr);

    // Two sample lanes and a third lane for the plug-in.
    std::vector<onebeat::core::Engine::ChannelDesc> rack(3);
    engine->setChannels(rack);
    engine->applyPendingWorkForTests();
    engine->channelSampler(0).setSample(plateau(0.5F));
    engine->channelSampler(1).setSample(plateau(0.25F));
    engine->channelSampler(0).collectRetiredSamples(false);
    engine->channelSampler(1).collectRetiredSamples(false);

    // Channel 1 is the selected lane — the one the old code would have taken.
    engine->setAuditionChannel(1);
    std::string error;
    REQUIRE(engine->installMissingInstrument("Piano", {}, 2, error));
    CHECK(engine->hasHostedInstrument(2));
    CHECK_FALSE(engine->hasHostedInstrument(1));

    onebeat::core::ScheduleBuilder builder;
    const auto beat = static_cast<int64_t>(48000.0 / 2.0);  // 120 BPM
    builder.addNote(1, onebeat::core::Sampler::RootNote, 1.0F, 0, beat / 2);
    engine->publishSchedule(builder.setLengthFrames(beat * 2).build(48000.0, 1));
    engine->postCommand(command(OB_CMD_TRANSPORT_PLAY));

    // Channel 1 still plays its own sample. Hosted onto channel 1 instead, this
    // would be silence — the plug-in stand-in produces none.
    const auto hosted_elsewhere = renderOffline(*engine, 12000, 128);
    CHECK(hosted_elsewhere.peak() == doctest::Approx(0.25F).epsilon(0.02));

    // Deleting the first lane renumbers the rack; the plug-in follows its
    // instrument down to channel 1 rather than staying on an index.
    std::vector<int> destination(onebeat::core::MaxRackChannels);
    for (size_t channel = 0; channel < destination.size(); ++channel) {
      destination[channel] = static_cast<int>(channel);
    }
    destination[2] = 1;
    REQUIRE(engine->remapHostedInstruments(destination, error));
    CHECK(engine->hasHostedInstrument(1));
    CHECK_FALSE(engine->hasHostedInstrument(2));
  }

  TEST_CASE("An audio-start event plays the loaded sample as a full one-shot") {
    auto engine = makeOfflineEngine();
    REQUIRE(engine != nullptr);

    std::vector<onebeat::core::Engine::ChannelDesc> rack(2);
    engine->setChannels(rack);
    engine->applyPendingWorkForTests();

    auto sample = std::make_unique<onebeat::core::SampleData>();
    sample->channels = 1;
    sample->sample_rate = 48000.0;
    sample->frames = 48000;
    sample->name = "song";
    sample->samples.assign(static_cast<size_t>(sample->frames), 0.25F);
    engine->channelSampler(1).setSample(std::move(sample));
    engine->channelSampler(1).collectRetiredSamples(false);

    onebeat::core::ScheduleBuilder builder;
    builder.addAudioStart(1, 0);
    engine->publishSchedule(builder.setLengthFrames(48000).build(48000.0, 1));
    engine->postCommand(command(OB_CMD_TRANSPORT_PLAY));

    const auto result = renderOffline(*engine, 48000, 128);
    CHECK(result.peak() == doctest::Approx(0.25F).epsilon(0.02));
    CHECK(result.rms() > 0.20F);
  }

  TEST_CASE("Arrangement sample loading targets its channel, not the preview voice") {
    auto engine = makeOfflineEngine();
    REQUIRE(engine != nullptr);

    std::vector<onebeat::core::Engine::ChannelDesc> rack(2);
    rack[1].one_shot = true;
    engine->setChannels(rack);
    engine->applyPendingWorkForTests();

    const std::string path = "/tmp/onebeat-arrangement-channel.wav";
    onebeat::testing::RenderResult source;
    source.left.assign(48000, 0.25F);
    source.right.assign(48000, 0.25F);
    REQUIRE(onebeat::testing::writeWav(source, path));
    std::string error;
    REQUIRE(engine->loadChannelSample(1, path, error));

    onebeat::core::ScheduleBuilder schedule;
    schedule.addAudioStart(1, 0);
    engine->publishSchedule(schedule.setLengthFrames(48000).build(48000.0, 1));
    engine->postCommand(command(OB_CMD_TRANSPORT_PLAY));
    CHECK(renderOffline(*engine, 12000, 128).peak() == doctest::Approx(0.25F).epsilon(0.02));

    std::error_code ignored;
    std::filesystem::remove(path, ignored);
  }

  TEST_CASE("An empty project's audio clip waits for its sample instead of the fallback tone") {
    auto engine = makeOfflineEngine();
    REQUIRE(engine != nullptr);

    const std::string path = "/tmp/onebeat-empty-project-song.wav";
    onebeat::testing::RenderResult source;
    source.left.assign(48000, 0.25F);
    source.right.assign(48000, 0.25F);
    REQUIRE(onebeat::testing::writeWav(source, path));

    onebeat::core::Engine::ChannelDesc audio;
    audio.sample_path = path;
    audio.one_shot = true;
    audio.clip.enabled = true;

    // Do not apply the pending channel work yet. This is the ordering used by
    // the real model publish: decoding is queued, while the schedule is ready
    // immediately. Channel 0 is the empty project's audition/fallback slot.
    engine->setChannels(std::vector<onebeat::core::Engine::ChannelDesc>{audio});
    onebeat::core::ScheduleBuilder schedule;
    schedule.addAudioStart(0, 0);
    engine->publishSchedule(schedule.setLengthFrames(48000).build(48000.0, 1));
    engine->postCommand(command(OB_CMD_TRANSPORT_PLAY));

    // The start is deferred, not rendered through the fallback sampler. If the
    // worker wins the race it may already be the real 0.25 sample; either way,
    // the built-in fallback is much louder and must never be what this event
    // starts.
    CHECK(renderOffline(*engine, 128, 128).peak() <= 0.27F);

    std::error_code ignored;
    engine.reset();
    std::filesystem::remove(path, ignored);
  }

  TEST_CASE("Two audio clips play in parallel on independent channels") {
    auto engine = makeOfflineEngine();
    REQUIRE(engine != nullptr);

    auto plateau = [](float level) {
      auto sample = std::make_unique<onebeat::core::SampleData>();
      sample->channels = 1;
      sample->sample_rate = 48000.0;
      sample->frames = 48000;
      sample->name = "parallel";
      sample->samples.assign(static_cast<size_t>(sample->frames), level);
      return sample;
    };

    std::vector<onebeat::core::Engine::ChannelDesc> rack(3);
    rack[1].one_shot = true;
    rack[2].one_shot = true;
    engine->setChannels(rack);
    engine->applyPendingWorkForTests();
    engine->channelSampler(1).setSample(plateau(0.25F));
    engine->channelSampler(2).setSample(plateau(0.5F));
    engine->channelSampler(1).collectRetiredSamples(false);
    engine->channelSampler(2).collectRetiredSamples(false);

    onebeat::core::ScheduleBuilder schedule;
    schedule.addAudioStart(1, 0);
    schedule.addAudioStart(2, 0);
    engine->publishSchedule(schedule.setLengthFrames(48000).build(48000.0, 1));
    engine->postCommand(command(OB_CMD_TRANSPORT_PLAY));

    const auto result = renderOffline(*engine, 12000, 128);
    CHECK(result.peak() == doctest::Approx(0.75F).epsilon(0.02));
  }

  TEST_CASE("Replacing a schedule releases voices from clips that were moved") {
    auto engine = makeOfflineEngine();
    REQUIRE(engine != nullptr);

    std::vector<onebeat::core::Engine::ChannelDesc> rack(2);
    engine->setChannels(rack);
    engine->applyPendingWorkForTests();

    auto sample = std::make_unique<onebeat::core::SampleData>();
    sample->channels = 1;
    sample->sample_rate = 48000.0;
    sample->frames = 48000 * 4;
    sample->name = "moving-song";
    sample->samples.assign(static_cast<size_t>(sample->frames), 0.25F);
    engine->channelSampler(1).setSample(std::move(sample));
    engine->channelSampler(1).collectRetiredSamples(false);

    onebeat::core::ScheduleBuilder old_schedule;
    old_schedule.addAudioStart(1, 0);
    engine->publishSchedule(old_schedule.setLengthFrames(48000 * 4).build(48000.0, 1));
    engine->postCommand(command(OB_CMD_TRANSPORT_PLAY));
    CHECK(renderOffline(*engine, 1024, 128).peak() > 0.20F);

    // A move/edit publishes a replacement schedule while transport is already
    // running. The old song must not continue from its previous position. The
    // ABI requests this channel-specific reset for the moved clip.
    onebeat::core::ScheduleBuilder moved_schedule;
    engine->requestChannelReset(1);
    engine->publishSchedule(moved_schedule.setLengthFrames(48000 * 4).build(48000.0, 2));
    // Let the sampler's click-safe release fade finish before measuring the
    // replacement schedule. The old voice must not remain at full level.
    renderOffline(*engine, 512, 128);
    const auto after_move = renderOffline(*engine, 2048, 128);
    CHECK(after_move.peak() < 0.05F);
  }

  // Editing a step in the channel rack republishes the whole schedule. That
  // used to release every voice in the rack, so painting a drum lane silenced
  // the melody a hosted plug-in was in the middle of playing. Only the channels
  // whose events actually changed may be released.
  TEST_CASE("Republishing a schedule leaves untouched channels sounding") {
    auto engine = makeOfflineEngine();
    REQUIRE(engine != nullptr);

    std::vector<onebeat::core::Engine::ChannelDesc> rack(2);
    // Channel 0 is the lane being edited and is silent, so everything measured
    // below is channel 1 — the lane nobody touched.
    rack[0].muted = true;
    engine->setChannels(rack);
    engine->applyPendingWorkForTests();

    auto sample = std::make_unique<onebeat::core::SampleData>();
    sample->channels = 1;
    sample->sample_rate = 48000.0;
    sample->frames = 48000;
    sample->name = "sustained";
    sample->samples.assign(48000, 0.5F);
    engine->channelSampler(1).setSample(std::move(sample));
    engine->channelSampler(1).collectRetiredSamples(false);

    // The note on channel 1 is identical in every schedule below; only the
    // events on channel 0 — the lane being edited — differ.
    const auto hold = [](onebeat::core::ScheduleBuilder& builder, onebeat::core::InstrumentId id) {
      builder.addNote(id, onebeat::core::Sampler::RootNote, 1.0F, 0, 48000);
    };

    onebeat::core::ScheduleBuilder first;
    hold(first, 1);
    hold(first, 0);
    engine->publishSchedule(first.setLengthFrames(48000).build(48000.0, 1));
    engine->postCommand(command(OB_CMD_TRANSPORT_PLAY));
    CHECK(renderOffline(*engine, 4096, 128).peak() > 0.20F);

    // The edit: another step on channel 0, and nothing at all on channel 1.
    onebeat::core::ScheduleBuilder edited;
    hold(edited, 1);
    hold(edited, 0);
    edited.addNote(0, onebeat::core::Sampler::RootNote, 1.0F, 24000, 12000);
    engine->publishSchedule(edited.setLengthFrames(48000).build(48000.0, 2));
    renderOffline(*engine, 512, 128);
    CHECK(renderOffline(*engine, 2048, 128).peak() > 0.20F);

    // And the guarantee the blanket release existed for: a voice whose own
    // channel was edited out from under it does not hang.
    onebeat::core::ScheduleBuilder without;
    hold(without, 0);
    engine->publishSchedule(without.setLengthFrames(48000).build(48000.0, 3));
    renderOffline(*engine, 512, 128);
    CHECK(renderOffline(*engine, 2048, 128).peak() < 0.05F);
  }

  TEST_CASE("A channel's notes do not sound on any other channel") {
    auto engine = makeOfflineEngine();
    REQUIRE(engine != nullptr);

    std::vector<onebeat::core::Engine::ChannelDesc> rack(2);
    // Channel 0 silent, channel 1 audible. A note addressed to channel 0 must
    // then produce nothing at all.
    rack[0].muted = true;
    engine->setChannels(rack);
    engine->applyPendingWorkForTests();

    auto sample = std::make_unique<onebeat::core::SampleData>();
    sample->channels = 1;
    sample->sample_rate = 48000.0;
    sample->frames = 48000;
    sample->name = "plateau";
    sample->samples.assign(48000, 0.5F);
    engine->channelSampler(0).setSample(std::move(sample));
    engine->channelSampler(0).collectRetiredSamples(false);

    onebeat::core::ScheduleBuilder builder;
    builder.addNote(0, onebeat::core::Sampler::RootNote, 1.0F, 0, 12000);
    engine->publishSchedule(builder.setLengthFrames(48000).build(48000.0, 1));
    engine->postCommand(command(OB_CMD_TRANSPORT_PLAY));

    CHECK(renderOffline(*engine, 12000, 128).isSilent());
  }

}  // TEST_SUITE
