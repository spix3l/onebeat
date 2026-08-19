// Stress tests (OB-1-07 §5, OB-1-10 §5). Run under TSan and ASan in CI.
#include <atomic>
#include <chrono>
#include <filesystem>
#include <string>
#include <thread>

#include <unistd.h>

#include "abi/onebeat_abi.h"
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
      engine->postCommand(
          command(OB_CMD_TRANSPORT_SEEK_FRAMES, static_cast<int64_t>(round) * 1000));
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

    // This used to assert `snapshot.xrun_count == 0`, and it was wrong to.
    // An offline render has no device and therefore no deadline to miss, so the
    // counter was measuring how often CI's scheduler descheduled the render
    // thread during the storm — which it did, intermittently, in Release only.
    // The engine no longer counts xruns without a device (`engine.cpp`
    // publishSnapshot), so the assertion would now be vacuous. What the storm
    // could genuinely break is checked above: every swap landed, playback never
    // went silent, and the audio stayed finite. The one thing a snapshot can
    // still add is that the last schedule to land is the live one.
    ob_snapshot snapshot{};
    engine->readSnapshot(snapshot);
    CHECK(snapshot.schedule_event_count > 0);
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

  // A project the size a user actually builds. The report this covers: "added
  // multiple playlist items and multiple channel rack items, the app crashed".
  //
  // The interesting number is not how big it gets but where the *fixed*
  // capacities sit — MaxRackChannels, MaxMixerTracks, MaxMixerEffects — because
  // every one of them indexes an array the audio thread walks. This deliberately
  // goes past all three, since a project that merely approaches them proves
  // nothing about the one that exceeds them.
  TEST_CASE("A project larger than every fixed capacity renders without misbehaving") {
    namespace fs = std::filesystem;
    const fs::path scratch =
        fs::temp_directory_path() / ("onebeat-large-" + std::to_string(::getpid()));
    fs::remove_all(scratch);
    fs::create_directories(scratch);

    onebeat::testing::RenderResult tone;
    tone.left.assign(2400, 0.25F);
    tone.right.assign(2400, 0.25F);
    const std::string sample = (scratch / "tone.wav").string();
    REQUIRE(onebeat::testing::writeWav(tone, sample));

    ob_engine_config config{};
    config.struct_size = sizeof(config);
    config.sample_rate = 48000.0;
    config.block_frames = 256;
    config.use_null_device = 1;
    ob_engine* engine = nullptr;
    REQUIRE(ob_engine_create(&config, &engine) == OB_OK);

    // Past MaxRackChannels (64) and, because each instrument auto-creates one,
    // past MaxMixerTracks too.
    constexpr int Instruments = 150;
    for (int i = 0; i < Instruments; ++i) {
      REQUIRE(ob_engine_instrument_add_sample(engine, "Ch", sample.c_str()) == OB_OK);
    }
    CHECK(ob_engine_instrument_count(engine) == Instruments);
    CHECK(ob_engine_mixer_track_count(engine) == Instruments + 1);

    ob_lane_info lane{};
    REQUIRE(ob_engine_lane_at(engine, 0, &lane) == OB_OK);

    // Pattern clips and audio clips both. Audio clips are the ones that consume
    // a rack channel each (model/flattener.h), so this is what actually pushes
    // the channel index past the end of the array.
    constexpr int PatternClips = 400;
    for (int i = 0; i < PatternClips; ++i) {
      REQUIRE(ob_engine_clip_add(engine, lane.id, "", static_cast<int64_t>(i) * 3840, 3840) ==
              OB_OK);
    }
    constexpr int AudioClips = 200;
    for (int i = 0; i < AudioClips; ++i) {
      REQUIRE(ob_engine_audio_clip_add(engine, lane.id, sample.c_str(),
                                       static_cast<int64_t>(i) * 1920) == OB_OK);
    }

    // Inserts past MaxMixerEffects would be the next ceiling; a chain on every
    // track is the realistic version of the same pressure.
    for (int i = 0; i < ob_engine_mixer_track_count(engine); ++i) {
      ob_mixer_track_info track{};
      if (ob_engine_mixer_track_at(engine, i, &track) != OB_OK) continue;
      ob_engine_mixer_effect_add(engine, track.id, "dev.onebeat.fx.reverb", -1);
      ob_engine_mixer_effect_add(engine, track.id, "dev.onebeat.fx.delay", -1);
    }

    REQUIRE(ob_engine_start(engine) == OB_OK);
    ob_command play{};
    play.type = OB_CMD_TRANSPORT_PLAY;
    REQUIRE(ob_engine_post_command(engine, &play) == OB_OK);
    // Long enough for the housekeeping thread to reconcile the rack and the
    // mixer, and for the audio thread to render what it published.
    std::this_thread::sleep_for(std::chrono::milliseconds(400));

    ob_snapshot snapshot{};
    ob_engine_read_snapshot(engine, &snapshot);
    CHECK(snapshot.callback_count > 0);

    // Editing while all of that is live is the other half of the report, and
    // the dangerous half: every edit reconciles the rack, which republishes the
    // channels' samples underneath whatever voices are currently sounding.
    for (int i = 0; i < 40; ++i) {
      ob_clip_info clip{};
      if (ob_engine_clip_at(engine, i, &clip) != OB_OK) continue;
      ob_engine_clip_move(engine, clip.id, "", static_cast<int64_t>(i) * 1920);
    }
    // Adding more audio clips mid-playback is what actually forces the sample
    // swap, so it happens here rather than only during the quiet set-up above.
    for (int i = 0; i < 20; ++i) {
      ob_engine_audio_clip_add(engine, lane.id, sample.c_str(), static_cast<int64_t>(i) * 960);
      std::this_thread::sleep_for(std::chrono::milliseconds(5));
    }
    std::this_thread::sleep_for(std::chrono::milliseconds(200));

    ob_engine_destroy(engine);
    fs::remove_all(scratch);
  }

}  // TEST_SUITE
