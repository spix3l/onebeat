#include "core/schedule.h"

#include <algorithm>

namespace onebeat::core {

std::unique_ptr<Schedule> ScheduleBuilder::build(double sample_rate, uint64_t generation) {
  // Stable sort so that events written at the same frame keep insertion order:
  // a note-off written before a note-on at the same frame must stay first, or a
  // re-trigger at a step boundary would kill the note it just started.
  std::stable_sort(events_.begin(), events_.end(),
                   [](const ScheduleEvent& lhs, const ScheduleEvent& rhs) {
                     if (lhs.frame != rhs.frame) {
                       return lhs.frame < rhs.frame;
                     }
                     return lhs.type > rhs.type;  // NoteOff (1) before NoteOn (0)
                   });

  int64_t length = length_frames_;
  if (length <= 0 && !events_.empty()) {
    length = events_.back().frame;
  }
  return std::make_unique<Schedule>(std::move(events_), length, sample_rate, generation);
}

}  // namespace onebeat::core
