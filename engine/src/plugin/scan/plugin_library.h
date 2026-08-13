// The plugin library as the app sees it (OB-2-02 scope §4, §5).
//
// Ties the three pieces together and owns the startup order that FR-PLG-05
// depends on: load the cache *synchronously* (a few milliseconds for a large
// library), so the list exists before the first frame is drawn, and only then
// start a scan whose results stream in underneath a working UI.
//
// Deliberately not part of `core::Engine`. Nothing here goes near the audio
// thread — it is filesystem work and a background thread — and putting it in
// the Engine would make every RT review read past it. The ABI layer owns one
// per engine handle.
#pragma once

#include <memory>
#include <string>
#include <vector>

#include "plugin/scan/plugin_cache.h"
#include "plugin/scan/scanner.h"

namespace onebeat::core {
class Diagnostics;
}

namespace onebeat::plugin::scan {

class PluginLibrary {
 public:
  // `cache_path` empty => PluginCache::defaultPath(). `probe` null => the
  // shipping `BundleNameProbe`; OB-2-05 passes the out-of-process one here.
  explicit PluginLibrary(std::string cache_path = std::string(),
                         core::Diagnostics* diagnostics = nullptr,
                         std::unique_ptr<ScanProbe> probe = nullptr);
  ~PluginLibrary();

  PluginLibrary(const PluginLibrary&) = delete;
  PluginLibrary& operator=(const PluginLibrary&) = delete;

  // Blocking, and meant to be: it is one file read, and the whole design is
  // that the app can afford to wait for it. Returns what the cache did, which
  // the caller logs — "rebuilt" is the only interesting answer.
  CacheLoadResult loadCache();

  // Empty => the standard locations. Set before `startScan()`.
  void setSearchPaths(std::vector<std::string> directories);

  bool startScan();
  void cancelScan() noexcept;
  bool scanning() const noexcept;

  // Drains whatever the scanner has settled since the last call into the list,
  // and commits + saves the cache the first time the scan completes. Cheap
  // enough to call once per UI frame; does nothing when there is nothing new.
  void pump();

  ScanProgress progress() const;

  // Sorted by display name. Stable between `pump()` calls, so a UI may hold an
  // index across a frame — but not across a pump, which is why the ABI copies a
  // row out rather than handing back a pointer.
  const std::vector<PluginDescriptor>& plugins() const noexcept { return plugins_; }

  // Bumped whenever `plugins()` changes in any way — a row added, a row
  // replaced, rows pruned. A UI that has already copied generation N can skip
  // the whole list on every frame until this moves, which is what keeps the
  // per-frame path free of a thousand struct copies.
  uint64_t generation() const noexcept { return generation_; }

 private:
  void rebuildListFromCache();

  PluginCache cache_;
  std::unique_ptr<ScanProbe> probe_;
  std::unique_ptr<PluginScanner> scanner_;
  core::Diagnostics* diagnostics_ = nullptr;

  std::vector<PluginDescriptor> plugins_;
  uint64_t generation_ = 0;
  bool committed_ = true;  // nothing to commit until a scan starts
};

}  // namespace onebeat::plugin::scan
