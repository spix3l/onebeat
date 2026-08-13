// The plugin scanner and its persistent cache (OB-2-02).
//
// The four acceptance criteria map onto the suites below:
//   - "list populates progressively"          -> "A scan streams results ..."
//   - "no rescan of unchanged plugins"        -> "A second scan probes nothing"
//   - "add/remove/update is detected"         -> "A changed bundle ..."
//   - "corrupt cache rebuilds, never crashes" -> the whole corruption suite
//
// Nothing here touches a real plugin: the probe is injected (see `ScanProbe`),
// so these tests exercise discovery, fingerprinting, incrementality, streaming
// and persistence — which is exactly the part OB-2-02 owns. Loading an actual
// CLAP bundle belongs to OB-2-07, and doing it without dying to OB-2-05.
#include <unistd.h>

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <functional>
#include <iterator>
#include <string>
#include <thread>
#include <vector>

#include "doctest.h"
#include "plugin/scan/plugin_cache.h"
#include "plugin/scan/plugin_library.h"
#include "plugin/scan/scanner.h"

using onebeat::plugin::scan::BundleRef;
using onebeat::plugin::scan::CacheFileHeader;
using onebeat::plugin::scan::CacheLoadResult;
using onebeat::plugin::scan::discoverBundles;
using onebeat::plugin::scan::fnv1a64;
using onebeat::plugin::scan::PluginCache;
using onebeat::plugin::scan::PluginDescriptor;
using onebeat::plugin::scan::PluginFormat;
using onebeat::plugin::scan::PluginScanner;
using onebeat::plugin::scan::ScanOutcome;
using onebeat::plugin::scan::ScanProbe;
using onebeat::plugin::scan::ScanState;

namespace fs = std::filesystem;

namespace {

// A temporary directory that removes itself, so a failing assertion cannot
// leave a half-built plugin library behind for the next run to trip over.
class TempDir {
 public:
  explicit TempDir(const char* label) {
    static std::atomic<int> counter{0};
    path_ = fs::temp_directory_path() /
            ("onebeat-" + std::string(label) + "-" + std::to_string(counter.fetch_add(1)) + "-" +
             std::to_string(::getpid()));
    fs::remove_all(path_);
    fs::create_directories(path_);
  }
  ~TempDir() {
    std::error_code code;
    fs::remove_all(path_, code);
  }
  TempDir(const TempDir&) = delete;
  TempDir& operator=(const TempDir&) = delete;

  const fs::path& path() const { return path_; }
  std::string str() const { return path_.string(); }
  std::string child(const std::string& name) const { return (path_ / name).string(); }

 private:
  fs::path path_;
};

// Builds the shape of a macOS plugin bundle. The scanner never opens the
// executable — only stats it — so its contents only have to differ when the
// test wants the fingerprint to differ.
std::string makeBundle(const fs::path& parent, const std::string& name,
                       const std::string& binary_contents = "MACHO") {
  const fs::path bundle = parent / (name + ".clap");
  fs::create_directories(bundle / "Contents" / "MacOS");
  {
    std::ofstream binary(bundle / "Contents" / "MacOS" / name, std::ios::binary);
    binary << binary_contents;
  }
  {
    std::ofstream plist(bundle / "Contents" / "Info.plist");
    plist << "<plist><dict><key>CFBundleVersion</key><string>1.0</string></dict></plist>";
  }
  return bundle.string();
}

// Rewrites a bundle's executable, which is what a plugin update looks like from
// the outside. The mtime is pushed forward explicitly rather than trusted to
// tick: two writes inside one filesystem timestamp granularity are otherwise
// indistinguishable, and this test would then fail once in a hundred runs.
void touchBundle(const std::string& bundle_path, const std::string& binary_contents) {
  const fs::path macos = fs::path(bundle_path) / "Contents" / "MacOS";
  for (const fs::directory_entry& entry : fs::directory_iterator(macos)) {
    {
      std::ofstream binary(entry.path(), std::ios::binary);
      binary << binary_contents;
    }
    fs::last_write_time(entry.path(), fs::file_time_type::clock::now() + std::chrono::hours(1));
    return;
  }
}

// Reports one plugin per bundle, named after it, and counts what it was asked
// about. `probed` is the number the incrementality criterion is measured by.
class CountingProbe : public ScanProbe {
 public:
  void probe(const BundleRef& bundle, std::vector<PluginDescriptor>& out) override {
    paths.push_back(bundle.path);
    if (before_each != nullptr) {
      before_each();
    }
    if (yields_nothing) {
      return;
    }
    PluginDescriptor descriptor;
    const std::string stem = fs::path(bundle.path).stem().string();
    descriptor.id.assign(("com.test." + stem).c_str());
    descriptor.name.assign(stem.c_str());
    descriptor.vendor.assign("Test Instruments");
    descriptor.version.assign("1.0.0");
    descriptor.audio_output_count = 1;
    descriptor.note_input_count = 1;
    descriptor.param_count = 3;
    out.push_back(descriptor);
  }

