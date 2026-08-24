// Non-RT logging, session files and crash groundwork (OB-1-12 §2/§4).
//
// The RT side never comes here — it pushes POD records onto rt::RtLog and this
// class formats and writes them from the housekeeping thread.
#pragma once

#include <cstdint>
#include <cstdio>
#include <mutex>
#include <string>

// MSVC has no `__attribute__((format))`; the checking is a GCC/Clang nicety, so
// it compiles away to nothing there rather than blocking the Windows build.
#if defined(__GNUC__) || defined(__clang__)
#define ONEBEAT_PRINTF_FORMAT(fmt_index, first_arg) \
  __attribute__((format(printf, fmt_index, first_arg)))
#else
#define ONEBEAT_PRINTF_FORMAT(fmt_index, first_arg)
#endif

namespace onebeat::core {

enum class LogLevel : uint8_t { Trace = 0, Debug = 1, Info = 2, Warn = 3, Error = 4 };

class Diagnostics {
 public:
  ~Diagnostics();

  // Non-RT. `directory` empty => ~/Library/Application Support/OneBeat/logs.
  // Keeps the most recent sessions and deletes older ones.
  void open(const std::string& directory);
  void close();

  void log(LogLevel level, const char* category, const std::string& message);
  void logf(LogLevel level, const char* category, const char* format, ...)
      ONEBEAT_PRINTF_FORMAT(4, 5);

  const std::string& sessionLogPath() const { return session_path_; }
  const std::string& directory() const { return directory_; }

  // Writes a marker file that survives SIGKILL of the process; removed on a
  // clean shutdown. A marker present at next launch means the last session
  // died unexpectedly (Stage 3's auto-save recovery reads this).
  void writeRunningMarker();
  void clearRunningMarker();
  bool previousSessionCrashed() const { return previous_session_crashed_; }

  // Installs handlers for the fatal signals so logs are flushed before exit.
  void installCrashHandler();

  static const char* levelName(LogLevel level);
  static std::string defaultLogDirectory();

 private:
  void writeLine(LogLevel level, const char* category, const char* message);

  std::mutex mutex_;
  std::FILE* file_ = nullptr;
  std::string directory_;
  std::string session_path_;
  std::string marker_path_;
  bool previous_session_crashed_ = false;
};

}  // namespace onebeat::core
