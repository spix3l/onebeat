// Project save/load (OB-3-05): the canonical writer, the forgiving reader, and
// the atomic bundle swap.
//
// The three claims this file is here to hold up, in the order they matter:
//
//   1. **Saving twice produces the same bytes**, and loading then saving
//      reproduces the file exactly — including the parts of the file this
//      version does not understand.
//   2. **A damaged project opens.** Every recoverable problem in
//      docs/project-format.md §8 has a case here, and each one asserts on the
//      *message*, because "it did not crash" is not the promise; FR-UX-12 is.
//   3. **A save cannot destroy the previous save.** There is a real fork and a
//      real SIGKILL at the one instant where it would hurt most.
#include <signal.h>
#include <sys/wait.h>
#include <unistd.h>

#include <clocale>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <sstream>
#include <string>
#include <vector>

#include "doctest.h"
#include "model/commands.h"
#include "model/json.h"
#include "model/project_io.h"

using onebeat::model::ArrangementLane;
using onebeat::model::ArrangementLaneId;
using onebeat::model::AutomationPoint;
using onebeat::model::AutomationSource;
using onebeat::model::Clip;
using onebeat::model::ClipId;
using onebeat::model::IdGenerator;
using onebeat::model::Instrument;
using onebeat::model::InstrumentId;
using onebeat::model::LoadIssue;
using onebeat::model::LoadOptions;
using onebeat::model::loadProject;
using onebeat::model::loadProjectJson;
using onebeat::model::LoadReport;
using onebeat::model::MixerTrack;
using onebeat::model::MixerTrackId;
using onebeat::model::Note;
using onebeat::model::NoteSequence;
using onebeat::model::OutputRoute;
using onebeat::model::Pattern;
using onebeat::model::PatternId;
using onebeat::model::PatternSource;
using onebeat::model::PluginFormat;
using onebeat::model::PluginRef;
using onebeat::model::Project;
using onebeat::model::Residue;
using onebeat::model::SaveOptions;
using onebeat::model::saveProject;
using onebeat::model::SaveReport;
using onebeat::model::sha256Hex;
using onebeat::model::Ticks;
using onebeat::model::TicksPerBarFourFour;
using onebeat::model::TicksPerQuarter;
using onebeat::model::velocityFromMidi1;
using onebeat::model::writeProjectJson;

namespace json = onebeat::model::json;

namespace {

// A directory that removes itself, so a failing assertion cannot leave a
// half-written bundle behind for the next run to trip over.
class TempDir {
 public:
  explicit TempDir(const std::string& label) {
    path_ = std::filesystem::temp_directory_path() /
            ("onebeat-io-" + label + "-" + std::to_string(::getpid()) + "-" +
             std::to_string(counter()++));
    std::filesystem::remove_all(path_);
    std::filesystem::create_directories(path_);
  }
  ~TempDir() {
    std::error_code code;
    std::filesystem::remove_all(path_, code);
  }
  TempDir(const TempDir&) = delete;
  TempDir& operator=(const TempDir&) = delete;

  const std::filesystem::path& path() const { return path_; }
  std::filesystem::path operator/(const std::string& name) const { return path_ / name; }

 private:
  static int& counter() {
    static int value = 0;
    return value;
  }
  std::filesystem::path path_;
};

std::string readWhole(const std::filesystem::path& path) {
  std::ifstream file(path, std::ios::binary);
  std::ostringstream out;
  out << file.rdbuf();
  return out.str();
}

std::vector<std::byte> bytesOf(std::string_view text) {
  std::vector<std::byte> out(text.size());
  std::memcpy(out.data(), text.data(), text.size());
  return out;
}

bool contains(const std::string& haystack, const std::string& needle) {
  return haystack.find(needle) != std::string::npos;
}

// True when the report says something about `needle`, whatever its severity.
bool reported(const LoadReport& report, const std::string& needle) {
  return contains(report.describe(), needle);
}

// A project with one of everything that has a field: four instruments' worth of
// variety in one, so that "deep equality" has something to be wrong about.
struct Fixture {
  Project project{IdGenerator::deterministic(0x0B7ULL)};
  InstrumentId piano;
  InstrumentId bass;
  PatternId verse;
  ArrangementLaneId keys;
  ClipId clip;
  MixerTrackId bus;

