// RT-safe logging (OB-1-12 §1).
//
// The audio thread may not format strings, take locks, or allocate, so it never
// logs text. It pushes a POD record — a message id plus a handful of numeric
// arguments — onto a fixed-size ring. A background thread pops records and
// formats them against a static message table. Overflow drops records and bumps
// a counter rather than blocking; the drop count is surfaced in the snapshot so
// a dropped log is visible rather than silent.
#pragma once

#include <atomic>
#include <cstdint>

#include "core/rt/rt.h"
#include "core/rt/spsc_ring.h"

namespace onebeat::rt {

enum class LogLevel : uint8_t { Trace = 0, Debug = 1, Info = 2, Warn = 3, Error = 4 };

// Message ids are a closed set so the RT side never touches a string. Adding a
// message means adding an id here and a format string in rt_log.cpp.
enum class RtMessage : uint16_t {
  None = 0,
  CallbackStarted = 1,        // a0 = sample rate, a1 = block frames
  Xrun = 2,                   // a0 = render nanos, a1 = budget nanos
  SchedulePicked = 3,         // a0 = schedule generation, a1 = event count
  VoiceStolen = 4,            // a0 = note stolen, a1 = note starting
  TransportStateChanged = 5,  // a0 = playing, a1 = position frames
  DeviceFormatChanged = 6,    // a0 = sample rate, a1 = block frames
  CommandQueueFull = 7,       // a0 = command type
  SampleSwapped = 8,             // a0 = frames, a1 = channels
  EventListFull = 9,             // a0 = events dropped, a1 = list capacity
  InstrumentProcessFailed = 10,  // a0 = port count, a1 = frames
};

struct RtLogRecord {
  uint64_t timestamp_ns;
  uint16_t message;  // RtMessage
  uint8_t level;     // LogLevel
  uint8_t reserved;
  uint32_t sequence;
  int64_t a0;
  int64_t a1;
};
static_assert(sizeof(RtLogRecord) == 32, "RtLogRecord is a frozen POD");

class RtLog {
 public:
  static constexpr size_t Capacity = 1024;

  // Audio thread. Never blocks. Drops (and counts) when the ring is full.
  void log(LogLevel level, RtMessage message, int64_t a0 = 0,
           int64_t a1 = 0) noexcept OB_NONBLOCKING;

  // Drain thread. Returns false when empty.
  bool pop(RtLogRecord& out) noexcept;

  uint64_t droppedCount() const noexcept { return dropped_.load(std::memory_order_relaxed); }

  // Format a drained record into caller-provided storage. Non-RT thread only.
  static void format(const RtLogRecord& record, char* out, size_t out_size) noexcept;
  static const char* messageName(RtMessage message) noexcept;

 private:
  SpscRing<RtLogRecord, Capacity> ring_;
  std::atomic<uint64_t> dropped_{0};
  std::atomic<uint32_t> sequence_{0};
};

}  // namespace onebeat::rt
