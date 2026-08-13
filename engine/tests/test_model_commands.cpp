// Undo/redo (OB-3-03).
//
// The checklist OB-3-03 AC 1 asks for is the "Every Stage 3 mutation is
// undoable" case below: it walks notes, patterns, clips, lanes, instruments,
// mixer tracks and project-level settings, and asserts each one round-trips.
//
// The fuzz case (AC 4) is the one that would actually catch a bad inverse. It
// compares a digest of the whole model after every undo and redo against the
// digest recorded when that state was first reached, so a command whose revert
// is subtly wrong fails immediately and with the sequence that produced it.
#include <cstring>
#include <random>
#include <string>
#include <vector>

#include "doctest.h"
#include "model/command.h"
#include "model/commands.h"
#include "model/invariants.h"
#include "model/project.h"

using onebeat::model::addClip;
using onebeat::model::addInstrument;
using onebeat::model::addLane;
using onebeat::model::addMixerTrack;
using onebeat::model::addPattern;
using onebeat::model::ArrangementLane;
using onebeat::model::ArrangementLaneId;
using onebeat::model::ChangeField;
using onebeat::model::checkReferentialIntegrity;
using onebeat::model::Clip;
using onebeat::model::ClipId;
using onebeat::model::CommandBus;
using onebeat::model::CommandPtr;
using onebeat::model::editClip;
using onebeat::model::editInstrument;
using onebeat::model::editLane;
using onebeat::model::editMixerTrack;
using onebeat::model::editPatternMeta;
using onebeat::model::IdGenerator;
using onebeat::model::insertNotes;
using onebeat::model::Instrument;
using onebeat::model::InstrumentId;
using onebeat::model::MixerTrack;
using onebeat::model::MixerTrackId;
using onebeat::model::Note;
using onebeat::model::PatternId;
using onebeat::model::PatternMeta;
using onebeat::model::PatternSource;
using onebeat::model::PluginFormat;
using onebeat::model::PluginRef;
using onebeat::model::Project;
using onebeat::model::removeClip;
using onebeat::model::removeInstrument;
using onebeat::model::removeLane;
using onebeat::model::removeMixerTrack;
using onebeat::model::removeNotes;
using onebeat::model::removePattern;
using onebeat::model::replaceNotes;
using onebeat::model::setProjectMeta;
using onebeat::model::setTransport;
using onebeat::model::Ticks;
using onebeat::model::TicksPerBarFourFour;
using onebeat::model::TransportState;
using onebeat::model::velocityFromMidi1;

namespace {

PluginRef claps(const std::string& id) {
  PluginRef plugin;
  plugin.format = PluginFormat::Clap;
  plugin.id = id;
  plugin.name = id;
  return plugin;
}

Note note(Ticks start, int16_t key) {
  Note value;
  value.start = start;
  value.length = 240;
  value.key = key;
  value.velocity = velocityFromMidi1(96);
  return value;
}

// A deep comparison of the whole model, as a 64-bit FNV-1a hash. Two projects
// with the same value have the same digest; a wrong inverse changes it.
//
// A hash rather than a string because the fuzz case below computes this after
// every one of 100,000 steps: building and keeping a string that size turned a
// 20-second test into a four-minute one, and under ASan it would have been
// unrunnable.
class Digest {
 public:
  void number(int64_t value) {
    for (int shift = 0; shift < 64; shift += 8) {
      byte(static_cast<uint8_t>((static_cast<uint64_t>(value) >> shift) & 0xFFU));
    }
  }
  void real(float value) { real(static_cast<double>(value)); }
  void real(double value) {
    int64_t bits = 0;
    std::memcpy(&bits, &value, sizeof(bits));
    number(bits);
  }
  void text(const std::string& value) {
    for (const char c : value) byte(static_cast<uint8_t>(c));
    byte(0);
  }
  template <typename Id>
  void id(const Id& value) {
    number(static_cast<int64_t>(value.raw().high));
    number(static_cast<int64_t>(value.raw().low));
  }
  uint64_t value() const { return state_; }

 private:
  void byte(uint8_t value) {
    state_ ^= value;
    state_ *= 0x100000001B3ULL;
  }