  size_t count() const { return paths.size(); }

  std::vector<std::string> paths;
  bool yields_nothing = false;
  std::function<void()> before_each = nullptr;
};

PluginDescriptor makeDescriptor(const std::string& path, const std::string& name) {
  PluginDescriptor descriptor;
  descriptor.path.assign(path.c_str());
  descriptor.name.assign(name.c_str());
  descriptor.id.assign(("com.test." + name).c_str());
  descriptor.format = PluginFormat::Clap;
  descriptor.fingerprint.binary_size = 42;
  descriptor.fingerprint.binary_mtime_nanos = 1234;
  return descriptor;
}

// Runs a scan to completion. A busy wait rather than a condition variable
// because the scanner's public surface is a progress poll — which is what the
// UI uses, so it is what the tests should exercise.
void runToCompletion(PluginScanner& scanner) {
  REQUIRE(scanner.start());
  scanner.join();
  REQUIRE(scanner.progress().state == ScanState::Complete);
}

std::vector<char> readAll(const std::string& path) {
  std::ifstream file(path, std::ios::binary);
  return std::vector<char>((std::istreambuf_iterator<char>(file)),
                           std::istreambuf_iterator<char>());
}

void writeAll(const std::string& path, const std::vector<char>& bytes) {
  std::ofstream file(path, std::ios::binary | std::ios::trunc);
  file.write(bytes.data(), static_cast<std::streamsize>(bytes.size()));
}

}  // namespace

