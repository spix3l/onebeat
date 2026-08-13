// The unified, time-stamped, in-block event list (OB-2-01 scope §3).
//
// One event type for every format. It is modelled on CLAP's event set because
// CLAP is the only one of the three that can express audio-rate non-destructive
// modulation and per-note expression; those are represented here as first-class
// events, and the VST3/AU adapters (Stage 5) down-map into them rather than the
// model up-casting to meet them. Down-mappings live in the adapters and are
// documented there, never smuggled into this file.
//
// Two structural choices differ from CLAP, both deliberate:
//
//  1. **Fixed-size events, not variable-size.** CLAP events carry a `size` in
//     their header and the list is walked by pointer arithmetic. Here every
//     event is the same 40 bytes, so a list is a plain contiguous array: a block
//     scan is a linear walk with no indirection, exactly like `ScheduleEvent`.
//     The cost is that MIDI 2.0 UMP is the largest payload we must fit; it does.
//  2. **Transport is not an event.** It travels in `ProcessBlock` (as CLAP's
//     `clap_process.transport` does), with a `TransportDiscontinuity` event
//     marking the *frame* of a jump. See plugin_instance.h.
#pragma once

#include <cstdint>
#include <vector>

#include "core/rt/rt.h"
#include "plugin/plugin_types.h"

namespace onebeat::plugin {

enum class EventType : uint16_t {
  None = 0,

  // --- notes ---
  NoteOn = 1,
  NoteOff = 2,
  // The voice must die *now* without a release stage — a voice was stolen, or
  // the sound is being cut for a live-recording punch. Distinct from NoteOff
  // because a release tail is musically wrong in both cases.
  NoteChoke = 3,
  // Plugin → host: this voice has finished, its `note_id` may be recycled and
  // any per-note modulation state for it can be dropped. Only ever an *output*
  // event; a host that ignores it leaks per-note automation state.
  NoteEnd = 4,

  // Per-note continuous control (CLAP note expression). Sub-addressed by
  // `expression`, valued in `value`. MPE maps into this; VST3 note expression
  // maps into this; AU has no equivalent and the adapter documents the loss.
  NoteExpression = 5,

  // --- parameters ---
  // Destructive: this *is* the new value, and it is what gets recorded.
  ParamValue = 6,
  // Non-destructive offset applied on top of the value, per CLAP. The value the
  // user sees and the project saves is unchanged; the plugin adds `value` to it
  // for as long as the modulation stands. This is the capability D5 exists to
  // preserve — VST3 and AU adapters collapse it onto ParamValue and say so.
  ParamModulation = 7,
  // Bracket a user gesture so the host records one undo step and knows when a
  // touch-latch automation pass begins and ends.
  ParamGestureBegin = 8,
  ParamGestureEnd = 9,

  // --- transport ---
  // The transport jumped, looped or changed tempo at this frame. The full
  // transport state is in ProcessBlock; this only marks the seam so a plugin can
  // reset a delay line or re-sync an LFO sample-accurately.
  TransportDiscontinuity = 10,

  // --- MIDI passthrough ---
  // Kept opaque on purpose: a plugin that wants MIDI semantics should get the
  // bytes we were given, not our interpretation of them.
  Midi1 = 11,
  Midi2 = 12,
  MidiSysex = 13,
};

// CLAP's note expression identifiers, with CLAP's value ranges.
enum class NoteExpressionId : uint32_t {
  Volume = 0,     // 0 .. 4  (linear gain, 1 = nominal)
  Pan = 1,        // 0 .. 1  (0.5 = centre)
  Tuning = 2,     // -120 .. +120 semitones
  Vibrato = 3,    // 0 .. 1
  Expression = 4, // 0 .. 1
  Brightness = 5, // 0 .. 1
  Pressure = 6,   // 0 .. 1
};

enum EventFlags : uint16_t {
  EventFlagNone = 0,
  // The value came from a live performance (a knob, a controller) rather than
  // from playback of recorded automation.
  EventFlagIsLive = 1U << 0U,
  // Do not record this into automation even though it is live.
  EventFlagDontRecord = 1U << 1U,
};

// One event. 40 bytes, POD, trivially copyable, no pointers except the sysex
// payload — which the producer guarantees to keep alive for the duration of the
// process() call and no longer.
struct PluginEvent {
  // Frames from the start of the block this list belongs to. Never absolute:
  // absolute time lives in the Schedule, and the flattener resolves it.
  uint32_t time = 0;
  uint16_t type = static_cast<uint16_t>(EventType::None);
  uint16_t flags = EventFlagNone;

