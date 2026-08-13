#include <array>
#include <chrono>
#include <cmath>
#include <csignal>
#include <string>
#include <thread>
#include <vector>

#include "core/audio_buffer.h"
#include "doctest.h"
#include "plugin/clap/clap_plugin_instance.h"
#include "plugin/host.h"
#include "plugin/sandbox/sandboxed_plugin_proxy.h"
#include "plugin/state.h"
#include "test_helpers.h"

using onebeat::core::AudioBufferPool;
using onebeat::plugin::EventList;
using onebeat::plugin::MemoryStateReader;
using onebeat::plugin::MemoryStateWriter;
using onebeat::plugin::NullPluginHost;
using onebeat::plugin::ParamInfo;
using onebeat::plugin::PluginEvent;
using onebeat::plugin::PortDirection;
using onebeat::plugin::ProcessBlock;
using onebeat::plugin::ProcessSetup;
using onebeat::plugin::ProcessStatus;
using onebeat::plugin::ThreadCheck;
using onebeat::plugin::clap::ClapPluginInstance;
using onebeat::plugin::sandbox::SandboxedPluginProxy;

namespace {

std::string healthyClap() {
  return std::string(OB_TEST_PLUGIN_DIR) + "/ob_test_plugin_ok.clap";
}

struct ClapRig {
  NullPluginHost host;
  std::unique_ptr<ClapPluginInstance> plugin;
  AudioBufferPool output;
  std::array<PluginEvent, 32> event_storage{};

  ClapRig() {
    std::string error;
    plugin = ClapPluginInstance::create(&host, healthyClap(), "dev.onebeat.test.synth", error);
    REQUIRE_MESSAGE(plugin != nullptr, error);
    ProcessSetup setup;
    setup.sample_rate = 48000.0;
    setup.max_block_frames = 128;
    REQUIRE(plugin->configure(setup));
    REQUIRE(plugin->activate());
    output.resize(2, 128);
  }

  float render(std::initializer_list<PluginEvent> input) {
    EventList events(event_storage.data(), static_cast<uint32_t>(event_storage.size()));
    for (const PluginEvent& event : input) REQUIRE(events.push(event));
    const auto view = output.view(128);
    view.clear();
    ProcessBlock block;
    block.frames = 128;
    block.audio_outputs = &view;
    block.audio_output_count = 1;
    block.in_events = events.view();
    const ThreadCheck::ScopedAudioThread audio;
    if (plugin->state() == onebeat::plugin::PluginInstance::State::Active) {
      REQUIRE(plugin->startProcessing());
    }
    CHECK(plugin->process(block) == onebeat::plugin::ProcessStatus::Continue);
    float peak = 0.0F;
    for (int frame = 0; frame < 128; ++frame) {
      peak = std::max(peak, std::abs(view.channel(0)[frame]));
    }
    return peak;
  }

  ~ClapRig() {
    if (plugin != nullptr &&
        plugin->state() == onebeat::plugin::PluginInstance::State::Processing) {
      const ThreadCheck::ScopedAudioThread audio;
      plugin->stopProcessing();
    }
    if (plugin != nullptr) plugin->deactivate();
  }
};

struct SandboxRig {
  NullPluginHost host;
  std::unique_ptr<SandboxedPluginProxy> plugin;
  AudioBufferPool output;
  std::array<PluginEvent, 32> event_storage{};

  explicit SandboxRig(const char* fixture = "ob_test_plugin_ok") {
    const std::string bundle = std::string(OB_TEST_PLUGIN_DIR) + "/" + fixture + ".clap";
    plugin = std::make_unique<SandboxedPluginProxy>(&host, bundle, "dev.onebeat.test.synth",
                                                    OB_TEST_HELPER);
    ProcessSetup setup;
    setup.sample_rate = 48000.0;
    setup.max_block_frames = 128;
    REQUIRE_MESSAGE(plugin->configure(setup), plugin->lastError());
    REQUIRE(plugin->activate());
    output.resize(2, 128);
  }

  ProcessStatus render(std::initializer_list<PluginEvent> input = {}) {
    EventList events(event_storage.data(), static_cast<uint32_t>(event_storage.size()));
    for (const PluginEvent& event : input) REQUIRE(events.push(event));
    const auto view = output.view(128);
    view.clear();
    ProcessBlock block;
    block.frames = 128;
    block.audio_outputs = &view;
    block.audio_output_count = 1;
    block.in_events = events.view();
    const ThreadCheck::ScopedAudioThread audio;
    if (plugin->state() == onebeat::plugin::PluginInstance::State::Active) {
      REQUIRE(plugin->startProcessing());
    }
    return plugin->process(block);
  }

  float peak() {
    const auto view = output.view(128);
    float result = 0.0F;
    for (int frame = 0; frame < 128; ++frame) {
      result = std::max(result, std::abs(view.channel(0)[frame]));
    }
    return result;
  }

