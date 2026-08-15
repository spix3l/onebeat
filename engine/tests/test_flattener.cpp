// The flattener (OB-3-04): model → schedule.
//
// At 120 BPM and 48 kHz one tick is exactly 25 frames, so every expectation in
// this file is hand-computable: a bar is 3,840 ticks and 96,000 frames. That is
// deliberate — a windowing test whose expected values come out of the code it
// is testing proves nothing.
#include <algorithm>
#include <string>
#include <vector>

#include "doctest.h"
#include "model/command.h"
#include "model/commands.h"
#include "model/flattener.h"
#include "model/project.h"
#include "test_helpers.h"
#include "testing/offline_driver.h"

using onebeat::core::EventType;
using onebeat::core::Schedule;
using onebeat::core::ScheduleEvent;
using onebeat::model::ArrangementLane;
using onebeat::model::ArrangementLaneId;
using onebeat::model::AudioSource;
using onebeat::model::AutomationPoint;
using onebeat::model::AutomationSource;
using onebeat::model::ChangeField;
using onebeat::model::Clip;
using onebeat::model::ClipId;
using onebeat::model::flatten;
using onebeat::model::FlattenOptions;
using onebeat::model::FlattenResult;
using onebeat::model::FlattenScheduler;
using onebeat::model::IdGenerator;
using onebeat::model::Instrument;
using onebeat::model::InstrumentId;
using onebeat::model::Note;
using onebeat::model::NoteSequence;
using onebeat::model::PatternId;
using onebeat::model::PatternSource;
using onebeat::model::PluginFormat;
using onebeat::model::PluginRef;
using onebeat::model::Project;
using onebeat::model::Ticks;
using onebeat::model::TicksPerBarFourFour;
using onebeat::model::velocityFromMidi1;
using onebeat::testing::renderOffline;
using onebeat::tests::command;
using onebeat::tests::makeOfflineEngine;

namespace {

constexpr double SampleRate = 48000.0;
constexpr int64_t FramesPerTick = 25;  // 120 BPM, 48 kHz

PluginRef claps(const std::string& id) {
  PluginRef plugin;
  plugin.format = PluginFormat::Clap;
  plugin.id = id;
  return plugin;
}

Note note(Ticks start, int16_t key, Ticks length = 240) {
  Note value;
  value.start = start;
  value.length = length;
  value.key = key;
  value.velocity = velocityFromMidi1(100);
  return value;
}

FlattenResult run(const Project& project, uint64_t generation = 1) {
  FlattenOptions options;
  options.sample_rate = SampleRate;
  options.generation = generation;
  return flatten(project, options);
}

std::vector<ScheduleEvent> eventsOf(const Schedule& schedule) {
  return std::vector<ScheduleEvent>(schedule.events(), schedule.events() + schedule.eventCount());
}

std::vector<int64_t> onsets(const Schedule& schedule) {
  std::vector<int64_t> frames;
  for (const ScheduleEvent& event : eventsOf(schedule)) {
    if (event.type == static_cast<uint16_t>(EventType::NoteOn)) frames.push_back(event.frame);
  }
  return frames;
}

std::vector<int64_t> ticksOfOnsets(const Schedule& schedule) {
  std::vector<int64_t> ticks;
  for (const int64_t frame : onsets(schedule)) ticks.push_back(frame / FramesPerTick);
  return ticks;
}

// Every note-on is answered by a note-off for the same instrument and key, and
// no note-off arrives before its note-on. This is the "no hanging notes" check
// (AC 4) and it is run over every windowing case rather than one of them.
bool notesAreBalanced(const Schedule& schedule) {
  std::map<std::pair<uint32_t, int16_t>, int> open;
  for (const ScheduleEvent& event : eventsOf(schedule)) {
    const auto key = std::make_pair(event.instrument, event.note);
    if (event.type == static_cast<uint16_t>(EventType::NoteOn)) {
      ++open[key];
    } else if (event.type == static_cast<uint16_t>(EventType::NoteOff)) {
      if (--open[key] < 0) return false;  // an off with no on
    }
  }
  for (const auto& [key, count] : open) {
    if (count != 0) return false;  // an on with no off
  }
  return true;
}

// A project with one instrument, one pattern and one lane, ready to place
// clips on. Built through the model API directly: the command layer is tested
// in test_model_commands.cpp and would only add noise here.
struct Scene {
  Project project{IdGenerator::deterministic(0xF1A77ULL)};
  InstrumentId instrument;
  PatternId pattern;
  ArrangementLaneId lane;