TEST_SUITE("unit") {
  // ------------------------------------------------------------------------
  // The cache file
  // ------------------------------------------------------------------------

  TEST_CASE("A saved cache reloads byte-identically") {
    TempDir dir("cache-roundtrip");
    const std::string path = dir.child("plugin-cache.bin");

    PluginCache written(path);
    written.upsert(makeDescriptor("/plugins/Alpha.clap", "Alpha"));
    written.upsert(makeDescriptor("/plugins/Beta.clap", "Beta"));
    REQUIRE(written.save());

    PluginCache read(path);
    REQUIRE(read.load() == CacheLoadResult::Ok);
    REQUIRE(read.size() == 2);
    CHECK(std::string(read.entries()[0].name.text()) == "Alpha");
    CHECK(std::string(read.entries()[1].vendor.text()) == "");
    CHECK(read.find("/plugins/Beta.clap", 0) != nullptr);
    CHECK(read.find("/plugins/Gamma.clap", 0) == nullptr);
  }

  TEST_CASE("Rows are keyed by (path, index), because one bundle is a factory") {
    PluginCache cache("/dev/null");
    PluginDescriptor first = makeDescriptor("/plugins/Suite.clap", "Bass");
    PluginDescriptor second = makeDescriptor("/plugins/Suite.clap", "Drums");
    second.index_in_bundle = 1;

    cache.upsert(first);
    cache.upsert(second);
    REQUIRE(cache.size() == 2);

    // Same key: an update, not a duplicate.
    second.name.assign("Drums Mk II");
    cache.upsert(second);
    REQUIRE(cache.size() == 2);
    CHECK(std::string(cache.find("/plugins/Suite.clap", 1)->name.text()) == "Drums Mk II");
  }

  TEST_CASE("An empty cache saves and reloads, rather than being treated as corrupt") {
    TempDir dir("cache-empty");
    const std::string path = dir.child("plugin-cache.bin");
    PluginCache cache(path);
    REQUIRE(cache.save());
    PluginCache reloaded(path);
    CHECK(reloaded.load() == CacheLoadResult::Ok);
    CHECK(reloaded.size() == 0);
  }

  TEST_CASE("A missing cache is the first run, not an error") {
    TempDir dir("cache-missing");
    PluginCache cache(dir.child("does-not-exist.bin"));
    CHECK(cache.load() == CacheLoadResult::Missing);
    CHECK(cache.size() == 0);
  }

  // Each of these is a way a cache file can be wrong. All of them must produce
  // an empty cache and `Rebuilt` — never a crash, never a partial load, and
  // never a descriptor that the rest of the engine would then trust.
  TEST_CASE("Every kind of corrupt cache rebuilds instead of crashing") {
    TempDir dir("cache-corrupt");
    const std::string path = dir.child("plugin-cache.bin");

    PluginCache seed(path);
    for (int i = 0; i < 4; ++i) {
      seed.upsert(makeDescriptor("/plugins/P" + std::to_string(i) + ".clap", "P"));
    }
    REQUIRE(seed.save());
    const std::vector<char> good = readAll(path);
    REQUIRE(good.size() == sizeof(CacheFileHeader) + 4 * sizeof(PluginDescriptor));

    SUBCASE("truncated mid-descriptor") {
      std::vector<char> bytes = good;
      bytes.resize(good.size() - 17);
      writeAll(path, bytes);
    }
    SUBCASE("truncated inside the header") {
      writeAll(path, std::vector<char>(good.begin(), good.begin() + 9));
    }
    SUBCASE("empty file") {
      writeAll(path, {});
    }
    SUBCASE("wrong magic") {
      std::vector<char> bytes = good;
      bytes[0] = 'X';
      writeAll(path, bytes);
    }
    SUBCASE("a schema version we do not know") {
      std::vector<char> bytes = good;
      const uint32_t future = 9999;
      std::memcpy(bytes.data() + 4, &future, sizeof(future));
      writeAll(path, bytes);
    }
    SUBCASE("a flipped bit in a descriptor") {
      std::vector<char> bytes = good;
      bytes[sizeof(CacheFileHeader) + 3] =
          static_cast<char>(bytes[sizeof(CacheFileHeader) + 3] ^ 0x40);
      writeAll(path, bytes);
    }
    SUBCASE("an entry count that would allocate the world") {
      std::vector<char> bytes = good;
      const uint64_t absurd = 1ULL << 40U;
      std::memcpy(bytes.data() + 8, &absurd, sizeof(absurd));
      writeAll(path, bytes);
    }
    SUBCASE("an entry count larger than the file") {
      std::vector<char> bytes = good;
      const uint64_t count = 40;
      std::memcpy(bytes.data() + 8, &count, sizeof(count));
      writeAll(path, bytes);
    }
    SUBCASE("trailing bytes after the last descriptor") {
      std::vector<char> bytes = good;
      bytes.push_back('\0');
      writeAll(path, bytes);
    }
    SUBCASE("random bytes that happen to be the right length") {
      std::vector<char> bytes(good.size());
      for (size_t i = 0; i < bytes.size(); ++i) {
        bytes[i] = static_cast<char>((i * 31 + 7) & 0xFF);
      }
      writeAll(path, bytes);
    }

    PluginCache cache(path);
    CHECK(cache.load() == CacheLoadResult::Rebuilt);
    CHECK(cache.size() == 0);
  }

  // The one memory-safety hazard in a POD cache: text is read as a C string,
  // and a file edited by hand need not terminate it. The checksum cannot catch
  // this, because the file is internally consistent — it is just wrong.
  TEST_CASE("Unterminated text in an otherwise valid cache is repaired on load") {
    TempDir dir("cache-unterminated");
    const std::string path = dir.child("plugin-cache.bin");

    PluginDescriptor descriptor = makeDescriptor("/plugins/Evil.clap", "Evil");
    std::memset(descriptor.name.value, 'A', sizeof(descriptor.name.value));
    std::memset(descriptor.path.value, 'B', sizeof(descriptor.path.value));
    // Also out of range for its enum, which would otherwise index a switch.
    std::memcpy(&descriptor.outcome, "\x7f", 1);

    CacheFileHeader header{};
    header.magic = onebeat::plugin::scan::CacheMagic;
    header.schema_version = onebeat::plugin::scan::CacheSchemaVersion;
    header.entry_count = 1;
    header.payload_checksum = fnv1a64(&descriptor, sizeof(descriptor));

    std::vector<char> bytes(sizeof(header) + sizeof(descriptor));
    std::memcpy(bytes.data(), &header, sizeof(header));
    std::memcpy(bytes.data() + sizeof(header), &descriptor, sizeof(descriptor));
    writeAll(path, bytes);

    PluginCache cache(path);
    REQUIRE(cache.load() == CacheLoadResult::Ok);
    REQUIRE(cache.size() == 1);
    // strlen is now bounded by the capacity rather than running off the struct.
    CHECK(std::strlen(cache.entries()[0].name.text()) == sizeof(descriptor.name.value) - 1);
    CHECK(std::strlen(cache.entries()[0].path.text()) == sizeof(descriptor.path.value) - 1);
    CHECK(cache.entries()[0].outcome == ScanOutcome::Ok);
  }

  TEST_CASE("A save that is interrupted leaves the previous cache intact") {
    TempDir dir("cache-atomic");
    const std::string path = dir.child("plugin-cache.bin");

    PluginCache original(path);
    original.upsert(makeDescriptor("/plugins/Alpha.clap", "Alpha"));
    REQUIRE(original.save());

    // Stand in for the crash: the temp file exists, the rename never happened.
    writeAll(path + ".tmp", {'g', 'a', 'r', 'b', 'a', 'g', 'e'});

    PluginCache reloaded(path);
    CHECK(reloaded.load() == CacheLoadResult::Ok);
    CHECK(reloaded.size() == 1);
  }

  // ------------------------------------------------------------------------
  // Discovery
  // ------------------------------------------------------------------------

  TEST_CASE("Discovery finds nested bundles but never descends into one") {
    TempDir dir("discover");
    fs::create_directories(dir.path() / "Acme");
    const std::string alpha = makeBundle(dir.path(), "Alpha");
    const std::string beta = makeBundle(dir.path() / "Acme", "Beta");
    // A resource inside a bundle that happens to end in .clap. Descending would
    // report it as a second plugin.
    fs::create_directories(fs::path(alpha) / "Contents" / "Resources" / "Preset.clap");

    const std::vector<BundleRef> found = discoverBundles({dir.str()}, PluginFormat::Clap);
    REQUIRE(found.size() == 2);
    CHECK(found[0].path == beta);  // sorted, so "Acme/Beta" precedes "Alpha"
    CHECK(found[1].path == alpha);
    CHECK(found[0].fingerprint.valid());
  }

  TEST_CASE("A symlink loop does not hang discovery") {
    TempDir dir("discover-loop");
    makeBundle(dir.path(), "Alpha");
    std::error_code code;
    fs::create_directory_symlink(dir.path(), dir.path() / "loop", code);
    if (code) {
      return;  // some CI filesystems forbid symlinks; the bound is still tested
    }
    const std::vector<BundleRef> found = discoverBundles({dir.str()}, PluginFormat::Clap);
    CHECK(found.size() == 1);
  }

  TEST_CASE("A search path that does not exist is not an error") {
    const std::vector<BundleRef> found =
        discoverBundles({"/no/such/directory/anywhere"}, PluginFormat::Clap);
    CHECK(found.empty());
  }

  // ------------------------------------------------------------------------
  // Scanning
  // ------------------------------------------------------------------------

  TEST_CASE("A first scan finds every bundle and persists them") {
    TempDir library("scan-library");
    TempDir state("scan-state");
    makeBundle(library.path(), "Alpha");
    makeBundle(library.path(), "Beta");
    makeBundle(library.path(), "Gamma");

    PluginCache cache(state.child("plugin-cache.bin"));
    REQUIRE(cache.load() == CacheLoadResult::Missing);

    CountingProbe probe;
    PluginScanner scanner(cache, probe);
    scanner.setSearchPaths({library.str()});
    runToCompletion(scanner);

    const auto progress = scanner.progress();
    CHECK(progress.bundles_discovered == 3);
    CHECK(progress.bundles_probed == 3);
    CHECK(progress.bundles_reused == 0);
    CHECK(progress.plugins_found == 3);

    std::vector<PluginDescriptor> streamed;
    CHECK(scanner.drain(streamed) == 3);
    CHECK(std::string(streamed[0].name.text()) == "Alpha");

    REQUIRE(scanner.commit());
    PluginCache reloaded(state.child("plugin-cache.bin"));
    REQUIRE(reloaded.load() == CacheLoadResult::Ok);
    CHECK(reloaded.size() == 3);
  }

  // AC: "Second run: no rescan of unchanged plugins."
  TEST_CASE("A second scan probes nothing") {
    TempDir library("rescan-library");
    TempDir state("rescan-state");
    makeBundle(library.path(), "Alpha");
    makeBundle(library.path(), "Beta");

    const std::string cache_path = state.child("plugin-cache.bin");
    {
      PluginCache cache(cache_path);
      cache.load();
      CountingProbe probe;
      PluginScanner scanner(cache, probe);
      scanner.setSearchPaths({library.str()});
      runToCompletion(scanner);
      REQUIRE(probe.count() == 2);
      REQUIRE(scanner.commit());
    }

    PluginCache cache(cache_path);
    REQUIRE(cache.load() == CacheLoadResult::Ok);
    CountingProbe probe;
    PluginScanner scanner(cache, probe);
    scanner.setSearchPaths({library.str()});
    runToCompletion(scanner);

    CHECK(probe.count() == 0);  // nothing was loaded
    const auto progress = scanner.progress();
    CHECK(progress.bundles_reused == 2);
    CHECK(progress.bundles_probed == 0);
    CHECK(progress.plugins_found == 2);  // and yet both are still listed

    std::vector<PluginDescriptor> streamed;
    CHECK(scanner.drain(streamed) == 2);
  }

  // AC: "Adding/removing/updating a plugin bundle is detected on next cycle."
  TEST_CASE("A changed bundle is reprobed; a new one is probed; a deleted one is dropped") {
    TempDir library("delta-library");
    TempDir state("delta-state");
    const std::string alpha = makeBundle(library.path(), "Alpha");
    const std::string beta = makeBundle(library.path(), "Beta");
    const std::string gamma = makeBundle(library.path(), "Gamma");

    const std::string cache_path = state.child("plugin-cache.bin");
    {
      PluginCache cache(cache_path);
      cache.load();
      CountingProbe probe;
      PluginScanner scanner(cache, probe);
      scanner.setSearchPaths({library.str()});
      runToCompletion(scanner);
      REQUIRE(scanner.commit());
    }

    touchBundle(beta, "MACHO-v2");        // updated
    fs::remove_all(gamma);                // uninstalled
    makeBundle(library.path(), "Delta");  // installed

    PluginCache cache(cache_path);
    REQUIRE(cache.load() == CacheLoadResult::Ok);
    REQUIRE(cache.size() == 3);
    CountingProbe probe;
    PluginScanner scanner(cache, probe);
    scanner.setSearchPaths({library.str()});
    runToCompletion(scanner);

    REQUIRE(probe.count() == 2);
    std::vector<std::string> probed = probe.paths;
    std::sort(probed.begin(), probed.end());
    CHECK(probed[0] == beta);
    CHECK(probed[1] == library.child("Delta.clap"));

    const auto progress = scanner.progress();
    CHECK(progress.bundles_reused == 1);  // Alpha only
    CHECK(progress.bundles_probed == 2);

    REQUIRE(scanner.commit());
    CHECK(cache.find(gamma.c_str(), 0) == nullptr);  // uninstalled, so gone
    CHECK(cache.find(alpha.c_str(), 0) != nullptr);
    CHECK(cache.size() == 3);
  }

  // AC: "app is interactive immediately; list populates progressively."
  //
  // The engine-side half of that claim: results are drainable while the scan is
  // still running, rather than arriving in one batch at the end. The UI half is
  // measured in the app (see the ticket close-out).
  TEST_CASE("A scan streams results while it is still running") {
    TempDir library("stream-library");
    TempDir state("stream-state");
    for (int i = 0; i < 6; ++i) {
      makeBundle(library.path(), "Plugin" + std::to_string(i));
    }

    PluginCache cache(state.child("plugin-cache.bin"));
    cache.load();

    std::atomic<bool> release{false};
    std::atomic<int> probed{0};
    CountingProbe probe;
    // Blocks the scanner after the third bundle, so the assertion below happens
    // at a known point rather than in a race with a fast scan.
    probe.before_each = [&release, &probed] {
      if (probed.fetch_add(1) == 3) {
        while (!release.load()) {
          std::this_thread::sleep_for(std::chrono::milliseconds(1));
        }
      }
    };

    PluginScanner scanner(cache, probe);
    scanner.setSearchPaths({library.str()});
    REQUIRE(scanner.start());

    std::vector<PluginDescriptor> streamed;
    const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(5);
    while (streamed.size() < 3 && std::chrono::steady_clock::now() < deadline) {
      scanner.drain(streamed);
      std::this_thread::sleep_for(std::chrono::milliseconds(1));
    }

    CHECK(streamed.size() >= 3);
    CHECK(scanner.running());  // still going, and the list already has entries

    release.store(true);
    scanner.join();
    scanner.drain(streamed);
    CHECK(streamed.size() == 6);
  }

  TEST_CASE("A bundle that yields no plugin is remembered, so it is probed once") {
    TempDir library("empty-bundle-library");
    TempDir state("empty-bundle-state");
    makeBundle(library.path(), "NotReally");

    const std::string cache_path = state.child("plugin-cache.bin");
    {
      PluginCache cache(cache_path);
      cache.load();
      CountingProbe probe;
      probe.yields_nothing = true;
      PluginScanner scanner(cache, probe);
      scanner.setSearchPaths({library.str()});
      runToCompletion(scanner);
      CHECK(scanner.progress().plugins_found == 0);
      REQUIRE(scanner.commit());
    }

    PluginCache cache(cache_path);
    REQUIRE(cache.load() == CacheLoadResult::Ok);
    REQUIRE(cache.size() == 1);
    CHECK(cache.entries()[0].outcome == ScanOutcome::NotAPlugin);

    CountingProbe probe;
    probe.yields_nothing = true;
    PluginScanner scanner(cache, probe);
    scanner.setSearchPaths({library.str()});
    runToCompletion(scanner);
    CHECK(probe.count() == 0);  // the disappointment is not repeated
  }

  TEST_CASE("A cancelled scan is not committed") {
    TempDir library("cancel-library");
    TempDir state("cancel-state");
    for (int i = 0; i < 8; ++i) {
      makeBundle(library.path(), "Plugin" + std::to_string(i));
    }

    PluginCache cache(state.child("plugin-cache.bin"));
    cache.load();
    CountingProbe probe;
    probe.before_each = [] { std::this_thread::sleep_for(std::chrono::milliseconds(2)); };

    PluginScanner scanner(cache, probe);
    scanner.setSearchPaths({library.str()});
    REQUIRE(scanner.start());
    scanner.cancel();
    scanner.join();

    CHECK(scanner.progress().state == ScanState::Cancelled);
    // A partial result would look like "the rest of your plugins were deleted".
    CHECK_FALSE(scanner.commit());
    CHECK(cache.size() == 0);
  }

  TEST_CASE("Two scans cannot run at once") {
    TempDir library("concurrent-library");
    TempDir state("concurrent-state");
    makeBundle(library.path(), "Alpha");

    PluginCache cache(state.child("plugin-cache.bin"));
    cache.load();
    CountingProbe probe;
    probe.before_each = [] { std::this_thread::sleep_for(std::chrono::milliseconds(20)); };

    PluginScanner scanner(cache, probe);
    scanner.setSearchPaths({library.str()});
    REQUIRE(scanner.start());
    CHECK_FALSE(scanner.start());
    scanner.join();
  }

  // ------------------------------------------------------------------------
  // The library façade — the startup order FR-PLG-05 actually depends on
  // ------------------------------------------------------------------------

  TEST_CASE("The cached list is on screen before the scan starts, and survives it") {
    TempDir library_dir("library-lib");
    TempDir state("library-state");
    makeBundle(library_dir.path(), "Alpha");
    makeBundle(library_dir.path(), "Beta");
    const std::string cache_path = state.child("plugin-cache.bin");

    {
      onebeat::plugin::scan::PluginLibrary library(cache_path);
      REQUIRE(library.loadCache() == CacheLoadResult::Missing);
      library.setSearchPaths({library_dir.str()});
      REQUIRE(library.startScan());
      while (library.scanning()) {
        library.pump();
      }
      library.pump();
      REQUIRE(library.plugins().size() == 2);
    }

    // Second launch: the list is populated by loadCache alone, before anything
    // has been scanned. This is the claim "the app is interactive immediately"
    // rests on.
    onebeat::plugin::scan::PluginLibrary library(cache_path);
    REQUIRE(library.loadCache() == CacheLoadResult::Ok);
    CHECK(library.plugins().size() == 2);
    CHECK(std::string(library.plugins()[0].name.text()) == "Alpha");

    const uint64_t before = library.generation();
    library.setSearchPaths({library_dir.str()});
    REQUIRE(library.startScan());
    // The list is not emptied for the duration of the scan.
    CHECK(library.plugins().size() == 2);
    while (library.scanning()) {
      library.pump();
    }
    library.pump();
    CHECK(library.plugins().size() == 2);
    CHECK(library.generation() > before);
  }

  TEST_CASE("The shipping probe reports what it found without pretending to know more") {
    TempDir library_dir("probe-lib");
    TempDir state("probe-state");
    makeBundle(library_dir.path(), "Diva");

    onebeat::plugin::scan::PluginLibrary library(state.child("plugin-cache.bin"));
    library.loadCache();
    library.setSearchPaths({library_dir.str()});
    REQUIRE(library.startScan());
    while (library.scanning()) {
      library.pump();
    }
    library.pump();

    REQUIRE(library.plugins().size() == 1);
    const PluginDescriptor& found = library.plugins()[0];
    CHECK(std::string(found.name.text()) == "Diva");
    CHECK(found.usable());
    // The honest part: nothing was opened, so nothing is claimed.
    CHECK_FALSE(found.introspected());
    CHECK(found.param_count == 0);
    CHECK(found.audio_output_count == 0);
  }

  // Without this, every row written before OB-2-07's probe exists would be
  // reused forever: the bundle never changed, so the fingerprint always matches.
  TEST_CASE("A stronger probe re-examines rows a weaker one wrote") {
    TempDir library_dir("upgrade-lib");
    TempDir state("upgrade-state");
    makeBundle(library_dir.path(), "Alpha");
    const std::string cache_path = state.child("plugin-cache.bin");

    {
      PluginCache cache(cache_path);
      cache.load();
      onebeat::plugin::scan::BundleNameProbe weak;
      PluginScanner scanner(cache, weak);
      scanner.setSearchPaths({library_dir.str()});
      runToCompletion(scanner);
      REQUIRE(scanner.commit());
    }

    // Same bundle, untouched. A probe that claims to introspect must still run.
    class IntrospectingProbe : public CountingProbe {
     public:
      uint32_t capabilities() const override {
        return onebeat::plugin::scan::DescriptorFlagIntrospected;
      }
      void probe(const BundleRef& bundle, std::vector<PluginDescriptor>& out) override {
        CountingProbe::probe(bundle, out);
        out.back().flags = onebeat::plugin::scan::DescriptorFlagIntrospected;
      }
    };

    PluginCache cache(cache_path);
    REQUIRE(cache.load() == CacheLoadResult::Ok);
    REQUIRE_FALSE(cache.entries()[0].introspected());
    IntrospectingProbe strong;
    PluginScanner scanner(cache, strong);
    scanner.setSearchPaths({library_dir.str()});
    runToCompletion(scanner);

    CHECK(strong.count() == 1);
    CHECK(scanner.progress().bundles_reused == 0);
    REQUIRE(scanner.commit());
    CHECK(cache.entries()[0].introspected());

    // ...and a third scan with the same probe reuses, so this is a one-time
    // upgrade rather than a permanent rescan.
    IntrospectingProbe again;
    PluginScanner third(cache, again);
    third.setSearchPaths({library_dir.str()});
    runToCompletion(third);
    CHECK(again.count() == 0);
  }

  // NFR-04: cold start with 500 cached plugins under 5 s. The engine's share of
  // that budget is loading the cache, and this pins it: the bound is 250 ms —
  // 5 % of the budget — not because the load is expected to be near it (it is
  // three orders of magnitude faster) but because a regression that made it
  // slow would be a regression in the design, not in a constant.
  TEST_CASE("A 500-entry cache loads in a small fraction of the cold-start budget") {
    TempDir dir("nfr04");
    const std::string path = dir.child("plugin-cache.bin");

    PluginCache written(path);
    for (int i = 0; i < 500; ++i) {
      written.upsert(
          makeDescriptor("/Library/Audio/Plug-Ins/CLAP/Vendor/Plugin" + std::to_string(i) + ".clap",
                         "Plugin " + std::to_string(i)));
    }
    REQUIRE(written.save());

    const auto start = std::chrono::steady_clock::now();
    PluginCache read(path);
    const CacheLoadResult result = read.load();
    const auto elapsed = std::chrono::steady_clock::now() - start;

    REQUIRE(result == CacheLoadResult::Ok);
    REQUIRE(read.size() == 500);

    const double millis =
        std::chrono::duration_cast<std::chrono::duration<double, std::milli>>(elapsed).count();
    MESSAGE("500-entry cache load: " << millis << " ms (file " << fs::file_size(path) / 1024
                                     << " KiB)");
    CHECK(millis < 250.0);
  }
}
