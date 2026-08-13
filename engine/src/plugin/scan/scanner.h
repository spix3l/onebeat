// The background plugin scanner (OB-2-02 scope §1, §2, §4; FR-PLG-05, NFR-04).
//
// Scanning must never block startup. The shape that guarantees it: the app
// loads the cache synchronously (a memcpy of half a megabyte), shows that list
// immediately, and *then* starts a scan on a background thread whose results
// stream in. The user sees their plugins in the time it takes to read one file,
// and a cold scan of a large library happens underneath a working UI.
//
// Nothing here is real-time. The scanner runs on its own `std::thread`,
// allocates freely, and touches the filesystem — it must never be called from
// the audio thread, and it never calls into the engine.
//
// **The probe is injected.** Discovering bundles and deciding which ones changed
// is filesystem work this ticket does; actually *loading* a plugin to ask what
// is inside it is not, because loading a plugin can crash the process (OB-2-03)
// and must therefore happen in the helper (OB-2-05). `ScanProbe` is the seam
// between the two: OB-2-05 supplies an out-of-process implementation and nothing
// in this file changes.
#pragma once

#include <atomic>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

#include "plugin/scan/descriptor.h"
#include "plugin/scan/plugin_cache.h"

namespace onebeat::core {
class Diagnostics;
}

namespace onebeat::plugin::scan {

// A bundle found on disk, before anything has been loaded from it.
struct BundleRef {
  std::string path;  // the .clap bundle or file
  PluginFormat format = PluginFormat::Clap;
  BundleFingerprint fingerprint;
};

class ScanProbe {
 public:
  virtual ~ScanProbe() = default;

  // [scanner-thread] Ask what plugins `bundle` contains. Appends one descriptor
  // per plugin; a bundle that yields none is recorded by the scanner as
  // `NotAPlugin` so it is not re-probed on every startup.
  //
  // The implementation owns its own failure handling: it must return rather
  // than throw, and — once OB-2-05 lands — a crash inside the plugin must be
  // observed as a dead child process, not as a dead scanner. An implementation
  // that runs in-process is a test fixture, never a shipping configuration.
  virtual void probe(const BundleRef& bundle, std::vector<PluginDescriptor>& out) = 0;

  // Which `DescriptorFlags` this probe is able to establish.
  //
  // This is what stops a cache from calcifying. Today's default probe never
  // opens a bundle, so it cannot set `DescriptorFlagIntrospected`. When
  // OB-2-07's probe arrives it can, and every row already cached — whose
  // fingerprint still matches perfectly — would otherwise be reused untouched
  // and never gain the information. Comparing capability against what the row
  // already carries makes the upgrade automatic and costs one scan.
  virtual uint32_t capabilities() const { return DescriptorFlagNone; }
};

// The probe the engine ships until a plugin can be loaded safely (OB-2-05) and
// meaningfully (OB-2-07).
//
// It never opens a bundle. It reports one row per bundle, named after the file,
// and sets no `DescriptorFlagIntrospected` — so the list a user sees on first
// run is their real library, with real names, and every row is honestly marked
// as not yet inspected rather than carrying invented port and parameter counts.
//
// Reading `Contents/Info.plist` for a better name would need CoreFoundation,
// which NFR-11 confines to the platform backend directory; a hand-rolled plist
// parser is not worth owning for a name that OB-2-07 replaces anyway.
class BundleNameProbe : public ScanProbe {
 public:
  void probe(const BundleRef& bundle, std::vector<PluginDescriptor>& out) override;
};

enum class ScanState : uint8_t {
  Idle = 0,
  Discovering = 1,  // walking the search paths
  Probing = 2,      // loading the bundles that changed
  Complete = 3,
  Cancelled = 4,
};

const char* scanStateName(ScanState state) noexcept;

struct ScanProgress {
  ScanState state = ScanState::Idle;
  uint32_t bundles_discovered = 0;
  // Bundles whose fingerprint matched the cache, so they were never loaded.
  // This is the number the "no rescan of unchanged plugins" criterion is
  // measured by, and it is logged at the end of every scan.
  uint32_t bundles_reused = 0;
  uint32_t bundles_probed = 0;
  uint32_t plugins_found = 0;
  // Rows dropped because their bundle is no longer on disk.
  uint32_t plugins_removed = 0;
  PluginPath current;  // what is being probed right now, for the progress line
};

class PluginScanner {
 public:
  // The scanner reads the cache once at `start()` and never touches it again
  // from the background thread; `commit()` writes results back on the caller's
  // thread. That is why there is no lock around the cache: it is not shared.
  PluginScanner(PluginCache& cache, ScanProbe& probe, core::Diagnostics* diagnostics = nullptr);
  ~PluginScanner();