  Scene() {
    instrument = project.createInstrument("Piano", claps("test.piano"));
    pattern = project.createPattern("Verse", TicksPerBarFourFour);
    lane = project.createLane("Keys");
  }

  void addNotes(std::vector<Note> notes) {
    project.updateSequence(pattern, instrument, [&notes](NoteSequence& sequence) {
      for (const Note& value : notes) sequence.insert(value);
    });
  }

  ClipId place(Ticks start, Ticks length, bool loop = true, Ticks window = 0,
               int16_t transpose = 0) {
    const ClipId id = project.createClip(lane, PatternSource{pattern}, start, length);
    project.updateClip(id, ChangeField::Transforms, [&](Clip& clip) {
      clip.transforms.loop = loop;
      clip.transforms.window_start = window;
      clip.transforms.transpose = transpose;
    });
    return id;
  }
};

}  // namespace

TEST_SUITE("unit") {
  TEST_CASE("A clip is the pattern's notes, moved to where the clip sits") {
    Scene scene;
    scene.addNotes({note(0, 60), note(960, 64), note(1920, 67)});
    scene.place(TicksPerBarFourFour, TicksPerBarFourFour);

    const FlattenResult result = run(scene.project);
    REQUIRE(result.schedule != nullptr);
    CHECK(result.clips_flattened == 1);
    CHECK(ticksOfOnsets(*result.schedule) == std::vector<int64_t>{TicksPerBarFourFour,
                                                                  TicksPerBarFourFour + 960,
                                                                  TicksPerBarFourFour + 1920});
    CHECK(notesAreBalanced(*result.schedule));
    CHECK(result.length_frames == TicksPerBarFourFour * 2 * FramesPerTick);
  }

  TEST_CASE("One pattern in two clips: editing the pattern moves both") {
    // The reference semantics of ARCHITECTURE.md §3.3, at the schedule level.
    Scene scene;
    scene.addNotes({note(0, 60)});
    scene.place(0, TicksPerBarFourFour);
    scene.place(TicksPerBarFourFour * 4, TicksPerBarFourFour);

    const FlattenResult before = run(scene.project);
    CHECK(ticksOfOnsets(*before.schedule) == std::vector<int64_t>{0, TicksPerBarFourFour * 4});

    scene.addNotes({note(1920, 67)});

    const FlattenResult after = run(scene.project, 2);
    // Both placements gained the note. No clip was edited.
    CHECK(ticksOfOnsets(*after.schedule) ==
          std::vector<int64_t>{0, 1920, TicksPerBarFourFour * 4, TicksPerBarFourFour * 4 + 1920});
    CHECK(after.hash != before.hash);
  }

  TEST_CASE("The windowing matrix") {
    // Pattern is one bar (3840) with notes on each beat.
    Scene scene;
    scene.addNotes({note(0, 60), note(960, 61), note(1920, 62), note(2880, 63)});

    SUBCASE("clip exactly one pattern long, no loop") {
      scene.place(0, TicksPerBarFourFour, false);
      const FlattenResult result = run(scene.project);
      CHECK(ticksOfOnsets(*result.schedule) == std::vector<int64_t>{0, 960, 1920, 2880});
      CHECK(notesAreBalanced(*result.schedule));
    }

    SUBCASE("clip twice the pattern, looping: the pattern repeats") {
      scene.place(0, TicksPerBarFourFour * 2, true);
      const FlattenResult result = run(scene.project);
      CHECK(ticksOfOnsets(*result.schedule) ==
            std::vector<int64_t>{0, 960, 1920, 2880, 3840, 4800, 5760, 6720});
      CHECK(notesAreBalanced(*result.schedule));
    }

    SUBCASE("clip twice the pattern, not looping: it plays once and stops") {
      scene.place(0, TicksPerBarFourFour * 2, false);
      const FlattenResult result = run(scene.project);
      CHECK(ticksOfOnsets(*result.schedule) == std::vector<int64_t>{0, 960, 1920, 2880});
      CHECK(notesAreBalanced(*result.schedule));
    }

    SUBCASE("clip shorter than the pattern truncates") {
      scene.place(0, 1920, true);
      const FlattenResult result = run(scene.project);
      CHECK(ticksOfOnsets(*result.schedule) == std::vector<int64_t>{0, 960});
      CHECK(notesAreBalanced(*result.schedule));
    }

    SUBCASE("a window offset skips what comes before it") {
      scene.place(0, 1920, false, 1920);
      const FlattenResult result = run(scene.project);
      // Source starts at 1920, so the notes at 1920 and 2880 play at 0 and 960.
      CHECK(ticksOfOnsets(*result.schedule) == std::vector<int64_t>{0, 960});
      CHECK(notesAreBalanced(*result.schedule));
    }

    SUBCASE("a window offset wraps when the clip loops") {
      scene.place(0, TicksPerBarFourFour, true, 1920);
      const FlattenResult result = run(scene.project);
      // From 1920: 62, 63, then wrapping to 60, 61.
      CHECK(ticksOfOnsets(*result.schedule) == std::vector<int64_t>{0, 960, 1920, 2880});
      const std::vector<ScheduleEvent> events = eventsOf(*result.schedule);
      std::vector<int16_t> keys;
      for (const ScheduleEvent& event : events) {
        if (event.type == static_cast<uint16_t>(EventType::NoteOn)) keys.push_back(event.note);
      }
      CHECK(keys == std::vector<int16_t>{62, 63, 60, 61});
      CHECK(notesAreBalanced(*result.schedule));
    }

    SUBCASE("a clip that ends mid-note cuts the note off at the boundary") {
      Scene held;
      held.addNotes({note(0, 60, TicksPerBarFourFour)});  // a whole-bar note
      held.place(0, 960, false);
      const FlattenResult result = run(held.project);

      const std::vector<ScheduleEvent> events = eventsOf(*result.schedule);
      REQUIRE(events.size() == 2);
      CHECK(events[0].type == static_cast<uint16_t>(EventType::NoteOn));
      CHECK(events[1].type == static_cast<uint16_t>(EventType::NoteOff));
      CHECK(events[1].frame == 960 * FramesPerTick);  // at the clip's end, not the note's
      CHECK(notesAreBalanced(*result.schedule));
    }

    SUBCASE("a note is cut at the loop boundary rather than sounding across it") {
      Scene held;
      held.addNotes({note(2880, 60, 1920)});  // runs a beat past the pattern's end
      held.place(0, TicksPerBarFourFour * 2, true);
      const FlattenResult result = run(held.project);

      CHECK(ticksOfOnsets(*result.schedule) == std::vector<int64_t>{2880, 6720});
      const std::vector<ScheduleEvent> events = eventsOf(*result.schedule);
      // First occurrence ends at the pattern boundary, where the next
      // iteration re-triggers it.
      CHECK(events[1].frame == TicksPerBarFourFour * FramesPerTick);
      CHECK(notesAreBalanced(*result.schedule));
    }
  }

  TEST_CASE("Audio clips become one-shot starts on dedicated channels") {
    Scene scene;
    AudioSource source;
    source.path = "/tmp/song.wav";
    source.destination = scene.project.masterTrack();
    const ClipId audio = scene.project.createClip(
        scene.lane, source, TicksPerBarFourFour * 2, TicksPerBarFourFour * 8);

    const FlattenResult result = run(scene.project);
    REQUIRE(result.schedule != nullptr);
    REQUIRE(result.audio_channel_index.count(audio) == 1);
    CHECK(result.audio_channel_index.at(audio) == 1U);  // after Scene's instrument
    CHECK(result.clips_flattened == 1);
    CHECK(result.length_frames == TicksPerBarFourFour * 10 * FramesPerTick);

    const std::vector<ScheduleEvent> events = eventsOf(*result.schedule);
    REQUIRE(events.size() == 1);
    CHECK(events[0].type == static_cast<uint16_t>(EventType::AudioStart));
    CHECK(events[0].instrument == 1U);
    CHECK(events[0].frame == TicksPerBarFourFour * 2 * FramesPerTick);
  }

  TEST_CASE("Transpose shifts only the clip it is on") {
    Scene scene;
    scene.addNotes({note(0, 60)});
    scene.place(0, TicksPerBarFourFour);
    scene.place(TicksPerBarFourFour, TicksPerBarFourFour, true, 0, 12);

    const FlattenResult result = run(scene.project);
    std::vector<int16_t> keys;
    for (const ScheduleEvent& event : eventsOf(*result.schedule)) {
      if (event.type == static_cast<uint16_t>(EventType::NoteOn)) keys.push_back(event.note);
    }
    CHECK(keys == std::vector<int16_t>{60, 72});

    // And the pattern itself is untouched: the transform is non-destructive.
    CHECK(scene.project.findPattern(scene.pattern)->sequences.at(scene.instrument).notes()[0].key ==
          60);
  }

  TEST_CASE("Pattern swing deterministically delays odd sixteenth steps") {
    Scene scene;
    scene.addNotes({note(0, 60), note(240, 60), note(480, 60), note(720, 60), note(315, 61)});
    scene.project.updatePattern(scene.pattern, ChangeField::Transforms,
                                [](onebeat::model::Pattern& pattern) { pattern.swing = 0.5; });
    scene.place(0, TicksPerBarFourFour, false);

    const FlattenResult first = run(scene.project);
    const FlattenResult second = run(scene.project);
    CHECK(ticksOfOnsets(*first.schedule) == std::vector<int64_t>{0, 300, 315, 480, 780});
    CHECK(first.hash == second.hash);
    CHECK(notesAreBalanced(*first.schedule));
  }

  TEST_CASE("A note transposed out of MIDI range is dropped, not wrapped") {
    Scene scene;
    scene.addNotes({note(0, 120)});
    scene.place(0, TicksPerBarFourFour, true, 0, 24);

    const FlattenResult result = run(scene.project);
    CHECK(result.notes_dropped == 1);
    CHECK(result.schedule->eventCount() == 0);
  }

  TEST_CASE("Mutes and solos gate events, not audio") {
    Scene scene;
    scene.addNotes({note(0, 60)});
    const ClipId clip = scene.place(0, TicksPerBarFourFour);

    SUBCASE("a muted lane fires nothing") {
      scene.project.updateLane(scene.lane, ChangeField::Muted,
                               [](ArrangementLane& lane) { lane.muted = true; });
      CHECK(run(scene.project).schedule->eventCount() == 0);
    }

    SUBCASE("a soloed lane silences the others") {
      const ArrangementLaneId other = scene.project.createLane("Other");
      scene.project.createClip(other, PatternSource{scene.pattern}, TicksPerBarFourFour,
                               TicksPerBarFourFour);
      scene.project.updateLane(other, ChangeField::Soloed,
                               [](ArrangementLane& lane) { lane.soloed = true; });

      const FlattenResult result = run(scene.project);
      CHECK(ticksOfOnsets(*result.schedule) == std::vector<int64_t>{TicksPerBarFourFour});
    }

    SUBCASE("a muted clip fires nothing") {
      scene.project.updateClip(clip, ChangeField::Muted, [](Clip& value) { value.muted = true; });
      CHECK(run(scene.project).schedule->eventCount() == 0);
    }

    SUBCASE("a muted instrument fires nothing") {
      scene.project.updateInstrument(scene.instrument, ChangeField::Muted,
                                     [](Instrument& value) { value.muted = true; });
      CHECK(run(scene.project).schedule->eventCount() == 0);
    }
  }

  TEST_CASE("Stacked identical notes: the later one cuts the earlier") {
    Scene scene;
    scene.addNotes({note(0, 60, TicksPerBarFourFour)});
    scene.place(0, TicksPerBarFourFour, false);
    scene.place(960, TicksPerBarFourFour, false);  // overlapping placement

    const FlattenResult result = run(scene.project);
    const std::vector<ScheduleEvent> events = eventsOf(*result.schedule);
    REQUIRE(events.size() == 4);
    CHECK(events[0].frame == 0);                    // first on
    CHECK(events[1].frame == 960 * FramesPerTick);  // first off, moved
    CHECK(events[1].type == static_cast<uint16_t>(EventType::NoteOff));
    CHECK(events[2].frame == 960 * FramesPerTick);  // second on
    CHECK(events[2].type == static_cast<uint16_t>(EventType::NoteOn));
    CHECK(notesAreBalanced(*result.schedule));
  }

  TEST_CASE("Automation points become parameter events") {
    Scene scene;
    AutomationSource source;
    source.target_kind = AutomationSource::TargetKind::Instrument;
    source.instrument = scene.instrument;
    source.parameter = 7;
    source.points = {AutomationPoint{0, 0.0F}, AutomationPoint{960, 0.5F},
                     AutomationPoint{1920, 1.0F},
                     AutomationPoint{TicksPerBarFourFour * 2, 0.25F}};  // past the clip's end
    scene.project.createClip(scene.lane, source, TicksPerBarFourFour, TicksPerBarFourFour);

    const FlattenResult result = run(scene.project);
    std::vector<std::pair<int64_t, float>> values;
    for (const ScheduleEvent& event : eventsOf(*result.schedule)) {
      if (event.type == static_cast<uint16_t>(EventType::ParamValue)) {
        CHECK(event.reserved == 7U);
        values.emplace_back(event.frame / FramesPerTick, event.value);
      }
    }
    REQUIRE(values.size() == 3);  // the fourth point is outside the clip
    CHECK(values[0].first == TicksPerBarFourFour);
    CHECK(values[2].second == doctest::Approx(1.0F));
  }

  TEST_CASE("The same model always flattens to the same bytes") {
    Scene scene;
    scene.addNotes({note(0, 60), note(960, 64)});
    scene.place(0, TicksPerBarFourFour * 2);
    scene.place(TicksPerBarFourFour * 2, TicksPerBarFourFour);

    const FlattenResult first = run(scene.project);
    for (int repeat = 0; repeat < 5; ++repeat) {
      CHECK(run(scene.project).hash == first.hash);
    }

    // And an edit that is undone leaves the schedule where it was — the
    // property golden tests will rest on.
    onebeat::model::CommandBus bus(scene.project);
    REQUIRE(bus.execute(
        onebeat::model::insertNotes(scene.pattern, scene.instrument, {note(1920, 67)})));
    CHECK(run(scene.project).hash != first.hash);
    REQUIRE(bus.undo());
    CHECK(run(scene.project).hash == first.hash);
  }

  TEST_CASE("The scheduler re-flattens only after something changes") {
    Scene scene;
    scene.addNotes({note(0, 60)});
    scene.place(0, TicksPerBarFourFour);

    FlattenScheduler scheduler(scene.project);
    CHECK(scheduler.dirty());

    const FlattenResult first = scheduler.flushIfDirty(SampleRate);
    REQUIRE(first.schedule != nullptr);
    CHECK(first.schedule->generation() == 1);
    CHECK_FALSE(scheduler.dirty());

    // Nothing changed: no schedule, so nothing is published and the live one is
    // not retired for no reason.
    CHECK(scheduler.flushIfDirty(SampleRate).schedule == nullptr);

    scene.addNotes({note(960, 64)});
    CHECK(scheduler.dirty());
    const FlattenResult second = scheduler.flushIfDirty(SampleRate);
    REQUIRE(second.schedule != nullptr);
    CHECK(second.schedule->generation() == 2);
    CHECK(second.event_count > first.event_count);
  }
}