  // The note address. All four accept wildcards, and a wildcarded NoteOff is
  // how "all notes off" is expressed — the model has no panic event, matching
  // CLAP exactly.
  NoteId note_id = AnyNote;
  int16_t port_index = AnyPort;
  int16_t channel = AnyChannel;
  int16_t key = AnyKey;
  int16_t reserved = 0;

  // ParamId for parameter events, NoteExpressionId for expression events, the
  // sysex byte count for MidiSysex, unused otherwise.
  uint32_t id = 0;

  union Payload {
    double number;          // velocity, parameter value, modulation amount, expression value
    const uint8_t* sysex;   // MidiSysex only; `id` holds the length
    uint8_t midi1[4];       // status + 2 data bytes
    uint32_t midi2[4];      // one UMP packet
  } payload = {0.0};

  EventType kind() const noexcept OB_NONBLOCKING { return static_cast<EventType>(type); }
  double value() const noexcept OB_NONBLOCKING { return payload.number; }

  // Does this event address the given concrete note? Wildcards match anything,
  // which is what makes a single event able to mean "every voice".
  bool matchesNote(NoteId id_to_match, int16_t port, int16_t channel_to_match,
                   int16_t key_to_match) const noexcept OB_NONBLOCKING {
    return (note_id == AnyNote || note_id == id_to_match) &&
           (port_index == AnyPort || port_index == port) &&
           (channel == AnyChannel || channel == channel_to_match) &&
           (key == AnyKey || key == key_to_match);
  }

  // --- factories -----------------------------------------------------------
  // Named rather than aggregate-initialised so that a caller cannot silently
  // put a velocity where a modulation amount belongs.

  static PluginEvent noteOn(uint32_t time_frames, int16_t key_value, double velocity,
                            NoteId note = AnyNote, int16_t channel_value = 0,
                            int16_t port = 0) noexcept OB_NONBLOCKING {
    return makeNote(EventType::NoteOn, time_frames, key_value, velocity, note, channel_value, port);
  }

  static PluginEvent noteOff(uint32_t time_frames, int16_t key_value, double velocity = 0.0,
                             NoteId note = AnyNote, int16_t channel_value = 0,
                             int16_t port = 0) noexcept OB_NONBLOCKING {
    return makeNote(EventType::NoteOff, time_frames, key_value, velocity, note, channel_value, port);
  }

  static PluginEvent noteChoke(uint32_t time_frames, int16_t key_value, NoteId note = AnyNote,
                               int16_t channel_value = AnyChannel,
                               int16_t port = AnyPort) noexcept OB_NONBLOCKING {
    return makeNote(EventType::NoteChoke, time_frames, key_value, 0.0, note, channel_value, port);
  }

  // Release every sounding voice. A fully wildcarded note-off, per CLAP.
  static PluginEvent allNotesOff(uint32_t time_frames) noexcept OB_NONBLOCKING {
    return makeNote(EventType::NoteOff, time_frames, AnyKey, 0.0, AnyNote, AnyChannel, AnyPort);
  }

  static PluginEvent noteEnd(uint32_t time_frames, int16_t key_value, NoteId note,
                             int16_t channel_value = 0, int16_t port = 0) noexcept OB_NONBLOCKING {
    return makeNote(EventType::NoteEnd, time_frames, key_value, 0.0, note, channel_value, port);
  }

  static PluginEvent noteExpression(uint32_t time_frames, NoteExpressionId expression, double value,
                                    NoteId note = AnyNote, int16_t key_value = AnyKey,
                                    int16_t channel_value = AnyChannel,
                                    int16_t port = AnyPort) noexcept OB_NONBLOCKING {
    PluginEvent event = makeNote(EventType::NoteExpression, time_frames, key_value, value, note,
                                 channel_value, port);
    event.id = static_cast<uint32_t>(expression);
    return event;
  }

  static PluginEvent paramValue(uint32_t time_frames, ParamId param, double value,
                                uint16_t event_flags = EventFlagNone) noexcept OB_NONBLOCKING {
    return makeParam(EventType::ParamValue, time_frames, param, value, event_flags);
  }

