// PluginInstance proxy backed by onebeat-plugin-host (OB-2-05).
#pragma once

#include <mach/mach.h>
#include <sys/types.h>

#include <atomic>
#include <string>
#include <vector>

#include "plugin/plugin_instance.h"
#include "plugin/sandbox/runtime_protocol.h"

namespace onebeat::plugin::sandbox {

class SandboxedPluginProxy final : public PluginInstance {
 public:
  SandboxedPluginProxy(PluginHost* host, std::string bundle_path, std::string plugin_id,
                       std::string helper_path = {});
  ~SandboxedPluginProxy() override;

  SandboxedPluginProxy(const SandboxedPluginProxy&) = delete;
  SandboxedPluginProxy& operator=(const SandboxedPluginProxy&) = delete;

  PluginName name() const override;
  void reset() noexcept OB_NONBLOCKING override;
  ProcessStatus process(const ProcessBlock& block) noexcept OB_NONBLOCKING override;

  uint32_t paramCount() const override;
  bool paramInfo(uint32_t index, ParamInfo& out) const override;
  bool paramValue(ParamId param, double& out) const override;
  bool paramValueToText(ParamId param, double value, char* out, size_t out_size) const override;
  bool paramTextToValue(ParamId param, const char* text, double& out) const override;

  uint32_t audioPortCount(PortDirection direction) const override;
  bool audioPortInfo(PortDirection direction, uint32_t index, AudioPortInfo& out) const override;
  uint32_t notePortCount(PortDirection direction) const override;
  bool notePortInfo(PortDirection direction, uint32_t index, NotePortInfo& out) const override;

  bool saveState(StateWriter& writer) const override;
  bool loadState(StateReader& reader) override;
  void onMainThread() override;
  uint32_t latencyFrames() const override;

  bool healthy() const noexcept { return !dead_.load(std::memory_order_acquire); }
  // Main-thread recovery. The helper is replaced and the most recently saved
  // or loaded opaque state checkpoint is restored before audio resumes.
  bool restartHost();
  bool hasEditor() const noexcept { return shared_ != nullptr && shared_->has_gui != 0; }
  bool openEditor();
  void closeEditor();
  pid_t helperPid() const noexcept { return child_pid_; }
  const std::string& lastError() const noexcept { return last_error_; }

 private:
  bool onConfigure(const ProcessSetup& setup) override;
  bool onActivate() override;
  void onDeactivate() override;
  bool onStartProcessing() noexcept OB_NONBLOCKING override;
  void onStopProcessing() noexcept OB_NONBLOCKING override;

  bool launch(const ProcessSetup& setup);
  void shutdown();
  bool control(const ControlRequest& request, ControlResponse& response,
               const uint8_t* payload = nullptr) const;
  void silence(const ProcessBlock& block) const noexcept OB_NONBLOCKING;

  std::string bundle_path_;
  std::string plugin_id_;
  std::string helper_path_;
  std::string shm_name_;
  mutable std::string last_error_;

  RuntimeShared* shared_ = nullptr;
  int control_fd_ = -1;
  mutable pid_t child_pid_ = -1;
  semaphore_t to_helper_ = MACH_PORT_NULL;
  semaphore_t to_host_ = MACH_PORT_NULL;
  uint32_t sequence_ = 0;
  uint32_t in_flight_ = 0;
  uint32_t consecutive_misses_ = 0;
  std::atomic<bool> dead_{false};
  mutable std::vector<uint8_t> checkpoint_;
};

}  // namespace onebeat::plugin::sandbox
