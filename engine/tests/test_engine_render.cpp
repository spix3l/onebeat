#include <cmath>

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

  TEST_CASE("The event-capture instrument records what it was sent") {
    onebeat::testing::EventCaptureInstrument instrument;
    instrument.prepare(48000.0, 128);
    instrument.noteOn(60, 1.0F);
    instrument.render(onebeat::core::AudioBufferView(), 0, 128);
    instrument.noteOff(60);

    REQUIRE(instrument.captured().size() == 2);
    CHECK(instrument.captured()[0].kind ==
          onebeat::testing::EventCaptureInstrument::Captured::Kind::NoteOn);
    CHECK(instrument.captured()[0].frame == 0);
    CHECK(instrument.captured()[1].frame == 128);
  }

}  // TEST_SUITE
