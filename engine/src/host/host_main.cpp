// `onebeat-plugin-host` — the process that touches third-party code so that
// OneBeat does not (OB-2-03 §1 and §4; ADR-003; OB-2-05 §6).
//
// Today it does one job: `--scan` a single bundle and report what is in it.
// That is deliberately the smallest useful version of the helper ADR-003
// describes. Scanning has no deadline and no audio transport, so none of the
// shared-memory and Mach-semaphore machinery is needed here; OB-2-05 adds the
// processing mode to this same binary, which is why the file is called
// `host_main` rather than `scan_main`.
//
// **The contract this executable exists to keep:** loading a plugin runs code
// nobody in this project wrote, at a moment when the user is doing nothing more
// dangerous than starting a DAW. A licence check that segfaults, a static
// initialiser that deadlocks on a lock file, a binary for the wrong
// architecture — all of these kill whichever process performs the `dlopen`. So
// this process performs it, one bundle at a time, and its death is a data point
// rather than a lost session.
//
// It therefore has to be paranoid about itself:
//   - Records go over an inherited fd, never stdout, because the plugin owns
//     stdout the moment it is loaded (see `scan_protocol.h`).
//   - The phase is announced *before* the risky call, not after.
//   - It exits with `_exit`, so a plugin's `atexit` handlers and static
//     destructors never run and cannot turn a successful scan into a crash.
//   - Its own crash handler writes a backtrace and then re-raises with the
//     default disposition, so the parent still observes the real signal.
#include <dlfcn.h>
#include <execinfo.h>
#include <fcntl.h>
#include <signal.h>
#include <unistd.h>

#include <cerrno>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <string>
#include <vector>

#include "plugin/scan/descriptor.h"
#include "plugin/scan/scan_protocol.h"

