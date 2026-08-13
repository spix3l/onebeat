#include "core/rt/rt_log.h"

#include <cinttypes>
#include <cstdio>
#include <iterator>

namespace onebeat::rt {
namespace {

struct MessageSpec {
  RtMessage id;
  const char* name;
  const char* format;  // consumes a0 then a1
};

// One table, drained off the audio thread. Keep entries in enum order.
constexpr MessageSpec Messages[] = {
    {RtMessage::None, "none", "(none) a0=%" PRId64 " a1=%" PRId64},
    {RtMessage::CallbackStarted, "callback_started",
     "audio callback started: %" PRId64 " Hz, %" PRId64 " frames"},
    {RtMessage::Xrun, "xrun", "xrun: render took %" PRId64 " ns, budget %" PRId64 " ns"},
    {RtMessage::SchedulePicked, "schedule_picked",
     "picked up schedule generation %" PRId64 " with %" PRId64 " events"},
    {RtMessage::VoiceStolen, "voice_stolen", "stole voice on note %" PRId64 " for note %" PRId64},
    {RtMessage::TransportStateChanged, "transport_state_changed",
     "transport playing=%" PRId64 " at frame %" PRId64},
    {RtMessage::DeviceFormatChanged, "device_format_changed",
     "device format now %" PRId64 " Hz, %" PRId64 " frames"},
    {RtMessage::CommandQueueFull, "command_queue_full",
     "command queue full, dropped command type %" PRId64 " (a1=%" PRId64 ")"},
    {RtMessage::SampleSwapped, "sample_swapped",
     "sample swapped in: %" PRId64 " frames, %" PRId64 " channels"},
    {RtMessage::EventListFull, "event_list_full",
     "instrument event list full, dropped %" PRId64 " events (capacity %" PRId64 ")"},
    {RtMessage::InstrumentProcessFailed, "instrument_process_failed",
     "instrument process() returned Error (a0=%" PRId64 " a1=%" PRId64 ")"},
};

const MessageSpec& specFor(RtMessage message) noexcept {
  const auto index = static_cast<size_t>(message);
  if (index < std::size(Messages) && Messages[index].id == message) {
    return Messages[index];
  }
  return Messages[0];
}

}  // namespace

void RtLog::log(LogLevel level, RtMessage message, int64_t a0, int64_t a1) noexcept OB_NONBLOCKING {
  RtLogRecord record{};
  record.timestamp_ns = monotonicNanos();
  record.message = static_cast<uint16_t>(message);
  record.level = static_cast<uint8_t>(level);
  record.sequence = sequence_.fetch_add(1, std::memory_order_relaxed);
  record.a0 = a0;
  record.a1 = a1;
  if (!ring_.tryPush(record)) {
    dropped_.fetch_add(1, std::memory_order_relaxed);
  }
}

bool RtLog::pop(RtLogRecord& out) noexcept {
  return ring_.tryPop(out);
}

const char* RtLog::messageName(RtMessage message) noexcept {
  return specFor(message).name;
}

void RtLog::format(const RtLogRecord& record, char* out, size_t out_size) noexcept {
  const MessageSpec& spec = specFor(static_cast<RtMessage>(record.message));
  std::snprintf(out, out_size, spec.format, record.a0, record.a1);
}

}  // namespace onebeat::rt