TEST_SUITE("engine") {
  TEST_CASE("Editing a pattern changes what both of its placements sound like") {
    // OB-3-04 AC 1, and the v0.3 exit behaviour: end to end, model → flattener
    // → schedule → the real process path → samples.
    Scene scene;
    scene.addNotes({note(0, 60)});
    scene.place(0, TicksPerBarFourFour);
    scene.place(TicksPerBarFourFour, TicksPerBarFourFour);

    const auto render = [&scene](uint64_t generation) {
      auto engine = makeOfflineEngine(SampleRate, 128);
      REQUIRE(engine != nullptr);
      FlattenOptions options;
      options.sample_rate = SampleRate;
      options.generation = generation;
      FlattenResult result = flatten(scene.project, options);
      engine->publishSchedule(std::move(result.schedule));
      engine->postCommand(command(OB_CMD_TRANSPORT_PLAY));
      return renderOffline(*engine, 192000, 128);
    };

    const auto before = render(1);
    CHECK(before.peak() > 0.01F);

    // One edit to the pattern, which both clips reference.
    scene.addNotes({note(1920, 67)});
    const auto after = render(2);

    CHECK_FALSE(onebeat::testing::sameSamples(before, after));
    CHECK(after.peak() > 0.01F);
  }
}

TEST_SUITE("stress") {
  // OB-3-04 AC 5. Two densities, because "1,000 clips" does not pin down the
  // work: what costs time is notes, and a clip can hold two or two hundred.
  // Both numbers are recorded in docs/flattener-budget.md.
  //
  // **A wall-clock assertion under a sanitizer measures the sanitizer.** ASan
  // and TSan instrument every access, so the budget rows in the doc come from
  // ordinary builds and the sanitizer runs prove only that the code is correct
  // and allocation-clean. What every build asserts is the work done — 1,000
  // clips flattened — and the only thing asserted about real timings is that
  // nothing has gone quadratic.
#if defined(ONEBEAT_SANITIZER_BUILD)
  constexpr bool Instrumented = true;
#else
  constexpr bool Instrumented = false;
#endif

  struct Bench {
    Project project{IdGenerator::deterministic(0x5EEDULL)};

    Bench(int instrument_count, int notes_per_instrument) {
      project.setDebugChecks(false);
      std::vector<InstrumentId> instruments;
      instruments.reserve(static_cast<size_t>(instrument_count));
      for (int i = 0; i < instrument_count; ++i) {
        instruments.push_back(project.createInstrument("I" + std::to_string(i), claps("test")));
      }
      std::vector<PatternId> patterns;
      patterns.reserve(16);
      for (int i = 0; i < 16; ++i) {
        const PatternId pattern = project.createPattern("P" + std::to_string(i));
        patterns.push_back(pattern);
        int voice = 0;
        for (const InstrumentId instrument : instruments) {
          // Every pattern/instrument pair gets its own pitches. Identical notes
          // in the same place collapse under the overlap rule, and a benchmark
          // measuring mostly-collapsed events measures the wrong thing.
          const int offset = (i * 8) + voice++;
          project.updateSequence(
              pattern, instrument, [offset, notes_per_instrument](NoteSequence& sequence) {
                for (int step = 0; step < notes_per_instrument; ++step) {
                  sequence.insert(
                      note(step * 240, static_cast<int16_t>(24 + ((offset + step) % 96))));
                }
              });
        }
      }
      std::vector<ArrangementLaneId> lanes;
      lanes.reserve(16);
      for (int i = 0; i < 16; ++i) lanes.push_back(project.createLane("L" + std::to_string(i)));

      for (int i = 0; i < 1000; ++i) {
        project.createClip(lanes[static_cast<size_t>(i) % lanes.size()],
                           PatternSource{patterns[static_cast<size_t>(i) % patterns.size()]},
                           TicksPerBarFourFour * static_cast<Ticks>(i / 16), TicksPerBarFourFour);
      }
    }

    FlattenResult best() {
      FlattenResult fastest;
      const int repeats = Instrumented ? 1 : 5;
      for (int repeat = 0; repeat < repeats; ++repeat) {
        FlattenResult result = run(project, static_cast<uint64_t>(repeat) + 1);
        if (fastest.schedule == nullptr || result.elapsed_ms < fastest.elapsed_ms) {
          fastest = std::move(result);
        }
      }
      return fastest;
    }
  };

  TEST_CASE("A 1,000-clip project flattens inside the budget at ordinary density") {
    Bench bench(2, 16);  // two instruments, 16 notes each: a typical pattern
    REQUIRE(bench.project.clips().size() == 1000);
    const FlattenResult result = bench.best();
    CHECK(result.clips_flattened == 1000);
    const std::string suffix =
        Instrumented ? " ms (instrumented build, not a budget measurement)" : " ms";
    MESSAGE("1,000 clips, ordinary density: " << result.event_count << " events, "
                                              << result.elapsed_ms << suffix);
    CHECK(result.event_count > 40000);
    if (!Instrumented) CHECK(result.elapsed_ms < 2000.0);
  }

  TEST_CASE("A 1,000-clip project of extreme density is measured, not assumed") {
    // Four times the events of the row above. Skipped under sanitizers: its
    // timing there would be meaningless, and producing that meaningless number
    // cost minutes of every CI run.
    if (Instrumented) return;

    Bench bench(8, 16);  // 128 notes per clip: heavier than any real arrangement
    const FlattenResult result = bench.best();
    MESSAGE("1,000 clips, extreme density: " << result.event_count << " events, "
                                             << result.elapsed_ms << " ms");
    CHECK(result.clips_flattened == 1000);
    CHECK(result.elapsed_ms < 2000.0);
  }
}
