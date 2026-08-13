// The domain model (OB-3-02), tested against ARCHITECTURE.md §2–§6.
//
// The interesting cases here are all negatives: things the model must make
// impossible, and cascades that must reach exactly as far as they should and no
// further. The anti-pattern table (§6) is walked item by item in
// docs/model-anti-pattern-review.md; the mechanical half of that walk lives in
// this file.
#include <set>
#include <string>
#include <vector>

#include "doctest.h"
#include "model/invariants.h"
#include "model/project.h"

using onebeat::model::ArrangementLaneId;
using onebeat::model::AutomationSource;
using onebeat::model::ChangeEvent;
using onebeat::model::ChangeField;
using onebeat::model::ChangeType;
using onebeat::model::checkReferentialIntegrity;
using onebeat::model::ClipId;
using onebeat::model::decodeUlid;
using onebeat::model::encodeUlid;
using onebeat::model::EntityKind;
using onebeat::model::IdGenerator;
using onebeat::model::InstrumentId;
using onebeat::model::MixerTrackId;
using onebeat::model::Note;
using onebeat::model::NoteSequence;
using onebeat::model::PatternId;
using onebeat::model::PatternSource;
using onebeat::model::PluginFormat;
using onebeat::model::PluginRef;
using onebeat::model::Preferences;
using onebeat::model::Project;
using onebeat::model::RawId;
using onebeat::model::Ticks;
using onebeat::model::TicksPerBarFourFour;
using onebeat::model::velocityFromMidi1;

namespace {

PluginRef claps(const std::string& id) {
  PluginRef plugin;
  plugin.format = PluginFormat::Clap;
  plugin.id = id;
  plugin.name = id;
  plugin.vendor = "Test";
  return plugin;
}

Note note(Ticks start, int16_t key) {
  Note value;
  value.start = start;
  value.length = 240;
  value.key = key;
  value.velocity = velocityFromMidi1(100);
  return value;
}

// A project with a deterministic generator, so failures name the same IDs on
// every run and in every CI job.
Project fixedProject() {
  return Project(IdGenerator::deterministic(0xB0A7ULL));
}

}  // namespace