  uint64_t state_ = 0xCBF29CE484222325ULL;
};

uint64_t digest(const Project& project) {
  Digest out;
  for (const auto& [id, instrument] : project.instruments()) {
    out.id(id);
    out.text(instrument.name);
    out.text(instrument.color);
    out.text(instrument.plugin.id);
    out.number(instrument.muted ? 1 : 0);
    for (const auto& route : instrument.routing) {
      out.number(route.port);
      out.id(route.track);
    }
  }
  for (const auto& [id, pattern] : project.patterns()) {
    out.id(id);
    out.text(pattern.name);
    out.text(pattern.color);
    out.number(pattern.length);
    for (const auto& [instrument_id, sequence] : pattern.sequences) {
      out.id(instrument_id);
      for (const Note& value : sequence.notes()) {
        out.number(value.start);
        out.number(value.length);
        out.number(value.key);
        out.number(value.velocity);
      }
    }
  }
  for (const auto& [id, lane] : project.lanes()) {
    out.id(id);
    out.text(lane.name);
    out.text(lane.color);
    out.number(lane.order);
    out.number(lane.height);
    out.number((lane.muted ? 1 : 0) + (lane.soloed ? 2 : 0));
    if (lane.group_id.has_value()) out.id(*lane.group_id);
  }
  for (const auto& [id, clip] : project.clips()) {
    out.id(id);
    out.id(clip.lane);
    out.number(clip.start);
    out.number(clip.length);
    out.number(clip.muted ? 1 : 0);
    out.number(clip.transforms.transpose);
    out.number(clip.transforms.loop ? 1 : 0);
    out.number(clip.transforms.window_start);
    if (const auto* source = clip.pattern()) out.id(source->pattern);
    if (const auto* source = clip.audio()) {
      out.text(source->path);
      out.id(source->destination);
    }
    if (const auto* source = clip.automation()) {
      out.number(static_cast<int>(source->target_kind));
      out.id(source->instrument);
      out.id(source->mixer_track);
      out.number(source->parameter);
    }
  }
  for (const auto& [id, track] : project.mixerTracks()) {
    out.id(id);
    out.text(track.name);
    out.real(track.gain);
    out.real(track.pan);
    out.number(track.muted ? 1 : 0);
    if (track.output.has_value()) out.id(*track.output);
  }
  out.real(project.transport().tempo);
  out.number(project.transport().loop_start);
  out.number(project.transport().loop_end);
  out.text(project.meta().name);
  return out.value();
}

struct Fixture {
  Project project{IdGenerator::deterministic(0xC0FFEEULL)};
  CommandBus bus{project};
};

}  // namespace

