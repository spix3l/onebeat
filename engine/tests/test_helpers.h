#pragma once

#include <cstdlib>
#include <memory>
#include <optional>
#include <string>

#include "core/engine.h"
#include "testing/offline_driver.h"

namespace onebeat::tests {

// Points the plug-in probe at a helper — or at nothing — for one test case, and
// puts the environment back afterwards.
//
// `OB_PLUGIN_HOST` is process-wide state that `setenv` never gives back. A
// hosting test that set it once therefore changed what every later test in the
// same binary saw: `SubprocessProbe::discoverHelperPath` started answering, so
// a scan test that expected no probe at all got its fake bundle really opened
// and reported as NotAPlugin. That failure appears only when the whole binary
// runs in one process, which is not how CI runs it — ctest gives each suite its
// own process, so it went unseen there and reproduced only locally.
//
// A test that cares about the probe now says which world it is in.
class ScopedPluginHost {
 public:
  // `path` == nullptr means "no helper is discoverable".
  explicit ScopedPluginHost(const char* path) {
    const char* current = std::getenv(EnvName);
    if (current != nullptr) previous_ = std::string(current);
    if (path != nullptr && path[0] != '\0') {
      ::setenv(EnvName, path, 1);
    } else {
      ::unsetenv(EnvName);
    }
  }

  ScopedPluginHost(const ScopedPluginHost&) = delete;
  ScopedPluginHost& operator=(const ScopedPluginHost&) = delete;
  ScopedPluginHost(ScopedPluginHost&&) = delete;
  ScopedPluginHost& operator=(ScopedPluginHost&&) = delete;

  ~ScopedPluginHost() {
    if (previous_.has_value()) {
      ::setenv(EnvName, previous_->c_str(), 1);
    } else {
      ::unsetenv(EnvName);
    }
  }

 private:
  static constexpr const char* EnvName = "OB_PLUGIN_HOST";
  std::optional<std::string> previous_;
};

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