  ~SandboxRig() {
    if (plugin != nullptr &&
        plugin->state() == onebeat::plugin::PluginInstance::State::Processing) {
      const ThreadCheck::ScopedAudioThread audio;
      plugin->stopProcessing();
    }
    if (plugin != nullptr) plugin->deactivate();
  }
};

}  // namespace

TEST_SUITE("engine") {
  TEST_CASE("The CLAP adapter maps identity, ports, parameters and latency") {
    ClapRig rig;
    CHECK(std::string(rig.plugin->name().text()) == "OneBeat Test Synth");
    CHECK(rig.plugin->audioPortCount(PortDirection::Input) == 0);
    CHECK(rig.plugin->audioPortCount(PortDirection::Output) == 1);
    CHECK(rig.plugin->notePortCount(PortDirection::Input) == 1);
    CHECK(rig.plugin->paramCount() == 1);
    CHECK(rig.plugin->latencyFrames() == 32);
    ParamInfo info;
    REQUIRE(rig.plugin->paramInfo(0, info));
    CHECK(info.id == 17);
    CHECK(std::string(info.name.text()) == "Gain");
  }

  TEST_CASE("CLAP notes and sample-positioned parameters produce audio") {
    ClapRig rig;
    CHECK(rig.render({PluginEvent::noteOn(0, 60, 1.0), PluginEvent::paramValue(0, 17, 0.8)}) >
          0.1F);
    CHECK(rig.render({PluginEvent::noteOff(0, 60)}) == doctest::Approx(0.0F));
  }

  TEST_CASE("CLAP state is an opaque byte-exact round trip") {
    ClapRig rig;
    rig.render({PluginEvent::paramValue(0, 17, 0.73)});
    MemoryStateWriter saved;
    REQUIRE(rig.plugin->saveState(saved));
    REQUIRE(saved.bytes().size() == sizeof(double));

    rig.render({PluginEvent::paramValue(0, 17, 0.12)});
    MemoryStateReader reader(saved.bytes());
    REQUIRE(rig.plugin->loadState(reader));
    double restored = 0.0;
    REQUIRE(rig.plugin->paramValue(17, restored));
    CHECK(restored == doctest::Approx(0.73));
  }

  TEST_CASE("A CLAP instance renders through the out-of-process runtime") {
    SandboxRig rig;
    CHECK(std::string(rig.plugin->name().text()) == "OneBeat Test Synth");
    CHECK(rig.plugin->paramCount() == 1);
    CHECK(rig.plugin->latencyFrames() == 32);
    CHECK(rig.render({PluginEvent::noteOn(0, 60, 1.0), PluginEvent::paramValue(0, 17, 0.8)}) ==
          ProcessStatus::Continue);
    CHECK(rig.peak() > 0.1F);
  }

  TEST_CASE("A plug-in process crash misses its deadline without taking down the engine") {
    SandboxRig rig("ob_test_plugin_process_crash");
    CHECK(rig.render({PluginEvent::noteOn(0, 60, 1.0)}) == ProcessStatus::Error);
    CHECK(rig.peak() == doctest::Approx(0.0F));
    CHECK(rig.render() == ProcessStatus::Error);
    CHECK_FALSE(rig.plugin->healthy());
  }

  TEST_CASE("A plug-in process hang is bounded and silenced") {
    SandboxRig rig("ob_test_plugin_process_hang");
    const auto started = std::chrono::steady_clock::now();
    CHECK(rig.render({PluginEvent::noteOn(0, 60, 1.0)}) == ProcessStatus::Error);
    CHECK(rig.render() == ProcessStatus::Error);
    CHECK_FALSE(rig.plugin->healthy());
#ifdef ONEBEAT_SANITIZER_BUILD
    constexpr auto max_test_deadline = std::chrono::milliseconds(250);
#else
    constexpr auto max_test_deadline = std::chrono::milliseconds(100);
#endif
    CHECK(std::chrono::steady_clock::now() - started < max_test_deadline);
  }

  TEST_CASE("A killed helper restarts from the last opaque state checkpoint") {
    SandboxRig rig;
    CHECK(rig.render({PluginEvent::paramValue(0, 17, 0.73)}) == ProcessStatus::Continue);
    MemoryStateWriter checkpoint;
    REQUIRE(rig.plugin->saveState(checkpoint));
    REQUIRE(::kill(rig.plugin->helperPid(), SIGKILL) == 0);
    std::this_thread::sleep_for(std::chrono::milliseconds(10));
    CHECK(rig.render() == ProcessStatus::Error);
    CHECK(rig.render() == ProcessStatus::Error);
    CHECK_FALSE(rig.plugin->healthy());
    REQUIRE_MESSAGE(rig.plugin->restartHost(), rig.plugin->lastError());
    double restored = 0.0;
    REQUIRE(rig.plugin->paramValue(17, restored));
    CHECK(restored == doctest::Approx(0.73));
  }
}
