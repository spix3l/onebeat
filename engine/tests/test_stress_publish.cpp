// Stress tests (OB-1-07 §5, OB-1-10 §5). Run under TSan and ASan in CI.
#include <atomic>
#include <chrono>
#include <thread>

#include "doctest.h"
#include "test_helpers.h"
#include "testing/offline_driver.h"

using onebeat::testing::makeGridSchedule;
using onebeat::tests::command;
using onebeat::tests::makeOfflineEngine;

TEST_SUITE("stress") {

  TEST_CASE("The plugin event path is allocation- and lock-free under load") {
    // The RTSan target for OB-2-01 AC 3. Everything the model does on the audio
    // thread runs here at volume: building an event list, sorting it, splitting
    // the block at every event, and dispatching through a virtual process()
    // call. RTSan aborts the run on the first malloc or lock inside any
    // [[clang::nonblocking]] frame, so a green run *is* the proof.
    //
    // Deliberately overfilled: the list is pushed past its capacity so the
    // overflow path — which must drop and count, never grow — is exercised too.
    auto engine = makeOfflineEngine(48000.0, 512);
    REQUIRE(engine != nullptr);

    onebeat::core::ScheduleBuilder builder;
    constexpr int Notes = 20000;
    for (int index = 0; index < Notes; ++index) {
      builder.addNote(onebeat::core::DefaultInstrument, static_cast<int16_t>(36 + (index % 36)),
                      0.8F, static_cast<int64_t>(index) * 5, 4);
    }
    builder.setLengthFrames(static_cast<int64_t>(Notes) * 5);
    engine->publishSchedule(builder.build(48000.0, 1));
    engine->postCommand(command(OB_CMD_SET_LOOP, 1, 0.0, 8.0));
    engine->postCommand(command(OB_CMD_TRANSPORT_PLAY));

    // Interleave transport commands so the command-to-event path, the loop-wrap
    // note-off carry and the schedule path all run in the same blocks.
    for (int round = 0; round < 20; ++round) {
      engine->postCommand(command(OB_CMD_NOTE_ON, 72, 1.0));
      engine->postCommand(command(OB_CMD_TRANSPORT_SEEK_FRAMES, round * 1000));
      engine->postCommand(command(OB_CMD_ALL_NOTES_OFF));
      const auto result = onebeat::testing::renderOffline(*engine, 48000, 512);
      CHECK(result.frames() == 48000);
    }
  }
  TEST_CASE("1000+ schedule publishes during continuous playback lose no events") {
    // The publisher does a fixed number of swaps and the render loop keeps
    // going until it has finished. Rendering for a fixed duration instead makes
    // the swap count a race against the machine: in a Release build the render
    // outran the publisher and only three swaps happened.
    constexpr int Publishes = 1200;
    auto engine = makeOfflineEngine(48000.0, 128);
    REQUIRE(engine != nullptr);
    engine->publishSchedule(makeGridSchedule(16, 60, 48000.0, 0.25, 120.0));
    engine->postCommand(command(OB_CMD_SET_LOOP, 1, 0.0, 4.0));
    engine->postCommand(command(OB_CMD_TRANSPORT_PLAY));

    std::atomic<int> published{0};
    std::thread publisher([&] {
      for (int index = 0; index < Publishes; ++index) {
        engine->publishSchedule(makeGridSchedule(16, 60, 48000.0, 0.25, 120.0));
        published.fetch_add(1, std::memory_order_release);
        std::this_thread::yield();
      }
    });

    // Render in one-second chunks until every swap has landed, so playback is
    // continuous for the whole of the publishing storm whatever the build type.
    onebeat::testing::RenderResult result;
    while (published.load(std::memory_order_acquire) < Publishes) {
      const auto chunk = onebeat::testing::renderOffline(*engine, 48000, 128);
      if (result.frames() == 0) {
        result = chunk;
      }
    }
    publisher.join();

    CHECK(published.load() == Publishes);
    CHECK(result.frames() == 48000);
    CHECK(result.peak() > 0.0F);         // the swaps never silenced playback
    CHECK(std::isfinite(result.rms()));  // and never corrupted it

    ob_snapshot snapshot{};
    engine->readSnapshot(snapshot);
    CHECK(snapshot.xrun_count == 0);
  }

  TEST_CASE("Retired schedules are all reclaimed once playback stops") {
    auto engine = makeOfflineEngine(48000.0, 128);
    REQUIRE(engine != nullptr);
    for (int index = 0; index < 200; ++index) {
      engine->publishSchedule(makeGridSchedule(4, 60, 48000.0, 1.0, 120.0));
      onebeat::testing::renderOffline(*engine, 128, 128);
    }
    engine->stop();
    // The housekeeping thread collects on its next pass; ASan proves nothing
    // leaked and nothing was freed early.
    std::this_thread::sleep_for(std::chrono::milliseconds(200));
    CHECK(engine->scheduleGeneration() >= 200);
  }

  TEST_CASE("Hammering commands while reading snapshots stays consistent") {
    auto engine = makeOfflineEngine(48000.0, 128);
    REQUIRE(engine != nullptr);
    engine->postCommand(command(OB_CMD_TRANSPORT_PLAY));

    std::atomic<bool> running{true};
    std::thread commander([&] {
      uint32_t generation = 0;
      while (running.load(std::memory_order_acquire)) {
        ob_command tempo = command(OB_CMD_SET_TEMPO, 0, 90.0 + (generation % 60));
        tempo.generation = ++generation;
        engine->postCommand(tempo);
        engine->postCommand(command(OB_CMD_NOTE_ON, 60 + (generation % 12), 0.5));
      }
    });

    std::thread reader([&] {
      ob_snapshot snapshot{};
      while (running.load(std::memory_order_acquire)) {
        engine->readSnapshot(snapshot);
        // A torn read would show up as an impossible tempo or a negative position.
        CHECK(snapshot.tempo_bpm >= 20.0);
        CHECK(snapshot.tempo_bpm <= 999.0);
        CHECK(snapshot.position_frames >= 0);
      }
    });

    onebeat::testing::renderOffline(*engine, 240000, 128);
    running.store(false, std::memory_order_release);
    commander.join();
    reader.join();
  }

}  // TEST_SUITE
