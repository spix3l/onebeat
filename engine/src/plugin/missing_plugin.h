// Silent, state-preserving placeholder for an unavailable instrument (OB-2-10).
#pragma once

#include <string>
#include <vector>

#include "plugin/plugin_instance.h"

namespace onebeat::plugin {

class MissingPlugin final : public PluginInstance {
 public:
  MissingPlugin(PluginHost* host, std::string name, std::vector<uint8_t> state = {})
      : PluginInstance(host), name_(std::move(name)), state_bytes_(std::move(state)) {}
  PluginName name() const override { return PluginName(name_.c_str()); }
  void reset() noexcept OB_NONBLOCKING override {}
  ProcessStatus process(const ProcessBlock& block) noexcept OB_NONBLOCKING override {
    for (uint32_t port = 0; port < block.audio_output_count; ++port)
      block.audio_outputs[port].clear();
    return ProcessStatus::Continue;
  }
  uint32_t paramCount() const override { return 0; }
  bool paramInfo(uint32_t, ParamInfo&) const override { return false; }
  bool paramValue(ParamId, double&) const override { return false; }
  bool paramValueToText(ParamId, double, char*, size_t) const override { return false; }
  bool paramTextToValue(ParamId, const char*, double&) const override { return false; }
  uint32_t audioPortCount(PortDirection direction) const override {
    return direction == PortDirection::Output ? 1U : 0U;
  }
  bool audioPortInfo(PortDirection direction, uint32_t index, AudioPortInfo& out) const override {
    if (direction != PortDirection::Output || index != 0) return false;
    out.id = 0;
    out.name.assign("Silent placeholder");
    out.channel_count = 2;
    out.layout = ChannelLayout::Stereo;
    out.is_main = true;
    return true;
  }
  bool saveState(StateWriter& writer) const override {
    return state_bytes_.empty() || writer.write(state_bytes_.data(), state_bytes_.size());
  }
  bool loadState(StateReader& reader) override {
    state_bytes_.resize(reader.remaining());
    return state_bytes_.empty() ||
           reader.read(state_bytes_.data(), state_bytes_.size()) == state_bytes_.size();
  }

 protected:
  bool onConfigure(const ProcessSetup&) override { return true; }
  bool onActivate() override { return true; }
  void onDeactivate() override {}
  bool onStartProcessing() noexcept OB_NONBLOCKING override { return true; }
  void onStopProcessing() noexcept OB_NONBLOCKING override {}

 private:
  std::string name_;
  std::vector<uint8_t> state_bytes_;
};

}  // namespace onebeat::plugin
