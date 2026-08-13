#include "core/schedule.h"
#include "doctest.h"

using onebeat::core::DefaultInstrument;
using onebeat::core::EventType;
using onebeat::core::ScheduleBuilder;

TEST_SUITE("unit") {
  TEST_CASE("Built schedules are time-ordered") {
    ScheduleBuilder builder;
    builder.addNote(DefaultInstrument, 60, 1.0F, 4800, 480);
    builder.addNote(DefaultInstrument, 62, 1.0F, 0, 480);
    builder.addNote(DefaultInstrument, 64, 1.0F, 2400, 480);
    const auto schedule = builder.build(48000.0, 1);

    int64_t previous = -1;
    for (int32_t index = 0; index < schedule->eventCount(); ++index) {
      CHECK(schedule->events()[index].frame >= previous);
      previous = schedule->events()[index].frame;
    }
    CHECK(schedule->eventCount() == 6);
  }

  TEST_CASE("A note-off at the same frame as a note-on is ordered first") {
    // Re-triggering the same note on a step boundary must not have the outgoing
    // note's off kill the incoming note.
    ScheduleBuilder builder;
    builder.addNote(DefaultInstrument, 60, 1.0F, 0, 4800);
    builder.addNote(DefaultInstrument, 60, 1.0F, 4800, 4800);
    const auto schedule = builder.build(48000.0, 1);

    int32_t index = schedule->lowerBound(4800);
    REQUIRE(index < schedule->eventCount());
    CHECK(schedule->events()[index].type == static_cast<uint16_t>(EventType::NoteOff));
    CHECK(schedule->events()[index + 1].type == static_cast<uint16_t>(EventType::NoteOn));
  }

  TEST_CASE("lowerBound finds the first event at or after a frame") {
    ScheduleBuilder builder;
    for (int index = 0; index < 16; ++index) {
      builder.addNote(DefaultInstrument, 60, 1.0F, index * 1000, 500);
    }
    const auto schedule = builder.build(48000.0, 1);

    CHECK(schedule->lowerBound(0) == 0);
    CHECK(schedule->events()[schedule->lowerBound(999)].frame == 1000);
    CHECK(schedule->events()[schedule->lowerBound(1000)].frame == 1000);
    CHECK(schedule->lowerBound(1'000'000) == schedule->eventCount());
  }

  TEST_CASE("Schedule length defaults to the last event when unset") {
    ScheduleBuilder builder;
    builder.addNote(DefaultInstrument, 60, 1.0F, 0, 4800);
    CHECK(builder.build(48000.0, 1)->lengthFrames() == 4800);
  }

  TEST_CASE("Parameter value and modulation remain sample-positioned and distinct") {
    ScheduleBuilder builder;
    builder.addParamValue(DefaultInstrument, 17, 0.25F, 32);
    builder.addParamModulation(DefaultInstrument, 17, 0.5F, 96);
    const auto schedule = builder.build(48000.0, 2);
    REQUIRE(schedule->eventCount() == 2);
    CHECK(schedule->events()[0].frame == 32);
    CHECK(schedule->events()[0].type == static_cast<uint16_t>(EventType::ParamValue));
    CHECK(schedule->events()[0].reserved == 17);
    CHECK(schedule->events()[1].frame == 96);
    CHECK(schedule->events()[1].type == static_cast<uint16_t>(EventType::ParamModulation));
  }

}  // TEST_SUITE