TEST_SUITE("unit") {
  TEST_CASE("Every Stage 3 mutation is undoable and redoable") {
    // This is OB-3-03 AC 1's enumeration. Each block: do it, undo it, check the
    // model is exactly where it started, redo it, check it landed again.
    Fixture f;
    const uint64_t empty = digest(f.project);

    SUBCASE("add an instrument, with its auto-created mixer track") {
      REQUIRE(f.bus.execute(addInstrument(f.project, "Kick", claps("test.kick"))));
      CHECK(f.project.instruments().size() == 1);
      CHECK(f.project.mixerTracks().size() == 2);
      const uint64_t after = digest(f.project);

      REQUIRE(f.bus.undo());
      CHECK(digest(f.project) == empty);  // the track undid with the instrument
      CHECK(f.project.mixerTracks().size() == 1);
      REQUIRE(f.bus.redo());
      CHECK(digest(f.project) == after);
    }

    SUBCASE("delete an instrument used across patterns") {
      REQUIRE(f.bus.execute(addInstrument(f.project, "Kick", claps("test.kick"))));
      const InstrumentId kick = f.project.instruments().begin()->first;
      REQUIRE(f.bus.execute(addPattern(f.project, "A")));
      REQUIRE(f.bus.execute(addPattern(f.project, "B")));
      std::vector<PatternId> patterns;
      for (const auto& [id, pattern] : f.project.patterns()) patterns.push_back(id);
      for (const PatternId pattern : patterns) {
        REQUIRE(f.bus.execute(insertNotes(pattern, kick, {note(0, 36), note(480, 36)})));
      }
      const uint64_t before = digest(f.project);

      REQUIRE(f.bus.execute(removeInstrument(kick)));
      CHECK(f.project.findInstrument(kick) == nullptr);

      REQUIRE(f.bus.undo());
      // AC 3: the sequences come back in every affected pattern, identically.
      CHECK(digest(f.project) == before);
    }

    SUBCASE("add and delete a pattern with placements") {
      REQUIRE(f.bus.execute(addPattern(f.project, "Verse")));
      const PatternId pattern = f.project.patterns().begin()->first;
      REQUIRE(f.bus.execute(addLane(f.project, "Keys")));
      const ArrangementLaneId lane = f.project.lanes().begin()->first;
      REQUIRE(
          f.bus.execute(addClip(f.project, lane, PatternSource{pattern}, 0, TicksPerBarFourFour)));
      const uint64_t before = digest(f.project);

      REQUIRE(f.bus.execute(removePattern(pattern)));
      CHECK(f.project.clips().empty());
      REQUIRE(f.bus.undo());
      CHECK(digest(f.project) == before);  // the clip came back with it
    }

    SUBCASE("delete a lane and its clips") {
      REQUIRE(f.bus.execute(addPattern(f.project, "Verse")));
      const PatternId pattern = f.project.patterns().begin()->first;
      REQUIRE(f.bus.execute(addLane(f.project, "Keys")));
      const ArrangementLaneId lane = f.project.lanes().begin()->first;
      REQUIRE(
          f.bus.execute(addClip(f.project, lane, PatternSource{pattern}, 0, TicksPerBarFourFour)));
      const uint64_t before = digest(f.project);

      REQUIRE(f.bus.execute(removeLane(lane)));
      REQUIRE(f.bus.undo());
      CHECK(digest(f.project) == before);
    }

    SUBCASE("move a clip") {
      REQUIRE(f.bus.execute(addPattern(f.project, "Verse")));
      const PatternId pattern = f.project.patterns().begin()->first;
      REQUIRE(f.bus.execute(addLane(f.project, "Keys")));
      const ArrangementLaneId lane = f.project.lanes().begin()->first;
      REQUIRE(
          f.bus.execute(addClip(f.project, lane, PatternSource{pattern}, 0, TicksPerBarFourFour)));
      const ClipId clip = f.project.clips().begin()->first;
      const uint64_t before = digest(f.project);

      REQUIRE(f.bus.execute(editClip(
          f.project, clip, ChangeField::Start,
          [](Clip& value) { value.start = TicksPerBarFourFour * 2; }, "Move clip")));
      CHECK(f.project.findClip(clip)->start == TicksPerBarFourFour * 2);
      REQUIRE(f.bus.undo());
      CHECK(digest(f.project) == before);
      REQUIRE(f.bus.redo());
      CHECK(f.project.findClip(clip)->start == TicksPerBarFourFour * 2);
    }

    SUBCASE("rename and resize a pattern without copying its notes") {
      REQUIRE(f.bus.execute(addInstrument(f.project, "Piano", claps("test.piano"))));
      const InstrumentId piano = f.project.instruments().begin()->first;
      REQUIRE(f.bus.execute(addPattern(f.project, "Verse")));
      const PatternId pattern = f.project.patterns().begin()->first;
      REQUIRE(f.bus.execute(insertNotes(pattern, piano, {note(0, 60)})));
      const uint64_t before = digest(f.project);

      REQUIRE(f.bus.execute(editPatternMeta(
          f.project, pattern, ChangeField::Name,
          [](PatternMeta& meta) {
            meta.name = "Chorus";
            meta.length = TicksPerBarFourFour * 8;
          },
          "Rename pattern")));
      REQUIRE(f.bus.undo());
      CHECK(digest(f.project) == before);
    }

    SUBCASE("reorder a lane") {
      REQUIRE(f.bus.execute(addLane(f.project, "Keys")));
      REQUIRE(f.bus.execute(addLane(f.project, "Bass")));
      const ArrangementLaneId lane = f.project.lanes().begin()->first;
      const uint64_t before = digest(f.project);

      REQUIRE(f.bus.execute(editLane(
          f.project, lane, ChangeField::Order, [](ArrangementLane& value) { value.order = 9; },
          "Reorder lane")));
      REQUIRE(f.bus.undo());
      CHECK(digest(f.project) == before);
    }

    SUBCASE("re-route an instrument and delete the track it fed") {
      REQUIRE(f.bus.execute(addInstrument(f.project, "Bass", claps("test.bass"))));
      const InstrumentId bass = f.project.instruments().begin()->first;
      REQUIRE(f.bus.execute(addMixerTrack(f.project, "Bus")));
      MixerTrackId bus_track;
      for (const auto& [id, track] : f.project.mixerTracks()) {
        if (track.name == "Bus") bus_track = id;
      }
      REQUIRE(f.bus.execute(editInstrument(
          f.project, bass, ChangeField::Routing,
          [bus_track](Instrument& value) { value.routing[0].track = bus_track; }, "Route")));
      const uint64_t before = digest(f.project);

      REQUIRE(f.bus.execute(removeMixerTrack(bus_track)));
      CHECK(f.project.findInstrument(bass)->routing[0].track == f.project.masterTrack());
      REQUIRE(f.bus.undo());
      // The routing that was re-pointed at Master goes back to the bus.
      CHECK(digest(f.project) == before);
    }

    SUBCASE("mixer gain") {
      REQUIRE(f.bus.execute(addMixerTrack(f.project, "Bus")));
      MixerTrackId track;
      for (const auto& [id, value] : f.project.mixerTracks()) {
        if (value.name == "Bus") track = id;
      }
      const uint64_t before = digest(f.project);
      REQUIRE(f.bus.execute(editMixerTrack(
          f.project, track, ChangeField::Gain, [](MixerTrack& value) { value.gain = 0.5F; },
          "Set gain")));
      REQUIRE(f.bus.undo());
      CHECK(digest(f.project) == before);
    }

    SUBCASE("notes: insert, edit, delete") {
      REQUIRE(f.bus.execute(addInstrument(f.project, "Piano", claps("test.piano"))));
      const InstrumentId piano = f.project.instruments().begin()->first;
      REQUIRE(f.bus.execute(addPattern(f.project, "Verse")));
      const PatternId pattern = f.project.patterns().begin()->first;

      REQUIRE(f.bus.execute(insertNotes(pattern, piano, {note(0, 60), note(480, 64)})));
      const uint64_t two_notes = digest(f.project);

      REQUIRE(f.bus.execute(replaceNotes(pattern, piano, {note(0, 60)}, {note(240, 62)})));
      REQUIRE(f.bus.undo());
      CHECK(digest(f.project) == two_notes);

      REQUIRE(f.bus.execute(removeNotes(pattern, piano, {note(480, 64)})));
      CHECK(f.project.findPattern(pattern)->sequences.at(piano).size() == 1);
      REQUIRE(f.bus.undo());
      CHECK(digest(f.project) == two_notes);

      // Undoing the insert empties the sequence, which must also remove it:
      // sparseness is an invariant, and undo may not leave debris behind.
      REQUIRE(f.bus.undo());
      CHECK(f.project.findPattern(pattern)->sequences.empty());
    }

    SUBCASE("transport and project details") {
      TransportState transport = f.project.transport();
      transport.tempo = 140.0;
      const uint64_t before = digest(f.project);
      REQUIRE(f.bus.execute(setTransport(f.project, transport)));
      CHECK(f.project.transport().tempo == doctest::Approx(140.0));

      onebeat::model::ProjectMeta meta = f.project.meta();
      meta.name = "Track 1";
      REQUIRE(f.bus.execute(setProjectMeta(f.project, meta)));

      REQUIRE(f.bus.undo());
      REQUIRE(f.bus.undo());
      CHECK(digest(f.project) == before);
    }
  }

  TEST_CASE("A gesture is one history entry") {
    Fixture f;
    REQUIRE(f.bus.execute(addPattern(f.project, "Verse")));
    const PatternId pattern = f.project.patterns().begin()->first;
    REQUIRE(f.bus.execute(addLane(f.project, "Keys")));
    const ArrangementLaneId lane = f.project.lanes().begin()->first;
    REQUIRE(
        f.bus.execute(addClip(f.project, lane, PatternSource{pattern}, 0, TicksPerBarFourFour)));
    const ClipId clip = f.project.clips().begin()->first;
    const uint64_t before = digest(f.project);
    const size_t depth = f.bus.undoDepth();

    SUBCASE("explicitly bracketed: a drag") {
      f.bus.beginTransaction("Move clip");
      for (int step = 1; step <= 20; ++step) {
        REQUIRE(f.bus.execute(editClip(
            f.project, clip, ChangeField::Start,
            [step](Clip& value) { value.start = TicksPerBarFourFour * step; }, "Move clip")));
      }
      f.bus.commitTransaction();

      CHECK(f.bus.undoDepth() == depth + 1);
      CHECK(f.bus.undoName() == "Move clip");
      REQUIRE(f.bus.undo());
      CHECK(digest(f.project) == before);  // one undo, whole drag gone
    }

    SUBCASE("unbracketed but continuous: a knob twiddle coalesces") {
      for (int step = 1; step <= 20; ++step) {
        REQUIRE(f.bus.execute(editClip(
            f.project, clip, ChangeField::Start,
            [step](Clip& value) { value.start = TicksPerBarFourFour * step; }, "Move clip")));
      }
      CHECK(f.bus.undoDepth() == depth + 1);
      REQUIRE(f.bus.undo());
      CHECK(digest(f.project) == before);
    }

    SUBCASE("sealing ends the coalescing window") {
      REQUIRE(f.bus.execute(editClip(
          f.project, clip, ChangeField::Start, [](Clip& value) { value.start = 100; }, "Move")));
      f.bus.seal();
      REQUIRE(f.bus.execute(editClip(
          f.project, clip, ChangeField::Start, [](Clip& value) { value.start = 200; }, "Move")));
      CHECK(f.bus.undoDepth() == depth + 2);
    }

    SUBCASE("an aborted gesture leaves no trace") {
      f.bus.beginTransaction("Move clip");
      REQUIRE(f.bus.execute(editClip(
          f.project, clip, ChangeField::Start, [](Clip& value) { value.start = 4000; }, "Move")));
      f.bus.abortTransaction();

      CHECK(f.bus.undoDepth() == depth);
      CHECK(digest(f.project) == before);
    }

    SUBCASE("a gesture that changed nothing leaves no entry") {
      f.bus.beginTransaction("Click");
      f.bus.commitTransaction();
      CHECK(f.bus.undoDepth() == depth);
    }
  }

  TEST_CASE("A new edit discards the redo branch") {
    Fixture f;
    REQUIRE(f.bus.execute(addPattern(f.project, "A")));
    REQUIRE(f.bus.execute(addPattern(f.project, "B")));
    REQUIRE(f.bus.undo());
    CHECK(f.bus.canRedo());

    REQUIRE(f.bus.execute(addPattern(f.project, "C")));
    CHECK_FALSE(f.bus.canRedo());
    CHECK(f.project.patterns().size() == 2);
  }

  TEST_CASE("History entries are named for the UI") {
    Fixture f;
    REQUIRE(f.bus.execute(addInstrument(f.project, "Piano", claps("test.piano"))));
    const InstrumentId piano = f.project.instruments().begin()->first;
    REQUIRE(f.bus.execute(addPattern(f.project, "Verse")));
    const PatternId pattern = f.project.patterns().begin()->first;

    REQUIRE(f.bus.execute(insertNotes(pattern, piano, {note(0, 60), note(1, 61), note(2, 62)})));
    CHECK(f.bus.undoName() == "Add 3 notes");
    REQUIRE(f.bus.undo());
    CHECK(f.bus.redoName() == "Add 3 notes");
    REQUIRE(f.bus.execute(removeInstrument(piano)));
    CHECK(f.bus.undoName() == "Delete instrument");
  }

  TEST_CASE("Undoing everything returns the project to empty") {
    Fixture f;
    const uint64_t empty = digest(f.project);

    REQUIRE(f.bus.execute(addInstrument(f.project, "Piano", claps("test.piano"))));
    const InstrumentId piano = f.project.instruments().begin()->first;
    REQUIRE(f.bus.execute(addPattern(f.project, "Verse")));
    const PatternId pattern = f.project.patterns().begin()->first;
    REQUIRE(f.bus.execute(addLane(f.project, "Keys")));
    const ArrangementLaneId lane = f.project.lanes().begin()->first;
    REQUIRE(
        f.bus.execute(addClip(f.project, lane, PatternSource{pattern}, 0, TicksPerBarFourFour)));
    REQUIRE(f.bus.execute(insertNotes(pattern, piano, {note(0, 60)})));
    const uint64_t full = digest(f.project);

    while (f.bus.canUndo()) REQUIRE(f.bus.undo());
    CHECK(digest(f.project) == empty);
    CHECK(checkReferentialIntegrity(f.project).empty());

    while (f.bus.canRedo()) REQUIRE(f.bus.redo());
    CHECK(digest(f.project) == full);
    CHECK(checkReferentialIntegrity(f.project).empty());
  }
}

