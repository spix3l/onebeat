// NoteSequence editor operations and the shared step/piano-roll proof (OB-3-08).
#include <chrono>
#include <cstdint>
#include <vector>

#include "doctest.h"
#include "model/command.h"
#include "model/commands.h"
#include "model/note_edit.h"
#include "model/project.h"

using namespace onebeat::model;

namespace {

PluginRef claps() {
  PluginRef plugin;
  plugin.format = PluginFormat::Clap;
  plugin.id = "test.notes";
  return plugin;
}

Note makeNote(Ticks start, int16_t key, Ticks length = 120,
              Velocity velocity = velocityFromMidi1(100)) {
  return Note{start, length, key, velocity};
}

struct Fixture {
  Project project{IdGenerator::deterministic(0x308ULL)};
  CommandBus bus{project};
  InstrumentId instrument;
  PatternId pattern;

  Fixture() {
    REQUIRE(bus.execute(addInstrument(project, "Piano", claps())));
    instrument = project.instruments().begin()->first;
    REQUIRE(bus.execute(addPattern(project, "Pattern")));
    pattern = project.patterns().begin()->first;
    bus.seal();
  }

  const NoteSequence& sequence() const {
    return project.findPattern(pattern)->sequences.at(instrument);
  }
};

}  // namespace

