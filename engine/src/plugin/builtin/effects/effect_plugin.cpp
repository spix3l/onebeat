#include "plugin/builtin/effects/effect_plugin.h"

#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>

namespace onebeat::plugin::builtin {
namespace {

// Frozen, like the sampler's. A reader that meets an unknown version reports a
// load failure rather than guessing (FR-PLG-10 applies to our own plug-ins).
constexpr uint32_t StateMagic = 0x4F424658U;  // 'OBFX'
constexpr uint32_t StateVersion = 1;

ParamInfo makeBypassInfo() noexcept {
  ParamInfo value;
  value.id = EffectParamBypass;
  value.name.assign("Bypass");
  value.module.assign("/");
  value.min_value = 0.0;
  value.max_value = 1.0;
  value.default_value = 0.0;
  // Stepped and flagged as *the* bypass: the host binds its own control here,
  // and automation drives the same parameter that button does.
  value.flags = ParamFlagIsAutomatable | ParamFlagIsStepped | ParamFlagIsBypass;
  return value;
}

const ParamInfo BypassParam = makeBypassInfo();

}  // namespace

void EffectPlugin::declareParams(const ParamInfo* params, size_t count) {
  params_[0] = BypassParam;
  values_[0] = ModulatedValue{BypassParam.default_value, 0.0};
  param_count_ = 1;
  for (size_t i = 0; i < count && param_count_ < MaxEffectParams; ++i) {
    params_[param_count_] = params[i];
    values_[param_count_] = ModulatedValue{params[i].default_value, 0.0};
    ++param_count_;
  }
}

size_t EffectPlugin::indexOf(ParamId param) const noexcept OB_NONBLOCKING {
  for (size_t i = 0; i < param_count_; ++i) {
    if (params_[i].id == param) return i;
  }
  return MaxEffectParams;
}

double EffectPlugin::value(ParamId param) const noexcept OB_NONBLOCKING {
  const size_t index = indexOf(param);
  if (index >= param_count_) return 0.0;
  return values_[index].effective(params_[index]);
}

bool EffectPlugin::paramInfo(uint32_t index, ParamInfo& out) const {
  OB_ASSERT_MAIN_THREAD();
  if (index >= param_count_) return false;
  out = params_[index];
  return true;
}

bool EffectPlugin::paramValue(ParamId param, double& out) const {
  OB_ASSERT_MAIN_THREAD();
  const size_t index = indexOf(param);
  if (index >= param_count_) return false;
  // The *base*: what the user set. Never the modulated value, which is a
  // per-block offset that must not be written back (D5).
  out = values_[index].base;
  return true;
}

bool EffectPlugin::paramValueToText(ParamId param, double value_in, char* out,
                                    size_t out_size) const {
  OB_ASSERT_MAIN_THREAD();
  if (out == nullptr || out_size == 0) return false;
  const size_t index = indexOf(param);
  if (index >= param_count_) return false;
  const ParamInfo& info = params_[index];
  if (info.has(ParamFlagIsStepped) && info.min_value == 0.0 && info.max_value == 1.0) {
    std::snprintf(out, out_size, "%s", value_in >= 0.5 ? "On" : "Off");
    return true;
  }
  // A percentage wherever the range says so, which covers mixes, feedbacks and
  // sizes — the majority of what an effect exposes.
  if (info.min_value == 0.0 && info.max_value == 1.0) {
    std::snprintf(out, out_size, "%.0f%%", value_in * 100.0);
    return true;
  }
  std::snprintf(out, out_size, "%.2f", value_in);
  return true;
}

bool EffectPlugin::paramTextToValue(ParamId param, const char* text, double& out) const {
  OB_ASSERT_MAIN_THREAD();
  if (text == nullptr) return false;
  const size_t index = indexOf(param);
  if (index >= param_count_) return false;
  const ParamInfo& info = params_[index];
  if (info.has(ParamFlagIsStepped) && info.min_value == 0.0 && info.max_value == 1.0) {
    out = (std::strcmp(text, "On") == 0 || std::strcmp(text, "on") == 0) ? 1.0 : 0.0;
    return true;
  }
  char* end = nullptr;
  const double parsed = std::strtod(text, &end);
  if (end == text) return false;
  // "50%" and "0.5" mean the same thing on a 0..1 parameter, and a user will
  // type whichever the readout showed them.
  const bool percent = end != nullptr && *end == '%';
  const double scaled = percent ? parsed / 100.0 : parsed;
  out = info.clamp(scaled);
  return true;
}

void EffectPlugin::applyEvent(const PluginEvent& event) noexcept OB_NONBLOCKING {
  if (event.kind() != EventType::ParamValue && event.kind() != EventType::ParamModulation) return;
  const size_t index = indexOf(event.id);
  if (index >= param_count_) return;
  if (event.kind() == EventType::ParamValue) {
    values_[index].base = params_[index].clamp(event.value());
  } else {
    // Never touches `base`. This is the whole point of the distinction.
    values_[index].modulation = event.value();
  }
}

void EffectPlugin::paramsFlush(const EventListView& in, EventList* /*out*/) {
  // Called while the transport is stopped. Without this, a knob turned between
  // takes does nothing until playback resumes.
  for (uint32_t i = 0; i < in.size(); ++i) applyEvent(in[i]);
}

void EffectPlugin::reset() noexcept OB_NONBLOCKING {
  OB_ASSERT_AUDIO_THREAD();
  for (size_t i = 0; i < param_count_; ++i) values_[i].modulation = 0.0;
  clearTail();
}

ProcessStatus EffectPlugin::process(const ProcessBlock& block) noexcept OB_NONBLOCKING {
  OB_ASSERT_AUDIO_THREAD();
  if (block.audio_output_count == 0) return ProcessStatus::Error;
  const core::AudioBufferView& io = block.output(MainPort);
  const EventListView& events = block.in_events;
  const uint32_t count = events.size();

  // Split the block at every event frame, exactly as the sampler does, so an
  // automated parameter takes effect on the sample it was written for rather
  // than at the next block boundary.
  uint32_t consumed = 0;
  uint32_t index = 0;
  while (consumed < block.frames) {
    uint32_t next = block.frames;
    if (index < count && events[index].time < block.frames) {
      next = events[index].time > consumed ? events[index].time : consumed;
    }
    if (next > consumed) {
      if (!bypassed()) {
        processAudio(io, static_cast<int>(consumed), static_cast<int>(next - consumed));
      }
      consumed = next;
    }
    while (index < count && events[index].time <= consumed && events[index].time < block.frames) {
      applyEvent(events[index]);
      ++index;
    }
  }
  // Always Continue: an effect with a tail must keep being called after its
  // input goes quiet, and the ones here all have one.
  return ProcessStatus::Continue;
}

uint32_t EffectPlugin::audioPortCount(PortDirection /*direction*/) const {
  return 1U;  // one stereo pair, in and out
}

bool EffectPlugin::audioPortInfo(PortDirection direction, uint32_t index,
                                 AudioPortInfo& out) const {
  if (index != 0) return false;
  out = AudioPortInfo{};
  out.id = MainPort;
  out.name.assign(direction == PortDirection::Input ? "Input" : "Output");
  out.channel_count = 2;
  out.layout = ChannelLayout::Stereo;
  out.is_main = true;
  // The mixer hands one bus buffer in and takes the same one out; saying so is
  // what lets it do that instead of copying every effect's output.
  out.supports_in_place = true;
  out.in_place_pair = MainPort;
  return true;
}

bool EffectPlugin::saveState(StateWriter& writer) const {
  OB_ASSERT_MAIN_THREAD();
  const uint32_t magic = StateMagic;
  const uint32_t version = StateVersion;
  const auto count = static_cast<uint32_t>(param_count_);
  if (!writer.write(&magic, sizeof(magic))) return false;
  if (!writer.write(&version, sizeof(version))) return false;
  if (!writer.write(&count, sizeof(count))) return false;
  for (size_t i = 0; i < param_count_; ++i) {
    // ID alongside value: a future version that adds a parameter in the middle
    // must still load this file, and a bare array of values could not.
    const uint32_t id = params_[i].id;
    const double base = values_[i].base;
    if (!writer.write(&id, sizeof(id))) return false;
    if (!writer.write(&base, sizeof(base))) return false;
  }
  return true;
}

bool EffectPlugin::loadState(StateReader& reader) {
  OB_ASSERT_MAIN_THREAD();
  uint32_t magic = 0;
  uint32_t version = 0;
  uint32_t count = 0;
  if (reader.read(&magic, sizeof(magic)) != sizeof(magic)) return false;
  if (reader.read(&version, sizeof(version)) != sizeof(version)) return false;
  if (reader.read(&count, sizeof(count)) != sizeof(count)) return false;
  if (magic != StateMagic || version != StateVersion) return false;
  for (uint32_t i = 0; i < count; ++i) {
    uint32_t id = 0;
    double base = 0.0;
    if (reader.read(&id, sizeof(id)) != sizeof(id)) return false;
    if (reader.read(&base, sizeof(base)) != sizeof(base)) return false;
    const size_t index = indexOf(id);
    // A parameter this build no longer has is skipped, not an error: dropping
    // one must not make every older project unloadable.
    if (index < param_count_) values_[index].base = params_[index].clamp(base);
  }
  return true;
}

}  // namespace onebeat::plugin::builtin
