// ABI freeze test (OB-1-10 §4).
//
// Every offset here was recorded when ABI 1.0 was frozen. A failure means the
// layout drifted: either revert it, or bump OB_ABI_VERSION_MAJOR and update
// these values deliberately, following the checklist in ADR-002 §8. Silently
// changing a field's position is how a Dart client starts reading the tempo out
// of the middle of a timestamp.
#include <unistd.h>
#include <chrono>
#include <cstddef>
#include <cstdlib>
#include <filesystem>
#include <thread>

#include "abi/onebeat_abi.h"
#include "doctest.h"
#include "test_helpers.h"

TEST_SUITE("abi") {
  // The minor version moves when functions or structs are *added* (ADR-002 §8);
  // the major is what a client refuses to run against, and it has not moved.
  TEST_CASE("ABI version is 1.6.0 and packs as documented") {
    CHECK(ob_abi_version() == OB_ABI_VERSION_PACKED);
    CHECK((ob_abi_version() >> 16) == 1);
    CHECK(std::string(ob_abi_version_string()) == "1.6.0");
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

  // Added in ABI 1.1 (OB-2-02). Frozen from here on for the same reason as the
  // rest: ffigen generates Dart structs from these offsets.
  TEST_CASE("ob_plugin_scan_status layout is frozen") {
    CHECK(sizeof(ob_plugin_scan_status) == 288);
    CHECK(offsetof(ob_plugin_scan_status, struct_size) == 0);
    CHECK(offsetof(ob_plugin_scan_status, state) == 4);
    CHECK(offsetof(ob_plugin_scan_status, bundles_discovered) == 8);
    CHECK(offsetof(ob_plugin_scan_status, bundles_reused) == 12);
    CHECK(offsetof(ob_plugin_scan_status, bundles_probed) == 16);
    CHECK(offsetof(ob_plugin_scan_status, plugins_found) == 20);
    CHECK(offsetof(ob_plugin_scan_status, plugin_count) == 24);
    CHECK(offsetof(ob_plugin_scan_status, list_generation) == 28);
    CHECK(offsetof(ob_plugin_scan_status, current) == 32);
  }

  TEST_CASE("ob_plugin_info layout is frozen") {
    CHECK(sizeof(ob_plugin_info) == 1000);
    CHECK(offsetof(ob_plugin_info, struct_size) == 0);
    CHECK(offsetof(ob_plugin_info, format) == 4);
    CHECK(offsetof(ob_plugin_info, outcome) == 8);
    CHECK(offsetof(ob_plugin_info, flags) == 12);
    CHECK(offsetof(ob_plugin_info, features) == 16);
    CHECK(offsetof(ob_plugin_info, param_count) == 20);
    CHECK(offsetof(ob_plugin_info, index_in_bundle) == 24);
    CHECK(offsetof(ob_plugin_info, audio_input_count) == 28);
    CHECK(offsetof(ob_plugin_info, audio_output_count) == 32);
    CHECK(offsetof(ob_plugin_info, note_input_count) == 36);
    CHECK(offsetof(ob_plugin_info, note_output_count) == 40);
    CHECK(offsetof(ob_plugin_info, scanned_at_nanos) == 48);
    CHECK(offsetof(ob_plugin_info, id) == 56);
    CHECK(offsetof(ob_plugin_info, name) == 184);
    CHECK(offsetof(ob_plugin_info, vendor) == 312);
    CHECK(offsetof(ob_plugin_info, version) == 440);
    CHECK(offsetof(ob_plugin_info, path) == 472);
    CHECK(offsetof(ob_plugin_info, failure_phase) == 984);
    CHECK(offsetof(ob_plugin_info, failure_signal) == 988);
    CHECK(offsetof(ob_plugin_info, retry_count) == 992);
  }

  TEST_CASE("ABI 1.4 hosted instance and parameter layouts are frozen") {
    CHECK(sizeof(ob_instance_info) == 920);
    CHECK(offsetof(ob_instance_info, instance_id) == 4);
    CHECK(offsetof(ob_instance_info, param_count) == 16);
    CHECK(offsetof(ob_instance_info, plugin_id) == 24);
    CHECK(offsetof(ob_instance_info, path) == 408);
    CHECK(sizeof(ob_param_info) == 432);
    CHECK(offsetof(ob_param_info, param_id) == 8);
    CHECK(offsetof(ob_param_info, min_value) == 16);
    CHECK(offsetof(ob_param_info, value) == 40);
    CHECK(offsetof(ob_param_info, name) == 48);
    CHECK(offsetof(ob_param_info, display) == 304);
  }

  TEST_CASE("ABI 1.5 project instrument layout is frozen") {
    CHECK(sizeof(ob_instrument_info) == 1088);
    CHECK(offsetof(ob_instrument_info, order) == 4);
    CHECK(offsetof(ob_instrument_info, affected_pattern_count) == 12);
    CHECK(offsetof(ob_instrument_info, id) == 24);
    CHECK(offsetof(ob_instrument_info, name) == 56);
    CHECK(offsetof(ob_instrument_info, color) == 184);
    CHECK(offsetof(ob_instrument_info, plugin_id) == 192);
    CHECK(offsetof(ob_instrument_info, plugin_path) == 576);
  }

  TEST_CASE("ABI 1.6 channel rack layouts are frozen") {
    CHECK(sizeof(ob_rack_pattern_info) == 192);
    CHECK(offsetof(ob_rack_pattern_info, length_ticks) == 8);
    CHECK(offsetof(ob_rack_pattern_info, swing) == 24);
    CHECK(offsetof(ob_rack_pattern_info, id) == 32);
    CHECK(sizeof(ob_rack_row_info) == 832);
    CHECK(offsetof(ob_rack_row_info, grid_ticks) == 8);
    CHECK(offsetof(ob_rack_row_info, instrument_id) == 28);
    CHECK(offsetof(ob_rack_row_info, step_active) == 60);
    CHECK(offsetof(ob_rack_row_info, step_velocity) == 316);
  }

  TEST_CASE("The plugin list is reachable through the C surface") {
    ob_engine_config config{};
    config.struct_size = sizeof(config);
    config.use_null_device = 1;
    config.block_frames = 128;
    config.log_directory = "/tmp/onebeat-tests/logs";

    ob_engine* engine = nullptr;
    REQUIRE(ob_engine_create(&config, &engine) == OB_OK);

    // Scans a directory that does not exist, so the test is hermetic: it must
    // not depend on what the machine running it happens to have installed.
    //
    // Deliberately *not* asserting that a second start returns
    // OB_ERR_ALREADY_RUNNING here. A scan with nothing to find finishes in
    // microseconds, so "is it still running?" is a race — one this test lost on
    // CI's TSan runner. Contention is tested deterministically in
    // test_plugin_scan.cpp, with a probe that blocks until the test says so.
    REQUIRE(ob_engine_plugin_scan_start(engine, "/nonexistent/onebeat-test-plugins\0\0") == OB_OK);

    // A wall-clock deadline with a yield rather than a fixed poll count: 2000
    // tight polls is a few milliseconds, which is not a safe margin on a loaded
    // sanitizer runner where the scan thread may simply not be scheduled yet.
    ob_plugin_scan_status status{};
    const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(10);
    while (status.state != OB_SCAN_COMPLETE && std::chrono::steady_clock::now() < deadline) {
      REQUIRE(ob_engine_plugin_scan_status(engine, &status) == OB_OK);
      std::this_thread::sleep_for(std::chrono::milliseconds(1));
    }
    CHECK(status.state == OB_SCAN_COMPLETE);
    CHECK(status.struct_size == sizeof(ob_plugin_scan_status));
    CHECK(status.bundles_discovered == 0);
    CHECK(status.plugin_count == 0);

    ob_plugin_info info{};
    CHECK(ob_engine_plugin_at(engine, 0, &info) == OB_ERR_INVALID_ARGUMENT);
    CHECK(ob_engine_plugin_at(engine, -1, &info) == OB_ERR_INVALID_ARGUMENT);
    CHECK(ob_engine_plugin_retry(engine, nullptr) == OB_ERR_INVALID_ARGUMENT);
    CHECK(ob_engine_plugin_retry(engine, "") == OB_ERR_INVALID_ARGUMENT);

    ob_engine_destroy(engine);
  }

  TEST_CASE("The hosted instance and generic parameter model cross the C surface") {
    REQUIRE(::setenv("OB_PLUGIN_HOST", OB_TEST_HELPER, 1) == 0);
    ob_engine_config config{};
    config.struct_size = sizeof(config);
    config.sample_rate = 48000.0;
    config.block_frames = 128;
    config.use_null_device = 1;
    config.log_directory = "/tmp/onebeat-tests/hosted-abi";
    ob_engine* engine = nullptr;
    REQUIRE(ob_engine_create(&config, &engine) == OB_OK);
    const std::string bundle = std::string(OB_TEST_PLUGIN_DIR) + "/ob_test_plugin_ok.clap";
    REQUIRE_MESSAGE(
        ob_engine_instance_add(engine, bundle.c_str(), "dev.onebeat.test.synth") == OB_OK,
        ob_last_error_message());
    CHECK(ob_engine_instance_count(engine) == 1);
    ob_instance_info instance{};
    REQUIRE(ob_engine_instance_at(engine, 0, &instance) == OB_OK);
    CHECK(instance.instance_id == 1);
    CHECK(std::string(instance.name) == "OneBeat Test Synth");
    CHECK(instance.param_count == 1);
    ob_param_info param{};
    REQUIRE(ob_engine_param_at(engine, instance.instance_id, 0, &param) == OB_OK);
    CHECK(param.param_id == 17);
    CHECK(std::string(param.name) == "Gain");
    CHECK_FALSE(std::string(param.display).empty());

    CHECK(ob_engine_instrument_count(engine) == 1);
    ob_instrument_info project_instrument{};
    REQUIRE(ob_engine_instrument_at(engine, 0, &project_instrument) == OB_OK);
    CHECK(std::string(project_instrument.name) == "OneBeat Test Synth");
    CHECK((project_instrument.flags & 2U) != 0U);
    CHECK(std::string(project_instrument.plugin_id) == "dev.onebeat.test.synth");

    ob_rack_pattern_info pattern{};
    REQUIRE(ob_engine_rack_pattern(engine, &pattern) == OB_OK);
    CHECK(pattern.length_ticks == 3840);
    CHECK(ob_engine_rack_row_count(engine) == 1);
    ob_rack_row_info row{};
    REQUIRE(ob_engine_rack_row_at(engine, 0, &row) == OB_OK);
    CHECK(row.step_count == 16);
    CHECK(row.note_count == 0);
    REQUIRE(ob_engine_rack_gesture_begin(engine, "Paint steps") == OB_OK);
    for (const int32_t step : {0, 4, 8, 12}) {
      REQUIRE(ob_engine_rack_toggle_step(engine, project_instrument.id, step) == OB_OK);
    }
    REQUIRE(ob_engine_rack_gesture_commit(engine) == OB_OK);
    REQUIRE(ob_engine_rack_set_step_velocity(engine, project_instrument.id, 4, 8192) == OB_OK);
    REQUIRE(ob_engine_rack_set_swing(engine, 0.5) == OB_OK);
    REQUIRE(ob_engine_rack_row_at(engine, 0, &row) == OB_OK);
    CHECK(row.note_count == 4);
    CHECK(row.step_active[4] == 1);
    CHECK(row.step_velocity[4] == 8192);
    CHECK(ob_engine_project_can_undo(engine) == 1);
    REQUIRE(ob_engine_rack_remove_sequence(engine, project_instrument.id) == OB_OK);
    REQUIRE(ob_engine_rack_row_at(engine, 0, &row) == OB_OK);
    CHECK(row.note_count == 0);
    CHECK_FALSE(std::string(ob_engine_project_undo_name(engine)).empty());
    ob_event schedule_event{};
    while (ob_engine_poll_event(engine, &schedule_event) == 1) {
    }
    REQUIRE(ob_engine_project_undo(engine) == OB_OK);
    bool undo_published = false;
    while (ob_engine_poll_event(engine, &schedule_event) == 1) {
      undo_published = undo_published || schedule_event.type == OB_EVT_SCHEDULE_PUBLISHED;
    }
    CHECK(undo_published);
    CHECK_FALSE(std::string(ob_engine_project_redo_name(engine)).empty());
    REQUIRE(ob_engine_rack_set_row_grid(engine, project_instrument.id, 120) == OB_OK);
    REQUIRE(ob_engine_rack_set_length(engine, 32) == OB_OK);
    REQUIRE(ob_engine_rack_row_at(engine, 0, &row) == OB_OK);
    CHECK(row.step_count == 64);
    REQUIRE(ob_engine_instrument_set_muted(engine, project_instrument.id, 1) == OB_OK);
    REQUIRE(ob_engine_instrument_at(engine, 0, &project_instrument) == OB_OK);
    CHECK((project_instrument.flags & 1U) != 0U);
    REQUIRE(ob_engine_instrument_replace(engine, project_instrument.id, bundle.c_str(),
                                         "dev.onebeat.test.synth") == OB_OK);

    REQUIRE(ob_engine_instrument_rename(engine, project_instrument.id, "Lead") == OB_OK);
    REQUIRE(ob_engine_instrument_duplicate(engine, project_instrument.id) == OB_OK);
    CHECK(ob_engine_instrument_count(engine) == 2);
    ob_instrument_info duplicate{};
    REQUIRE(ob_engine_instrument_at(engine, 1, &duplicate) == OB_OK);
    CHECK(std::string(duplicate.name) == "Lead 2");
    CHECK(std::string(duplicate.id) != std::string(project_instrument.id));
    CHECK((duplicate.flags & 2U) != 0U);

    REQUIRE(ob_engine_instrument_reorder(engine, duplicate.id, 0) == OB_OK);
    REQUIRE(ob_engine_instrument_at(engine, 0, &duplicate) == OB_OK);
    CHECK(std::string(duplicate.name) == "Lead 2");
    CHECK(ob_engine_project_can_undo(engine) == 1);
    REQUIRE(ob_engine_project_undo(engine) == OB_OK);
    REQUIRE(ob_engine_project_redo(engine) == OB_OK);

    REQUIRE(ob_engine_instrument_remove(engine, project_instrument.id) == OB_OK);
    CHECK(ob_engine_instrument_count(engine) == 1);
    CHECK(ob_engine_instance_remove(engine, instance.instance_id) == OB_OK);
    CHECK(ob_engine_instance_count(engine) == 0);
    CHECK(ob_engine_instrument_count(engine) == 0);
    ob_engine_destroy(engine);
  }

  TEST_CASE("Scratch sessions preserve an opaque chunk through a missing placeholder") {
    namespace fs = std::filesystem;
    REQUIRE(::setenv("OB_PLUGIN_HOST", OB_TEST_HELPER, 1) == 0);
    const fs::path scratch =
        fs::path("/tmp/onebeat-tests") / ("stage2-session-" + std::to_string(::getpid()));
    fs::remove_all(scratch);
    fs::create_directories(scratch);
    const fs::path bundle = scratch / "SavedSynth.clap";
    fs::create_directory_symlink(fs::path(OB_TEST_PLUGIN_DIR) / "ob_test_plugin_ok.clap", bundle);
    const fs::path session = scratch / "session.obs2";

    ob_engine_config config{};
    config.struct_size = sizeof(config);
    config.use_null_device = 1;
    config.block_frames = 128;
    config.log_directory = "/tmp/onebeat-tests/session-abi";
    ob_engine* engine = nullptr;
    REQUIRE(ob_engine_create(&config, &engine) == OB_OK);
    REQUIRE(ob_engine_instance_add(engine, bundle.c_str(), "dev.onebeat.test.synth") == OB_OK);
    REQUIRE(ob_engine_start(engine) == OB_OK);
    std::this_thread::sleep_for(std::chrono::milliseconds(10));
    REQUIRE_MESSAGE(ob_engine_session_save(engine, session.c_str()) == OB_OK,
                    std::string(ob_last_error_message()));
    const auto state_hash_before = fs::file_size(session);
    REQUIRE(ob_engine_instance_remove(engine, 1) == OB_OK);
    fs::remove(bundle);

    REQUIRE(ob_engine_session_load(engine, session.c_str()) == OB_OK);
    ob_instance_info missing{};
    REQUIRE(ob_engine_instance_at(engine, 0, &missing) == OB_OK);
    CHECK((missing.flags & OB_INSTANCE_FLAG_MISSING) != 0U);
    CHECK(std::string(missing.name) == "OneBeat Test Synth");
    REQUIRE(ob_engine_session_save(engine, session.c_str()) == OB_OK);
    CHECK(fs::file_size(session) == state_hash_before);
    ob_engine_destroy(engine);
    fs::remove_all(scratch);
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