  // Per-note parameter value: the same parameter, scoped to one voice. Only
  // legal for parameters flagged modulatable/automatable per note.
  static PluginEvent paramValueForNote(uint32_t time_frames, ParamId param, double value,
                                       NoteId note, int16_t key_value = AnyKey,
                                       int16_t channel_value = AnyChannel,
                                       int16_t port = AnyPort) noexcept OB_NONBLOCKING {
    PluginEvent event = makeParam(EventType::ParamValue, time_frames, param, value, EventFlagNone);
    event.note_id = note;
    event.key = key_value;
    event.channel = channel_value;
    event.port_index = port;
    return event;
  }

  static PluginEvent paramModulation(uint32_t time_frames, ParamId param, double amount,
                                     NoteId note = AnyNote, int16_t key_value = AnyKey,
                                     int16_t channel_value = AnyChannel,
                                     int16_t port = AnyPort) noexcept OB_NONBLOCKING {
    PluginEvent event =
        makeParam(EventType::ParamModulation, time_frames, param, amount, EventFlagNone);
    event.note_id = note;
    event.key = key_value;
    event.channel = channel_value;
    event.port_index = port;
    return event;
  }

  static PluginEvent paramGesture(uint32_t time_frames, ParamId param,
                                  bool begin) noexcept OB_NONBLOCKING {
    return makeParam(begin ? EventType::ParamGestureBegin : EventType::ParamGestureEnd,
                      time_frames, param, 0.0, EventFlagNone);
  }

  static PluginEvent transportDiscontinuity(uint32_t time_frames) noexcept OB_NONBLOCKING {
    PluginEvent event;
    event.time = time_frames;
    event.type = static_cast<uint16_t>(EventType::TransportDiscontinuity);
    return event;
  }

  static PluginEvent midi1(uint32_t time_frames, uint8_t status, uint8_t data1, uint8_t data2,
                           int16_t port = 0) noexcept OB_NONBLOCKING {
    PluginEvent event;
    event.time = time_frames;
    event.type = static_cast<uint16_t>(EventType::Midi1);
    event.port_index = port;
    event.payload.midi1[0] = status;
    event.payload.midi1[1] = data1;
    event.payload.midi1[2] = data2;
    event.payload.midi1[3] = 0;
    return event;
  }

  // `bytes` must outlive the process() call that receives this event. The model
  // never copies sysex: a 64 KB dump has no business in a fixed-size event, and
  // the producer already owns a buffer.
  static PluginEvent midiSysex(uint32_t time_frames, const uint8_t* bytes, uint32_t size,
                               int16_t port = 0) noexcept OB_NONBLOCKING {
    PluginEvent event;
    event.time = time_frames;
    event.type = static_cast<uint16_t>(EventType::MidiSysex);
    event.port_index = port;
    event.id = size;
    event.payload.sysex = bytes;
    return event;
  }

 private:
  static PluginEvent makeNote(EventType kind_value, uint32_t time_frames, int16_t key_value,
                              double value, NoteId note, int16_t channel_value,
                              int16_t port) noexcept OB_NONBLOCKING {
    PluginEvent event;
    event.time = time_frames;
    event.type = static_cast<uint16_t>(kind_value);
    event.note_id = note;
    event.key = key_value;
    event.channel = channel_value;
    event.port_index = port;
    event.payload.number = value;
    return event;
  }

  static PluginEvent makeParam(EventType kind_value, uint32_t time_frames, ParamId param,
                               double value, uint16_t event_flags) noexcept OB_NONBLOCKING {
    PluginEvent event;
    event.time = time_frames;
    event.type = static_cast<uint16_t>(kind_value);
    event.flags = event_flags;
    event.id = param;
    event.payload.number = value;
    return event;
  }
};

static_assert(sizeof(PluginEvent) == 40, "PluginEvent layout is frozen (see docs/clap-coverage.md)");

// --------------------------------------------------------------------------
// Lists
// --------------------------------------------------------------------------

// A read-only, time-ordered window onto someone else's events. This is what a
// plugin sees in `ProcessBlock::in_events`: it can walk it and binary-search it,
// and it cannot alter or outlive it.
class EventListView {
 public:
  EventListView() = default;
  EventListView(const PluginEvent* events, uint32_t count) noexcept
      : events_(events), count_(count) {}