  Fixture() {
    PluginRef ref;
    ref.format = PluginFormat::Clap;
    ref.id = "com.onebeat.piano";
    ref.name = "OneBeat Piano";
    ref.vendor = "OneBeat";
    ref.path_hint = "@bundled/OneBeatPiano.clap";
    piano = project.createInstrument("Piano", ref);

    ref.id = "org.surge-synth-team.surge-xt";
    ref.name = "Surge XT";
    ref.vendor = "Surge Synth Team";
    ref.path_hint = "/Library/Audio/Plug-Ins/CLAP/Surge XT.clap";
    bass = project.createInstrument("Bass", ref);

    bus = project.createMixerTrack("Bus", project.masterTrack());
    project.updateInstrument(
        bass, onebeat::model::ChangeField::Routing,
        [&](Instrument& instrument) { instrument.routing = {OutputRoute{1, bus}}; });

    verse = project.createPattern("Verse", TicksPerBarFourFour * 2);
    project.updateSequence(verse, piano, [](NoteSequence& sequence) {
      sequence.insert(Note{0, 480, 60, velocityFromMidi1(100)});
      sequence.insert(Note{480, 240, 64, velocityFromMidi1(80)});
      sequence.insert(Note{960, 1920, 67, velocityFromMidi1(127)});
    });
    project.updateSequence(verse, bass, [](NoteSequence& sequence) {
      sequence.insert(Note{0, 720, 36, velocityFromMidi1(110)});
    });

    keys = project.createLane("Keys");
    project.updateLane(keys, onebeat::model::ChangeField::Name, [](ArrangementLane& lane) {
      lane.color = "#4FB286";
      lane.height = 120;
      lane.muted = true;
    });
    clip = project.createClip(keys, PatternSource{verse}, TicksPerBarFourFour,
                              TicksPerBarFourFour * 4);
    project.updateClip(clip, onebeat::model::ChangeField::Transforms, [](Clip& value) {
      value.transforms.transpose = -3;
      value.transforms.window_start = 240;
      value.transforms.velocity_scale = 0.75F;
    });

    onebeat::model::TransportState transport;
    transport.tempo = 128.5;
    transport.time_signature = {7, 8};
    transport.loop_enabled = true;
    transport.loop_end = TicksPerBarFourFour * 3;
    project.setTransport(transport);

    onebeat::model::ProjectMeta meta;
    meta.name = "Round trip";
    meta.created_with = "OneBeat 0.3.0";
    project.setMeta(meta);
  }
};

// Deep model equality, field by field. Deliberately not a hash: when this fails
// it must say *which* field the file lost.
void requireSameModel(const Project& a, const Project& b) {
  REQUIRE(a.meta().name == b.meta().name);
  REQUIRE(a.meta().created_with == b.meta().created_with);
  REQUIRE(a.transport().tempo == doctest::Approx(b.transport().tempo));
  REQUIRE(a.transport().time_signature.numerator == b.transport().time_signature.numerator);
  REQUIRE(a.transport().time_signature.denominator == b.transport().time_signature.denominator);
  REQUIRE(a.transport().loop_enabled == b.transport().loop_enabled);
  REQUIRE(a.transport().loop_start == b.transport().loop_start);
  REQUIRE(a.transport().loop_end == b.transport().loop_end);
  REQUIRE(a.masterTrack() == b.masterTrack());

  REQUIRE(a.instruments().size() == b.instruments().size());
  for (const auto& [id, left] : a.instruments()) {
    const Instrument* right = b.findInstrument(id);
    REQUIRE(right != nullptr);
    CHECK(left.name == right->name);
    CHECK(left.color == right->color);
    CHECK(left.order == right->order);
    CHECK(left.muted == right->muted);
    CHECK(left.plugin.format == right->plugin.format);
    CHECK(left.plugin.id == right->plugin.id);
    CHECK(left.plugin.name == right->plugin.name);
    CHECK(left.plugin.vendor == right->plugin.vendor);
    CHECK(left.plugin.path_hint == right->plugin.path_hint);
    CHECK(left.plugin.state_ref == right->plugin.state_ref);
    CHECK(left.plugin.state_sha256 == right->plugin.state_sha256);
    CHECK(left.note_defaults.velocity == right->note_defaults.velocity);
    CHECK(left.note_defaults.pan == doctest::Approx(right->note_defaults.pan));
    CHECK(left.note_defaults.pitch_offset == right->note_defaults.pitch_offset);
    REQUIRE(left.routing.size() == right->routing.size());
    for (size_t i = 0; i < left.routing.size(); ++i) {
      CHECK(left.routing[i].port == right->routing[i].port);
      CHECK(left.routing[i].track == right->routing[i].track);
    }
  }

  REQUIRE(a.patterns().size() == b.patterns().size());
  for (const auto& [id, left] : a.patterns()) {
    const Pattern* right = b.findPattern(id);
    REQUIRE(right != nullptr);
    CHECK(left.name == right->name);
    CHECK(left.color == right->color);
    CHECK(left.length == right->length);
    REQUIRE(left.sequences.size() == right->sequences.size());
    for (const auto& [instrument, sequence] : left.sequences) {
      const auto other = right->sequences.find(instrument);
      REQUIRE(other != right->sequences.end());
      REQUIRE(sequence.notes() == other->second.notes());
    }
  }

  REQUIRE(a.lanes().size() == b.lanes().size());
  for (const auto& [id, left] : a.lanes()) {
    const ArrangementLane* right = b.findLane(id);
    REQUIRE(right != nullptr);
    CHECK(left.name == right->name);
    CHECK(left.color == right->color);
    CHECK(left.height == right->height);
    CHECK(left.order == right->order);
    CHECK(left.collapsed == right->collapsed);
    CHECK(left.muted == right->muted);
    CHECK(left.soloed == right->soloed);
    CHECK(left.group_id == right->group_id);
  }

  REQUIRE(a.clips().size() == b.clips().size());
  for (const auto& [id, left] : a.clips()) {
    const Clip* right = b.findClip(id);
    REQUIRE(right != nullptr);
    CHECK(left.lane == right->lane);
    CHECK(left.start == right->start);
    CHECK(left.length == right->length);
    CHECK(left.muted == right->muted);
    CHECK(left.transforms.transpose == right->transforms.transpose);
    CHECK(left.transforms.loop == right->transforms.loop);
    CHECK(left.transforms.window_start == right->transforms.window_start);
    CHECK(left.transforms.velocity_scale == doctest::Approx(right->transforms.velocity_scale));
    CHECK(left.transforms.time_nudge == right->transforms.time_nudge);
    CHECK(left.transforms.probability == doctest::Approx(right->transforms.probability));
    REQUIRE(left.isPattern() == right->isPattern());
    if (left.isPattern()) CHECK(left.pattern()->pattern == right->pattern()->pattern);
    if (const AutomationSource* source = left.automation()) {
      const AutomationSource* other = right->automation();
      REQUIRE(other != nullptr);
      CHECK(source->target_kind == other->target_kind);
      CHECK(source->parameter == other->parameter);
      REQUIRE(source->points.size() == other->points.size());
      for (size_t i = 0; i < source->points.size(); ++i) {
        CHECK(source->points[i].position == other->points[i].position);
        CHECK(source->points[i].value == doctest::Approx(other->points[i].value));
      }
    }
  }

  REQUIRE(a.mixerTracks().size() == b.mixerTracks().size());
  for (const auto& [id, left] : a.mixerTracks()) {
    const MixerTrack* right = b.findMixerTrack(id);
    REQUIRE(right != nullptr);
    CHECK(left.name == right->name);
    CHECK(left.gain == doctest::Approx(right->gain));
    CHECK(left.pan == doctest::Approx(right->pan));
    CHECK(left.muted == right->muted);
    CHECK(left.soloed == right->soloed);
    CHECK(left.output == right->output);
  }
}

}  // namespace

