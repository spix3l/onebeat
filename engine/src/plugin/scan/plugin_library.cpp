#include "plugin/scan/plugin_library.h"

#include <algorithm>
#include <cstring>
#include <filesystem>

// `strcasecmp` is POSIX; MSVC spells the same function `_stricmp` and declares
// it in <string.h> rather than <strings.h>.
#if defined(_WIN32)
#include <string.h>
#define ONEBEAT_STRCASECMP _stricmp
#else
#include <strings.h>
#define ONEBEAT_STRCASECMP strcasecmp
#endif

#include "core/diagnostics.h"
#include "plugin/scan/subprocess_probe.h"

namespace onebeat::plugin::scan {
namespace {

// Case-insensitive, so "Zebra" does not sort above "arturia". The comparison
// falls back to the path when two plugins share a display name, which happens
// whenever a vendor ships the same plugin in two formats — without the
// tie-break the order would depend on filesystem enumeration order and the list
// would shuffle between launches.
bool byDisplayName(const PluginDescriptor& a, const PluginDescriptor& b) {
  const int name = ONEBEAT_STRCASECMP(a.name.text(), b.name.text());
  if (name != 0) {
    return name < 0;
  }
  const int path = std::strcmp(a.path.text(), b.path.text());
  if (path != 0) {
    return path < 0;
  }
  return a.index_in_bundle < b.index_in_bundle;
}

}  // namespace

namespace {

// The probe a shipped build uses, with the fallback that keeps a broken
// installation working rather than silent.
std::unique_ptr<ScanProbe> defaultProbe(const std::string& cache_path,
                                        core::Diagnostics* diagnostics) {
  SubprocessProbeOptions options;
  options.crash_log_directory = std::filesystem::path(cache_path).parent_path().string();
  auto probe = std::make_unique<SubprocessProbe>(options, diagnostics);
  if (probe->available()) {
    return probe;
  }
  // No helper binary: a build that did not produce one, or a bundle assembled
  // without it. Falling back to `BundleNameProbe` costs the crash containment
  // this ticket is about, but it cannot itself crash — it never opens a
  // bundle — so the app still starts and still lists the user's plugins. The
  // log line is how anyone finds out; it is a build defect, not a user error.
  if (diagnostics != nullptr) {
    diagnostics->logf(core::LogLevel::Warn, "plugin-scan",
                      "no %s helper found; scanning without crash containment",
                      "onebeat-plugin-host");
  }
  return std::make_unique<BundleNameProbe>();
}

}  // namespace

PluginLibrary::PluginLibrary(std::string cache_path, core::Diagnostics* diagnostics,
                             std::unique_ptr<ScanProbe> probe)
    : cache_(cache_path.empty() ? PluginCache::defaultPath() : std::move(cache_path)),
      probe_(probe != nullptr ? std::move(probe) : defaultProbe(cache_.path(), diagnostics)),
      diagnostics_(diagnostics) {
  scanner_ = std::make_unique<PluginScanner>(cache_, *probe_, diagnostics);
}

// Out of line because the members it destroys are only complete types here.
PluginLibrary::~PluginLibrary() = default;

CacheLoadResult PluginLibrary::loadCache() {
  const CacheLoadResult result = cache_.load();
  rebuildListFromCache();
  if (diagnostics_ != nullptr) {
    diagnostics_->logf(core::LogLevel::Info, "plugin-scan", "cache %s: %zu plugins from %s",
                       cacheLoadResultName(result), cache_.size(), cache_.path().c_str());
  }
  return result;
}

void PluginLibrary::setSearchPaths(std::vector<std::string> directories) {
  scanner_->setSearchPaths(std::move(directories));
}

bool PluginLibrary::startScan() {
  if (!scanner_->start()) {
    return false;
  }
  committed_ = false;
  // The list is *not* cleared here. Clearing it would empty the browser for the
  // duration of the scan, which is the exact failure FR-PLG-05 is about: the
  // cached list stays on screen and is replaced row by row as the scan settles.
  return true;
}

bool PluginLibrary::retryPlugin(const std::string& bundle_path) {
  if (!scanner_->startRetry(bundle_path)) {
    return false;
  }
  committed_ = false;
  return true;
}

void PluginLibrary::cancelScan() noexcept {
  scanner_->cancel();
}

bool PluginLibrary::scanning() const noexcept {
  return scanner_->running();
}

void PluginLibrary::pump() {
  std::vector<PluginDescriptor> fresh;
  if (scanner_->drain(fresh) > 0) {
    for (const PluginDescriptor& descriptor : fresh) {
      auto existing = std::find_if(
          plugins_.begin(), plugins_.end(), [&descriptor](const PluginDescriptor& candidate) {
            return candidate.index_in_bundle == descriptor.index_in_bundle &&
                   std::strcmp(candidate.path.text(), descriptor.path.text()) == 0;
          });
      if (existing != plugins_.end()) {
        *existing = descriptor;
      } else {
        plugins_.push_back(descriptor);
      }
    }
    std::sort(plugins_.begin(), plugins_.end(), byDisplayName);
    ++generation_;
  }

  if (!committed_ && !scanner_->running() && scanner_->progress().state == ScanState::Complete) {
    committed_ = true;
    if (!scanner_->commit() && diagnostics_ != nullptr) {
      // Not fatal, and deliberately not surfaced to the user: the scan already
      // happened and the list on screen is correct. The only cost is that the
      // next launch rescans, which is slow rather than wrong.
      diagnostics_->logf(core::LogLevel::Warn, "plugin-scan",
                         "could not write the plugin cache to %s; the next launch will rescan",
                         cache_.path().c_str());
    }
    // The scan is authoritative about what exists, so rows for bundles it did
    // not see (uninstalled since last launch) go now.
    rebuildListFromCache();
  }
}

ScanProgress PluginLibrary::progress() const {
  return scanner_->progress();
}

void PluginLibrary::rebuildListFromCache() {
  plugins_ = cache_.entries();
  std::sort(plugins_.begin(), plugins_.end(), byDisplayName);
  ++generation_;
}

}  // namespace onebeat::plugin::scan