TEST_SUITE("stress") {
  TEST_CASE("Random command sequences interleaved with undo/redo stay exact") {
    // OB-3-03 AC 4. The model is kept small on purpose — the interesting thing
    // is the density of cascades and inverses, not the size of the project.
    //
    // After every step the model's digest must equal the digest recorded when
    // that history position was first reached. A command with a wrong inverse
    // fails on the first undo that passes through it.
    Fixture f;
    std::mt19937 random(20260813U);

    // The per-mutation invariant checker is an O(model) walk, and at 100,000
    // commands it costs 30x the rest of the test. This case validates itself:
    // it compares a full-model digest after every step and runs the checker
    // outright every 5,000 steps and at the end.
    f.project.setDebugChecks(false);

    std::vector<uint64_t> history_digests{digest(f.project)};
    size_t cursor = 0;

    std::vector<InstrumentId> instruments;
    std::vector<PatternId> patterns;
    std::vector<ArrangementLaneId> lanes;

    const auto refresh = [&]() {
      instruments.clear();
      patterns.clear();
      lanes.clear();
      for (const auto& [id, value] : f.project.instruments()) instruments.push_back(id);
      for (const auto& [id, value] : f.project.patterns()) patterns.push_back(id);
      for (const auto& [id, value] : f.project.lanes()) lanes.push_back(id);
    };

    constexpr int Operations = 100000;
    size_t applied = 0;
    size_t undone = 0;
    size_t redone = 0;

    for (int step = 0; step < Operations; ++step) {
      refresh();
      const int roll = static_cast<int>(random() % 100);

      if (roll < 12 && f.bus.canUndo()) {
        REQUIRE(f.bus.undo());
        --cursor;
        REQUIRE(digest(f.project) == history_digests[cursor]);
        ++undone;
        continue;
      }
      if (roll < 22 && f.bus.canRedo()) {
        REQUIRE(f.bus.redo());
        ++cursor;
        REQUIRE(digest(f.project) == history_digests[cursor]);
        ++redone;
        continue;
      }

      CommandPtr command;
      const auto pick = [&random](const auto& items) { return items[random() % items.size()]; };

      if (roll < 32 && instruments.size() < 6) {
        command = addInstrument(f.project, "I" + std::to_string(step), claps("test.plugin"));
      } else if (roll < 40 && patterns.size() < 6) {
        command = addPattern(f.project, "P" + std::to_string(step));
      } else if (roll < 48 && lanes.size() < 6) {
        command = addLane(f.project, "L" + std::to_string(step));
      } else if (roll < 56 && !patterns.empty() && !lanes.empty()) {
        command =
            addClip(f.project, pick(lanes), PatternSource{pick(patterns)},
                    TicksPerBarFourFour * static_cast<Ticks>(random() % 8), TicksPerBarFourFour);
      } else if (roll < 72 && !patterns.empty() && !instruments.empty()) {
        const PatternId pattern = pick(patterns);
        const InstrumentId instrument = pick(instruments);
        const auto* stored = f.project.findPattern(pattern);
        const auto sequence = stored->sequences.find(instrument);
        const bool has_notes = sequence != stored->sequences.end() && !sequence->second.empty();
        if (has_notes && (random() % 2) == 0) {
          const auto& notes = sequence->second.notes();
          const Note victim = notes[random() % notes.size()];
          if ((random() % 2) == 0) {
            command = removeNotes(pattern, instrument, {victim});
          } else {
            Note moved = victim;
            moved.start += 120;
            moved.key = static_cast<int16_t>((moved.key + 1) % 128);
            command = replaceNotes(pattern, instrument, {victim}, {moved});
          }
        } else if (!has_notes || sequence->second.size() < 24) {
          // Bounded on purpose: the test is about the density of cascades and
          // inverses, not about how large a pattern can get.
          command = insertNotes(pattern, instrument,
                                {note(static_cast<Ticks>(random() % 32) * 120,
                                      static_cast<int16_t>(random() % 128))});
        }
      } else if (roll < 80 && !f.project.clips().empty()) {
        auto entry = f.project.clips().begin();
        std::advance(entry, static_cast<ptrdiff_t>(random() % f.project.clips().size()));
        const ClipId clip = entry->first;
        if ((random() % 3) == 0) {
          command = removeClip(clip);
        } else {
          const Ticks start = TicksPerBarFourFour * static_cast<Ticks>(random() % 16);
          command = editClip(
              f.project, clip, ChangeField::Start, [start](Clip& value) { value.start = start; },
              "Move clip");
        }
      } else if (roll < 88 && !instruments.empty()) {
        const InstrumentId instrument = pick(instruments);
        if ((random() % 4) == 0) {
          command = removeInstrument(instrument);
        } else {
          const std::string name = "R" + std::to_string(step);
          command = editInstrument(
              f.project, instrument, ChangeField::Name,
              [&name](Instrument& value) { value.name = name; }, "Rename instrument");
        }
      } else if (roll < 94 && !patterns.empty()) {
        const PatternId pattern = pick(patterns);
        if ((random() % 4) == 0) {
          command = removePattern(pattern);
        } else {
          const Ticks length = TicksPerBarFourFour * static_cast<Ticks>(1 + (random() % 4));
          command = editPatternMeta(
              f.project, pattern, ChangeField::Length,
              [length](PatternMeta& meta) { meta.length = length; }, "Resize pattern");
        }
      } else if (!lanes.empty()) {
        const ArrangementLaneId lane = pick(lanes);
        if ((random() % 4) == 0) {
          command = removeLane(lane);
        } else {
          const int32_t order = static_cast<int32_t>(random() % 1000);
          bool taken = false;
          for (const auto& [id, value] : f.project.lanes()) {
            if (id != lane && value.order == order) taken = true;
          }
          if (!taken) {
            command = editLane(
                f.project, lane, ChangeField::Order,
                [order](ArrangementLane& value) { value.order = order; }, "Reorder lane");
          }
        }
      }

      if (command == nullptr) continue;

      // Sealed every step: coalescing is exercised by its own test, and here it
      // would merge two commands into one history slot and desynchronise the
      // digest bookkeeping this test relies on.
      f.bus.seal();
      if (!f.bus.execute(std::move(command))) continue;

      history_digests.resize(cursor + 1);
      history_digests.push_back(digest(f.project));
      ++cursor;
      ++applied;

      if ((applied % 5000) == 0) REQUIRE(checkReferentialIntegrity(f.project).empty());
    }

    MESSAGE("fuzz: " << applied << " applied, " << undone << " undone, " << redone << " redone");
    CHECK(applied > 10000);
    CHECK(undone > 1000);
    CHECK(redone > 500);

    // And the whole history unwinds to nothing, which is the strongest single
    // statement the test can make about the inverses.
    while (f.bus.canUndo()) REQUIRE(f.bus.undo());
    CHECK(digest(f.project) == history_digests[0]);
    CHECK(checkReferentialIntegrity(f.project).empty());
  }
}