TEST_SUITE("unit") {
  // ------------------------------------------------------------------------
  // The writer's rules, one case per rule of docs/project-format.md §6
  // ------------------------------------------------------------------------

  TEST_CASE("The canonical writer follows its own rules") {
    json::Object root;
    root.emplace("zebra", json::Value::integer(1));
    root.emplace("alpha", json::Value::integer(2));
    root.emplace("version", json::Value::integer(1));
    root.emplace("format", json::Value::string("onebeat.project"));
    root.emplace("numbers", json::Value::array({json::Value::integer(0), json::Value::integer(480),
                                                json::Value::integer(60)}));
    root.emplace("strings",
                 json::Value::array({json::Value::string("a"), json::Value::string("b")}));
    root.emplace("empty_array", json::Value::array({}));
    root.emplace("empty_object", json::Value::object({}));
    root.emplace("real", json::Value::real(0.5));
    root.emplace("negative_zero", json::Value::real(-0.0));

    const std::string text =
        json::writeCanonical(json::Value::object(root), {"format", "version"}).value();

    const std::string expected =
        "{\n"
        "  \"format\": \"onebeat.project\",\n"
        "  \"version\": 1,\n"
        "  \"alpha\": 2,\n"
        "  \"empty_array\": [],\n"
        "  \"empty_object\": {},\n"
        "  \"negative_zero\": 0.000000,\n"
        "  \"numbers\": [0, 480, 60],\n"
        "  \"real\": 0.500000,\n"
        "  \"strings\": [\n"
        "    \"a\",\n"
        "    \"b\"\n"
        "  ],\n"
        "  \"zebra\": 1\n"
        "}\n";
    CHECK(text == expected);
  }

  TEST_CASE("A number that has no JSON spelling is refused, not written as null") {
    json::Object root;
    root.emplace("gain", json::Value::real(std::nan("")));
    CHECK_FALSE(json::writeCanonical(json::Value::object(root)).has_value());

    json::Object infinite;
    infinite.emplace("gain", json::Value::real(HUGE_VAL));
    CHECK_FALSE(json::writeCanonical(json::Value::object(infinite)).has_value());
  }

  TEST_CASE("Strings escape only what JSON requires") {
    CHECK(json::escapeString("plain") == "\"plain\"");
    CHECK(json::escapeString("say \"hi\"") == "\"say \\\"hi\\\"\"");
    CHECK(json::escapeString("back\\slash") == "\"back\\\\slash\"");
    CHECK(json::escapeString("line\nbreak") == "\"line\\u000abreak\"");
    // Non-ASCII stays literal, so a name in any script is readable in a diff.
    CHECK(json::escapeString("サビ") == "\"サビ\"");
    CHECK(json::escapeString("Éclair") == "\"Éclair\"");
  }

  TEST_CASE("Integers stay integers and reals keep six places") {
    json::ParseError error;
    const std::optional<json::Value> value =
        json::parse("{\"ticks\": 15360, \"tempo\": 112.0, \"big\": 9007199254740993}", error);
    REQUIRE(value.has_value());
    CHECK(value->find("ticks")->isInt());
    CHECK(value->find("ticks")->asInt() == 15360);
    // Above 2^53: a parser that stored everything as a double would lose this.
    CHECK(value->find("big")->asInt() == 9007199254740993LL);
    CHECK(value->find("tempo")->isReal());
    CHECK(json::writeCanonical(*value).value() ==
          "{\n  \"big\": 9007199254740993,\n  \"tempo\": 112.000000,\n  \"ticks\": 15360\n}\n");
  }

  TEST_CASE("Malformed JSON is reported with a position") {
    json::ParseError error;
    CHECK_FALSE(json::parse("{\"a\": 1,\n \"b\": }", error).has_value());
    CHECK(error.line == 2);
    CHECK(error.column > 0);
    CHECK_FALSE(error.message.empty());

    CHECK_FALSE(json::parse("", error).has_value());
    CHECK_FALSE(json::parse("{\"a\": 1} trailing", error).has_value());
    CHECK(json::parse("\xEF\xBB\xBF{\"a\": 1}", error).has_value());  // a BOM is tolerated
  }

  TEST_CASE("Escapes survive a round trip") {
    json::ParseError error;
    const std::optional<json::Value> value =
        json::parse(R"({"a": "tab\there", "b": "éA", "c": "🎹"})", error);
    REQUIRE(value.has_value());
    CHECK(*value->find("a")->asString() == "tab\there");
    CHECK(*value->find("b")->asString() == "éA");
    CHECK(*value->find("c")->asString() == "🎹");  // surrogate pair → one code point
  }

  TEST_CASE("The file does not depend on the machine's locale") {
    Fixture fixture;
    const std::string reference = writeProjectJson(fixture.project, Residue{});

    // A locale whose decimal separator is a comma. If it is not installed on
    // this machine the test still runs; the assertion it makes is then that
    // nothing changed, which is also true.
    const char* previous = std::setlocale(LC_NUMERIC, nullptr);
    const std::string saved = previous == nullptr ? "C" : previous;
    if (std::setlocale(LC_NUMERIC, "de_DE.UTF-8") != nullptr) {
      const std::string german = writeProjectJson(fixture.project, Residue{});
      CHECK(german == reference);
      CHECK(contains(german, "\"tempo\": 128.500000"));

      Project reloaded;
      Residue residue;
      const LoadReport report = loadProjectJson(german, reloaded, residue);
      REQUIRE(report.ok);
      CHECK(reloaded.transport().tempo == doctest::Approx(128.5));
    }
    std::setlocale(LC_NUMERIC, saved.c_str());
  }

  // ------------------------------------------------------------------------
  // Round trip
  // ------------------------------------------------------------------------

  TEST_CASE("Load then save is byte-identical, and the model comes back whole") {
    Fixture fixture;
    const std::string first = writeProjectJson(fixture.project, Residue{});
    REQUIRE_FALSE(first.empty());

    Project reloaded;
    Residue residue;
    const LoadReport report = loadProjectJson(first, reloaded, residue);
    REQUIRE(report.ok);
    CHECK(report.clean());

    const std::string second = writeProjectJson(reloaded, residue);
    CHECK(second == first);
    requireSameModel(fixture.project, reloaded);

    // And a third time from the reloaded model, because a writer that is
    // stable only on its own output is not stable.
    Project again;
    Residue again_residue;
    REQUIRE(loadProjectJson(second, again, again_residue).ok);
    CHECK(writeProjectJson(again, again_residue) == first);
  }

  TEST_CASE("An automation clip round-trips its points") {
    Fixture fixture;
    AutomationSource automation;
    automation.target_kind = AutomationSource::TargetKind::Instrument;
    automation.instrument = fixture.piano;
    automation.parameter = 7;
    automation.points = {AutomationPoint{0, 0.25F}, AutomationPoint{960, 0.75F}};
    const ClipId id = fixture.project.createClip(fixture.keys, automation, 0, TicksPerBarFourFour);
    REQUIRE(fixture.project.findClip(id) != nullptr);

    const std::string text = writeProjectJson(fixture.project, Residue{});
    CHECK(contains(text, "\"points\": [\n"));
    CHECK(contains(text, "[0, 0.250000]"));

    Project reloaded;
    Residue residue;
    REQUIRE(loadProjectJson(text, reloaded, residue).ok);
    requireSameModel(fixture.project, reloaded);
    CHECK(writeProjectJson(reloaded, residue) == text);
  }

  TEST_CASE("An empty project round-trips") {
    Project project;
    const std::string text = writeProjectJson(project, Residue{});
    Project reloaded;
    Residue residue;
    const LoadReport report = loadProjectJson(text, reloaded, residue);
    REQUIRE(report.ok);
    CHECK(reloaded.mixerTracks().size() == 1);
    CHECK(reloaded.masterTrack() == project.masterTrack());
    CHECK(writeProjectJson(reloaded, residue) == text);
  }

  // ------------------------------------------------------------------------
  // Forward compatibility (FR-PRJ-03, §7)
  // ------------------------------------------------------------------------

  TEST_CASE("What a future version added is kept and written back in place") {
    Fixture fixture;
    std::string text = writeProjectJson(fixture.project, Residue{});

    // Four kinds of "from the future", one of each shape §7 names.
    const std::string instrument_key = fixture.piano.str();
    const std::string pattern_key = fixture.verse.str();
    text = [&] {
      json::ParseError error;
      std::optional<json::Value> document = json::parse(text, error);
      REQUIRE(document.has_value());
      json::Object& root = *document->asObject();

      // (1) a whole top-level map nobody here has heard of
      json::Object modulations;
      json::Object one;
      one.emplace("depth", json::Value::real(0.5));
      modulations.emplace("mod_01K2QF8Z90000000000000001", json::Value::object(one));
      root.emplace("modulations", json::Value::object(modulations));

      // (2) an unknown field on a known entity
      json::Object* instruments = root.at("instruments").asObject();
      instruments->at(instrument_key).asObject()->emplace("macro_count", json::Value::integer(4));

      // (3) an unknown property on a note
      json::Object* patterns = root.at("patterns").asObject();
      json::Object* sequences = patterns->at(pattern_key).asObject()->at("sequences").asObject();
      json::Array notes = *sequences->at(instrument_key).asArray();
      json::Array first = *notes[0].asArray();
      json::Object properties;
      properties.emplace("pan", json::Value::real(-0.25));
      first.push_back(json::Value::object(properties));
      notes[0] = json::Value::array(first);
      sequences->at(instrument_key) = json::Value::array(notes);

      // (4) an entity of a kind this version cannot model at all
      json::Object* clips = root.at("clips").asObject();
      json::Object future_clip;
      json::Object future_source;
      future_source.emplace("type", json::Value::string("granular"));
      future_source.emplace("grain_size", json::Value::integer(120));
      future_clip.emplace("lane_id", json::Value::string(fixture.keys.str()));
      future_clip.emplace("start", json::Value::integer(0));
      future_clip.emplace("length", json::Value::integer(960));
      future_clip.emplace("source", json::Value::object(future_source));
      clips->emplace("clp_01K2QF8Z990000000000000010", json::Value::object(future_clip));

      return json::writeCanonical(*document, {"format", "version"}).value();
    }();

    Project reloaded;
    Residue residue;
    const LoadReport report = loadProjectJson(text, reloaded, residue);
    REQUIRE(report.ok);
    // Kept, and said so — silently keeping it would be just as wrong as
    // silently dropping it, because the UI has to be able to say the project
    // holds things this version will not play.
    CHECK(reported(report, "Kept, not understood: top-level 'modulations'"));
    CHECK(reported(report, "'granular'"));
    CHECK(reloaded.clips().size() == 1);  // the granular clip is not in the session

    const std::string rewritten = writeProjectJson(reloaded, residue);
    CHECK(rewritten == text);
  }

  TEST_CASE("The properties of a note that was edited away do not move to another note") {
    Fixture fixture;
    const std::string instrument_key = fixture.piano.str();
    const std::string pattern_key = fixture.verse.str();

    json::ParseError error;
    std::optional<json::Value> document =
        json::parse(writeProjectJson(fixture.project, Residue{}), error);
    REQUIRE(document.has_value());
    json::Object* sequences = document->asObject()
                                  ->at("patterns")
                                  .asObject()
                                  ->at(pattern_key)
                                  .asObject()
                                  ->at("sequences")
                                  .asObject();
    json::Array notes = *sequences->at(instrument_key).asArray();
    json::Array second = *notes[1].asArray();
    json::Object properties;
    properties.emplace("pan", json::Value::real(-0.25));
    second.push_back(json::Value::object(properties));
    notes[1] = json::Value::array(second);
    sequences->at(instrument_key) = json::Value::array(notes);
    const std::string text = json::writeCanonical(*document, {"format", "version"}).value();

    Project project;
    Residue residue;
    REQUIRE(loadProjectJson(text, project, residue).ok);
    CHECK(residue.note_properties.size() == 1);
    // While the note is there, its properties are written back with it.
    CHECK(contains(writeProjectJson(project, residue), "{\"pan\": -0.250000}"));

    // Move the note the properties belonged to. They described *that* note; the
    // note is gone, so they go with it rather than landing on its neighbour.
    onebeat::model::CommandBus bus(project);
    REQUIRE(bus.execute(onebeat::model::removeNotes(fixture.verse, fixture.piano,
                                                    {Note{480, 240, 64, velocityFromMidi1(80)}})));
    const std::string rewritten = writeProjectJson(project, residue);
    CHECK_FALSE(contains(rewritten, "-0.250000"));
  }

  TEST_CASE("A project from a newer version is refused, not half-read") {
    Fixture fixture;
    std::string text = writeProjectJson(fixture.project, Residue{});
    const size_t position = text.find("\"version\": 1");
    REQUIRE(position != std::string::npos);
    text.replace(position, std::string("\"version\": 1").size(), "\"version\": 9");

    Project project;
    Residue residue;
    const LoadReport report = loadProjectJson(text, project, residue);
    CHECK_FALSE(report.ok);
    CHECK(reported(report, "newer version of OneBeat"));
    CHECK(reported(report, "project format 9"));
    CHECK(project.instruments().empty());  // the caller's project is untouched
  }

  TEST_CASE("A file that is not a OneBeat project is refused") {
    Project project;
    Residue residue;
    CHECK_FALSE(
        loadProjectJson(R"({"format": "com.other.daw", "version": 1})", project, residue).ok);
    CHECK_FALSE(loadProjectJson("not json at all", project, residue).ok);
    CHECK_FALSE(loadProjectJson("[]", project, residue).ok);
    const LoadReport report = loadProjectJson("{}", project, residue);
    CHECK_FALSE(report.ok);
    CHECK(reported(report, "not a OneBeat project"));
  }

  TEST_CASE("A different tick resolution is refused rather than rescaled") {
    Fixture fixture;
    std::string text = writeProjectJson(fixture.project, Residue{});
    const std::string from = "\"ticks_per_quarter\": " + std::to_string(TicksPerQuarter);
    const size_t position = text.find(from);
    REQUIRE(position != std::string::npos);
    text.replace(position, from.size(), "\"ticks_per_quarter\": 480");

    Project project;
    Residue residue;
    const LoadReport report = loadProjectJson(text, project, residue);
    CHECK_FALSE(report.ok);
    CHECK(reported(report, "480 ticks per quarter"));
  }

  // ------------------------------------------------------------------------
  // Damaged projects open (FR-UX-12, §8)
  // ------------------------------------------------------------------------

  TEST_CASE("A clip whose pattern is missing is removed, by name, and the rest loads") {
    Fixture fixture;
    std::string text = writeProjectJson(fixture.project, Residue{});
    const std::string pattern_key = fixture.verse.str();

    // Delete the pattern from the file, leaving the clip pointing at nothing —
    // exactly the file a merge conflict or a half-finished sync produces.
    json::ParseError error;
    std::optional<json::Value> document = json::parse(text, error);
    REQUIRE(document.has_value());
    document->asObject()->at("patterns").asObject()->erase(pattern_key);
    text = json::writeCanonical(*document, {"format", "version"}).value();

    Project project;
    Residue residue;
    const LoadReport report = loadProjectJson(text, project, residue);
    REQUIRE(report.ok);  // it opens
    CHECK(project.clips().empty());
    CHECK(project.instruments().size() == 2);  // and everything else survived
    CHECK(project.lanes().size() == 1);
    CHECK(reported(report, fixture.clip.str()));
    CHECK(reported(report, "the pattern it plays is not in this project"));

    // The dropped clip does not come back on the next save.
    CHECK_FALSE(contains(writeProjectJson(project, residue), fixture.clip.str()));
  }

  TEST_CASE("Notes for an instrument that is gone are removed, with a count") {
    Fixture fixture;
    std::string text = writeProjectJson(fixture.project, Residue{});
    json::ParseError error;
    std::optional<json::Value> document = json::parse(text, error);
    REQUIRE(document.has_value());
    document->asObject()->at("instruments").asObject()->erase(fixture.piano.str());
    text = json::writeCanonical(*document, {"format", "version"}).value();

    Project project;
    Residue residue;
    const LoadReport report = loadProjectJson(text, project, residue);
    REQUIRE(report.ok);
    CHECK(reported(report, "3 note(s) for an instrument that is not in this project"));
    const Pattern* pattern = project.findPattern(fixture.verse);
    REQUIRE(pattern != nullptr);
    CHECK(pattern->sequences.size() == 1);
  }

  TEST_CASE("A mixer with no master, two masters, or a loop is repaired") {
    SUBCASE("no master at all") {
      Project project;
      Residue residue;
      const std::string text =
          R"({"format": "onebeat.project", "version": 1, "mixer_tracks": {)"
          R"("mix_01K2QF8Z30KEYS000000000100": {"name": "Keys", "output_id": "mix_01K2QF8Z34MASTER0000000050"}}})";
      const LoadReport report = loadProjectJson(text, project, residue);
      REQUIRE(report.ok);
      CHECK(reported(report, "no master track"));
      CHECK(project.findMixerTrack(project.masterTrack()) != nullptr);
      CHECK(project.findMixerTrack(project.masterTrack())->output == std::nullopt);
    }

    SUBCASE("two tracks claim to be the master") {
      Project project;
      Residue residue;
      const std::string text =
          R"({"format": "onebeat.project", "version": 1, "mixer_tracks": {)"
          R"("mix_01K2QF8Z30KEYS000000000100": {"name": "First", "output_id": null},)"
          R"("mix_01K2QF8Z31BASS000000000200": {"name": "Second", "output_id": null}}})";
      const LoadReport report = loadProjectJson(text, project, residue);
      REQUIRE(report.ok);
      CHECK(reported(report, "had no output"));
      // The older of the two wins: it is the one the project was built around.
      CHECK(project.findMixerTrack(project.masterTrack())->name == "First");
      const MixerTrack* second =
          project.findMixerTrack(MixerTrackId::parse("mix_01K2QF8Z31BASS000000000200").value());
      REQUIRE(second != nullptr);
      CHECK(second->output == project.masterTrack());
    }

    SUBCASE("a track feeds back into itself") {
      Project project;
      Residue residue;
      const std::string text =
          R"({"format": "onebeat.project", "version": 1, "mixer_tracks": {)"
          R"("mix_01K2QF8Z30KEYS000000000100": {"name": "Main", "output_id": null},)"
          R"("mix_01K2QF8Z31BASS000000000200": {"name": "A", "output_id": "mix_01K2QF8Z32SYNTH00000000030"},)"
          R"("mix_01K2QF8Z32SYNTH00000000030": {"name": "B", "output_id": "mix_01K2QF8Z31BASS000000000200"}}})";
      const LoadReport report = loadProjectJson(text, project, residue);
      REQUIRE(report.ok);
      CHECK(reported(report, "fed back into itself"));
    }
  }

  TEST_CASE("Values outside their range are clamped and reported") {
    const std::string text =
        R"({"format": "onebeat.project", "version": 1,)"
        R"("transport": {"tempo": -4.0},)"
        R"("instruments": {"ins_01K2QF8Z00KEYS000000000100": {"name": "Piano"}},)"
        R"("patterns": {"pat_01K2QF8Z10CHRDS00000001000": {"name": "P", "length": 3840,)"
        R"("sequences": {"ins_01K2QF8Z00KEYS000000000100": [[0, 480, 200, 99999], [0, -5, 60, 100], [960, 480, 60, 100]]}}}})";

    Project project;
    Residue residue;
    const LoadReport report = loadProjectJson(text, project, residue);
    REQUIRE(report.ok);
    CHECK(project.transport().tempo == doctest::Approx(120.0));
    CHECK(reported(report, "out of range; using 120"));
    CHECK(reported(report, "outside the key range"));
    CHECK(reported(report, "1 unusable note record"));

    const Pattern* pattern =
        project.findPattern(PatternId::parse("pat_01K2QF8Z10CHRDS00000001000").value());
    REQUIRE(pattern != nullptr);
    const NoteSequence& sequence = pattern->sequences.begin()->second;
    REQUIRE(sequence.size() == 2);
    CHECK(sequence.notes()[0].key == 127);
    CHECK(sequence.notes()[0].velocity == onebeat::model::MaxVelocity);
  }

  TEST_CASE("Overlapping notes of the same pitch survive load unchanged") {
    const std::string text =
        R"({"format": "onebeat.project", "version": 1,)"
        R"("instruments": {"ins_01K2QF8Z00KEYS000000000100": {"name": "Piano"}},)"
        R"("patterns": {"pat_01K2QF8Z10CHRDS00000001000": {"name": "P", "length": 3840,)"
        R"("sequences": {"ins_01K2QF8Z00KEYS000000000100": [[0, 960, 60, 12900], [480, 960, 60, 12900]]}}}})";

    Project project;
    Residue residue;
    const LoadReport report = loadProjectJson(text, project, residue);
    REQUIRE(report.ok);
    const NoteSequence& sequence = project.patterns().begin()->second.sequences.begin()->second;
    REQUIRE(sequence.size() == 2);
    CHECK(sequence.notes()[0].length == 960);
    CHECK(sequence.notes()[1].length == 960);
    CHECK(sequence.isSorted());
  }

  TEST_CASE("A hand-written file loads and is normalised, keeping what it said") {
    // Not canonical: unsorted keys, missing optional fields, a bare routing
    // string, integers where reals are written. All legal per §7.
    const std::string text =
        R"({"version": 1, "format": "onebeat.project",)"
        R"("meta": {"name": "By hand"},)"
        R"("transport": {"tempo": 90},)"
        R"("mixer_tracks": {"mix_01K2QF8Z34MASTER0000000050": {"name": "Main", "output_id": null, "gain": 1}},)"
        R"("instruments": {"ins_01K2QF8Z00KEYS000000000100": {"name": "Piano",)"
        R"("routing": ["mix_01K2QF8Z34MASTER0000000050"], "plugin": {"format": "clap", "id": "x"}}}})";

    Project project;
    Residue residue;
    const LoadReport report = loadProjectJson(text, project, residue);
    REQUIRE(report.ok);
    CHECK(project.meta().name == "By hand");
    CHECK(project.transport().tempo == doctest::Approx(90.0));
    const Instrument* piano =
        project.findInstrument(InstrumentId::parse("ins_01K2QF8Z00KEYS000000000100").value());
    REQUIRE(piano != nullptr);
    REQUIRE(piano->routing.size() == 1);
    CHECK(piano->routing[0].track == project.masterTrack());

    // The normalisation is a one-off: saving again changes nothing further.
    const std::string normalised = writeProjectJson(project, residue);
    Project again;
    Residue again_residue;
    REQUIRE(loadProjectJson(normalised, again, again_residue).ok);
    CHECK(writeProjectJson(again, again_residue) == normalised);
  }

  // ------------------------------------------------------------------------
  // Bundles on disk
  // ------------------------------------------------------------------------

  TEST_CASE("SHA-256 matches the published vectors") {
    CHECK(sha256Hex("") == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855");
    CHECK(sha256Hex("abc") == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad");
    CHECK(sha256Hex("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq") ==
          "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1");
    // Longer than one block and longer than the padding boundary, which is
    // where a hand-written implementation gets it wrong.
    CHECK(sha256Hex(std::string(1000000, 'a')) ==
          "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0");
  }

  TEST_CASE("A bundle carries plugin state in sidecars, verified by hash") {
    TempDir temp("sidecars");
    const std::filesystem::path bundle = temp / "MyTrack.obt";
    Fixture fixture;

    const std::string piano_state = "PIANO-STATE-CHUNK";
    const std::string bass_state(4096, '\x7F');
    SaveOptions options;
    options.created_with = "OneBeat 0.3.0";
    options.state_provider = [&](InstrumentId id) {
      if (id == fixture.piano) return bytesOf(piano_state);
      if (id == fixture.bass) return bytesOf(bass_state);
      return std::vector<std::byte>{};
    };
    const SaveReport saved = saveProject(bundle, fixture.project, Residue{}, options);
    REQUIRE(saved.ok);
    REQUIRE(saved.state_written.size() == 2);
    CHECK(std::filesystem::exists(bundle / "project.json"));
    CHECK(std::filesystem::exists(bundle / saved.state_written.at(fixture.piano).state_ref));
    CHECK(saved.state_written.at(fixture.piano).sha256 == sha256Hex(piano_state));

    std::map<InstrumentId, std::string> restored;
    LoadOptions load;
    load.state_sink = [&](InstrumentId id, const std::vector<std::byte>& bytes) {
      restored.emplace(id, std::string(reinterpret_cast<const char*>(bytes.data()), bytes.size()));
    };
    Project project;
    Residue residue;
    const LoadReport report = loadProject(bundle, project, residue, load);
    REQUIRE(report.ok);
    CHECK(report.clean());
    CHECK(restored.at(fixture.piano) == piano_state);
    CHECK(restored.at(fixture.bass) == bass_state);

    SUBCASE("a sidecar that was lost is reported and the instrument keeps its defaults") {
      std::filesystem::remove(bundle / saved.state_written.at(fixture.piano).state_ref);
      restored.clear();
      Project second;
      Residue second_residue;
      const LoadReport again = loadProject(bundle, second, second_residue, load);
      REQUIRE(again.ok);
      CHECK(again.count(LoadIssue::Severity::Warning) == 1);
      CHECK(reported(again, "could not restore its settings"));
      CHECK(restored.count(fixture.piano) == 0);
      CHECK(restored.count(fixture.bass) == 1);  // the others are unaffected
    }

    SUBCASE("a damaged sidecar is not handed to the plugin") {
      const std::filesystem::path path = bundle / saved.state_written.at(fixture.bass).state_ref;
      std::ofstream(path, std::ios::binary) << "corrupted";
      restored.clear();
      Project second;
      Residue second_residue;
      const LoadReport again = loadProject(bundle, second, second_residue, load);
      REQUIRE(again.ok);
      CHECK(reported(again, "damaged settings"));
      CHECK(restored.count(fixture.bass) == 0);
    }

    SUBCASE("Save As carries the sidecars across") {
      const std::filesystem::path copy = temp / "Copy.obt";
      SaveOptions as;
      as.copy_state_from = bundle;
      REQUIRE(saveProject(copy, project, residue, as).ok);
      restored.clear();
      Project second;
      Residue second_residue;
      REQUIRE(loadProject(copy, second, second_residue, load).ok);
      CHECK(restored.at(fixture.piano) == piano_state);
    }
  }

  TEST_CASE("Opening a folder that is not a project says so") {
    TempDir temp("empty");
    Project project;
    Residue residue;
    const LoadReport report = loadProject(temp / "Nothing.obt", project, residue);
    CHECK_FALSE(report.ok);
    CHECK(reported(report, "no project.json"));
  }

  TEST_CASE("Saving twice over the same bundle leaves one bundle and no litter") {
    TempDir temp("resave");
    const std::filesystem::path bundle = temp / "Track.obt";
    Fixture fixture;
    REQUIRE(saveProject(bundle, fixture.project, Residue{}).ok);
    const std::string first = readWhole(bundle / "project.json");
    REQUIRE(saveProject(bundle, fixture.project, Residue{}).ok);
    CHECK(readWhole(bundle / "project.json") == first);

    size_t entries = 0;
    for (const auto& entry : std::filesystem::directory_iterator(temp.path())) {
      (void)entry;
      ++entries;
    }
    CHECK(entries == 1);  // no staging directory left behind
  }

  TEST_CASE("The previous save is intact at the instant a save could be killed") {
    TempDir temp("atomic");
    const std::filesystem::path bundle = temp / "Track.obt";
    Fixture fixture;
    REQUIRE(saveProject(bundle, fixture.project, Residue{}).ok);
    const std::string original = readWhole(bundle / "project.json");

    onebeat::model::ProjectMeta meta;
    meta.name = "Changed";
    fixture.project.setMeta(meta);

    bool checked = false;
    SaveOptions options;
    options.crash_hook = [&] {
      // The new bundle is fully staged; the swap has not happened. Everything a
      // reader can see is still the previous save, whole.
      CHECK(readWhole(bundle / "project.json") == original);
      Project project;
      Residue residue;
      CHECK(loadProject(bundle, project, residue).ok);
      CHECK(project.meta().name == "Round trip");
      checked = true;
    };
    REQUIRE(saveProject(bundle, fixture.project, Residue{}, options).ok);
    CHECK(checked);
    CHECK(contains(readWhole(bundle / "project.json"), "\"name\": \"Changed\""));
  }

#if !defined(ONEBEAT_SANITIZER_BUILD)
  // A real fork and a real SIGKILL. Not run under the sanitizers: forking a
  // sanitized process and killing it mid-syscall is a known source of hangs and
  // false reports, and what is being tested here is the filesystem, which the
  // sanitizers have nothing to say about.
  TEST_CASE("kill -9 in the middle of a save leaves the previous save intact") {
    TempDir temp("kill9");
    const std::filesystem::path bundle = temp / "Track.obt";
    Fixture fixture;
    REQUIRE(saveProject(bundle, fixture.project, Residue{}).ok);
    const std::string original = readWhole(bundle / "project.json");
    REQUIRE_FALSE(original.empty());

    onebeat::model::ProjectMeta meta;
    meta.name = "Never written";
    fixture.project.setMeta(meta);

    const pid_t child = ::fork();
    REQUIRE(child >= 0);
    if (child == 0) {
      SaveOptions options;
      options.crash_hook = [] { ::kill(::getpid(), SIGKILL); };
      saveProject(bundle, fixture.project, Residue{}, options);
      ::_exit(0);  // unreachable: the hook does not return
    }
    int status = 0;
    ::waitpid(child, &status, 0);
    REQUIRE(WIFSIGNALED(status));
    REQUIRE(WTERMSIG(status) == SIGKILL);

    // The bundle the user had is byte-for-byte the bundle they still have.
    CHECK(readWhole(bundle / "project.json") == original);
    Project project;
    Residue residue;
    const LoadReport report = loadProject(bundle, project, residue);
    REQUIRE(report.ok);
    CHECK(project.meta().name == "Round trip");
  }
#endif

  TEST_CASE("The worked example in the docs is what this writer produces") {
    // docs/examples/demo.obt is normative-by-example: ADR-004 and
    // docs/project-format.md both point at it. If the writer and the example
    // ever disagree, one of them is lying to the reader — so they are compared
    // on every run rather than by eye when someone remembers.
    const std::filesystem::path bundle = OB_DEMO_BUNDLE;
    REQUIRE(std::filesystem::exists(bundle / "project.json"));

    Project project;
    Residue residue;
    LoadOptions options;
    options.load_state = false;  // the example ships no sidecars, on purpose
    const LoadReport report = loadProject(bundle, project, residue, options);
    REQUIRE(report.ok);
    CHECK(report.clean());
    CHECK(writeProjectJson(project, residue) == readWhole(bundle / "project.json"));
  }
}
