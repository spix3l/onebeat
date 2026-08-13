#include "plugin/scan/scanner.h"

#include <algorithm>
#include <chrono>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <system_error>

#include "core/diagnostics.h"

namespace onebeat::plugin::scan {
namespace {

namespace fs = std::filesystem;

// CLAP bundles nest: vendors ship `CLAP/Acme/Thing.clap`. The spec says search
// recursively, so we do — but with a depth bound, because a symlink pointing at
// an ancestor turns "recursively" into "forever". Eight levels is deeper than
// any real installer and shallow enough that the walk stays milliseconds.
constexpr int MaxSearchDepth = 8;

const char* extensionFor(PluginFormat format) noexcept {
  switch (format) {
    case PluginFormat::Clap:
      return ".clap";
    case PluginFormat::Vst3:
      return ".vst3";
    case PluginFormat::AudioUnit:
      return ".component";
    case PluginFormat::Unknown:
    case PluginFormat::Builtin:
      return "";
  }
  return "";
}

int64_t mtimeNanos(const fs::directory_entry& entry) noexcept {
  std::error_code code;
  const auto time = fs::last_write_time(entry, code);
  if (code) {
    return 0;
  }
  return std::chrono::duration_cast<std::chrono::nanoseconds>(time.time_since_epoch()).count();
}

int64_t nowUnixNanos() noexcept {
  return std::chrono::duration_cast<std::chrono::nanoseconds>(
             std::chrono::system_clock::now().time_since_epoch())
      .count();
}

// A macOS bundle is a directory; CLAP also permits a bare shared library. Both
// are matched by extension, so this only has to answer "does this name end the
// search" — the contents are the probe's problem.
bool isBundle(const fs::directory_entry& entry, const char* extension) {
  std::error_code code;
  const std::string name = entry.path().filename().string();
  const size_t suffix_length = std::strlen(extension);
  if (suffix_length == 0 || name.size() <= suffix_length) {
    return false;
  }
  return name.compare(name.size() - suffix_length, suffix_length, extension) == 0;
}

// An explicit worklist rather than recursion. Not a style preference: the walk
// runs over directories the user controls, and a deep tree would otherwise put
// an attacker-influenced bound on our stack depth. The heap grows instead, and
// `MaxSearchDepth` bounds it.
void walk(const fs::path& root, const char* extension, std::vector<BundleRef>& out,
          PluginFormat format) {
  struct Pending {
    fs::path directory;
    int depth;
  };
  std::vector<Pending> worklist{{root, 0}};

  while (!worklist.empty()) {
    const Pending current = std::move(worklist.back());
    worklist.pop_back();
    if (current.depth > MaxSearchDepth) {
      continue;
    }

    std::error_code code;
    // Deliberately not `recursive_directory_iterator`: it descends into
    // directories we have already decided are bundles, so a .clap containing a
    // nested .clap-named resource would be reported twice.
    fs::directory_iterator it(current.directory, fs::directory_options::skip_permission_denied,
                              code);
    if (code) {
      continue;
    }
    for (const fs::directory_entry& entry : it) {
      if (isBundle(entry, extension)) {
        BundleRef bundle;
        bundle.path = entry.path().string();
        bundle.format = format;
        bundle.fingerprint = fingerprintBundle(bundle.path);
        out.push_back(std::move(bundle));
        continue;  // do not descend into a bundle
      }
      // Symlinks are not followed: one pointing at / turns a 40 ms walk into an
      // unbounded one, and pointing at an ancestor makes it a cycle.
      if (entry.is_directory(code) && !entry.is_symlink(code)) {
        worklist.push_back({entry.path(), current.depth + 1});
      }
    }
  }
}

}  // namespace

const char* scanStateName(ScanState state) noexcept {
  switch (state) {
    case ScanState::Idle:
      return "idle";
    case ScanState::Discovering:
      return "discovering";
    case ScanState::Probing:
      return "probing";
    case ScanState::Complete:
      return "complete";
    case ScanState::Cancelled:
      return "cancelled";
  }
  return "unknown";
}

void BundleNameProbe::probe(const BundleRef& bundle, std::vector<PluginDescriptor>& out) {
  PluginDescriptor descriptor;
  const std::string stem = fs::path(bundle.path).stem().string();
  descriptor.name.assign(stem.c_str());
  // Not the plugin's real id — it does not have one until something opens it.
  // The path is unique and stable, which is what the cache key needs; the
  // moment a real probe runs, this is overwritten with the plugin's own id.
  descriptor.id.assign(bundle.path.c_str());
  descriptor.flags = DescriptorFlagNone;
  out.push_back(descriptor);
}

BundleFingerprint fingerprintBundle(const std::string& path) {
  BundleFingerprint print;
  std::error_code code;
  const fs::path bundle(path);

  const fs::directory_entry root(bundle, code);
  if (code) {
    return print;
  }

  if (root.is_directory(code)) {
    // `Foo.clap/Contents/MacOS/Foo` by convention, but a bundle is free to name
    // its executable anything, so take the first regular file in MacOS/ rather
    // than assuming. Info.plist is where the version lives, which is why it is
    // fingerprinted too: a version bump with an unchanged binary still counts.
    const fs::path macos = bundle / "Contents" / "MacOS";
    fs::directory_iterator it(macos, code);
    if (!code) {
      for (const fs::directory_entry& entry : it) {
        if (entry.is_regular_file(code)) {
          print.binary_size = static_cast<uint64_t>(entry.file_size(code));
          print.binary_mtime_nanos = mtimeNanos(entry);
          break;
        }
      }
    }
    const fs::directory_entry plist(bundle / "Contents" / "Info.plist", code);
    if (!code && plist.is_regular_file(code)) {
      print.plist_size = static_cast<uint64_t>(plist.file_size(code));
      print.plist_mtime_nanos = mtimeNanos(plist);
    }
    return print;
  }

  if (root.is_regular_file(code)) {
    print.binary_size = static_cast<uint64_t>(root.file_size(code));
    print.binary_mtime_nanos = mtimeNanos(root);
  }
  return print;
}

std::vector<BundleRef> discoverBundles(const std::vector<std::string>& directories,
                                       PluginFormat format) {
  std::vector<BundleRef> found;
  const char* extension = extensionFor(format);
  if (extension[0] == '\0') {
    return found;
  }
  for (const std::string& directory : directories) {
    walk(fs::path(directory), extension, found, format);
  }
  // Stable order so two scans of an unchanged library produce identical logs
  // and identical cache files — which is what makes "nothing was rescanned"
  // something a test can assert rather than eyeball.
  std::sort(found.begin(), found.end(),
            [](const BundleRef& a, const BundleRef& b) { return a.path < b.path; });
  return found;
}

std::vector<std::string> PluginScanner::defaultSearchPaths(PluginFormat format) {
  const char* home = std::getenv("HOME");
  const std::string user = home != nullptr ? std::string(home) : std::string();

  std::vector<std::string> paths;
  switch (format) {
    case PluginFormat::Clap:
      paths.emplace_back("/Library/Audio/Plug-Ins/CLAP");
      if (!user.empty()) {
        paths.push_back(user + "/Library/Audio/Plug-Ins/CLAP");
      }
      break;
    case PluginFormat::Vst3:
      paths.emplace_back("/Library/Audio/Plug-Ins/VST3");
      if (!user.empty()) {
        paths.push_back(user + "/Library/Audio/Plug-Ins/VST3");
      }
      break;
    case PluginFormat::AudioUnit:
      paths.emplace_back("/Library/Audio/Plug-Ins/Components");
      if (!user.empty()) {
        paths.push_back(user + "/Library/Audio/Plug-Ins/Components");
      }
      break;
    case PluginFormat::Unknown:
    case PluginFormat::Builtin:
      break;
  }
  return paths;
}

PluginScanner::PluginScanner(PluginCache& cache, ScanProbe& probe, core::Diagnostics* diagnostics)
    : cache_(cache), probe_(probe), diagnostics_(diagnostics) {}

PluginScanner::~PluginScanner() {
  cancel();
  join();
}

void PluginScanner::setSearchPaths(std::vector<std::string> directories) {
  search_paths_ = std::move(directories);
}

bool PluginScanner::start() {
  if (running_.exchange(true, std::memory_order_acq_rel)) {
    return false;
  }
  join();  // reap a finished previous thread before replacing it
  cancel_requested_.store(false, std::memory_order_release);
  prune_on_commit_ = true;
  retry_seed_ = 0;

  {
    std::lock_guard<std::mutex> lock(mutex_);
    progress_ = ScanProgress{};
    progress_.state = ScanState::Discovering;
    pending_.clear();
    settled_.clear();
    live_paths_.clear();
    // The one point where the cache is read by anything but the owning thread,
    // and it happens before the background thread exists.
    baseline_ = cache_.entries();
  }

  // The search paths are copied here rather than read from the background
  // thread, so `setSearchPaths()` during a scan changes the *next* scan and
  // cannot tear the running one.
  std::vector<std::string> directories = search_paths_;
  if (directories.empty()) {
    directories = defaultSearchPaths(PluginFormat::Clap);
  }

  thread_ = std::thread([this, directories = std::move(directories)] {
    // An exception escaping a std::thread's entry point calls std::terminate.
    // Scanning walks a filesystem the user controls and calls a probe that will
    // eventually be a child process, so "something threw" is a case that will
    // happen — and losing the user's session to it would be absurd. The scan
    // ends as though it had been cancelled, which is already the state that
    // means "do not commit this".
    try {
      run(directories);
    } catch (...) {
      std::lock_guard<std::mutex> lock(mutex_);
      progress_.state = ScanState::Cancelled;
      running_.store(false, std::memory_order_release);
    }
  });
  return true;
}

bool PluginScanner::startRetry(const std::string& bundle_path) {
  if (running_.exchange(true, std::memory_order_acq_rel)) {
    return false;
  }
  join();
  cancel_requested_.store(false, std::memory_order_release);
  prune_on_commit_ = false;

  BundleRef bundle;
  bundle.path = bundle_path;
  bundle.format = PluginFormat::Clap;
  bundle.fingerprint = fingerprintBundle(bundle_path);

  {
    std::lock_guard<std::mutex> lock(mutex_);
    progress_ = ScanProgress{};
    progress_.state = ScanState::Probing;
    progress_.bundles_discovered = 1;
    pending_.clear();
    settled_.clear();
    live_paths_.clear();
    baseline_ = cache_.entries();

    // Everything this bundle already has in the cache is dropped from the
    // baseline, which is what forces a re-probe: the reuse rule in
    // `probeBundles` keys off finding a matching row, and there will not be
    // one. The retry count is carried over first, so a second failure reads as
    // "tried twice" rather than as a fresh problem.
    uint8_t previous = 0;
    for (const PluginDescriptor& row : baseline_) {
      if (row.path.text() == bundle_path) {
        previous = std::max(previous, row.retry_count);
      }
    }
    retry_seed_ = previous < 255 ? static_cast<uint8_t>(previous + 1) : previous;
    baseline_.erase(std::remove_if(baseline_.begin(), baseline_.end(),
                                   [&bundle_path](const PluginDescriptor& row) {
                                     return row.path.text() == bundle_path;
                                   }),
                    baseline_.end());
  }

  thread_ = std::thread([this, bundle] {
    try {
      probeBundles({bundle});
    } catch (...) {
      std::lock_guard<std::mutex> lock(mutex_);
      progress_.state = ScanState::Cancelled;
      running_.store(false, std::memory_order_release);
    }
  });
  return true;
}

void PluginScanner::cancel() noexcept {
  cancel_requested_.store(true, std::memory_order_release);
}

void PluginScanner::join() {
  if (thread_.joinable()) {
    thread_.join();
  }
}

ScanProgress PluginScanner::progress() const {
  std::lock_guard<std::mutex> lock(mutex_);
  return progress_;
}

size_t PluginScanner::drain(std::vector<PluginDescriptor>& out) {
  std::lock_guard<std::mutex> lock(mutex_);
  const size_t count = pending_.size();
  out.insert(out.end(), pending_.begin(), pending_.end());
  pending_.clear();
  return count;
}

void PluginScanner::run(const std::vector<std::string>& directories) {
  const std::vector<BundleRef> bundles = discoverBundles(directories, PluginFormat::Clap);

  {
    std::lock_guard<std::mutex> lock(mutex_);
    progress_.bundles_discovered = static_cast<uint32_t>(bundles.size());
    progress_.state = ScanState::Probing;
  }

  probeBundles(bundles);
}

// The body of a scan, shared by the full walk and by a one-bundle retry. Both
// need identical reuse, streaming, cancellation and completion behaviour, and
// the surest way to get that is for there to be one copy of it.
void PluginScanner::probeBundles(const std::vector<BundleRef>& bundles) {
  std::vector<PluginDescriptor> probed;
  for (const BundleRef& bundle : bundles) {
    if (cancel_requested_.load(std::memory_order_acquire)) {
      std::lock_guard<std::mutex> lock(mutex_);
      progress_.state = ScanState::Cancelled;
      running_.store(false, std::memory_order_release);
      return;
    }

    {
      std::lock_guard<std::mutex> lock(mutex_);
      progress_.current.assign(bundle.path.c_str());
      live_paths_.push_back(bundle.path);
    }

    // The incremental decision (scope §2). Every cached row for this bundle
    // whose fingerprint still matches is reused verbatim — including a
    // quarantined one, which is the point: a plugin that crashed the scanner
    // must not be re-probed on every launch (OB-2-03).
    probed.clear();
    bool reused = false;
    if (bundle.fingerprint.valid()) {
      const uint32_t wanted = probe_.capabilities();
      for (const PluginDescriptor& cached : baseline_) {
        if (cached.path.text() != bundle.path || cached.fingerprint != bundle.fingerprint) {
          continue;
        }
        // The bundle has not changed, but the *probe* may have grown since the
        // row was written. A row that knows less than this probe could tell us
        // is re-probed rather than reused.
        if ((cached.flags & wanted) != wanted) {
          probed.clear();
          reused = false;
          break;
        }
        probed.push_back(cached);
        reused = true;
      }
    }

    if (!reused) {
      probe_.probe(bundle, probed);
      for (PluginDescriptor& descriptor : probed) {
        descriptor.path.assign(bundle.path.c_str());
        descriptor.format = bundle.format;
        descriptor.fingerprint = bundle.fingerprint;
        descriptor.scanned_at_nanos = nowUnixNanos();
        // Zero for a full scan, and the carried-over count for a retry. A
        // bundle whose fingerprint changed is a new version, and starting its
        // count again is the right answer there: the user has not yet tried
        // *this* build of it.
        descriptor.retry_count = retry_seed_;
      }
      // A bundle that yielded nothing is remembered as such, so the next launch
      // skips it instead of paying for the same disappointment.
      if (probed.empty()) {
        PluginDescriptor empty;
        empty.path.assign(bundle.path.c_str());
        empty.name.assign(fs::path(bundle.path).stem().string().c_str());
        empty.format = bundle.format;
        empty.outcome = ScanOutcome::NotAPlugin;
        empty.fingerprint = bundle.fingerprint;
        empty.scanned_at_nanos = nowUnixNanos();
        probed.push_back(empty);
      }
    }

    {
      std::lock_guard<std::mutex> lock(mutex_);
      if (reused) {
        ++progress_.bundles_reused;
      } else {
        ++progress_.bundles_probed;
      }
      for (const PluginDescriptor& descriptor : probed) {
        if (descriptor.usable()) {
          ++progress_.plugins_found;
        }
        settled_.push_back(descriptor);
        pending_.push_back(descriptor);
      }
    }
  }

  {
    std::lock_guard<std::mutex> lock(mutex_);
    progress_.current.assign("");
    progress_.state = ScanState::Complete;
  }

  if (diagnostics_ != nullptr) {
    const ScanProgress final_progress = progress();
    // The line the "no rescan of unchanged plugins" criterion is verified from.
    diagnostics_->logf(core::LogLevel::Info, "plugin-scan",
                       "scan complete: %u bundles discovered, %u reused from cache, %u probed, "
                       "%u plugins available",
                       final_progress.bundles_discovered, final_progress.bundles_reused,
                       final_progress.bundles_probed, final_progress.plugins_found);
  }

  running_.store(false, std::memory_order_release);
}

bool PluginScanner::commit() {
  std::vector<PluginDescriptor> settled;
  std::vector<std::string> live;
  {
    std::lock_guard<std::mutex> lock(mutex_);
    if (progress_.state != ScanState::Complete) {
      return false;
    }
    settled = settled_;
    live = live_paths_;
  }

  // A retry has seen one bundle, so it is in no position to conclude that every
  // other plugin has been uninstalled.
  const size_t removed = prune_on_commit_ ? cache_.retainOnly(live) : 0;
  for (const PluginDescriptor& descriptor : settled) {
    cache_.upsert(descriptor);
  }
  {
    std::lock_guard<std::mutex> lock(mutex_);
    progress_.plugins_removed = static_cast<uint32_t>(removed);
  }
  return cache_.save();
}

}  // namespace onebeat::plugin::scan
