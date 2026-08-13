// ABI freeze test (OB-1-10 §4).
//
// Every offset here was recorded when ABI 1.0 was frozen. A failure means the
// layout drifted: either revert it, or bump OB_ABI_VERSION_MAJOR and update
// these values deliberately, following the checklist in ADR-002 §8. Silently
// changing a field's position is how a Dart client starts reading the tempo out
// of the middle of a timestamp.
#include <cstddef>

#include "abi/onebeat_abi.h"
#include "doctest.h"
#include "test_helpers.h"

TEST_SUITE("abi") {
  TEST_CASE("ABI version is 1.0.0 and packs as documented") {
    CHECK(ob_abi_version() == OB_ABI_VERSION_PACKED);
    CHECK((ob_abi_version() >> 16) == 1);
    CHECK(std::string(ob_abi_version_string()) == "1.0.0");
  }

  TEST_CASE("ob_command layout is frozen") {
    CHECK(sizeof(ob_command) == 32);
    CHECK(offsetof(ob_command, type) == 0);
    CHECK(offsetof(ob_command, generation) == 4);
    CHECK(offsetof(ob_command, i64_a) == 8);
    CHECK(offsetof(ob_command, f64_a) == 16);
    CHECK(offsetof(ob_command, f64_b) == 24);
  }

  TEST_CASE("ob_snapshot layout is frozen") {
    CHECK(sizeof(ob_snapshot) == 168);
    CHECK(offsetof(ob_snapshot, struct_version) == 0);
    CHECK(offsetof(ob_snapshot, struct_size) == 4);
    CHECK(offsetof(ob_snapshot, playing) == 8);
    CHECK(offsetof(ob_snapshot, loop_enabled) == 12);
    CHECK(offsetof(ob_snapshot, position_frames) == 16);
    CHECK(offsetof(ob_snapshot, host_time_ns) == 24);
    CHECK(offsetof(ob_snapshot, callback_count) == 32);
    CHECK(offsetof(ob_snapshot, xrun_count) == 40);
    CHECK(offsetof(ob_snapshot, dropped_log_records) == 48);
    CHECK(offsetof(ob_snapshot, last_command_generation) == 56);
    CHECK(offsetof(ob_snapshot, position_beats) == 64);
    CHECK(offsetof(ob_snapshot, position_seconds) == 72);
    CHECK(offsetof(ob_snapshot, tempo_bpm) == 80);
    CHECK(offsetof(ob_snapshot, loop_start_beats) == 88);
    CHECK(offsetof(ob_snapshot, loop_end_beats) == 96);
    CHECK(offsetof(ob_snapshot, sample_rate) == 104);
    CHECK(offsetof(ob_snapshot, bar) == 112);
    CHECK(offsetof(ob_snapshot, beat) == 116);
    CHECK(offsetof(ob_snapshot, tick) == 120);
    CHECK(offsetof(ob_snapshot, block_frames) == 124);
    CHECK(offsetof(ob_snapshot, active_voices) == 128);
    CHECK(offsetof(ob_snapshot, latency_frames_output) == 132);
    CHECK(offsetof(ob_snapshot, latency_frames_roundtrip) == 136);
    CHECK(offsetof(ob_snapshot, schedule_event_count) == 140);
    CHECK(offsetof(ob_snapshot, peak_left) == 144);
    CHECK(offsetof(ob_snapshot, peak_right) == 148);
    CHECK(offsetof(ob_snapshot, rms_left) == 152);
    CHECK(offsetof(ob_snapshot, rms_right) == 156);
    CHECK(offsetof(ob_snapshot, cpu_load) == 160);
    CHECK(offsetof(ob_snapshot, master_gain) == 164);
    // The seqlock publishes the struct as 64-bit words.
    CHECK(sizeof(ob_snapshot) % sizeof(uint64_t) == 0);
  }

  TEST_CASE("ob_event layout is frozen") {
    CHECK(sizeof(ob_event) == 120);
    CHECK(offsetof(ob_event, type) == 0);
    CHECK(offsetof(ob_event, code) == 4);
    CHECK(offsetof(ob_event, i64_a) == 8);
    CHECK(offsetof(ob_event, f64_a) == 16);
    CHECK(offsetof(ob_event, text) == 24);
  }

  TEST_CASE("The full lifecycle round-trips through the C surface") {
    ob_engine_config config{};
    config.struct_size = sizeof(config);
    config.sample_rate = 48000.0;
    config.block_frames = 128;
    config.use_null_device = 1;
    config.log_directory = "/tmp/onebeat-tests/logs";

    ob_engine* engine = nullptr;
    REQUIRE(ob_engine_create(&config, &engine) == OB_OK);
    REQUIRE(engine != nullptr);

    ob_command play{};
    play.type = OB_CMD_TRANSPORT_PLAY;
    play.generation = 7;
    CHECK(ob_engine_post_command(engine, &play) == OB_OK);

    ob_snapshot snapshot{};
    CHECK(ob_engine_read_snapshot(engine, &snapshot) == OB_OK);

    const uint8_t steps[8] = {100, 0, 80, 0, 100, 0, 80, 0};
    CHECK(ob_engine_set_step_pattern(engine, steps, 8, 60, 0.5) == OB_OK);
    CHECK(std::string(ob_engine_output_device_name(engine)).find("Null") != std::string::npos);

    ob_event event{};
    bool saw_schedule_event = false;
    while (ob_engine_poll_event(engine, &event) == 1) {
      saw_schedule_event = saw_schedule_event || event.type == OB_EVT_SCHEDULE_PUBLISHED;
    }
    CHECK(saw_schedule_event);

    ob_engine_destroy(engine);
  }

  TEST_CASE("Bad arguments produce status codes and messages, never crashes") {
    CHECK(ob_engine_create(nullptr, nullptr) == OB_ERR_INVALID_ARGUMENT);
    CHECK(std::string(ob_last_error_message()).empty() == false);
    CHECK(ob_engine_post_command(nullptr, nullptr) == OB_ERR_INVALID_ARGUMENT);
    CHECK(ob_engine_read_snapshot(nullptr, nullptr) == OB_ERR_INVALID_ARGUMENT);
    CHECK(ob_engine_poll_event(nullptr, nullptr) == 0);
    CHECK(std::string(ob_status_name(OB_ERR_QUEUE_FULL)) == "OB_ERR_QUEUE_FULL");
    ob_engine_destroy(nullptr);  // must be a no-op
  }

}  // TEST_SUITE