TEST_SUITE("unit") {
  // ------------------------------------------------------------------------
  // Identity (§1, FR-PRJ-02, ADR-004)
  // ------------------------------------------------------------------------

  TEST_CASE("A ULID round-trips through its text form") {
    const RawId id{0x0192FEDCBA987654ULL, 0x0123456789ABCDEFULL};
    const std::string text = encodeUlid(id);
    CHECK(text.size() == 26);
    const auto decoded = decodeUlid(text);
    REQUIRE(decoded.has_value());
    CHECK(*decoded == id);
  }

  TEST_CASE("An ID carrying the wrong prefix does not parse as another kind") {
    IdGenerator generator = IdGenerator::deterministic(7);
    const InstrumentId instrument = generator.next<EntityKind::Instrument>();
    const std::string text = instrument.str();

    CHECK(text.rfind("ins_", 0) == 0);
    CHECK(InstrumentId::parse(text).has_value());
    // The same 26 characters, addressed as a lane, is a dangling reference the
    // loader must reject rather than resolve to something plausible.
    CHECK_FALSE(ArrangementLaneId::parse(text).has_value());
  }

  TEST_CASE("A deterministic generator is reproducible and strictly increasing") {
    IdGenerator first = IdGenerator::deterministic(42);
    IdGenerator second = IdGenerator::deterministic(42);

    RawId previous{};
    for (int i = 0; i < 100; ++i) {
      const RawId a = first.nextRaw();
      const RawId b = second.nextRaw();
      CHECK(a == b);
      if (i > 0) CHECK(previous < a);
      previous = a;
    }
  }

  TEST_CASE("IDs are never reused across 10k create/delete cycles") {
    // ADR-004 chose ULIDs so that never-reuse is structural: there is no
    // counter to persist and no tombstone list, and this is the test that says
    // so. If it ever fails, the identifier scheme changed, not the bookkeeping.
    Project project = fixedProject();
    std::set<std::string> seen;

    for (int i = 0; i < 10000; ++i) {
      const PatternId pattern = project.createPattern("scratch");
      CHECK(seen.insert(pattern.str()).second);
      REQUIRE(project.deletePattern(pattern));
    }
    CHECK(seen.size() == 10000);
    CHECK(project.patterns().empty());
  }

  // ------------------------------------------------------------------------
  // The two axes (§2, §4)
  // ------------------------------------------------------------------------

  TEST_CASE("A new instrument gets its own mixer track, routed by ID") {
    Project project = fixedProject();
    const InstrumentId instrument = project.createInstrument("Kick", claps("test.kick"));

    const auto* stored = project.findInstrument(instrument);
    REQUIRE(stored != nullptr);
    REQUIRE(stored->routing.size() == 1);
    // D-M2: not Master. A beginner can EQ their kick without first learning a
    // routing system.
    CHECK(stored->routing[0].track != project.masterTrack());
    const auto* track = project.findMixerTrack(stored->routing[0].track);
    REQUIRE(track != nullptr);
    CHECK(track->name == "Kick");
    CHECK(track->output.has_value());
    CHECK(*track->output == project.masterTrack());
  }

  TEST_CASE("The auto-track preference is honoured") {
    Project project = fixedProject();
    Preferences preferences;
    preferences.auto_create_mixer_track = false;
    project.setPreferences(preferences);

    const InstrumentId instrument = project.createInstrument("Kick", claps("test.kick"));
    const auto* stored = project.findInstrument(instrument);
    REQUIRE(stored != nullptr);
    CHECK(stored->routing[0].track == project.masterTrack());
    CHECK(project.mixerTracks().size() == 1);
  }

  TEST_CASE("Many instruments share one mixer track") {
    // Anti-pattern §6.4: a hardwired 1:1 instrument↔track relationship makes
    // drum busses impossible. Eight instruments into one track is normal.
    Project project = fixedProject();
    const MixerTrackId drums = project.createMixerTrack("Drums");

    for (int i = 0; i < 8; ++i) {
      const InstrumentId instrument =
          project.createInstrument("Drum " + std::to_string(i), claps("test.drum"));
      REQUIRE(project.updateInstrument(
          instrument, ChangeField::Routing,
          [drums](onebeat::model::Instrument& value) { value.routing[0].track = drums; }));
    }

    size_t routed = 0;
    for (const auto& [id, instrument] : project.instruments()) {
      if (instrument.routing[0].track == drums) ++routed;
    }
    CHECK(routed == 8);
    CHECK(project.mixerTrackImpact(drums).instruments.size() == 8);
  }

  TEST_CASE("Lane order is a field, so reordering touches no clip") {
    Project project = fixedProject();
    const PatternId pattern = project.createPattern("Verse");
    const ArrangementLaneId first = project.createLane("Keys");
    const ArrangementLaneId second = project.createLane("Bass");
    const ClipId clip = project.createClip(second, PatternSource{pattern}, 0, TicksPerBarFourFour);

    REQUIRE(project.findLane(first)->order == 0);
    REQUIRE(project.findLane(second)->order == 1);

    REQUIRE(project.updateLane(first, ChangeField::Order,
                               [](onebeat::model::ArrangementLane& lane) { lane.order = 5; }));

    // The clip's record is untouched: it names its lane, and the lane's order
    // is the lane's business (FR-PRJ-02).
    CHECK(project.findClip(clip)->lane == second);
    CHECK(project.findClip(clip)->start == 0);
  }

  // ------------------------------------------------------------------------
  // Patterns are references, not copies (§3.3, anti-pattern §6.3)
  // ------------------------------------------------------------------------

  TEST_CASE("Editing a pattern is seen by every clip that references it") {
    Project project = fixedProject();
    const InstrumentId instrument = project.createInstrument("Piano", claps("test.piano"));
    const PatternId pattern = project.createPattern("Verse");
    const ArrangementLaneId lane = project.createLane("Keys");

    const ClipId a = project.createClip(lane, PatternSource{pattern}, 0, TicksPerBarFourFour);
    const ClipId b =
        project.createClip(lane, PatternSource{pattern}, TicksPerBarFourFour, TicksPerBarFourFour);
    CHECK(project.patternUsageCount(pattern) == 2);

    REQUIRE(project.updateSequence(pattern, instrument, [](NoteSequence& sequence) {
      sequence.insert(note(0, 60));
      sequence.insert(note(480, 64));
    }));

    // Both placements resolve to the same pattern; there is no per-clip note
    // storage to fall out of step, because a clip holds a PatternId and the
    // type system offers no other path to notes.
    for (const ClipId id : {a, b}) {
      const auto* clip = project.findClip(id);
      REQUIRE(clip != nullptr);
      REQUIRE(clip->pattern() != nullptr);
      const auto* referenced = project.findPattern(clip->pattern()->pattern);
      REQUIRE(referenced != nullptr);
      CHECK(referenced->sequences.at(instrument).size() == 2);
    }
  }

  TEST_CASE("A clip referencing something absent never enters the model") {
    Project project = fixedProject();
    const ArrangementLaneId lane = project.createLane("Keys");
    PatternId stale = project.createPattern("Gone");
    REQUIRE(project.deletePattern(stale));

    const ClipId clip = project.createClip(lane, PatternSource{stale}, 0, TicksPerBarFourFour);
    CHECK_FALSE(clip.valid());
    CHECK(project.clips().empty());
  }

  TEST_CASE("A pattern's sequence map stays sparse") {
    Project project = fixedProject();
    const InstrumentId instrument = project.createInstrument("Piano", claps("test.piano"));
    const PatternId pattern = project.createPattern("Verse");

    REQUIRE(project.updateSequence(pattern, instrument,
                                   [](NoteSequence& sequence) { sequence.insert(note(0, 60)); }));
    CHECK(project.findPattern(pattern)->sequences.size() == 1);

    // Emptying a sequence removes it: the pattern must not claim to use an
    // instrument it holds no notes for (D-M5 is a view over this map).
    REQUIRE(project.updateSequence(pattern, instrument,
                                   [](NoteSequence& sequence) { sequence.clear(); }));
    CHECK(project.findPattern(pattern)->sequences.empty());
  }

  // ------------------------------------------------------------------------
  // Cascades and impact reports (§6 of the ticket, ARCHITECTURE.md §3.1)
  // ------------------------------------------------------------------------

  TEST_CASE("Deleting an instrument reports and removes its notes from every pattern") {
    Project project = fixedProject();
    const InstrumentId kick = project.createInstrument("Kick", claps("test.kick"));
    const InstrumentId snare = project.createInstrument("Snare", claps("test.snare"));

    // A 3×2 matrix: both instruments used in three patterns.
    std::vector<PatternId> patterns;
    for (int i = 0; i < 3; ++i) {
      const PatternId pattern = project.createPattern("Pattern " + std::to_string(i));
      patterns.push_back(pattern);
      REQUIRE(project.updateSequence(pattern, kick, [](NoteSequence& sequence) {
        sequence.insert(note(0, 36));
        sequence.insert(note(960, 36));
      }));
      REQUIRE(project.updateSequence(
          pattern, snare, [](NoteSequence& sequence) { sequence.insert(note(480, 38)); }));
    }

    const auto impact = project.instrumentImpact(kick);
    CHECK(impact.patterns.size() == 3);
    CHECK(impact.note_count == 6);  // what the confirmation dialog must state
    CHECK(impact.tracks.size() == 1);

    REQUIRE(project.deleteInstrument(kick));

    for (const PatternId pattern : patterns) {
      const auto* stored = project.findPattern(pattern);
      REQUIRE(stored != nullptr);
      CHECK(stored->sequences.count(kick) == 0);
      // The cascade reaches exactly as far as it should: the snare is untouched.
      CHECK(stored->sequences.at(snare).size() == 1);
    }
    CHECK(project.findInstrument(kick) == nullptr);
  }

  TEST_CASE("Deleting a pattern takes its placements and nothing else") {
    Project project = fixedProject();
    const PatternId doomed = project.createPattern("Doomed");
    const PatternId kept = project.createPattern("Kept");
    const ArrangementLaneId lane = project.createLane("Lane");

    project.createClip(lane, PatternSource{doomed}, 0, TicksPerBarFourFour);
    project.createClip(lane, PatternSource{doomed}, TicksPerBarFourFour, TicksPerBarFourFour);
    const ClipId survivor =
        project.createClip(lane, PatternSource{kept}, TicksPerBarFourFour * 2, TicksPerBarFourFour);

    CHECK(project.patternImpact(doomed).clips.size() == 2);
    REQUIRE(project.deletePattern(doomed));

    CHECK(project.clips().size() == 1);
    CHECK(project.findClip(survivor) != nullptr);
    CHECK(project.findLane(lane) != nullptr);
  }

  TEST_CASE("Deleting a lane takes its clips and leaves the patterns alone") {
    Project project = fixedProject();
    const PatternId pattern = project.createPattern("Verse");
    const ArrangementLaneId lane = project.createLane("Keys");
    const ArrangementLaneId other = project.createLane("Bass");
    project.createClip(lane, PatternSource{pattern}, 0, TicksPerBarFourFour);
    const ClipId elsewhere =
        project.createClip(other, PatternSource{pattern}, 0, TicksPerBarFourFour);

    CHECK(project.laneImpact(lane).clips.size() == 1);
    REQUIRE(project.deleteLane(lane));

    CHECK(project.findPattern(pattern) != nullptr);
    CHECK(project.findClip(elsewhere) != nullptr);
    CHECK(project.clips().size() == 1);
  }

  TEST_CASE("Deleting a mixer track re-points what fed it instead of orphaning it") {
    Project project = fixedProject();
    const InstrumentId instrument = project.createInstrument("Bass", claps("test.bass"));
    const MixerTrackId own = project.findInstrument(instrument)->routing[0].track;
    const MixerTrackId bus = project.createMixerTrack("Bus");
    REQUIRE(
        project.updateMixerTrack(own, ChangeField::Output,
                                 [bus](onebeat::model::MixerTrack& track) { track.output = bus; }));

    REQUIRE(project.deleteMixerTrack(bus));
    // The instrument still makes sound, into Master. Nothing is lost, which is
    // the only acceptable outcome of deleting a routing destination.
    CHECK(project.findMixerTrack(own)->output.value() == project.masterTrack());

    REQUIRE(project.deleteMixerTrack(own));
    CHECK(project.findInstrument(instrument)->routing[0].track == project.masterTrack());
  }

  TEST_CASE("Master cannot be deleted") {
    Project project = fixedProject();
    CHECK_FALSE(project.deleteMixerTrack(project.masterTrack()));
    CHECK(project.findMixerTrack(project.masterTrack()) != nullptr);
  }

  TEST_CASE("An automation clip dies with the target it automates") {
    Project project = fixedProject();
    const InstrumentId instrument = project.createInstrument("Lead", claps("test.lead"));
    const ArrangementLaneId lane = project.createLane("Automation");

    AutomationSource source;
    source.target_kind = AutomationSource::TargetKind::Instrument;
    source.instrument = instrument;
    source.parameter = 3;
    const ClipId clip = project.createClip(lane, source, 0, TicksPerBarFourFour);
    REQUIRE(clip.valid());

    CHECK(project.instrumentImpact(instrument).clips.size() == 1);
    REQUIRE(project.deleteInstrument(instrument));
    CHECK(project.findClip(clip) == nullptr);
  }

  // ------------------------------------------------------------------------
  // Change notification (§7)
  // ------------------------------------------------------------------------

  TEST_CASE("Change events name the entity and the field that changed") {
    Project project = fixedProject();
    std::vector<ChangeEvent> events;
    const auto token = project.changes().subscribe(
        [&events](const ChangeEvent& event) { events.push_back(event); });

    const InstrumentId instrument = project.createInstrument("Piano", claps("test.piano"));
    const PatternId pattern = project.createPattern("Verse");
    events.clear();

    REQUIRE(
        project.updateInstrument(instrument, ChangeField::Name,
                                 [](onebeat::model::Instrument& value) { value.name = "Rhodes"; }));
    REQUIRE(events.size() == 1);
    CHECK(events[0].type == ChangeType::Modified);
    CHECK(events[0].kind == EntityKind::Instrument);
    CHECK(events[0].field == ChangeField::Name);
    CHECK(events[0].id == instrument.raw());

    events.clear();
    REQUIRE(project.updateSequence(pattern, instrument,
                                   [](NoteSequence& sequence) { sequence.insert(note(0, 60)); }));
    REQUIRE(events.size() == 1);
    CHECK(events[0].kind == EntityKind::Pattern);
    CHECK(events[0].field == ChangeField::Notes);
    // Note edits carry which instrument's sequence moved, so the channel rack
    // repaints one row rather than the whole pattern.
    CHECK(events[0].related == instrument.raw());

    project.changes().unsubscribe(token);
    events.clear();
    REQUIRE(project.updatePattern(pattern, ChangeField::Name,
                                  [](onebeat::model::Pattern& value) { value.name = "Chorus"; }));
    CHECK(events.empty());
  }

  TEST_CASE("Deleting an instrument tells listeners about every pattern it touched") {
    Project project = fixedProject();
    const InstrumentId instrument = project.createInstrument("Kick", claps("test.kick"));
    const PatternId first = project.createPattern("A");
    const PatternId second = project.createPattern("B");
    for (const PatternId pattern : {first, second}) {
      REQUIRE(project.updateSequence(pattern, instrument,
                                     [](NoteSequence& sequence) { sequence.insert(note(0, 36)); }));
    }

    std::vector<ChangeEvent> events;
    project.changes().subscribe([&events](const ChangeEvent& event) { events.push_back(event); });
    REQUIRE(project.deleteInstrument(instrument));

    size_t pattern_notices = 0;
    bool removed_instrument = false;
    for (const ChangeEvent& event : events) {
      if (event.kind == EntityKind::Pattern && event.field == ChangeField::Notes) ++pattern_notices;
      if (event.kind == EntityKind::Instrument && event.type == ChangeType::Removed) {
        removed_instrument = true;
      }
    }
    CHECK(pattern_notices == 2);
    CHECK(removed_instrument);
  }

  // ------------------------------------------------------------------------
  // Invariants (§6)
  // ------------------------------------------------------------------------

  TEST_CASE("A project built through the model's own operations is always consistent") {
    Project project = fixedProject();
    const InstrumentId instrument = project.createInstrument("Piano", claps("test.piano"));
    const PatternId pattern = project.createPattern("Verse");
    const ArrangementLaneId lane = project.createLane("Keys");
    project.createClip(lane, PatternSource{pattern}, 0, TicksPerBarFourFour);
    REQUIRE(project.updateSequence(pattern, instrument,
                                   [](NoteSequence& sequence) { sequence.insert(note(0, 60)); }));

    CHECK(checkReferentialIntegrity(project).empty());
  }

  TEST_CASE("The checker catches what a hand-edited file can break") {
    // Reached through `adopt`, which is the load path's seam: a file may say
    // anything, and the loader must report rather than abort.
    Project project = fixedProject();
    const InstrumentId instrument = project.createInstrument("Piano", claps("test.piano"));
    const PatternId pattern = project.createPattern("Verse");
    const ArrangementLaneId lane = project.createLane("Keys");
    project.createClip(lane, PatternSource{pattern}, 0, TicksPerBarFourFour);
    REQUIRE(project.updateSequence(pattern, instrument,
                                   [](NoteSequence& sequence) { sequence.insert(note(0, 60)); }));

    SUBCASE("a clip pointing at a deleted pattern") {
      Project::Tables tables = project.copyTables();
      tables.patterns.clear();
      Project broken = fixedProject();
      broken.adopt(std::move(tables));
      CHECK_FALSE(checkReferentialIntegrity(broken).empty());
    }

    SUBCASE("a sequence for an instrument that is gone") {
      Project::Tables tables = project.copyTables();
      tables.instruments.clear();
      Project broken = fixedProject();
      broken.adopt(std::move(tables));
      CHECK_FALSE(checkReferentialIntegrity(broken).empty());
    }

    SUBCASE("two lanes claiming the same order") {
      Project::Tables tables = project.copyTables();
      const ArrangementLaneId second = project.createLane("Bass");
      tables = project.copyTables();
      tables.lanes.at(second).order = tables.lanes.at(lane).order;
      Project broken = fixedProject();
      broken.adopt(std::move(tables));
      CHECK_FALSE(checkReferentialIntegrity(broken).empty());
    }

    SUBCASE("a mixer routing cycle") {
      Project::Tables tables = project.copyTables();
      const MixerTrackId a = project.createMixerTrack("A");
      const MixerTrackId b = project.createMixerTrack("B");
      tables = project.copyTables();
      tables.mixer_tracks.at(a).output = b;
      tables.mixer_tracks.at(b).output = a;
      Project broken = fixedProject();
      broken.adopt(std::move(tables));
      CHECK_FALSE(checkReferentialIntegrity(broken).empty());
    }

    SUBCASE("no master at all") {
      Project::Tables tables = project.copyTables();
      for (auto& [id, track] : tables.mixer_tracks) {
        if (!track.output.has_value()) track.output = id;
      }
      Project broken = fixedProject();
      broken.adopt(std::move(tables));
      CHECK_FALSE(checkReferentialIntegrity(broken).empty());
    }
  }

  // ------------------------------------------------------------------------
  // Notes (§2 storage only — editing is OB-3-08)
  // ------------------------------------------------------------------------

  TEST_CASE("A sequence keeps canonical order however notes arrive") {
    NoteSequence sequence;
    sequence.insert(note(960, 64));
    sequence.insert(note(0, 67));
    sequence.insert(note(0, 60));
    sequence.insert(note(480, 62));

    CHECK(sequence.isSorted());
    const auto& notes = sequence.notes();
    REQUIRE(notes.size() == 4);
    CHECK(notes[0].key == 60);  // same start, lower key first
    CHECK(notes[1].key == 67);
    CHECK(notes[2].start == 480);
    CHECK(notes[3].start == 960);
    CHECK(sequence.contentEnd() == 1200);
  }

  TEST_CASE("MIDI-1 velocity survives the 14-bit representation exactly") {
    for (int midi = 0; midi <= 127; ++midi) {
      const auto velocity = velocityFromMidi1(static_cast<uint8_t>(midi));
      CHECK(velocity % 129 == 0);
      CHECK(velocity / 129 == midi);
    }
    CHECK(velocityFromMidi1(127) == onebeat::model::MaxVelocity);
  }
}
