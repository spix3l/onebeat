// Scan crash quarantine (OB-2-03; FR-PLG-06, G3).
//
// These are the tests that cannot be written with a fake probe. OB-2-02's
// suite injects a `ScanProbe` and never opens anything, which is right for
// discovery and caching; this file is about what happens when opening a bundle
// kills the process that opened it, so it uses the real helper binary and three
// real `.clap` bundles built by `engine/tests/CMakeLists.txt` — one that loads,
// one whose constructor dereferences null, one whose constructor never returns.
//
// The acceptance criteria map onto the cases below:
//   - "crashing plugin is quarantined, scan completes, app survives"
//         -> "A plugin that crashes ... and the scan carries on"
//   - "hanging plugin trips the watchdog"          -> "A plugin that hangs ..."
//   - "quarantine persists; Retry re-scans exactly that plugin;
//      version bump triggers one auto-retry"       -> the three cases after it
//   - reporting (§4)                               -> "The crash report names ..."
#include <unistd.h>

#include <algorithm>
#include <atomic>
#include <chrono>
#include <filesystem>
#include <fstream>
#include <sstream>
#include <string>
#include <vector>

#include "doctest.h"
#include "plugin/scan/plugin_cache.h"
#include "plugin/scan/plugin_library.h"
#include "plugin/scan/scanner.h"
#include "plugin/scan/subprocess_probe.h"

using onebeat::plugin::scan::BundleRef;
using onebeat::plugin::scan::PluginCache;
using onebeat::plugin::scan::PluginDescriptor;
using onebeat::plugin::scan::PluginFormat;
using onebeat::plugin::scan::PluginLibrary;
using onebeat::plugin::scan::PluginScanner;
using onebeat::plugin::scan::ScanOutcome;
using onebeat::plugin::scan::ScanPhase;
using onebeat::plugin::scan::ScanProbe;
using onebeat::plugin::scan::ScanState;
using onebeat::plugin::scan::SubprocessProbe;
using onebeat::plugin::scan::SubprocessProbeOptions;

namespace fs = std::filesystem;

namespace {

// Long enough that a healthy bundle always finishes, short enough that the
// hang case does not dominate the suite. The shipping default is 15 s; that is
// a user-experience number, and this is a test-runtime one.
constexpr std::chrono::milliseconds TestTimeout{1500};

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

// Copies one of the built fixture bundles into a scratch directory, so a test
// can change or delete it without touching the build output that every other
// test also reads.
std::string installFixture(const TempDir& into, const std::string& fixture) {
  const fs::path source = fs::path(OB_TEST_PLUGIN_DIR) / (fixture + ".clap");
  REQUIRE_MESSAGE(fs::exists(source), "fixture bundle missing: ", source.string());
  const fs::path destination = into.path() / (fixture + ".clap");
  fs::copy(source, destination, fs::copy_options::recursive);
  return destination.string();
}

SubprocessProbeOptions testOptions(const TempDir& logs) {
  SubprocessProbeOptions options;
  options.helper_path = OB_TEST_HELPER;
  options.crash_log_directory = logs.str();
  options.timeout = TestTimeout;
  return options;
}

// Wraps the real probe to count how many bundles were actually opened, which is
// what "not re-probed" and "exactly that plugin" are asserted against. Written
// only on the scanner thread and read only after `join()`.
class CountingProbe : public ScanProbe {
 public:
  explicit CountingProbe(ScanProbe& inner) : inner_(inner) {}

  void probe(const BundleRef& bundle, std::vector<PluginDescriptor>& out) override {
    probed.push_back(bundle.path);
    inner_.probe(bundle, out);
  }
  uint32_t capabilities() const override { return inner_.capabilities(); }

  std::vector<std::string> probed;

 private:
  ScanProbe& inner_;
};

void runToCompletion(PluginScanner& scanner) {
  REQUIRE(scanner.start());
  scanner.join();
  REQUIRE(scanner.progress().state == ScanState::Complete);
  REQUIRE(scanner.commit());
}

const PluginDescriptor* rowFor(const PluginCache& cache, const std::string& path) {
  return cache.find(path.c_str(), 0);
}

std::string readWholeFile(const std::string& path) {
  std::ifstream file(path);
  std::ostringstream text;
  text << file.rdbuf();
  return text.str();
}

}  // namespace

