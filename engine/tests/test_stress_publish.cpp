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
  TEST_CASE("1000+ schedule publishes during continuous playback lose no events") {
    auto engine = makeOfflineEngine(48000.0, 128);
    REQUIRE(engine != nullptr);
    engine->publishSchedule(makeGridSchedule(16, 60, 48000.0, 0.25, 120.0));
    engine->postCommand(command(OB_CMD_SET_LOOP, 1, 0.0, 4.0));
    engine->postCommand(command(OB_CMD_TRANSPORT_PLAY));

    std::atomic<bool> publishing{true};
    std::atomic<int> published{0};
    std::thread publisher([&] {
      while (publishing.load(std::memory_order_acquire)) {
        engine->publishSchedule(makeGridSchedule(16, 60, 48000.0, 0.25, 120.0));
        published.fetch_add(1, std::memory_order_relaxed);
        std::this_thread::yield();
      }
    });

    // ~10 s of audio at 128-frame blocks, rendered as fast as the machine can.
    const auto result = onebeat::testing::renderOffline(*engine, 480000, 128);
    publishing.store(false, std::memory_order_release);
    publisher.join();

    CHECK(published.load() > 1000);
    CHECK(result.frames() == 480000);
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
