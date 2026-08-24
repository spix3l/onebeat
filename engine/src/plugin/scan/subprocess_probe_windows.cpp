#include "plugin/scan/subprocess_probe.h"

#include <cstdlib>
#include <filesystem>
#include <utility>

namespace onebeat::plugin::scan {

std::string SubprocessProbe::discoverHelperPath() {
  const char* override_path = std::getenv("OB_PLUGIN_HOST");
  return override_path != nullptr ? std::string(override_path) : std::string();
}

SubprocessProbe::SubprocessProbe(SubprocessProbeOptions options, core::Diagnostics* diagnostics)
    : options_(std::move(options)), diagnostics_(diagnostics) {
  if (options_.helper_path.empty()) options_.helper_path = discoverHelperPath();
}

bool SubprocessProbe::available() const {
  std::error_code error;
  return !options_.helper_path.empty() && std::filesystem::exists(options_.helper_path, error);
}

void SubprocessProbe::probe(const BundleRef& bundle, std::vector<PluginDescriptor>& out) {
  BundleNameProbe fallback;
  fallback.probe(bundle, out);
}

}  // namespace onebeat::plugin::scan