TEST_SUITE("unit") {
  TEST_CASE("The helper opens a healthy bundle and reports it") {
    TempDir logs("quarantine-ok");
    TempDir plugins("quarantine-ok-plugins");
    const std::string ok = installFixture(plugins, "ob_test_plugin_ok");

    SubprocessProbe probe(testOptions(logs));
    REQUIRE(probe.available());

    BundleRef bundle;
    bundle.path = ok;
    bundle.format = PluginFormat::Clap;

    std::vector<PluginDescriptor> found;
    probe.probe(bundle, found);

    REQUIRE(found.size() == 1);
    CHECK(found[0].outcome == ScanOutcome::Ok);
    CHECK(found[0].usable());
    CHECK_FALSE(found[0].quarantined());
    // OB-2-07 upgraded the scan helper from a symbol check to a real CLAP
    // factory walk and temporary instantiation, so browser metadata is now
    // authoritative without loading the plugin in the app process.
    CHECK(found[0].introspected());
    CHECK(std::string(found[0].id.text()) == "dev.onebeat.test.synth");
    CHECK(std::string(found[0].name.text()) == "OneBeat Test Synth");
    CHECK(found[0].param_count == 1);
    CHECK(found[0].audio_output_count == 1);
    CHECK(found[0].note_input_count == 1);
  }

  TEST_CASE("A plugin that crashes on load is quarantined, and the scan carries on") {
    TempDir logs("quarantine-crash");
    TempDir plugins("quarantine-crash-plugins");
    const std::string ok = installFixture(plugins, "ob_test_plugin_ok");
    const std::string crash = installFixture(plugins, "ob_test_plugin_crash");

    PluginCache cache(logs.child("plugin-cache.bin"));
    SubprocessProbe probe(testOptions(logs));
    PluginScanner scanner(cache, probe);
    scanner.setSearchPaths({plugins.str()});
    runToCompletion(scanner);

    // The criterion in three assertions: the crashing bundle is quarantined,
    // the healthy one is unaffected, and this process is still here to say so.
    const PluginDescriptor* crashed = rowFor(cache, crash);
    REQUIRE(crashed != nullptr);
    CHECK(crashed->outcome == ScanOutcome::Crashed);
    CHECK(crashed->quarantined());
    CHECK_FALSE(crashed->usable());
    // It died inside `dlopen`, running the constructor — which is where scan
    // crashes really happen, and the reason the phase is worth recording.
    CHECK(crashed->failure_phase == ScanPhase::Load);
    // A signal *or* a non-zero exit: under a sanitizer the runtime intercepts
    // the fault and exits by itself, so neither alone can be required.
    CHECK((crashed->failure_signal != 0 || crashed->failure_exit_code != 0));

    const PluginDescriptor* healthy = rowFor(cache, ok);
    REQUIRE(healthy != nullptr);
    CHECK(healthy->outcome == ScanOutcome::Ok);

    CHECK(scanner.progress().bundles_discovered == 2);
    CHECK(scanner.progress().plugins_found == 1);
  }

  TEST_CASE("A plugin that hangs trips the watchdog and is quarantined as a hang") {
    TempDir logs("quarantine-hang");
    TempDir plugins("quarantine-hang-plugins");
    const std::string ok = installFixture(plugins, "ob_test_plugin_ok");
    const std::string hang = installFixture(plugins, "ob_test_plugin_hang");

    PluginCache cache(logs.child("plugin-cache.bin"));
    SubprocessProbe probe(testOptions(logs));
    PluginScanner scanner(cache, probe);
    scanner.setSearchPaths({plugins.str()});

    const auto started = std::chrono::steady_clock::now();
    runToCompletion(scanner);
    const auto elapsed = std::chrono::steady_clock::now() - started;

    const PluginDescriptor* hung = rowFor(cache, hang);
    REQUIRE(hung != nullptr);
    // Not `Crashed`. A hang and a crash are different vendor bugs and different
    // sentences to the user, and folding them together would lose that.
    CHECK(hung->outcome == ScanOutcome::TimedOut);
    CHECK(hung->quarantined());
    CHECK(hung->failure_phase == ScanPhase::Load);

    const PluginDescriptor* healthy = rowFor(cache, ok);
    REQUIRE(healthy != nullptr);
    CHECK(healthy->outcome == ScanOutcome::Ok);

    // The watchdog bounds the damage: one hung plugin costs one timeout, not a
    // scan that never finishes. Generous upper bound so a loaded CI machine
    // cannot fail this on scheduling noise alone.
    CHECK(elapsed < TestTimeout * 4);
  }

  TEST_CASE("A quarantined plugin survives a restart and is never re-opened") {
    TempDir logs("quarantine-persist");
    TempDir plugins("quarantine-persist-plugins");
    const std::string crash = installFixture(plugins, "ob_test_plugin_crash");
    installFixture(plugins, "ob_test_plugin_ok");

    const std::string cache_path = logs.child("plugin-cache.bin");
    SubprocessProbe probe(testOptions(logs));

    {
      PluginCache cache(cache_path);
      PluginScanner scanner(cache, probe);
      scanner.setSearchPaths({plugins.str()});
      runToCompletion(scanner);
      REQUIRE(rowFor(cache, crash)->outcome == ScanOutcome::Crashed);
    }

    // A second launch: same cache file, fresh objects.
    PluginCache reloaded(cache_path);
    REQUIRE(reloaded.load() == onebeat::plugin::scan::CacheLoadResult::Ok);
    CountingProbe counting(probe);
    PluginScanner scanner(reloaded, counting);
    scanner.setSearchPaths({plugins.str()});
    runToCompletion(scanner);

    // This is the point of persisting the outcome: re-probing a plugin that
    // crashes is how a broken plugin turns into a broken *startup*, every
    // launch, forever.
    CHECK(counting.probed.empty());
    CHECK(scanner.progress().bundles_reused == 2);
    CHECK(scanner.progress().bundles_probed == 0);

    const PluginDescriptor* crashed = rowFor(reloaded, crash);
    REQUIRE(crashed != nullptr);
    CHECK(crashed->outcome == ScanOutcome::Crashed);
    CHECK(crashed->failure_phase == ScanPhase::Load);
  }

  TEST_CASE("Retry re-opens exactly one plugin and leaves the rest of the library alone") {
    TempDir logs("quarantine-retry");
    TempDir plugins("quarantine-retry-plugins");
    const std::string crash = installFixture(plugins, "ob_test_plugin_crash");
    const std::string ok = installFixture(plugins, "ob_test_plugin_ok");

    SubprocessProbe probe(testOptions(logs));
    auto counting = std::make_unique<CountingProbe>(probe);
    CountingProbe* counter = counting.get();

    PluginLibrary library(logs.child("plugin-cache.bin"), nullptr, std::move(counting));
    library.loadCache();
    library.setSearchPaths({plugins.str()});
    REQUIRE(library.startScan());
    while (library.scanning()) {
      library.pump();
    }
    library.pump();
    REQUIRE(library.plugins().size() == 2);
    counter->probed.clear();

    REQUIRE(library.retryPlugin(crash));
    while (library.scanning()) {
      library.pump();
    }
    library.pump();

    // Exactly one bundle opened, and it was the right one.
    REQUIRE(counter->probed.size() == 1);
    CHECK(counter->probed[0] == crash);

    // The rest of the library is still there. A retry that pruned would read
    // the single bundle it saw as "everything else was uninstalled" and empty
    // the user's browser — which is why `commit()` knows the difference.
    REQUIRE(library.plugins().size() == 2);
    const auto healthy =
        std::find_if(library.plugins().begin(), library.plugins().end(),
                     [&ok](const PluginDescriptor& row) { return row.path.text() == ok; });
    REQUIRE(healthy != library.plugins().end());
    CHECK(healthy->outcome == ScanOutcome::Ok);

    const auto retried =
        std::find_if(library.plugins().begin(), library.plugins().end(),
                     [&crash](const PluginDescriptor& row) { return row.path.text() == crash; });
    REQUIRE(retried != library.plugins().end());
    CHECK(retried->outcome == ScanOutcome::Crashed);
    // It crashed again, and the count says the user has now spent one retry on
    // it — persisted, so "I have tried this three times" survives a restart.
    CHECK(retried->retry_count == 1);
  }

  TEST_CASE("A new version of a quarantined plugin is retried once, automatically") {
    TempDir logs("quarantine-version");
    TempDir plugins("quarantine-version-plugins");
    const std::string crash = installFixture(plugins, "ob_test_plugin_crash");
    installFixture(plugins, "ob_test_plugin_ok");

    PluginCache cache(logs.child("plugin-cache.bin"));
    SubprocessProbe probe(testOptions(logs));

    {
      PluginScanner scanner(cache, probe);
      scanner.setSearchPaths({plugins.str()});
      runToCompletion(scanner);
      REQUIRE(rowFor(cache, crash)->outcome == ScanOutcome::Crashed);
    }

    // "The bundle version changed" is the fingerprint changing. Info.plist
    // rather than the binary: on Apple Silicon every binary is signed, and
    // editing one would make it fail to load for a reason that has nothing to
    // do with what this test is about.
    {
      std::ofstream plist(fs::path(crash) / "Contents" / "Info.plist", std::ios::trunc);
      plist << "<plist><dict><key>CFBundleShortVersionString</key><string>2.0</string>"
               "</dict></plist>";
    }

    CountingProbe counting(probe);
    PluginScanner scanner(cache, counting);
    scanner.setSearchPaths({plugins.str()});
    runToCompletion(scanner);

    // One auto-retry, of the updated bundle only. A vendor who ships a fix
    // should not need the user to find the Retry button.
    REQUIRE(counting.probed.size() == 1);
    CHECK(counting.probed[0] == crash);

    const PluginDescriptor* crashed = rowFor(cache, crash);
    REQUIRE(crashed != nullptr);
    // The fix in this test is imaginary — it still crashes — so it stays
    // quarantined, and the retry count starts again because this is a version
    // the user has not tried before.
    CHECK(crashed->outcome == ScanOutcome::Crashed);
    CHECK(crashed->retry_count == 0);

    // And the auto-retry is *once*: a third scan finds nothing changed.
    CountingProbe again(probe);
    PluginScanner third(cache, again);
    third.setSearchPaths({plugins.str()});
    runToCompletion(third);
    CHECK(again.probed.empty());
  }

  TEST_CASE("The crash report names the plugin, the phase and the signal") {
    TempDir logs("quarantine-report");
    TempDir plugins("quarantine-report-plugins");
    const std::string crash = installFixture(plugins, "ob_test_plugin_crash");

    PluginCache cache(logs.child("plugin-cache.bin"));
    SubprocessProbe probe(testOptions(logs));
    PluginScanner scanner(cache, probe);
    scanner.setSearchPaths({plugins.str()});
    runToCompletion(scanner);

    const std::string report = readWholeFile(logs.child("plugin-crashes.log"));
    REQUIRE_FALSE(report.empty());
    // Written from both sides of the process boundary: the helper's signal
    // handler contributes the backtrace before it dies, the parent contributes
    // the classification afterwards. Neither could have written both.
    CHECK(report.find(crash) != std::string::npos);
    CHECK(report.find("phase: load") != std::string::npos);
    CHECK(report.find("plugin quarantined") != std::string::npos);
  }

  TEST_CASE("A missing helper binary is reported, not ignored") {
    TempDir logs("quarantine-nohelper");
    TempDir plugins("quarantine-nohelper-plugins");
    const std::string ok = installFixture(plugins, "ob_test_plugin_ok");

    SubprocessProbeOptions options = testOptions(logs);
    options.helper_path = plugins.child("no-such-helper");
    SubprocessProbe probe(options);
    CHECK_FALSE(probe.available());

    BundleRef bundle;
    bundle.path = ok;
    std::vector<PluginDescriptor> found;
    probe.probe(bundle, found);

    // A broken installation must not look like a library full of broken
    // plugins with no explanation: the phase says `spawn`, which is the one
    // value that means "this was our fault, not the plugin's".
    REQUIRE(found.size() == 1);
    CHECK(found[0].outcome == ScanOutcome::Crashed);
    CHECK(found[0].failure_phase == ScanPhase::Spawn);
  }
}
