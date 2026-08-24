#include "plugin/sandbox/sandboxed_plugin_proxy.h"

#include <utility>

namespace onebeat::plugin::sandbox {

namespace {
constexpr const char* Unsupported =
    "Out-of-process third-party plug-in hosting is not available in the initial Windows build.";
}

SandboxedPluginProxy::SandboxedPluginProxy(PluginHost* host, std::string bundle_path,
                                           std::string plugin_id, std::string helper_path)
    : PluginInstance(host),
      bundle_path_(std::move(bundle_path)),
      plugin_id_(std::move(plugin_id)),
      helper_path_(std::move(helper_path)),
      last_error_(Unsupported) {}

SandboxedPluginProxy::~SandboxedPluginProxy() = default;

PluginName SandboxedPluginProxy::name() const {
  return PluginName(plugin_id_.c_str());
}
bool SandboxedPluginProxy::onConfigure(const ProcessSetup&) {
  return false;
}
bool SandboxedPluginProxy::onActivate() {
  return false;
}
void SandboxedPluginProxy::onDeactivate() {}
bool SandboxedPluginProxy::onStartProcessing() noexcept OB_NONBLOCKING {
  return false;
}
void SandboxedPluginProxy::onStopProcessing() noexcept OB_NONBLOCKING {}
void SandboxedPluginProxy::reset() noexcept OB_NONBLOCKING {}

void SandboxedPluginProxy::silence(const ProcessBlock& block) const noexcept OB_NONBLOCKING {
  for (uint32_t port = 0; port < block.audio_output_count; ++port) {
    block.audio_outputs[port].clear();
  }
}

ProcessStatus SandboxedPluginProxy::process(const ProcessBlock& block) noexcept OB_NONBLOCKING {
  silence(block);
  return ProcessStatus::Error;
}

uint32_t SandboxedPluginProxy::paramCount() const {
  return 0;
}
bool SandboxedPluginProxy::paramInfo(uint32_t, ParamInfo&) const {
  return false;
}
bool SandboxedPluginProxy::paramValue(ParamId, double&) const {
  return false;
}
bool SandboxedPluginProxy::paramValueToText(ParamId, double, char*, size_t) const {
  return false;
}
bool SandboxedPluginProxy::paramTextToValue(ParamId, const char*, double&) const {
  return false;
}
uint32_t SandboxedPluginProxy::audioPortCount(PortDirection) const {
  return 0;
}
bool SandboxedPluginProxy::audioPortInfo(PortDirection, uint32_t, AudioPortInfo&) const {
  return false;
}
uint32_t SandboxedPluginProxy::notePortCount(PortDirection) const {
  return 0;
}
bool SandboxedPluginProxy::notePortInfo(PortDirection, uint32_t, NotePortInfo&) const {
  return false;
}
bool SandboxedPluginProxy::saveState(StateWriter&) const {
  return false;
}
bool SandboxedPluginProxy::loadState(StateReader&) {
  return false;
}
void SandboxedPluginProxy::onMainThread() {}
uint32_t SandboxedPluginProxy::latencyFrames() const {
  return 0;
}
bool SandboxedPluginProxy::restartHost() {
  return false;
}
bool SandboxedPluginProxy::openEditor() {
  return false;
}
void SandboxedPluginProxy::closeEditor() {}

}  // namespace onebeat::plugin::sandbox
