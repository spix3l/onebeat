// onebeat_devtool — drives the engine from the terminal, with no Flutter in the
// picture. It exists so that engine work can be verified (and demonstrated for
// the stage exit checklist) without the app, and so that a contributor can hear
// sound one minute after cloning.
//
//   onebeat_devtool devices                 list output devices
//   onebeat_devtool play [seconds] [bpm]    play a 16-step pattern on the default device
//   onebeat_devtool formats                 open every rate/buffer combination and
//                                           report the granted format and latency
//   onebeat_devtool render <out.wav>        offline render, no hardware needed
#include <algorithm>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <string>
#include <thread>
#include <vector>

#include "abi/onebeat_abi.h"
#include "core/engine.h"
#include "testing/offline_driver.h"

namespace {

using onebeat::core::Engine;
using onebeat::core::EngineConfig;

ob_command command(ob_command_type type, int64_t i64 = 0, double f64_a = 0.0, double f64_b = 0.0) {
  ob_command value{};
  value.type = static_cast<uint32_t>(type);
  value.i64_a = i64;
  value.f64_a = f64_a;
  value.f64_b = f64_b;
  return value;
}

void applyDemoPattern(Engine& engine, double tempo_bpm) {
  const uint8_t steps[16] = {127, 0, 60, 0, 100, 0, 60, 40, 127, 0, 60, 0, 100, 30, 60, 0};
  const double step_beats = 0.25;
  onebeat::core::ScheduleBuilder builder;
  const auto step_frames =
      static_cast<int64_t>((engine.config().sample_rate * 60.0 / tempo_bpm) * step_beats);
  for (int index = 0; index < 16; ++index) {
    if (steps[index] == 0) {
      continue;
    }
    builder.addNote(onebeat::core::DefaultInstrument, 60, static_cast<float>(steps[index]) / 127.0F,
                    index * step_frames, step_frames);
  }
  builder.setLengthFrames(16 * step_frames);
  engine.publishSchedule(builder.build(engine.config().sample_rate, 1));
  engine.postCommand(command(OB_CMD_SET_TEMPO, 0, tempo_bpm));
  engine.postCommand(command(OB_CMD_SET_LOOP, 1, 0.0, 4.0));
}

int listDevices() {
  EngineConfig config;
  Engine engine(config);
  std::string error;
  if (!engine.initialise(error)) {
    std::printf("Could not open the audio system: %s\n", error.c_str());
    return 1;
  }
  for (const auto& device : engine.device()->enumerateOutputDevices()) {
    std::printf("%s%-40s %d ch  rates:", device.is_default_output ? "* " : "  ",
                device.name.c_str(), device.max_output_channels);
    for (const double rate : device.sample_rates) {
      std::printf(" %.0f", rate);
    }
    std::printf("\n");
  }
  return 0;
}

int play(double seconds, double tempo_bpm) {
  EngineConfig config;
  config.sample_rate = 48000.0;
  config.block_frames = 128;

  Engine engine(config);
  std::string error;
  if (!engine.initialise(error)) {
    std::printf("Could not start the engine: %s\n", error.c_str());
    return 1;
  }
  applyDemoPattern(engine, tempo_bpm);
  if (!engine.start(error)) {
    std::printf("Could not start playback: %s\n", error.c_str());
    return 1;
  }
  engine.postCommand(command(OB_CMD_TRANSPORT_PLAY));

  std::printf("Playing on '%s' at %.0f Hz / %d frames (round-trip latency %.2f ms)\n",
              engine.deviceName().c_str(), engine.config().sample_rate,
              engine.config().block_frames,
              1000.0 * engine.device()->roundTripLatencyFrames() / engine.config().sample_rate);

  const auto until = std::chrono::steady_clock::now() + std::chrono::duration<double>(seconds);
  ob_snapshot snapshot{};
  while (std::chrono::steady_clock::now() < until) {
    std::this_thread::sleep_for(std::chrono::milliseconds(250));
    engine.readSnapshot(snapshot);
    std::printf("\r%3d.%d.%03d  %6.1f BPM  peak %5.2f  voices %2d  cpu %4.1f%%  xruns %llu   ",
                snapshot.bar, snapshot.beat, snapshot.tick, snapshot.tempo_bpm,
                static_cast<double>(snapshot.peak_left), snapshot.active_voices,
                static_cast<double>(snapshot.cpu_load) * 100.0,
                static_cast<unsigned long long>(snapshot.xrun_count));
    std::fflush(stdout);
  }
  std::printf("\n");

  engine.readSnapshot(snapshot);
  std::printf("Done. callbacks=%llu xruns=%llu dropped_log_records=%llu\n",
              static_cast<unsigned long long>(snapshot.callback_count),
              static_cast<unsigned long long>(snapshot.xrun_count),
              static_cast<unsigned long long>(snapshot.dropped_log_records));
  std::printf("Session log: %s\n", engine.diagnostics().sessionLogPath().c_str());
  engine.stop();
  return snapshot.xrun_count == 0 ? 0 : 2;
}

// OB-1-05 acceptance: a tone plays at every supported rate and buffer size, and
// the granted format and latency are reported for each.
int formats() {
  int failures = 0;
  for (const double rate : {44100.0, 48000.0, 88200.0, 96000.0}) {
    for (const int block : {64, 128, 256, 512, 1024, 2048}) {
      EngineConfig config;
      config.sample_rate = rate;
      config.block_frames = block;
      Engine engine(config);
      std::string error;
      if (!engine.initialise(error)) {
        std::printf("%7.0f Hz / %4d frames  FAILED: %s\n", rate, block, error.c_str());
        ++failures;
        continue;
      }
      applyDemoPattern(engine, 120.0);
      if (!engine.start(error)) {
        std::printf("%7.0f Hz / %4d frames  FAILED to start: %s\n", rate, block, error.c_str());
        ++failures;
        continue;
      }
      engine.postCommand(command(OB_CMD_TRANSPORT_PLAY));

      // Peak is instantaneous, so sample it across the whole run rather than
      // once at the end: a sparse pattern is silent most of the time.
      ob_snapshot snapshot{};
      float loudest = 0.0F;
      for (int tick = 0; tick < 60; ++tick) {
        std::this_thread::sleep_for(std::chrono::milliseconds(20));
        engine.readSnapshot(snapshot);
        loudest = std::max(loudest, snapshot.peak_left);
      }
      snapshot.peak_left = loudest;
      engine.stop();
      std::printf(
          "%7.0f Hz / %4d frames  granted %7.0f Hz / %4d  latency %6.2f ms  peak %4.2f  xruns "
          "%llu\n",
          rate, block, snapshot.sample_rate, snapshot.block_frames,
          1000.0 * snapshot.latency_frames_roundtrip / snapshot.sample_rate,
          static_cast<double>(snapshot.peak_left),
          static_cast<unsigned long long>(snapshot.xrun_count));
      if (loudest <= 0.0F) {
        ++failures;
      }
    }
  }
  return failures == 0 ? 0 : 1;
}

int render(const std::string& path) {
  EngineConfig config;
  config.use_null_device = true;
  config.free_running_null_device = false;
  config.block_frames = 128;

  Engine engine(config);
  std::string error;
  if (!engine.initialise(error)) {
    std::printf("Could not create the engine: %s\n", error.c_str());
    return 1;
  }
  applyDemoPattern(engine, 120.0);
  engine.postCommand(command(OB_CMD_TRANSPORT_PLAY));
  const auto result = onebeat::testing::renderOffline(engine, 48000 * 4, 128);
  if (!onebeat::testing::writeWav(result, path)) {
    std::printf("Could not write %s\n", path.c_str());
    return 1;
  }
  std::printf("Wrote %s (%zu frames, peak %.3f, rms %.3f)\n", path.c_str(), result.frames(),
              static_cast<double>(result.peak()), static_cast<double>(result.rms()));
  return 0;
}

}  // namespace

int main(int argc, char** argv) {
  const std::string mode = argc > 1 ? argv[1] : "play";
  if (mode == "devices") {
    return listDevices();
  }
  if (mode == "formats") {
    return formats();
  }
  if (mode == "render") {
    return render(argc > 2 ? argv[2] : "onebeat-demo.wav");
  }
  if (mode == "play") {
    const double seconds = argc > 2 ? std::atof(argv[2]) : 8.0;
    const double tempo = argc > 3 ? std::atof(argv[3]) : 120.0;
    return play(seconds, tempo);
  }
  std::printf("usage: onebeat_devtool [devices|play [seconds] [bpm]|formats|render <out.wav>]\n");
  return 64;
}
