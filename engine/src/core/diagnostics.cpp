#include "core/diagnostics.h"

#include <csignal>
#include <cstdarg>
#include <cstdlib>
#include <cstring>
#include <ctime>
#include <filesystem>
#include <vector>

namespace onebeat::core {
namespace {

constexpr int MaxRetainedSessions = 10;

// Set once by installCrashHandler so the signal handler can flush without
// touching anything that needs a lock.
std::FILE* g_crash_flush_target = nullptr;

void crashHandler(int signal_number) {
  if (g_crash_flush_target != nullptr) {
    std::fprintf(g_crash_flush_target, "[FATAL] terminating on signal %d\n", signal_number);
    std::fflush(g_crash_flush_target);
  }
  std::signal(signal_number, SIG_DFL);
  std::raise(signal_number);
}

std::string timestampForFilename() {
  const std::time_t now = std::time(nullptr);
  std::tm parts{};
  localtime_r(&now, &parts);
  char buffer[32];
  std::strftime(buffer, sizeof(buffer), "%Y%m%d-%H%M%S", &parts);
  return buffer;
}

std::string timestampForLine() {
  const std::time_t now = std::time(nullptr);
  std::tm parts{};
  localtime_r(&now, &parts);
  char buffer[32];
  std::strftime(buffer, sizeof(buffer), "%H:%M:%S", &parts);
  return buffer;
}

}  // namespace

Diagnostics::~Diagnostics() {
  close();
}

std::string Diagnostics::defaultLogDirectory() {
  const char* home = std::getenv("HOME");
  const std::string base = home != nullptr ? std::string(home) : std::string("/tmp");
  return base + "/Library/Application Support/OneBeat/logs";
}

void Diagnostics::open(const std::string& directory) {
  std::lock_guard<std::mutex> lock(mutex_);
  directory_ = directory.empty() ? defaultLogDirectory() : directory;

  std::error_code code;
  std::filesystem::create_directories(directory_, code);

  marker_path_ = directory_ + "/session.running";
  previous_session_crashed_ = std::filesystem::exists(marker_path_, code);

  // Retain only the most recent sessions.
  std::vector<std::filesystem::path> logs;
  for (const auto& entry : std::filesystem::directory_iterator(directory_, code)) {
    if (entry.path().extension() == ".log") {
      logs.push_back(entry.path());
    }
  }
  std::sort(logs.begin(), logs.end());
  while (logs.size() >= static_cast<size_t>(MaxRetainedSessions)) {
    std::filesystem::remove(logs.front(), code);
    logs.erase(logs.begin());
  }

  session_path_ = directory_ + "/onebeat-" + timestampForFilename() + ".log";
  file_ = std::fopen(session_path_.c_str(), "we");
  if (file_ != nullptr) {
    writeLine(LogLevel::Info, "session", "log opened");
    if (previous_session_crashed_) {
      writeLine(LogLevel::Warn, "session",
                "the previous session did not shut down cleanly (marker file present)");
    }
  }
}

void Diagnostics::close() {
  std::lock_guard<std::mutex> lock(mutex_);
  if (file_ != nullptr) {
    writeLine(LogLevel::Info, "session", "log closed");
    std::fclose(file_);
    file_ = nullptr;
    g_crash_flush_target = nullptr;
  }
}

const char* Diagnostics::levelName(LogLevel level) {
  switch (level) {
    case LogLevel::Trace:
      return "TRACE";
    case LogLevel::Debug:
      return "DEBUG";
    case LogLevel::Info:
      return "INFO";
    case LogLevel::Warn:
      return "WARN";
    case LogLevel::Error:
      return "ERROR";
  }
  return "INFO";
}

void Diagnostics::writeLine(LogLevel level, const char* category, const char* message) {
  if (file_ == nullptr) {
    return;
  }
  std::fprintf(file_, "%s %-5s [%s] %s\n", timestampForLine().c_str(), levelName(level), category,
               message);
  std::fflush(file_);
}

void Diagnostics::log(LogLevel level, const char* category, const std::string& message) {
  std::lock_guard<std::mutex> lock(mutex_);
  writeLine(level, category, message.c_str());
}

void Diagnostics::logf(LogLevel level, const char* category, const char* format, ...) {
  char buffer[512];
  va_list args;
  va_start(args, format);
  std::vsnprintf(buffer, sizeof(buffer), format, args);
  va_end(args);
  std::lock_guard<std::mutex> lock(mutex_);
  writeLine(level, category, buffer);
}

void Diagnostics::writeRunningMarker() {
  std::lock_guard<std::mutex> lock(mutex_);
  if (marker_path_.empty()) {
    return;
  }
  std::FILE* marker = std::fopen(marker_path_.c_str(), "we");
  if (marker != nullptr) {
    std::fprintf(marker, "%s\n", session_path_.c_str());
    std::fclose(marker);
  }
}

void Diagnostics::clearRunningMarker() {
  std::lock_guard<std::mutex> lock(mutex_);
  if (!marker_path_.empty()) {
    std::error_code code;
    std::filesystem::remove(marker_path_, code);
  }
}

void Diagnostics::installCrashHandler() {
  std::lock_guard<std::mutex> lock(mutex_);
  g_crash_flush_target = file_;
  for (const int signal_number : {SIGSEGV, SIGBUS, SIGILL, SIGFPE, SIGABRT}) {
    std::signal(signal_number, &crashHandler);
  }
}

}  // namespace onebeat::core
