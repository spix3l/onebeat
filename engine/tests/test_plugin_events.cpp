// The event model (OB-2-01 scope §3).
//
// These are the invariants the whole hosting layer will lean on: fixed layout,
// wildcard addressing, a list that never allocates, and a sort that is stable
// at equal timestamps. The last one is not a nicety — an unstable sort turns a
// note-off/note-on retrigger at the same frame into a hanging note.
#include <array>

#include "doctest.h"
#include "plugin/event.h"

using onebeat::plugin::AnyChannel;
using onebeat::plugin::AnyKey;
using onebeat::plugin::AnyNote;
using onebeat::plugin::AnyPort;
using onebeat::plugin::EventList;
using onebeat::plugin::EventListView;
using onebeat::plugin::EventType;
using onebeat::plugin::NoteExpressionId;
using onebeat::plugin::PluginEvent;

TEST_SUITE("unit") {
  TEST_CASE("The event layout is frozen and trivially copyable") {
    CHECK(sizeof(PluginEvent) == 40);
    CHECK(std::is_trivially_copyable_v<PluginEvent>);
    // A default-constructed event addresses nothing and does nothing.
    const PluginEvent empty;
    CHECK(empty.kind() == EventType::None);
    CHECK(empty.note_id == AnyNote);
  }

  TEST_CASE("Note factories fill the address tuple") {
    const PluginEvent on = PluginEvent::noteOn(64, 60, 0.8, 7, 3, 1);
    CHECK(on.kind() == EventType::NoteOn);
    CHECK(on.time == 64);
    CHECK(on.key == 60);
    CHECK(on.value() == doctest::Approx(0.8));
    CHECK(on.note_id == 7);
    CHECK(on.channel == 3);
    CHECK(on.port_index == 1);
  }

  TEST_CASE("Wildcards match anything, which is how 'all notes off' is expressed") {
    const PluginEvent panic = PluginEvent::allNotesOff(0);
    CHECK(panic.kind() == EventType::NoteOff);
    CHECK(panic.key == AnyKey);
    CHECK(panic.channel == AnyChannel);
    CHECK(panic.port_index == AnyPort);
    CHECK(panic.note_id == AnyNote);
    CHECK(panic.matchesNote(1, 0, 0, 60));
    CHECK(panic.matchesNote(99, 3, 15, 21));

    // A specific note-off matches only its own voice.
    const PluginEvent one = PluginEvent::noteOff(0, 60, 0.0, 5, 2, 1);
    CHECK(one.matchesNote(5, 1, 2, 60));
    CHECK_FALSE(one.matchesNote(6, 1, 2, 60));  // wrong note id
    CHECK_FALSE(one.matchesNote(5, 1, 2, 61));  // wrong key
    CHECK_FALSE(one.matchesNote(5, 0, 2, 60));  // wrong port
  }

  TEST_CASE("Modulation and value are different events carrying different meanings") {
    const PluginEvent value = PluginEvent::paramValue(0, 42, 0.5);
    const PluginEvent modulation = PluginEvent::paramModulation(0, 42, -0.25);
    CHECK(value.kind() == EventType::ParamValue);
    CHECK(modulation.kind() == EventType::ParamModulation);
    CHECK(value.id == 42);
    CHECK(modulation.id == 42);
    CHECK(modulation.value() == doctest::Approx(-0.25));
    // Modulation is note-addressable; a plain value change is not scoped.
    CHECK(modulation.note_id == AnyNote);
  }

  TEST_CASE("Note expression carries its identifier in the id field") {
    const PluginEvent event =
        PluginEvent::noteExpression(12, NoteExpressionId::Tuning, -1.5, 3, 60, 0, 0);
    CHECK(event.kind() == EventType::NoteExpression);
    CHECK(event.id == static_cast<uint32_t>(NoteExpressionId::Tuning));
    CHECK(event.value() == doctest::Approx(-1.5));
    CHECK(event.note_id == 3);
  }

  TEST_CASE("MIDI passthrough keeps the bytes opaque") {
    const PluginEvent event = PluginEvent::midi1(0, 0x90, 60, 100);
    CHECK(event.kind() == EventType::Midi1);
    CHECK(event.payload.midi1[0] == 0x90);
    CHECK(event.payload.midi1[1] == 60);
    CHECK(event.payload.midi1[2] == 100);

    const std::array<uint8_t, 4> dump = {0xF0, 0x7E, 0x00, 0xF7};
    const PluginEvent sysex = PluginEvent::midiSysex(0, dump.data(), static_cast<uint32_t>(dump.size()));
    CHECK(sysex.id == 4);  // length rides in `id`; the bytes are borrowed
    CHECK(sysex.payload.sysex == dump.data());
  }

  TEST_CASE("The event list never grows: overflow is dropped and counted") {
    std::array<PluginEvent, 4> storage{};
    EventList list(storage.data(), static_cast<uint32_t>(storage.size()));

    for (int index = 0; index < 4; ++index) {
      CHECK(list.push(PluginEvent::noteOn(0, static_cast<int16_t>(index), 1.0)));
    }
    CHECK(list.size() == 4);
    CHECK(list.overflowCount() == 0);

    // The fifth is refused rather than reallocating on the audio thread.
    CHECK_FALSE(list.push(PluginEvent::noteOn(0, 99, 1.0)));
    CHECK(list.size() == 4);
    CHECK(list.overflowCount() == 1);
    CHECK(list[3].key == 3);  // the earlier events survive intact

    list.clear();
    CHECK(list.size() == 0);
    CHECK(list.overflowCount() == 0);
  }

  TEST_CASE("Sorting by time is stable, so same-frame ordering survives") {
    std::array<PluginEvent, 8> storage{};
    EventList list(storage.data(), static_cast<uint32_t>(storage.size()));

    // Interleaved arrival: a command at frame 0, then schedule events. The
    // note-off and note-on at frame 100 must keep this order — reversed, the
    // note-on is immediately cancelled and the note never sounds.
    list.push(PluginEvent::noteOn(0, 40, 1.0));
    list.push(PluginEvent::noteOff(100, 60));
    list.push(PluginEvent::noteOn(100, 60, 1.0));
    list.push(PluginEvent::noteOff(50, 40));
    list.push(PluginEvent::noteOn(100, 67, 1.0));

    list.sortByTime();

    CHECK(list[0].time == 0);
    CHECK(list[1].time == 50);
    CHECK(list[2].time == 100);
    CHECK(list[2].kind() == EventType::NoteOff);
    CHECK(list[2].key == 60);
    CHECK(list[3].kind() == EventType::NoteOn);
    CHECK(list[3].key == 60);
    CHECK(list[4].key == 67);  // third event at frame 100 stays third
  }

  TEST_CASE("lowerBound finds the first event at or after a frame") {
    std::array<PluginEvent, 4> storage{};
    EventList list(storage.data(), static_cast<uint32_t>(storage.size()));
    list.push(PluginEvent::noteOn(0, 60, 1.0));
    list.push(PluginEvent::noteOn(10, 61, 1.0));
    list.push(PluginEvent::noteOn(10, 62, 1.0));
    list.push(PluginEvent::noteOn(30, 63, 1.0));

    const EventListView view = list.view();
    CHECK(view.lowerBound(0) == 0);
    CHECK(view.lowerBound(1) == 1);
    CHECK(view.lowerBound(10) == 1);  // the *first* of the pair at 10
    CHECK(view.lowerBound(11) == 3);
    CHECK(view.lowerBound(31) == 4);  // past the end
  }

  TEST_CASE("An empty view is safe to walk") {
    const EventListView view;
    CHECK(view.empty());
    CHECK(view.size() == 0);
    CHECK(view.begin() == view.end());
    CHECK(view.lowerBound(0) == 0);
  }
}  // TEST_SUITE
