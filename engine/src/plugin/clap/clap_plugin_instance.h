// CLAP -> OneBeat model adapter (OB-2-07).
#pragma once

#include <array>
#include <cstdint>
#include <memory>
#include <string>
#include <vector>

#include <clap/clap.h>

#include "plugin/plugin_instance.h"

namespace onebeat::plugin::clap {

class ClapPluginInstance final : public PluginInstance {
 public:
  static std::unique_ptr<ClapPluginInstance> create(PluginHost* host,
                                                    const std::string& bundle_path,
                                                    const std::string& plugin_id,
                                                    std::string& error);
  ~ClapPluginInstance() override;

  ClapPluginInstance(const ClapPluginInstance&) = delete;
  ClapPluginInstance& operator=(const ClapPluginInstance&) = delete;

  PluginName name() const override;
  void reset() noexcept OB_NONBLOCKING override;
  ProcessStatus process(const ProcessBlock& block) noexcept OB_NONBLOCKING override;

  uint32_t paramCount() const override;
  bool paramInfo(uint32_t index, ParamInfo& out) const override;
  bool paramValue(ParamId param, double& out) const override;
  bool paramValueToText(ParamId param, double value, char* out, size_t out_size) const override;
  bool paramTextToValue(ParamId param, const char* text, double& out) const override;
  void paramsFlush(const EventListView& in, EventList* out) override;

  uint32_t audioPortCount(PortDirection direction) const override;
  bool audioPortInfo(PortDirection direction, uint32_t index, AudioPortInfo& out) const override;
  uint32_t notePortCount(PortDirection direction) const override;
  bool notePortInfo(PortDirection direction, uint32_t index, NotePortInfo& out) const override;

  bool saveState(StateWriter& writer) const override;
  bool loadState(StateReader& reader) override;
  void onMainThread() override;
  uint32_t latencyFrames() const override;
  uint32_t tailFrames() const noexcept OB_NONBLOCKING override;

  const clap_plugin_t* rawPlugin() const noexcept { return plugin_; }
  const clap_plugin_gui_t* guiExtension() const noexcept { return gui_; }
  bool showEditor();
  void hideEditor();
  void pumpEditorEvents();
  PluginHost* callbackHost() const noexcept { return host(); }
  uint32_t inputEventCount() const noexcept { return input_header_count_; }
  const clap_event_header_t* inputEventAt(uint32_t index) const noexcept {
    return index < input_header_count_ ? input_headers_[index] : nullptr;
  }
  bool pushOutputEvent(const clap_event_header_t* event) noexcept OB_NONBLOCKING {
    return collectOutput(event);
  }
  static ClapPluginInstance& fromHost(const clap_host_t* host) noexcept;

 private:
  union ClapEventStorage {
    clap_event_header_t header;
    clap_event_note_t note;
    clap_event_note_expression_t expression;
    clap_event_param_value_t param_value;
    clap_event_param_mod_t param_mod;
    clap_event_param_gesture_t gesture;
    clap_event_midi_t midi;
    clap_event_midi_sysex_t sysex;
    clap_event_midi2_t midi2;
  };

  ClapPluginInstance(PluginHost* host, std::string bundle_path, void* library,
                     const clap_plugin_entry_t* entry, const clap_plugin_t* plugin);

 protected:
  bool onConfigure(const ProcessSetup& setup) override;
  bool onActivate() override;
  void onDeactivate() override;
  bool onStartProcessing() noexcept OB_NONBLOCKING override;
  void onStopProcessing() noexcept OB_NONBLOCKING override;

 private:
  void cacheExtensions();
  const clap_event_header_t* convertInput(const PluginEvent& event,
                                          ClapEventStorage& storage) noexcept OB_NONBLOCKING;
  bool collectOutput(const clap_event_header_t* event) noexcept OB_NONBLOCKING;
  void prepareInputEvents(const EventListView& input) noexcept OB_NONBLOCKING;
  void prepareAudio(const ProcessBlock& block) noexcept OB_NONBLOCKING;
  std::string bundle_path_;
  void* library_ = nullptr;
  const clap_plugin_entry_t* entry_ = nullptr;
  const clap_plugin_t* plugin_ = nullptr;

  const clap_plugin_params_t* params_ = nullptr;
  const clap_plugin_state_t* state_ = nullptr;
  const clap_plugin_audio_ports_t* audio_ports_ = nullptr;
  const clap_plugin_note_ports_t* note_ports_ = nullptr;
  const clap_plugin_latency_t* latency_ = nullptr;
  const clap_plugin_tail_t* tail_ = nullptr;
  const clap_plugin_gui_t* gui_ = nullptr;
  void* editor_context_ = nullptr;

  clap_host_t clap_host_{};
  clap_input_events_t input_events_{};
  clap_output_events_t output_events_{};
  EventList* current_output_ = nullptr;

  std::vector<ClapEventStorage> converted_inputs_;
  std::vector<const clap_event_header_t*> input_headers_;
  uint32_t input_header_count_ = 0;
  std::vector<clap_audio_buffer_t> clap_inputs_;
  std::vector<clap_audio_buffer_t> clap_outputs_;
  std::vector<std::array<float*, core::MaxChannels>> input_channels_;
  std::vector<std::array<float*, core::MaxChannels>> output_channels_;
};

}  // namespace onebeat::plugin::clap