  uint32_t size() const noexcept OB_NONBLOCKING { return count_; }
  bool empty() const noexcept OB_NONBLOCKING { return count_ == 0; }
  const PluginEvent& operator[](uint32_t index) const noexcept OB_NONBLOCKING {
    return events_[index];
  }
  const PluginEvent* begin() const noexcept OB_NONBLOCKING { return events_; }
  const PluginEvent* end() const noexcept OB_NONBLOCKING { return events_ + count_; }

  // Index of the first event at or after `time`. The list is sorted, so this is
  // the same bounded binary search the schedule uses.
  uint32_t lowerBound(uint32_t time) const noexcept OB_NONBLOCKING {
    uint32_t low = 0;
    uint32_t high = count_;
    while (low < high) {
      const uint32_t mid = low + ((high - low) / 2U);
      if (events_[mid].time < time) {
        low = mid + 1U;
      } else {
        high = mid;
      }
    }
    return low;
  }

 private:
  const PluginEvent* events_ = nullptr;
  uint32_t count_ = 0;
};

// A writable list over **borrowed** storage. The audio thread fills one of these
// every block and never allocates: capacity is fixed at prepare() time, and an
// overflow drops the event and bumps a counter rather than growing. A silently
// resizing container on the audio thread is the classic way an RT invariant dies
// six months after it was written.
class EventList {
 public:
  EventList() = default;
  EventList(PluginEvent* storage, uint32_t capacity) noexcept
      : events_(storage), capacity_(capacity) {}

  bool push(const PluginEvent& event) noexcept OB_NONBLOCKING {
    if (count_ >= capacity_) {
      ++overflow_;
      return false;
    }
    events_[count_] = event;
    ++count_;
    return true;
  }

  void clear() noexcept OB_NONBLOCKING {
    count_ = 0;
    overflow_ = 0;
  }

  uint32_t size() const noexcept OB_NONBLOCKING { return count_; }
  uint32_t capacity() const noexcept OB_NONBLOCKING { return capacity_; }
  // Non-zero means events were lost this block. Surfaced rather than swallowed:
  // dropped events are inaudible until they are not.
  uint32_t overflowCount() const noexcept OB_NONBLOCKING { return overflow_; }

  PluginEvent& operator[](uint32_t index) noexcept OB_NONBLOCKING { return events_[index]; }
  const PluginEvent& operator[](uint32_t index) const noexcept OB_NONBLOCKING {
    return events_[index];
  }

  EventListView view() const noexcept OB_NONBLOCKING { return EventListView(events_, count_); }

  // Insertion sort, in place, no allocation, **stable** — two events at the same
  // frame keep the order they were pushed in, which is the difference between a
  // note-off/note-on retrigger working and a hanging note. Events arrive very
  // nearly sorted (one merge of schedule order and command order), so this is
  // linear in practice and never worse than the tiny lists it runs on.
  void sortByTime() noexcept OB_NONBLOCKING {
    for (uint32_t index = 1; index < count_; ++index) {
      const PluginEvent key = events_[index];
      uint32_t position = index;
      while (position > 0 && events_[position - 1U].time > key.time) {
        events_[position] = events_[position - 1U];
        --position;
      }
      events_[position] = key;
    }
  }

 private:
  PluginEvent* events_ = nullptr;
  uint32_t capacity_ = 0;
  uint32_t count_ = 0;
  uint32_t overflow_ = 0;
};

// Owns the storage an EventList borrows. Resized only on a non-RT thread, at
// prepare() time, exactly like AudioBufferPool.
class EventBuffer {
 public:
  // Non-RT thread only.
  void reserve(uint32_t capacity) {
    storage_.assign(capacity, PluginEvent{});
    capacity_ = capacity;
  }

  // Audio thread. Hands out an empty list over the reserved storage.
  EventList list() noexcept OB_NONBLOCKING { return EventList(storage_.data(), capacity_); }

  uint32_t capacity() const noexcept OB_NONBLOCKING { return capacity_; }

 private:
  std::vector<PluginEvent> storage_;
  uint32_t capacity_ = 0;
};

}  // namespace onebeat::plugin
