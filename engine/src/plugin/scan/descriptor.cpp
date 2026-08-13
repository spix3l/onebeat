#include "plugin/scan/descriptor.h"

namespace onebeat::plugin::scan {

const char* formatName(PluginFormat format) noexcept {
  switch (format) {
    case PluginFormat::Unknown:
      return "unknown";
    case PluginFormat::Builtin:
      return "builtin";
    case PluginFormat::Clap:
      return "CLAP";
    case PluginFormat::Vst3:
      return "VST3";
    case PluginFormat::AudioUnit:
      return "AU";
  }
  return "unknown";
}

const char* outcomeName(ScanOutcome outcome) noexcept {
  switch (outcome) {
    case ScanOutcome::Ok:
      return "ok";
    case ScanOutcome::NotAPlugin:
      return "not-a-plugin";
    case ScanOutcome::Crashed:
      return "crashed";
    case ScanOutcome::TimedOut:
      return "timed-out";
  }
  return "unknown";
}

}  // namespace onebeat::plugin::scan
