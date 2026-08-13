// The flattened schedule (ARCHITECTURE.md §7, OB-1-07).
//
// THE rule of this codebase: the audio thread never walks a reference graph.
// Edits mutate the model off-thread, a flattening pass resolves every reference
// into this flat, time-ordered, absolutely-positioned array, and the result is
// published immutably by atomic swap (see rt/publisher.h).
//
// In v0.1 the "model" is a step pattern typed at the ABI, so the flattener is
// trivial — but the *machinery* here is the final one. Stage 3 replaces the
// producer, never the consumer.
#pragma once

#include <cstdint>
#include <memory>
#include <vector>

#include "core/rt/rt.h"

namespace onebeat::core {

using InstrumentId = uint32_t;
inline constexpr InstrumentId DefaultInstrument = 0;

enum class EventType : uint16_t {
  NoteOn = 0,          // value = velocity 0..1
  NoteOff = 1,         // value unused
  TempoChange = 2,     // value = bpm
  ParamValue = 3,      // reserved = ParamId, value is the absolute value
  ParamModulation = 4  // reserved = ParamId, value is a non-destructive offset
};

// POD, 24 bytes, sorted by `frame`. Deliberately cache-friendly: a block scan
// is a linear walk over a contiguous array.
struct ScheduleEvent {
  int64_t frame;            // absolute frames from the schedule origin
  InstrumentId instrument;  // resolved at flatten time, never a pointer chase
  uint16_t type;            // EventType
  int16_t note;             // MIDI note number, -1 where not applicable
  float value;
  uint32_t reserved;
};
static_assert(sizeof(ScheduleEvent) == 24, "ScheduleEvent layout is frozen");

// Immutable after construction. Never mutated once published.
class Schedule {
 public:
  Schedule(std::vector<ScheduleEvent> events, int64_t length_frames, double sample_rate,
           uint64_t generation)
      : events_(std::move(events)),
        length_frames_(length_frames),
        sample_rate_(sample_rate),
        generation_(generation) {}

  const ScheduleEvent* events() const noexcept OB_NONBLOCKING { return events_.data(); }
  int32_t eventCount() const noexcept OB_NONBLOCKING {
    return static_cast<int32_t>(events_.size());
  }
  int64_t lengthFrames() const noexcept OB_NONBLOCKING { return length_frames_; }
  double sampleRate() const noexcept OB_NONBLOCKING { return sample_rate_; }
  uint64_t generation() const noexcept OB_NONBLOCKING { return generation_; }

  // Index of the first event at or after `frame`. Binary search over a sorted
  // array: bounded, branch-predictable, no allocation.
  int32_t lowerBound(int64_t frame) const noexcept OB_NONBLOCKING {
    int32_t low = 0;
    int32_t high = static_cast<int32_t>(events_.size());
    while (low < high) {
      const int32_t mid = low + ((high - low) / 2);
      if (events_[static_cast<size_t>(mid)].frame < frame) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    return low;
  }

 private:
  const std::vector<ScheduleEvent> events_;
  const int64_t length_frames_;
  const double sample_rate_;
  const uint64_t generation_;
};

// Builds schedules off the audio thread. Sorting and allocation live here.
class ScheduleBuilder {
 public:
  ScheduleBuilder& addNote(InstrumentId instrument, int16_t note, float velocity,
                           int64_t start_frame, int64_t duration_frames) {
    events_.push_back(ScheduleEvent{start_frame, instrument,
                                    static_cast<uint16_t>(EventType::NoteOn), note, velocity, 0});
    events_.push_back(ScheduleEvent{start_frame + duration_frames, instrument,
                                    static_cast<uint16_t>(EventType::NoteOff), note, 0.0F, 0});
    return *this;
  }

  // The flattener knows how many events it is about to add; a 200,000-event
  // schedule that grows from nothing reallocates a multi-megabyte buffer twenty
  // times on the way (OB-3-04 budget work).
  ScheduleBuilder& reserve(size_t events) {
    events_.reserve(events);
    return *this;
  }

  ScheduleBuilder& addEvent(const ScheduleEvent& event) {
    events_.push_back(event);
    return *this;
  }

  ScheduleBuilder& addParamValue(InstrumentId instrument, uint32_t param, float value,
                                 int64_t frame) {
    events_.push_back(ScheduleEvent{frame, instrument, static_cast<uint16_t>(EventType::ParamValue),
                                    -1, value, param});
    return *this;
  }

  ScheduleBuilder& addParamModulation(InstrumentId instrument, uint32_t param, float amount,
                                      int64_t frame) {
    events_.push_back(ScheduleEvent{
        frame, instrument, static_cast<uint16_t>(EventType::ParamModulation), -1, amount, param});
    return *this;
  }

  ScheduleBuilder& setLengthFrames(int64_t frames) {
    length_frames_ = frames;
    return *this;
  }

  std::unique_ptr<Schedule> build(double sample_rate, uint64_t generation);

 private:
  std::vector<ScheduleEvent> events_;
  int64_t length_frames_ = 0;
};

}  // namespace onebeat::core
