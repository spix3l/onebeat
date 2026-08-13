#pragma once

#include <memory>
#include <string>

#include "core/engine.h"
#include "testing/offline_driver.h"

namespace onebeat::tests {

// An engine on the on-demand null backend: deterministic, hardware-free, and
// driven exactly one block at a time by the offline driver.
inline std::unique_ptr<core::Engine> makeOfflineEngine(double sample_rate = 48000.0,
                                                       int block_frames = 128) {
  core::EngineConfig config;
  config.sample_rate = sample_rate;
  config.block_frames = block_frames;
  config.use_null_device = true;
  config.free_running_null_device = false;
  config.log_directory = "/tmp/onebeat-tests/logs";

  auto engine = std::make_unique<core::Engine>(config);
  std::string error;
  if (!engine->initialise(error)) {
    return nullptr;
  }
  return engine;
}

inline ob_command command(ob_command_type type, int64_t i64 = 0, double f64_a = 0.0,
                          double f64_b = 0.0) {
  ob_command value{};
  value.type = static_cast<uint32_t>(type);
  value.i64_a = i64;
  value.f64_a = f64_a;
  value.f64_b = f64_b;
  return value;
}

}  // namespace onebeat::tests