TEST_SUITE("unit") {
  TEST_CASE("Snapping is deterministic around the grid origin") {
    const NoteGrid grid{240, 0};
    CHECK(snapTick(119, grid) == 0);
    CHECK(snapTick(120, grid) == 240);
    CHECK(snapTick(-120, grid) == 0);  // half chooses the later line
    CHECK(snapTick(-121, grid) == -240);
  }

  TEST_CASE("Range and lasso queries select the canonical sequence") {
    NoteSequence sequence;
    sequence.insert(makeNote(0, 60, 500));  // sounds into the range
    sequence.insert(makeNote(420, 64));     // begins in the range
    sequence.insert(makeNote(500, 70));     // wrong pitch for the range
    sequence.insert(makeNote(600, 65));     // half-open end: outside

    const auto onsets = sequence.startingIn(400, 600);
    REQUIRE(onsets.size() == 2);
    CHECK(onsets[0].start == 420);
    CHECK(onsets[1].start == 500);

    const auto painted = selectNotesInRange(sequence, NoteRange{400, 600, 60, 65});
    REQUIRE(painted.size() == 2);
    CHECK(painted[0].start == 0);
    CHECK(painted[1].start == 420);

    const auto lasso = selectNotes(
        sequence, [](const Note& note) { return note.key % 2 == 0 && note.start >= 400; });
    REQUIRE(lasso.size() == 2);
    CHECK(lasso[0].key == 64);
    CHECK(lasso[1].key == 70);
  }

  TEST_CASE("Entry uses instrument defaults and every edit operation undoes") {
    Fixture f;
    REQUIRE(f.bus.execute(editInstrument(
        f.project, f.instrument, ChangeField::NoteDefaults,
        [](Instrument& value) { value.note_defaults.velocity = velocityFromMidi1(73); },
        "Set note defaults")));
    f.bus.seal();

    REQUIRE(f.bus.execute(addNote(f.project, f.pattern, f.instrument, 101, 239, 60)));
    REQUIRE(f.sequence().size() == 1);
    CHECK(f.sequence().notes()[0].velocity == velocityFromMidi1(73));
    const Note original = f.sequence().notes()[0];
    f.bus.seal();

    SUBCASE("move snaps the group anchor and preserves offsets") {
      REQUIRE(f.bus.execute(insertNotes(f.pattern, f.instrument, {makeNote(341, 64, 239)})));
      f.bus.seal();
      const std::vector<Note> before = f.sequence().notes();
      REQUIRE(f.bus.execute(moveNotes(f.pattern, f.instrument, before, 80, 2, NoteGrid{240, 0})));
      const auto& after = f.sequence().notes();
      REQUIRE(after.size() == 2);
      CHECK(after[0].start == 240);
      CHECK(after[1].start == 480);
      CHECK(after[1].start - after[0].start == 240);
      CHECK(after[0].key == 62);
      REQUIRE(f.bus.undo());
      CHECK(f.sequence().notes() == before);
    }

    SUBCASE("resize") {
      REQUIRE(
          f.bus.execute(resizeNotes(f.pattern, f.instrument, {original}, 130, NoteGrid{120, 0})));
      CHECK(f.sequence().notes()[0].length == 379);  // end 340 -> 470 -> 480
      REQUIRE(f.bus.undo());
      CHECK(f.sequence().notes()[0] == original);
    }

    SUBCASE("velocity set and scale") {
      REQUIRE(f.bus.execute(
          setNoteVelocity(f.pattern, f.instrument, {original}, velocityFromMidi1(80))));
      CHECK(f.sequence().notes()[0].velocity == velocityFromMidi1(80));
      const Note set = f.sequence().notes()[0];
      f.bus.seal();
      REQUIRE(f.bus.execute(scaleNoteVelocity(f.pattern, f.instrument, {set}, 0.5)));
      CHECK(f.sequence().notes()[0].velocity == velocityFromMidi1(40));
      REQUIRE(f.bus.undo());
      CHECK(f.sequence().notes()[0] == set);
    }

    SUBCASE("transpose clamps the selection as a group") {
      REQUIRE(f.bus.execute(transposeNotes(f.pattern, f.instrument, {original}, 80)));
      CHECK(f.sequence().notes()[0].key == 127);
      REQUIRE(f.bus.undo());
      CHECK(f.sequence().notes()[0] == original);
    }

    SUBCASE("duplicate") {
      REQUIRE(f.bus.execute(
          duplicateNotes(f.pattern, f.instrument, {original}, 200, NoteGrid{240, 0})));
      REQUIRE(f.sequence().size() == 2);
      CHECK(f.sequence().notes()[1].start == 240);
      REQUIRE(f.bus.undo());
      CHECK(f.sequence().notes() == std::vector<Note>{original});
    }
  }

  TEST_CASE("Quantise strength matches hand-computed fixtures") {
    Fixture f;
    const std::vector<Note> before{makeNote(50, 60), makeNote(120, 63), makeNote(170, 61),
                                   makeNote(350, 62)};
    REQUIRE(f.bus.execute(insertNotes(f.pattern, f.instrument, before)));
    f.bus.seal();

    REQUIRE(f.bus.execute(quantiseNotes(f.pattern, f.instrument, before, NoteGrid{240, 0}, 0.5)));
    const auto& notes = f.sequence().notes();
    REQUIRE(notes.size() == 4);
    CHECK(notes[0].start == 25);   // 50 halfway toward 0
    CHECK(notes[1].start == 180);  // tie 120 targets 240, halfway is 180
    CHECK(notes[2].start == 205);  // 170 halfway toward 240
    CHECK(notes[3].start == 295);  // 350 halfway back toward 240

    REQUIRE(f.bus.undo());
    CHECK(f.sequence().notes() == before);
  }

  TEST_CASE("A note drag coalesces to one undo entry") {
    Fixture f;
    const Note initial = makeNote(0, 60);
    REQUIRE(f.bus.execute(insertNotes(f.pattern, f.instrument, {initial})));
    f.bus.seal();
    const size_t depth = f.bus.undoDepth();

    Note current = initial;
    for (int step = 1; step <= 20; ++step) {
      const Note before = current;
      current.start = step * 12;
      REQUIRE(f.bus.execute(replaceNotes(f.pattern, f.instrument, {before}, {current})));
    }
    CHECK(f.bus.undoDepth() == depth + 1);
    CHECK(f.sequence().notes()[0].start == 240);
    REQUIRE(f.bus.undo());
    CHECK(f.sequence().notes()[0] == initial);
  }

  TEST_CASE("A stale or invalid batch edit is rejected atomically") {
    Fixture f;
    const Note kept = makeNote(0, 60);
    REQUIRE(f.bus.execute(insertNotes(f.pattern, f.instrument, {kept})));
    f.bus.seal();
    const size_t depth = f.bus.undoDepth();

    Note invalid = kept;
    invalid.length = 0;
    CHECK_FALSE(f.bus.execute(insertNotes(f.pattern, f.instrument, {invalid})));
    CHECK_FALSE(f.bus.execute(
        replaceNotes(f.pattern, f.instrument, {makeNote(99, 61)}, {makeNote(120, 61)})));
    CHECK(f.bus.undoDepth() == depth);
    CHECK(f.sequence().notes() == std::vector<Note>{kept});
  }

  TEST_CASE("Step and piano roll round-trip without touching off-grid notes") {
    Fixture f;
    const NoteGrid grid{240, 0};
    const Note off_grid = makeNote(250, 36, 90, velocityFromMidi1(72));
    REQUIRE(f.bus.execute(insertNotes(f.pattern, f.instrument, {off_grid})));
    f.bus.seal();

    StepCell cell = inspectStep(f.sequence(), 36, 1, grid);
    CHECK_FALSE(cell.active());
    REQUIRE(cell.off_grid.size() == 1);
    CHECK(cell.off_grid[0] == off_grid);

    // Rack on -> piano-roll note, with the instrument's entry defaults.
    REQUIRE(f.bus.execute(toggleStep(f.project, f.pattern, f.instrument, 36, 1, grid)));
    cell = inspectStep(f.sequence(), 36, 1, grid);
    REQUIRE(cell.on_grid.size() == 1);
    CHECK(cell.on_grid[0].start == 240);
    CHECK(cell.on_grid[0].length == 240);
    CHECK(cell.on_grid[0].velocity == DefaultVelocity);
    REQUIRE(cell.off_grid.size() == 1);

    f.bus.seal();
    // Rack off removes only the exact grid onset. The piano-roll-only note is
    // still represented by the cell's off-grid indicator.
    REQUIRE(f.bus.execute(toggleStep(f.project, f.pattern, f.instrument, 36, 1, grid)));
    cell = inspectStep(f.sequence(), 36, 1, grid);
    CHECK_FALSE(cell.active());
    REQUIRE(cell.off_grid.size() == 1);
    CHECK(cell.off_grid[0] == off_grid);
  }
}