  PluginScanner(const PluginScanner&) = delete;
  PluginScanner& operator=(const PluginScanner&) = delete;

  // Empty means "the standard locations for every format we can host".
  void setSearchPaths(std::vector<std::string> directories);
  const std::vector<std::string>& searchPaths() const noexcept { return search_paths_; }

  // The standard CLAP locations (scope §1). The structure takes a format so
  // that Stage 5's VST3 and AU paths are an added case here rather than a
  // second, parallel scanner.
  static std::vector<std::string> defaultSearchPaths(PluginFormat format);

  // False if a scan is already running. Non-blocking: returns as soon as the
  // thread is launched.
  bool start();

  // Re-probe exactly one bundle (OB-2-03 §3, the *Retry* action).
  //
  // Runs through the same machinery as a full scan — same thread, same probe,
  // same streaming — with two differences that matter:
  //
  //   * the bundle is probed even though its fingerprint is unchanged, because
  //     "unchanged" is precisely the state a retry exists to override;
  //   * `commit()` does not prune, since a scan of one bundle has seen one
  //     bundle and knows nothing about whether the rest still exist. Without
  //     that, retrying one plugin would delete the user's entire library.
  //
  // False if a scan is already running.
  bool startRetry(const std::string& bundle_path);

  // Asks the running scan to stop at the next bundle boundary. Does not join.
  void cancel() noexcept;

  bool running() const noexcept { return running_.load(std::memory_order_acquire); }

  // Blocks until the background thread has finished. Safe to call when idle.
  void join();

  ScanProgress progress() const;

  // Takes the descriptors settled since the last call — both freshly probed and
  // reused-from-cache — so the UI list grows as the scan proceeds. Returns how
  // many were appended.
  size_t drain(std::vector<PluginDescriptor>& out);

  // Moves the finished scan's results into the cache and saves it. Call after
  // the scan reaches Complete; a cancelled scan is not committed, because a
  // partial result would look like "these plugins were deleted" on the next
  // run. Returns false if the cache could not be written.
  bool commit();

 private:
  void run(const std::vector<std::string>& directories);
  void probeBundles(const std::vector<BundleRef>& bundles);

  PluginCache& cache_;
  ScanProbe& probe_;
  core::Diagnostics* diagnostics_ = nullptr;

  std::vector<std::string> search_paths_;

  std::thread thread_;
  std::atomic<bool> running_{false};
  std::atomic<bool> cancel_requested_{false};

  mutable std::mutex mutex_;
  ScanProgress progress_;
  std::vector<PluginDescriptor> pending_;  // drained by the UI
  std::vector<PluginDescriptor> settled_;  // the full result, for commit()
  std::vector<std::string> live_paths_;    // for pruning deleted bundles
  // A snapshot of the cache taken at start(), so the diff needs no lock.
  std::vector<PluginDescriptor> baseline_;
  // A full scan sees everything, so it may delete rows for bundles it did not
  // find. A retry sees one bundle and may not.
  bool prune_on_commit_ = true;
  // Carried across a retry: how many times the user has already tried this
  // plugin. Read from the cache before the row is dropped from the baseline,
  // so a retry that fails again counts up rather than resetting to one.
  uint8_t retry_seed_ = 0;
};

// Exposed for tests and for OB-2-05's helper, which fingerprints the same way.
BundleFingerprint fingerprintBundle(const std::string& path);

// Walks `directories` for bundles of `format`. Exposed separately from the
// scanner because discovery is pure and testable and probing is neither.
std::vector<BundleRef> discoverBundles(const std::vector<std::string>& directories,
                                       PluginFormat format);

}  // namespace onebeat::plugin::scan
