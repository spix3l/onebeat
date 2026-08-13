#include "model/flattener.h"

#include <algorithm>
#include <chrono>
#include <cstring>

#include "core/time_map.h"

namespace onebeat::model {
namespace {

// A note resolved onto the timeline but still in ticks: absolute position,
// absolute end, and the instrument it belongs to. Collected first, then
// de-overlapped, then converted — because the overlap rule (below) is a
// statement about musical time, not about frames.
struct ResolvedNote {
  Ticks start = 0;
  Ticks end = 0;
  core::InstrumentId instrument = 0;
  int16_t key = 0;
  float velocity = 0.0F;
};

struct ResolvedParam {
  Ticks position = 0;
  core::InstrumentId instrument = 0;
  uint32_t parameter = 0;
  float value = 0.0F;
};

// Which lanes are allowed to fire. Lane mute is an **event gate** (D-M4): the
// clips on it are not scheduled at all, which is a different thing from the
// mixer's audio gate and is why the two have different names in the UI.
std::vector<ArrangementLaneId> audibleLanes(const Project& project) {
  bool any_solo = false;
  for (const auto& [id, lane] : project.lanes()) {
    if (lane.soloed) any_solo = true;
  }

  std::vector<ArrangementLaneId> audible;
  for (const auto& [id, lane] : project.lanes()) {
    if (lane.muted) continue;
    if (any_solo && !lane.soloed) continue;
    audible.push_back(id);
  }
  return audible;
}

// Occurrences of one source note inside one clip, in clip-relative ticks.
//
// The source position advances continuously from `window_start` and, when the
// clip loops, wraps modulo the pattern length. A note is truncated at the end
// of the pattern rather than allowed to sound across a loop boundary: the next
// iteration re-triggers it, and a note that bled across would either double or
// hang depending on the plugin. Same rule at the clip's end (scope §2).
void collectOccurrences(const Note& note, const Clip& clip, Ticks pattern_length,
                        std::vector<std::pair<Ticks, Ticks>>& out) {
  out.clear();
  if (pattern_length <= 0 || clip.length <= 0 || note.length <= 0) return;

  const Ticks window = clip.transforms.window_start;

  if (!clip.transforms.loop) {
    // One pass from the window: anything before it never plays.
    const Ticks offset = note.start - window;
    if (offset < 0 || offset >= clip.length) return;
    const Ticks end =
        std::min({offset + note.length, clip.length, offset + (pattern_length - note.start)});
    if (end > offset) out.emplace_back(offset, end);
    return;
  }

  // Looping: the first occurrence is wherever this note falls in the first
  // wrapped pass, then once per pattern length until the clip ends.
  Ticks first = ((note.start - window) % pattern_length + pattern_length) % pattern_length;
  for (Ticks position = first; position < clip.length; position += pattern_length) {
    const Ticks truncated_by_pattern = pattern_length - note.start;
    const Ticks end =
        std::min({position + note.length, position + truncated_by_pattern, clip.length});
    if (end > position) out.emplace_back(position, end);
  }
}

// Two occurrences of the same (instrument, key) overlapping — stacked clips,
// or a pattern placed twice on top of itself — are resolved by **the later
// note-on cutting the earlier note**: the earlier note's off moves to the
// later note's on. Every alternative is worse: dropping the later note loses
// an edit the user made, and letting both run leaves the note-off ambiguous
// and, on most plugins, hanging.
void resolveOverlaps(std::vector<ResolvedNote>& notes) {
  std::sort(notes.begin(), notes.end(), [](const ResolvedNote& a, const ResolvedNote& b) {
    if (a.instrument != b.instrument) return a.instrument < b.instrument;
    if (a.key != b.key) return a.key < b.key;
    if (a.start != b.start) return a.start < b.start;
    return a.end < b.end;
  });

  for (size_t i = 0; i + 1 < notes.size(); ++i) {
    ResolvedNote& current = notes[i];
    const ResolvedNote& next = notes[i + 1];
    if (current.instrument != next.instrument || current.key != next.key) continue;
    if (next.start < current.end) current.end = next.start;
  }

  // A note cut to nothing by an identical note starting at the same tick is
  // not a note. Removing it here keeps the schedule free of zero-length pairs.
  notes.erase(std::remove_if(notes.begin(), notes.end(),
                             [](const ResolvedNote& note) { return note.end <= note.start; }),
              notes.end());
}

// FNV-1a over 64-bit words rather than bytes. A large project is ~200,000
// events — 4.6 MB — and hashing that a byte at a time cost more than the rest
// of the flatten put together. `ScheduleEvent` is a frozen 24-byte POD with no
// padding (see core/schedule.h), so reading it as three words is well-defined
// and stable.
uint64_t hashEvents(const core::ScheduleEvent* events, int32_t count, int64_t length) {
  uint64_t state = 0xCBF29CE484222325ULL;
  const auto mix = [&state](uint64_t word) {
    state ^= word;
    state *= 0x100000001B3ULL;
  };
  static_assert(sizeof(core::ScheduleEvent) == 24);
  for (int32_t i = 0; i < count; ++i) {
    uint64_t words[3];
    std::memcpy(words, &events[i], sizeof(words));
    mix(words[0]);
    mix(words[1]);
    mix(words[2]);
  }
  mix(static_cast<uint64_t>(length));
  return state;
}

}  // namespace

FlattenResult flatten(const Project& project, const FlattenOptions& options) {
  const auto started = std::chrono::steady_clock::now();

  FlattenResult result;

  // Dense instrument indices, assigned in ULID order so the mapping is a pure
  // function of the model.
  core::InstrumentId next_index = 0;
  for (const auto& [id, instrument] : project.instruments()) {
    result.instrument_index.emplace(id, next_index++);
  }

  const core::TimeMap time_map(options.sample_rate, project.transport().tempo);
  const auto toFrames = [&time_map](Ticks ticks) {
    return time_map.beatsToFrames(static_cast<double>(ticks) /
                                  static_cast<double>(TicksPerQuarter));
  };

  std::vector<ResolvedNote> notes;
  // One allocation growth curve instead of twenty: a large arrangement resolves
  // to hundreds of thousands of notes, and the reallocation was measurable.
  size_t note_estimate = 0;
  for (const auto& [pattern_id, pattern] : project.patterns()) {
    for (const auto& [instrument_id, sequence] : pattern.sequences) {
      note_estimate += sequence.size();
    }
  }
  notes.reserve(note_estimate * (project.clips().empty() ? 1 : 2));

  std::vector<ResolvedParam> params;
  std::vector<std::pair<Ticks, Ticks>> occurrences;
  Ticks end_ticks = 0;

  for (const ArrangementLaneId lane_id : audibleLanes(project)) {
    for (const ClipId clip_id : project.clipsOnLane(lane_id)) {
      const Clip* clip = project.findClip(clip_id);
      if (clip == nullptr || clip->muted || clip->length <= 0) continue;
      end_ticks = std::max(end_ticks, clip->start + clip->length);

      if (const PatternSource* source = clip->pattern()) {
        const Pattern* pattern = project.findPattern(source->pattern);
        if (pattern == nullptr) continue;
        const Ticks pattern_length = pattern->length > 0          ? pattern->length
                                     : pattern->sequences.empty() ? 0
                                                                  : 1;
        if (pattern_length <= 0) continue;

        ++result.clips_flattened;
        for (const auto& [instrument_id, sequence] : pattern->sequences) {
          const Instrument* instrument = project.findInstrument(instrument_id);
          if (instrument == nullptr || instrument->muted) continue;
          const auto index = result.instrument_index.find(instrument_id);
          if (index == result.instrument_index.end()) continue;

          for (const Note& note : sequence.notes()) {
            // Non-destructive transform, applied here and never to the stored
            // note (D-M3): the pattern is untouched and every other placement
            // of it is unaffected.
            const int32_t key = note.key + clip->transforms.transpose;
            if (key < 0 || key > 127) {
              ++result.notes_dropped;
              continue;
            }

            collectOccurrences(note, *clip, pattern_length, occurrences);
            for (const auto& [start, end] : occurrences) {
              ResolvedNote resolved;
              resolved.start = clip->start + start;
              resolved.end = clip->start + end;
              resolved.instrument = index->second;
              resolved.key = static_cast<int16_t>(key);
              resolved.velocity = velocityToUnit(note.velocity);
              notes.push_back(resolved);
            }
          }
        }
        continue;
      }

      if (const AutomationSource* source = clip->automation()) {
        // Structural (scope §4): the points a curve is made of become the
        // parameter events of OB-2-09. Stage 4 adds interpolation between
        // them; the path from clip to plugin parameter is proven now.
        if (source->target_kind != AutomationSource::TargetKind::Instrument) continue;
        const auto index = result.instrument_index.find(source->instrument);
        if (index == result.instrument_index.end()) continue;
        ++result.clips_flattened;
        for (const AutomationPoint& point : source->points) {
          if (point.position < 0 || point.position >= clip->length) continue;
          params.push_back(ResolvedParam{clip->start + point.position, index->second,
                                         source->parameter, point.value});
        }
      }
      // Audio clips have no note or parameter events; they arrive with the
      // audio engine in Stage 9 and are skipped rather than half-handled.
    }
  }

  resolveOverlaps(notes);

  core::ScheduleBuilder builder;
  builder.reserve((notes.size() * 2) + params.size());
  for (const ResolvedNote& note : notes) {
    const int64_t start_frame = toFrames(note.start);
    const int64_t end_frame = toFrames(note.end);
    // A note whose two ends round to the same frame would be a note-on and a
    // note-off in the same sample; give it one frame so it is audible at all.
    const int64_t duration = std::max<int64_t>(1, end_frame - start_frame);
    builder.addNote(note.instrument, note.key, note.velocity, start_frame, duration);
  }
  std::sort(params.begin(), params.end(), [](const ResolvedParam& a, const ResolvedParam& b) {
    if (a.position != b.position) return a.position < b.position;
    if (a.instrument != b.instrument) return a.instrument < b.instrument;
    return a.parameter < b.parameter;
  });
  for (const ResolvedParam& param : params) {
    builder.addParamValue(param.instrument, param.parameter, param.value, toFrames(param.position));
  }

  result.length_frames = toFrames(end_ticks);
  builder.setLengthFrames(result.length_frames);
  result.schedule = builder.build(options.sample_rate, options.generation);
  result.event_count = static_cast<size_t>(result.schedule->eventCount());

  result.hash =
      hashEvents(result.schedule->events(), result.schedule->eventCount(), result.length_frames);

  result.elapsed_ms =
      std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - started).count();
  return result;
}

FlattenScheduler::FlattenScheduler(Project& project) : project_(project) {
  // Every change dirties the schedule. Which changes *cannot* affect it (a
  // rename, a colour) is knowable from the field, and skipping those is the
  // first optimisation to make if the budget is ever missed — but guessing
  // wrong means an edit that does not play, so v0.3 re-flattens on everything.
  token_ = project_.changes().subscribe([this](const ChangeEvent&) { dirty_ = true; });
}

FlattenScheduler::~FlattenScheduler() {
  project_.changes().unsubscribe(token_);
}

FlattenResult FlattenScheduler::flushIfDirty(double sample_rate) {
  if (!dirty_) return FlattenResult{};

  FlattenOptions options;
  options.sample_rate = sample_rate;
  options.generation = ++generation_;
  FlattenResult result = flatten(project_, options);
  dirty_ = false;
  return result;
}

}  // namespace onebeat::model