TEST_SUITE("stress") {
  TEST_CASE("A 10k-note range query and edit fit one UI frame") {
#if defined(ONEBEAT_SANITIZER_BUILD)
    constexpr bool Instrumented = true;
#else
    constexpr bool Instrumented = false;
#endif
    Fixture f;
    f.project.setDebugChecks(false);
    std::vector<Note> notes;
    notes.reserve(10000);
    for (int i = 0; i < 10000; ++i) {
      notes.push_back(
          makeNote(static_cast<Ticks>(i) * 30, static_cast<int16_t>(24 + (i % 88)), 20));
    }
    REQUIRE(f.bus.execute(insertNotes(f.pattern, f.instrument, notes)));
    f.bus.seal();

    const auto query_started = std::chrono::steady_clock::now();
    const auto visible = selectNotesInRange(f.sequence(), NoteRange{120000, 124800, 0, 127});
    const auto query_elapsed = std::chrono::steady_clock::now() - query_started;
    REQUIRE(visible.size() == 160);
    const auto edit_started = std::chrono::steady_clock::now();
    REQUIRE(f.bus.execute(quantiseNotes(f.pattern, f.instrument, notes, NoteGrid{30, 0}, 1.0)));
    const auto edit_elapsed = std::chrono::steady_clock::now() - edit_started;
    const auto elapsed = query_elapsed + edit_elapsed;
    CHECK(f.sequence().size() == 10000);
    MESSAGE("10k notes: range query ",
            std::chrono::duration<double, std::milli>(query_elapsed).count(), " ms, edit ",
            std::chrono::duration<double, std::milli>(edit_elapsed).count(), " ms");
    if (!Instrumented) {
      CHECK(elapsed < std::chrono::microseconds(16667));
    }
  }
}
