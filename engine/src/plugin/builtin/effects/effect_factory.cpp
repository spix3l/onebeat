#include "plugin/builtin/effects/effect_factory.h"

#include <cstring>

#include "plugin/builtin/effects/delay_plugin.h"
#include "plugin/builtin/effects/halftime_plugin.h"
#include "plugin/builtin/effects/reverb_plugin.h"
#include "plugin/builtin/effects/reverse_plugin.h"

namespace onebeat::plugin::builtin {
namespace {

const EffectDescriptor Effects[] = {
    {ReverbPlugin::Identifier, "OneBeat Reverb",
     "Room, hall and plate colours from a comb-and-allpass network."},
    {DelayPlugin::Identifier, "OneBeat Delay", "Stereo feedback delay with damping and ping-pong."},
    {HalftimePlugin::Identifier, "OneBeat Halftime",
     "Slows the signal and resyncs to the beat, with or without the pitch."},
    {ReversePlugin::Identifier, "OneBeat Reverse",
     "Captures a window of audio and plays it back backwards."},
};

constexpr size_t EffectCount = sizeof(Effects) / sizeof(Effects[0]);

}  // namespace

const EffectDescriptor* builtinEffects() noexcept {
  return Effects;
}

size_t builtinEffectCount() noexcept {
  return EffectCount;
}

const EffectDescriptor* findBuiltinEffect(const char* id) noexcept {
  if (id == nullptr) return nullptr;
  for (const EffectDescriptor& entry : Effects) {
    if (std::strcmp(entry.id, id) == 0) return &entry;
  }
  return nullptr;
}

std::unique_ptr<EffectPlugin> createBuiltinEffect(const char* id, PluginHost* host) {
  if (id == nullptr) return nullptr;
  if (std::strcmp(id, ReverbPlugin::Identifier) == 0) {
    return std::make_unique<ReverbPlugin>(host);
  }
  if (std::strcmp(id, DelayPlugin::Identifier) == 0) {
    return std::make_unique<DelayPlugin>(host);
  }
  if (std::strcmp(id, HalftimePlugin::Identifier) == 0) {
    return std::make_unique<HalftimePlugin>(host);
  }
  if (std::strcmp(id, ReversePlugin::Identifier) == 0) {
    return std::make_unique<ReversePlugin>(host);
  }
  return nullptr;
}

}  // namespace onebeat::plugin::builtin
