#include "plugin/scan/subprocess_probe.h"

#include <dlfcn.h>
#include <poll.h>
#include <signal.h>
#include <spawn.h>
#include <sys/wait.h>
#include <unistd.h>

#include <array>
#include <cerrno>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <ctime>
#include <filesystem>
#include <system_error>
#include <thread>

#include "core/diagnostics.h"
#include "plugin/scan/scan_protocol.h"

extern "C" char** environ;

namespace onebeat::plugin::scan {
namespace {

namespace fs = std::filesystem;

constexpr const char* HelperFileName = "onebeat-plugin-host";

// A data symbol to hand `dladdr`, purely so the lookup below needs no
// function-pointer-to-`void*` cast — which is conditionally supported at best
// and rejected outright by `-Wpedantic -Werror`, which this build uses.
const char ImageAnchor = 0;
constexpr const char* CrashLogFileName = "plugin-crashes.log";

// A ceiling on what the helper is allowed to say. The pipe is inherited by the
// plugin as well as by our code, so a plugin that writes to file descriptor 3 —
// deliberately or by reusing a descriptor it never opened — is writing into
// this stream. The magic and the size bound below are what stop that from being
// anything worse than a bundle that fails to scan.
constexpr size_t MaxStreamBytes = size_t{4} * 1024 * 1024;

// What we learned from one helper run.
struct HelperResult {
  std::vector<PluginDescriptor> descriptors;
  ScanPhase phase = ScanPhase::Spawn;
  bool saw_done = false;
  bool stream_ok = true;
  bool timed_out = false;
  bool spawn_failed = false;
  int wait_status = 0;
};

int64_t nowUnixNanos() noexcept {
  return std::chrono::duration_cast<std::chrono::nanoseconds>(
             std::chrono::system_clock::now().time_since_epoch())
      .count();
}

bool exists(const std::string& path) {
  if (path.empty()) {
    return false;
  }
  std::error_code code;
  return fs::exists(fs::path(path), code) && !code;
}

// Consumes as many complete records as `buffer` holds, leaving any partial one
// at the front. Returns false the moment the stream stops making sense, which
// the caller treats exactly like a crash: we do not know what the helper found,
// so we must not pretend we do.
bool consumeRecords(std::vector<char>& buffer, HelperResult& result) {
  size_t offset = 0;
  while (buffer.size() - offset >= sizeof(ScanRecordHeader)) {
    ScanRecordHeader header{};
    std::memcpy(&header, buffer.data() + offset, sizeof(header));
    if (header.magic != ScanRecordMagic) {
      return false;
    }
    if (header.size > ScanDescriptorSize) {
      return false;
    }
    const size_t total = sizeof(header) + header.size;
    if (buffer.size() - offset < total) {
      break;  // partial record; wait for more
    }
    const char* payload = buffer.data() + offset + sizeof(header);

    switch (static_cast<ScanRecordTag>(header.tag)) {
      case ScanRecordTag::Phase: {
        if (header.size != sizeof(uint32_t)) {
          return false;
        }
        uint32_t phase = 0;
        std::memcpy(&phase, payload, sizeof(phase));
        if (phase > static_cast<uint32_t>(ScanPhase::Done)) {
          return false;
        }
        result.phase = static_cast<ScanPhase>(phase);
        break;
      }
      case ScanRecordTag::Descriptor: {
        if (header.size != ScanDescriptorSize) {
          return false;
        }
        PluginDescriptor descriptor;
        std::memcpy(&descriptor, payload, sizeof(descriptor));
        result.descriptors.push_back(descriptor);
        break;
      }
      case ScanRecordTag::Done:
        result.saw_done = true;
        break;
      default:
        return false;
    }
    offset += total;
  }
  buffer.erase(buffer.begin(), buffer.begin() + static_cast<std::ptrdiff_t>(offset));
  return true;
}

// Runs the helper once, to completion or to the watchdog, whichever comes
// first. Everything about the child's fate is in the returned struct;
// interpretation is the caller's.
HelperResult runHelper(const std::string& helper, const std::string& bundle,
                       const std::string& crash_log, std::chrono::milliseconds timeout) {
  HelperResult result;

  int fds[2] = {-1, -1};
  if (::pipe(fds) != 0) {
    result.spawn_failed = true;
    return result;
  }

  posix_spawn_file_actions_t actions;
  posix_spawn_file_actions_init(&actions);
  // The child talks on ScanPipeFd and nothing else. Its stdout and stderr stay
  // inherited on purpose: a plugin's own complaints are worth seeing in a
  // terminal, and they cannot corrupt anything now that the records are
  // elsewhere.
  //
  // **The order of these three actions is load-bearing**, because file actions
  // run in sequence and `pipe()` hands back the two lowest free descriptors —
  // which in a process that has only stdin, stdout and stderr open means
  // exactly 3 and 4. Closing the read end *after* the dup2 would therefore
  // close the descriptor the dup2 had just created, and the child would write
  // its results into a closed fd. That is not a hypothetical: it is what this
  // code did first, and every bundle scanned as though it had crashed.
  posix_spawn_file_actions_addclose(&actions, fds[0]);
  posix_spawn_file_actions_adddup2(&actions, fds[1], ScanPipeFd);
  if (fds[1] != ScanPipeFd) {
    posix_spawn_file_actions_addclose(&actions, fds[1]);
  }

  const std::string pipe_argument = std::to_string(ScanPipeFd);
  std::vector<std::string> arguments{helper, "--scan", bundle, "--pipe-fd", pipe_argument};
  if (!crash_log.empty()) {
    arguments.emplace_back("--crash-log");
    arguments.push_back(crash_log);
  }
  std::vector<char*> argv;
  argv.reserve(arguments.size() + 1);
  for (std::string& argument : arguments) {
    argv.push_back(argument.data());
  }
  argv.push_back(nullptr);

  // `posix_spawn` rather than fork+exec: the scanner runs on a background
  // thread of a process that owns an audio device, and fork() in a
  // multi-threaded process gives a child in which almost nothing is legal to
  // call. posix_spawn does the unsafe part inside libc, correctly.
  pid_t pid = -1;
  const int spawned = ::posix_spawn(&pid, helper.c_str(), &actions, nullptr, argv.data(), environ);
  posix_spawn_file_actions_destroy(&actions);
  ::close(fds[1]);
  if (spawned != 0) {
    ::close(fds[0]);
    result.spawn_failed = true;
    return result;
  }

  std::vector<char> buffer;
  std::array<char, 4096> chunk{};
  size_t total_read = 0;
  const auto deadline = std::chrono::steady_clock::now() + timeout;

  while (true) {
    const auto now = std::chrono::steady_clock::now();
    if (now >= deadline) {
      result.timed_out = true;
      break;
    }
    const auto remaining =
        std::chrono::duration_cast<std::chrono::milliseconds>(deadline - now).count();

    pollfd descriptor{};
    descriptor.fd = fds[0];
    descriptor.events = POLLIN;
    const int ready = ::poll(&descriptor, 1, static_cast<int>(remaining) + 1);
    if (ready < 0) {
      if (errno == EINTR) {
        continue;
      }
      result.stream_ok = false;
      break;
    }
    if (ready == 0) {
      result.timed_out = true;
      break;
    }

    const ssize_t bytes = ::read(fds[0], chunk.data(), chunk.size());
    if (bytes < 0) {
      if (errno == EINTR) {
        continue;
      }
      result.stream_ok = false;
      break;
    }
    if (bytes == 0) {
      break;  // the helper closed the pipe: it exited, one way or another
    }
    total_read += static_cast<size_t>(bytes);
    if (total_read > MaxStreamBytes) {
      result.stream_ok = false;
      break;
    }
    buffer.insert(buffer.end(), chunk.data(), chunk.data() + bytes);
    if (!consumeRecords(buffer, result)) {
      result.stream_ok = false;
      break;
    }
  }
  ::close(fds[0]);

  // The watchdog covers the child's *lifetime*, not just its talkativeness.
  //
  // Reaching EOF on the pipe is not the same as the helper having exited: a
  // plugin that closes file descriptors it did not open — or simply hangs after
  // our last record — leaves a child that will never be reaped. A blocking
  // `waitpid` there turns a hung plugin into a hung scan, which is the exact
  // failure this ticket exists to prevent. So the wait is bounded too, and
  // anything still alive at the deadline is killed.
  bool reaped = false;
  while (!reaped && std::chrono::steady_clock::now() < deadline && !result.timed_out) {
    const pid_t done = ::waitpid(pid, &result.wait_status, WNOHANG);
    if (done == pid) {
      reaped = true;
    } else if (done < 0 && errno != EINTR) {
      break;
    } else if (done == 0) {
      std::this_thread::sleep_for(std::chrono::milliseconds(1));
    }
  }
  if (!reaped) {
    // A helper killed for talking nonsense keeps that classification; one
    // killed merely for still being here at the deadline is a hang, which is a
    // different sentence to the user.
    if (result.stream_ok) {
      result.timed_out = true;
    }
    // SIGKILL, not SIGTERM: a process wedged inside a plugin's static
    // initialiser is in no state to run a handler, and a polite signal it
    // ignores buys nothing.
    ::kill(pid, SIGKILL);
    // Now safe to block: SIGKILL cannot be caught, blocked or ignored, so this
    // returns as soon as the kernel has torn the process down.
    while (::waitpid(pid, &result.wait_status, 0) < 0 && errno == EINTR) {
    }
  }
  return result;
}

// The parent's half of the crash report (OB-2-03 §4). The helper's own handler
// wrote the backtrace before it died; this adds what only the parent can know —
// that it died, how, and whether it was killed by the watchdog rather than by
// a fault.
void appendCrashContext(const std::string& crash_log, const std::string& bundle,
                        const PluginDescriptor& descriptor) {
  if (crash_log.empty()) {
    return;
  }
  std::FILE* file = std::fopen(crash_log.c_str(), "ae");
  if (file == nullptr) {
    return;
  }
  const std::time_t when = std::time(nullptr);
  char stamp[64] = "unknown time";
  std::tm broken{};
  if (::localtime_r(&when, &broken) != nullptr) {
    std::strftime(stamp, sizeof(stamp), "%Y-%m-%d %H:%M:%S", &broken);
  }
  std::fprintf(file,
               "\n--- plugin quarantined ---\nwhen: %s\nplugin: %s\noutcome: %s\nphase: %s\n"
               "signal: %u\nexit: %u\n",
               stamp, bundle.c_str(), outcomeName(descriptor.outcome),
               scanPhaseName(descriptor.failure_phase),
               static_cast<unsigned>(descriptor.failure_signal),
               static_cast<unsigned>(descriptor.failure_exit_code));
  std::fclose(file);
}

}  // namespace

std::string SubprocessProbe::discoverHelperPath() {
  // 1. An explicit override. Tests use it, and so does anyone debugging a
  //    helper built somewhere other than where the dylib lives.
  const char* override_path = std::getenv("OB_PLUGIN_HOST");
  if (override_path != nullptr && override_path[0] != '\0') {
    return std::string(override_path);
  }

  // 2. Next to the engine dylib. `dladdr` on one of our own symbols answers
  //    "where am I loaded from", which is the only reliable way to find a
  //    sibling file: the working directory belongs to the app, and
  //    `argv[0]` belongs to whatever launched it.
  Dl_info info{};
  if (::dladdr(&ImageAnchor, &info) != 0 && info.dli_fname != nullptr) {
    const fs::path self(info.dli_fname);
    const fs::path directory = self.parent_path();
    std::string sibling = (directory / HelperFileName).string();
    if (exists(sibling)) {
      return sibling;
    }
    // 3. A shipped bundle. The helper owns native editor windows, so macOS
    //    requires it to have its own application bundle and bundle identity.
    const std::string helper_app = (directory / ".." / "Helpers" / "onebeat-plugin-host.app" /
                                    "Contents" / "MacOS" / HelperFileName)
                                       .string();
    if (exists(helper_app)) {
      return helper_app;
    }
    // Legacy/developer bundle layout, kept as a recovery fallback.
    const std::string bundled = (directory / ".." / "MacOS" / HelperFileName).string();
    if (exists(bundled)) {
      return bundled;
    }
  }
  return std::string();
}

SubprocessProbe::SubprocessProbe(SubprocessProbeOptions options, core::Diagnostics* diagnostics)
    : options_(std::move(options)), diagnostics_(diagnostics) {
  if (options_.helper_path.empty()) {
    options_.helper_path = discoverHelperPath();
  }
}

bool SubprocessProbe::available() const {
  return exists(options_.helper_path);
}

void SubprocessProbe::probe(const BundleRef& bundle, std::vector<PluginDescriptor>& out) {
  const std::string crash_log =
      options_.crash_log_directory.empty()
          ? std::string()
          : (fs::path(options_.crash_log_directory) / CrashLogFileName).string();

  const HelperResult result =
      runHelper(options_.helper_path, bundle.path, crash_log, options_.timeout);

  // A clean run: the helper announced Done, exited 0, and the stream parsed.
  // Only then are its descriptors believed.
  const bool exited_cleanly = WIFEXITED(result.wait_status) && WEXITSTATUS(result.wait_status) == 0;
  if (!result.spawn_failed && !result.timed_out && result.stream_ok && result.saw_done &&
      exited_cleanly) {
    for (const PluginDescriptor& descriptor : result.descriptors) {
      out.push_back(descriptor);
    }
    return;
  }

  // Everything else is a quarantine. One row, named after the bundle so the UI
  // has something to call it, carrying why.
  PluginDescriptor quarantined;
  quarantined.name.assign(fs::path(bundle.path).stem().string().c_str());
  quarantined.id.assign(bundle.path.c_str());
  quarantined.path.assign(bundle.path.c_str());
  quarantined.format = bundle.format;
  quarantined.fingerprint = bundle.fingerprint;
  quarantined.scanned_at_nanos = nowUnixNanos();
  quarantined.failure_phase = result.phase;

  if (result.spawn_failed) {
    // Our fault, not the plugin's: the helper is missing or unrunnable. Still
    // recorded against the bundle, because that is what the user sees, but the
    // phase says `spawn` and the log line below says whose problem it is.
    quarantined.outcome = ScanOutcome::Crashed;
    quarantined.failure_phase = ScanPhase::Spawn;
  } else if (result.timed_out) {
    quarantined.outcome = ScanOutcome::TimedOut;
  } else {
    quarantined.outcome = ScanOutcome::Crashed;
    if (WIFSIGNALED(result.wait_status)) {
      quarantined.failure_signal = static_cast<uint8_t>(WTERMSIG(result.wait_status));
    }
    if (WIFEXITED(result.wait_status)) {
      quarantined.failure_exit_code = static_cast<uint8_t>(WEXITSTATUS(result.wait_status));
    }
    // A helper that exited 0 without saying Done is still a crash: under a
    // sanitizer the runtime intercepts the fault and exits by itself, and a
    // truncated stream means we do not know what the bundle contains. Silence
    // is not consent.
  }

  appendCrashContext(crash_log, bundle.path, quarantined);
  if (diagnostics_ != nullptr) {
    diagnostics_->logf(core::LogLevel::Warn, "plugin-scan",
                       "quarantined %s: %s during %s (signal %u, exit %u)", bundle.path.c_str(),
                       outcomeName(quarantined.outcome), scanPhaseName(quarantined.failure_phase),
                       static_cast<unsigned>(quarantined.failure_signal),
                       static_cast<unsigned>(quarantined.failure_exit_code));
  }
  out.push_back(quarantined);
}

}  // namespace onebeat::plugin::scan
