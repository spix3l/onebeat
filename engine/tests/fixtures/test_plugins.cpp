// The three plugins OB-2-03 needs in order to be tested at all.
//
// A quarantine feature cannot be demonstrated against real plugins: the ones
// that crash do so on somebody else's machine, at somebody else's version, and
// a test that depends on that is not a test. So the failures are built here, in
// the repository, as real `.clap` bundles that the real helper really `dlopen`s
// (`engine/tests/CMakeLists.txt` assembles them).
//
// **They crash from a static initialiser on purpose.** That is not a contrived
// choice — it is where scan crashes actually happen, because `dlopen` runs a
// plugin's constructors, its licence check and its dongle probe before any host
// code gets a say. A test plugin that crashed in a function we called would be
// testing a much easier problem.
//
// One file, three targets, selected by a macro so the harmless parts stay
// identical between them.
#include <cstdint>

#if defined(OB_TEST_PLUGIN_HANG)
#include <time.h>
#endif

// `__attribute__((constructor))` rather than a static initialiser with a side
// effect: an unused constant's initialiser is something the optimiser is
// entitled to delete, and a "crashing" plugin that quietly loads would make
// this whole test file lie. A constructor function is the same dyld hook a real
// plugin's global objects run through, and it cannot be elided.
#if defined(OB_TEST_PLUGIN_CRASH)

// A null store through a volatile pointer. The volatile is what stops the
// compiler from replacing the undefined behaviour with something cheaper —
// including nothing at all.
__attribute__((constructor)) void obTestCrashOnLoad() {
  volatile int* nowhere = nullptr;
  *nowhere = 1;
}

#elif defined(OB_TEST_PLUGIN_HANG)

// Never returns, so `dlopen` never returns, so the helper is wedged with the
// dyld lock held — the shape of a real licence check waiting on a dongle that
// is not there. Nothing short of SIGKILL gets us out of it, which is why the
// watchdog sends SIGKILL.
__attribute__((constructor)) void obTestHangOnLoad() {
  while (true) {
    const timespec interval{1, 0};
    nanosleep(&interval, nullptr);
  }
}

#endif

// The prefix of `clap_plugin_entry_t`. Matches `ClapEntryPrefix` in the helper;
// both are replaced by the vendored CLAP headers in OB-2-07.
struct TestClapEntry {
  uint32_t clap_version_major;
  uint32_t clap_version_minor;
  uint32_t clap_version_revision;
  bool (*init)(const char* plugin_path);
  void (*deinit)();
  const void* (*get_factory)(const char* factory_id);
};

extern "C" {

bool obTestInit(const char*) {
  return true;
}
void obTestDeinit() {}
const void* obTestGetFactory(const char*) {
  return nullptr;
}

// Exported by all three, including the ones that never reach the point of being
// asked for it: the crash and hang fixtures are otherwise valid CLAP bundles,
// which is what makes them a fair test of the helper rather than of its
// argument parsing.
//
// `extern` is load-bearing. A namespace-scope `const` object has *internal*
// linkage in C++ unless it says otherwise, so without it this symbol would not
// be exported and `dlsym` would find nothing — the bundle would scan as
// "not a plugin" and the happy-path test would fail for a reason unrelated to
// anything it is testing. Real CLAP plugins written in C++ carry the same
// `extern`.
extern __attribute__((visibility("default"))) const TestClapEntry clap_entry;
const TestClapEntry clap_entry = {
    1, 2, 0, obTestInit, obTestDeinit, obTestGetFactory,
};

}  // extern "C"