namespace {

namespace fs = std::filesystem;
using onebeat::plugin::scan::PluginDescriptor;
using onebeat::plugin::scan::ScanPhase;
using onebeat::plugin::scan::ScanRecordHeader;
using onebeat::plugin::scan::ScanRecordMagic;
using onebeat::plugin::scan::ScanRecordTag;

// --- state the signal handler is allowed to read -----------------------------
//
// Everything here is written before the first risky call and only read from the
// handler. `sig_atomic_t` for the phase; plain buffers for the text, which the
// handler only ever hands to write().
int g_record_fd = onebeat::plugin::scan::ScanPipeFd;
int g_crash_fd = -1;
volatile sig_atomic_t g_phase = static_cast<sig_atomic_t>(ScanPhase::Spawn);
char g_bundle[1024] = {};

// write() can return short and can be interrupted. Both are ordinary here: the
// parent reads at its own pace, and a watchdog timer fires SIGALRM-adjacent
// interruptions in the general case.
bool writeAll(int fd, const void* data, size_t size) {
  const char* cursor = static_cast<const char*>(data);
  size_t remaining = size;
  while (remaining > 0) {
    const ssize_t written = ::write(fd, cursor, remaining);
    if (written < 0) {
      if (errno == EINTR) {
        continue;
      }
      return false;
    }
    cursor += written;
    remaining -= static_cast<size_t>(written);
  }
  return true;
}

bool writeRecord(ScanRecordTag tag, const void* payload, size_t size) {
  ScanRecordHeader header{};
  header.magic = ScanRecordMagic;
  header.tag = static_cast<uint32_t>(tag);
  header.size = static_cast<uint32_t>(size);
  header.reserved = 0;
  if (!writeAll(g_record_fd, &header, sizeof(header))) {
    return false;
  }
  return size == 0 || writeAll(g_record_fd, payload, size);
}

void announce(ScanPhase phase) {
  g_phase = static_cast<sig_atomic_t>(phase);
  const uint32_t value = static_cast<uint32_t>(phase);
  writeRecord(ScanRecordTag::Phase, &value, sizeof(value));
}

// --- the crash handler -------------------------------------------------------

// Async-signal-safe integer formatting. `snprintf` is not on the safe list and
// this needs to work on a stack that a plugin has just corrupted.
void writeUnsigned(int fd, unsigned value) {
  char digits[20];
  size_t length = 0;
  do {
    digits[length++] = static_cast<char>('0' + (value % 10U));
    value /= 10U;
  } while (value != 0 && length < sizeof(digits));
  char reversed[20];
  for (size_t i = 0; i < length; ++i) {
    reversed[i] = digits[length - 1 - i];
  }
  writeAll(fd, reversed, length);
}

void writeLiteral(int fd, const char* text) {
  writeAll(fd, text, std::strlen(text));
}

// Writes what OB-2-03 §4 asks for — plugin path, phase, and a stack if one can
// be had — then lets the signal kill us for real.
//
// Re-raising rather than `_exit`ing is the important part: the parent
// classifies the failure from the wait status, and an exit code would turn a
// segfault into "the helper decided to stop", which is a different and much
// less useful thing to tell a user.
extern "C" void crashHandler(int signal_number) {
  if (g_crash_fd >= 0) {
    writeLiteral(g_crash_fd, "\n--- plugin scan crash ---\nplugin: ");
    writeLiteral(g_crash_fd, g_bundle);
    writeLiteral(g_crash_fd, "\nphase: ");
    writeLiteral(g_crash_fd, onebeat::plugin::scan::scanPhaseName(static_cast<ScanPhase>(g_phase)));
    writeLiteral(g_crash_fd, "\nsignal: ");
    writeUnsigned(g_crash_fd, static_cast<unsigned>(signal_number));
    writeLiteral(g_crash_fd, "\nbacktrace:\n");
    // `backtrace_symbols_fd` is the only variant that does not allocate, which
    // is why it is the one used here. The frames are the plugin's, which is
    // exactly what a vendor bug report needs.
    void* frames[64];
    const int depth = ::backtrace(frames, 64);
    ::backtrace_symbols_fd(frames, depth, g_crash_fd);
    writeLiteral(g_crash_fd, "\n");
    ::fsync(g_crash_fd);
  }

  struct sigaction restore = {};
  restore.sa_handler = SIG_DFL;
  ::sigaction(signal_number, &restore, nullptr);
  ::raise(signal_number);
}

void installCrashHandlers() {
  // SIGABRT is in the list because a plugin that fails an assertion or throws
  // through a `noexcept` boundary arrives that way, and it is a crash from the
  // user's point of view no matter how tidily it was reached.
  const int signals[] = {SIGSEGV, SIGBUS, SIGILL, SIGFPE, SIGABRT, SIGTRAP};
  for (const int number : signals) {
    struct sigaction action = {};
    action.sa_handler = crashHandler;
    action.sa_flags = SA_RESETHAND;
    // Unqualified: on Darwin `sigemptyset` is a macro, so `::sigemptyset` does
    // not compile.
    sigemptyset(&action.sa_mask);
    ::sigaction(number, &action, nullptr);
  }
}

// --- CLAP entry point, minimally ---------------------------------------------

// The first 24 bytes of `clap_plugin_entry_t`, which is all this ticket needs.
// Declared here rather than vendoring the CLAP headers because nothing is
// *called* through it: OB-2-07 vendors the SDK and replaces this outright.
// Reading the version is enough to distinguish "a CLAP bundle" from "a dylib
// that happens to live in the CLAP folder".
struct ClapEntryPrefix {
  uint32_t clap_version_major;
  uint32_t clap_version_minor;
  uint32_t clap_version_revision;
  bool (*init)(const char* plugin_path);
  void (*deinit)();
  const void* (*get_factory)(const char* factory_id);
};

// A bundle is a directory with the binary inside it; CLAP also allows a bare
// dylib. Mirrors `fingerprintBundle`'s rule — first regular file in
// Contents/MacOS — rather than assuming the conventional name, because a bundle
// is free to name its executable anything.
std::string binaryInside(const std::string& bundle_path) {
  std::error_code code;
  const fs::path bundle(bundle_path);
  const fs::directory_entry root(bundle, code);
  if (code) {
    return std::string();
  }
  if (!root.is_directory(code)) {
    return bundle_path;
  }
  fs::directory_iterator it(bundle / "Contents" / "MacOS", code);
  if (code) {
    return std::string();
  }
  for (const fs::directory_entry& entry : it) {
    if (entry.is_regular_file(code)) {
      return entry.path().string();
    }
  }
  return std::string();
}

int usage() {
  writeLiteral(STDERR_FILENO,
               "usage: onebeat-plugin-host --scan <bundle> [--crash-log <file>] [--pipe-fd <n>]\n");
  return 2;
}

}  // namespace

int main(int argc, char** argv) {
  std::string bundle_path;
  std::string crash_log_path;

  for (int i = 1; i < argc; ++i) {
    const std::string argument(argv[i]);
    const bool has_value = i + 1 < argc;
    if (argument == "--scan" && has_value) {
      bundle_path = argv[++i];
    } else if (argument == "--crash-log" && has_value) {
      crash_log_path = argv[++i];
    } else if (argument == "--pipe-fd" && has_value) {
      g_record_fd = std::atoi(argv[++i]);
    } else {
      return usage();
    }
  }
  if (bundle_path.empty()) {
    return usage();
  }

  std::strncpy(g_bundle, bundle_path.c_str(), sizeof(g_bundle) - 1);
  if (!crash_log_path.empty()) {
    g_crash_fd = ::open(crash_log_path.c_str(), O_WRONLY | O_CREAT | O_APPEND | O_CLOEXEC, 0644);
  }
  installCrashHandlers();

  const std::string binary = binaryInside(bundle_path);
  if (binary.empty()) {
    // Nothing to load: an empty bundle, or one whose layout we do not
    // recognise. Not a crash, and not this process's business to editorialise
    // about — the parent records `NotAPlugin` from the absence of descriptors.
    announce(ScanPhase::Done);
    writeRecord(ScanRecordTag::Done, nullptr, 0);
    ::_exit(0);
  }

  // Everything from here can take the process down, and that is the point.
  announce(ScanPhase::Load);
  // RTLD_LOCAL so two bundles that export the same symbol cannot see each
  // other's; RTLD_NOW so a missing symbol fails here, in the phase the user is
  // told about, rather than at some later call.
  void* handle = ::dlopen(binary.c_str(), RTLD_NOW | RTLD_LOCAL);
  if (handle == nullptr) {
    writeLiteral(STDERR_FILENO, "dlopen failed: ");
    const char* error = ::dlerror();
    writeLiteral(STDERR_FILENO, error != nullptr ? error : "unknown");
    writeLiteral(STDERR_FILENO, "\n");
    announce(ScanPhase::Done);
    writeRecord(ScanRecordTag::Done, nullptr, 0);
    ::_exit(0);
  }

  announce(ScanPhase::Enumerate);
  const void* symbol = ::dlsym(handle, "clap_entry");
  std::vector<PluginDescriptor> found;
  if (symbol != nullptr) {
    const ClapEntryPrefix* entry = static_cast<const ClapEntryPrefix*>(symbol);
    // Only CLAP 1.x. A 0.x or 2.x entry point is a bundle we cannot host, and
    // guessing would mean calling function pointers whose signatures we do not
    // know — which is a crash with extra steps.
    if (entry->clap_version_major == 1 && entry->get_factory != nullptr) {
      PluginDescriptor descriptor;
      const std::string stem = fs::path(bundle_path).stem().string();
      descriptor.name.assign(stem.c_str());
      // Still not the plugin's real id: reading that means calling `init` and
      // walking the factory, which is OB-2-07's job and another crash surface.
      // The row is honestly marked as not introspected.
      descriptor.id.assign(bundle_path.c_str());
      descriptor.flags = onebeat::plugin::scan::DescriptorFlagNone;
      descriptor.failure_phase = ScanPhase::None;
      found.push_back(descriptor);
    }
  }

  for (const PluginDescriptor& descriptor : found) {
    writeRecord(ScanRecordTag::Descriptor, &descriptor, sizeof(descriptor));
  }
  announce(ScanPhase::Done);
  writeRecord(ScanRecordTag::Done, nullptr, 0);

  // No `dlclose`, no `return`. The plugin's static destructors and `atexit`
  // handlers are as capable of crashing as its initialisers were, and there is
  // nothing left to gain from running them: the results are already down the
  // pipe, and the kernel reclaims everything a moment from now.
  ::_exit(0);
}
