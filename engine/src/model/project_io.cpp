#include "model/project_io.h"

#include <fcntl.h>
#include <sys/stdio.h>
#include <unistd.h>

#include <algorithm>
#include <array>
#include <cerrno>
#include <cstring>
#include <fstream>
#include <sstream>
#include <system_error>

#include "model/invariants.h"

namespace onebeat::model {
namespace {

constexpr std::string_view FormatTag = "onebeat.project";
constexpr int64_t FormatVersion = 1;

// --------------------------------------------------------------------------
// SHA-256 (FIPS 180-4)
// --------------------------------------------------------------------------
// Small enough to own, and owning it avoids a dependency on OpenSSL or on
// CommonCrypto — the latter would put an Apple header in `model/`, which
// tools/seam_check.sh exists to prevent.

constexpr std::array<uint32_t, 64> Sha256K = {
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2};

constexpr uint32_t rotr(uint32_t value, uint32_t bits) {
  return (value >> bits) | (value << (32 - bits));
}

void sha256Block(const uint8_t* block, std::array<uint32_t, 8>& state) {
  std::array<uint32_t, 64> w{};
  for (size_t i = 0; i < 16; ++i) {
    w[i] = (static_cast<uint32_t>(block[i * 4]) << 24U) |
           (static_cast<uint32_t>(block[(i * 4) + 1]) << 16U) |
           (static_cast<uint32_t>(block[(i * 4) + 2]) << 8U) |
           static_cast<uint32_t>(block[(i * 4) + 3]);
  }
  for (size_t i = 16; i < 64; ++i) {
    const uint32_t s0 = rotr(w[i - 15], 7) ^ rotr(w[i - 15], 18) ^ (w[i - 15] >> 3U);
    const uint32_t s1 = rotr(w[i - 2], 17) ^ rotr(w[i - 2], 19) ^ (w[i - 2] >> 10U);
    w[i] = w[i - 16] + s0 + w[i - 7] + s1;
  }

  std::array<uint32_t, 8> v = state;
  for (size_t i = 0; i < 64; ++i) {
    const uint32_t s1 = rotr(v[4], 6) ^ rotr(v[4], 11) ^ rotr(v[4], 25);
    const uint32_t ch = (v[4] & v[5]) ^ (~v[4] & v[6]);
    const uint32_t temp1 = v[7] + s1 + ch + Sha256K[i] + w[i];
    const uint32_t s0 = rotr(v[0], 2) ^ rotr(v[0], 13) ^ rotr(v[0], 22);
    const uint32_t maj = (v[0] & v[1]) ^ (v[0] & v[2]) ^ (v[1] & v[2]);
    const uint32_t temp2 = s0 + maj;
    v[7] = v[6];
    v[6] = v[5];
    v[5] = v[4];
    v[4] = v[3] + temp1;
    v[3] = v[2];
    v[2] = v[1];
    v[1] = v[0];
    v[0] = temp1 + temp2;
  }
  for (size_t i = 0; i < 8; ++i) state[i] += v[i];
}

// --------------------------------------------------------------------------
// Filesystem helpers
// --------------------------------------------------------------------------

// Durability, not just correctness: `rename` only promises to be atomic with
// respect to *other renames*. Without fsync on the files first, a power loss
// can leave the directory entry pointing at a file whose contents never
// reached the disk, which is the one failure that looks like corruption.
bool writeFileSynced(const std::filesystem::path& path, const void* data, size_t size,
                     std::string& error) {
  const int fd = ::open(path.c_str(), O_WRONLY | O_CREAT | O_TRUNC, 0644);
  if (fd < 0) {
    error = "could not create '" + path.string() + "': " + std::strerror(errno);
    return false;
  }
  const auto* cursor = static_cast<const char*>(data);
  size_t remaining = size;
  while (remaining > 0) {
    const ssize_t written = ::write(fd, cursor, remaining);
    if (written <= 0) {
      if (errno == EINTR) continue;
      error = "could not write '" + path.string() + "': " + std::strerror(errno);
      ::close(fd);
      return false;
    }
    cursor += written;
    remaining -= static_cast<size_t>(written);
  }
  if (::fsync(fd) != 0) {
    error = "could not flush '" + path.string() + "': " + std::strerror(errno);
    ::close(fd);
    return false;
  }
  ::close(fd);
  return true;
}

// A file's own fsync does not promise that the *directory entry* naming it
// survives a power loss; the directory needs its own.
void syncDirectory(const std::filesystem::path& path) {
  const int fd = ::open(path.c_str(), O_RDONLY);
  if (fd < 0) return;
  ::fsync(fd);
  ::close(fd);
}

bool readFile(const std::filesystem::path& path, std::string& out, std::string& error) {
  std::ifstream file(path, std::ios::binary);
  if (!file) {
    error = "could not open '" + path.string() + "'";
    return false;
  }
  std::ostringstream buffer;
  buffer << file.rdbuf();
  out = buffer.str();
  return true;
}

// --------------------------------------------------------------------------
// Reading fields: consume-and-strip
// --------------------------------------------------------------------------
//
// The residue is the parsed document with everything we understood removed. So
// reading a field and forgetting it from the document are the same act — which
// means a field added to the writer without being added to the reader shows up
// as a duplicate in the output rather than being silently dropped, and a field
// we have never heard of survives because nobody took it.

json::Value take(json::Object& object, std::string_view key) {
  const auto entry = object.find(std::string(key));
  if (entry == object.end()) return json::Value::null();
  json::Value value = entry->second;
  object.erase(entry);
  return value;
}

std::string takeString(json::Object& object, std::string_view key,
                       const std::string& fallback = {}) {
  const json::Value value = take(object, key);
  const std::string* text = value.asString();
  return text == nullptr ? fallback : *text;
}

int64_t takeInt(json::Object& object, std::string_view key, int64_t fallback = 0) {
  const json::Value value = take(object, key);
  return value.isNumber() ? value.asInt(fallback) : fallback;
}

double takeDouble(json::Object& object, std::string_view key, double fallback = 0.0) {
  const json::Value value = take(object, key);
  return value.isNumber() ? value.asDouble(fallback) : fallback;
}

float takeFloat(json::Object& object, std::string_view key, float fallback) {
  return static_cast<float>(takeDouble(object, key, static_cast<double>(fallback)));
}

bool takeBool(json::Object& object, std::string_view key, bool fallback = false) {
  const json::Value value = take(object, key);
  return value.isBool() ? value.asBool() : fallback;
}

// Removes objects and maps that ended up empty because we understood all of
// them, so the residue holds only what is genuinely left over.
void pruneEmpty(json::Value& value) {
  json::Object* object = value.asObject();
  if (object == nullptr) return;
  for (auto entry = object->begin(); entry != object->end();) {
    pruneEmpty(entry->second);
    const json::Object* child = entry->second.asObject();
    if (child != nullptr && child->empty()) {
      entry = object->erase(entry);
    } else {
      ++entry;
    }
  }
}

// Residue never overwrites: the model is the authority on every field it
// models, and the residue only supplies what the model has no opinion about.
void mergeResidue(json::Object& into, const json::Object& from) {
  for (const auto& [key, value] : from) {
    const auto existing = into.find(key);
    if (existing == into.end()) {
      into.emplace(key, value);
      continue;
    }
    json::Object* target = existing->second.asObject();
    const json::Object* source = value.asObject();
    if (target != nullptr && source != nullptr) mergeResidue(*target, *source);
  }
}

// --------------------------------------------------------------------------
// Enum spellings (docs/project-format.md §5.1, §5.4)
// --------------------------------------------------------------------------

std::string_view pluginFormatText(PluginFormat format) {
  switch (format) {
    case PluginFormat::Builtin:
      return "builtin";
    case PluginFormat::Clap:
      return "clap";
    case PluginFormat::Vst3:
      return "vst3";
    case PluginFormat::AudioUnit:
      return "au";
    case PluginFormat::Unknown:
      break;
  }
  return "";
}

PluginFormat pluginFormatFrom(std::string_view text) {
  if (text == "builtin") return PluginFormat::Builtin;
  if (text == "clap") return PluginFormat::Clap;
  if (text == "vst3") return PluginFormat::Vst3;
  if (text == "au") return PluginFormat::AudioUnit;
  return PluginFormat::Unknown;
}

}  // namespace

// --------------------------------------------------------------------------
// Public hashing
// --------------------------------------------------------------------------

std::string sha256Hex(const std::byte* data, size_t size) {
  std::array<uint32_t, 8> state = {0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
                                   0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19};
  const auto* bytes = reinterpret_cast<const uint8_t*>(data);

  size_t offset = 0;
  for (; offset + 64 <= size; offset += 64) sha256Block(bytes + offset, state);

  std::array<uint8_t, 128> tail{};
  const size_t remainder = size - offset;
  std::memcpy(tail.data(), bytes + offset, remainder);
  tail[remainder] = 0x80;
  const size_t tail_size = remainder < 56 ? 64 : 128;
  const uint64_t bits = static_cast<uint64_t>(size) * 8;
  for (size_t i = 0; i < 8; ++i) {
    tail[tail_size - 1 - i] = static_cast<uint8_t>((bits >> (8 * i)) & 0xFFU);
  }
  for (size_t i = 0; i < tail_size; i += 64) sha256Block(tail.data() + i, state);

  std::string hex;
  hex.reserve(64);
  constexpr std::string_view Digits = "0123456789abcdef";
  for (const uint32_t word : state) {
    for (int shift = 28; shift >= 0; shift -= 4) {
      hex.push_back(Digits[(word >> static_cast<uint32_t>(shift)) & 0xFU]);
    }
  }
  return hex;
}

std::string sha256Hex(std::string_view text) {
  return sha256Hex(reinterpret_cast<const std::byte*>(text.data()), text.size());
}

// --------------------------------------------------------------------------
// Report
// --------------------------------------------------------------------------

size_t LoadReport::count(LoadIssue::Severity severity) const {
  return static_cast<size_t>(
      std::count_if(issues.begin(), issues.end(),
                    [severity](const LoadIssue& issue) { return issue.severity == severity; }));
}

std::string LoadReport::describe() const {
  std::string text;
  for (const LoadIssue& issue : issues) {
    switch (issue.severity) {
      case LoadIssue::Severity::Error:
        text += "error: ";
        break;
      case LoadIssue::Severity::Warning:
        text += "warning: ";
        break;
      case LoadIssue::Severity::Info:
        text += "note: ";
        break;
    }
    text += issue.message;
    text += '\n';
  }
  return text;
}

std::string Residue::noteKey(PatternId pattern, InstrumentId instrument, const Note& note) {
  return pattern.str() + "/" + instrument.str() + "/" + std::to_string(note.start) + "/" +
         std::to_string(note.length) + "/" + std::to_string(note.key) + "/" +
         std::to_string(note.velocity);
}

// --------------------------------------------------------------------------
// Writing the model
// --------------------------------------------------------------------------

namespace {

json::Value writeTransport(const TransportState& transport) {
  json::Object loop;
  loop.emplace("enabled", json::Value::boolean(transport.loop_enabled));
  loop.emplace("start", json::Value::integer(transport.loop_start));
  loop.emplace("end", json::Value::integer(transport.loop_end));

  json::Object out;
  out.emplace("tempo", json::Value::real(transport.tempo));
  out.emplace("time_signature",
              json::Value::array({json::Value::integer(transport.time_signature.numerator),
                                  json::Value::integer(transport.time_signature.denominator)}));
  out.emplace("loop", json::Value::object(std::move(loop)));
  return json::Value::object(std::move(out));
}

json::Value writeInstrument(const Instrument& instrument,
                            const SaveReport::StateRecord* state_override) {
  json::Object plugin;
  // An unrecognised format has no spelling to write. Omitting the key lets the
  // residue put the original string back (docs/project-format.md §7), and a
  // reader treats a missing format exactly as it treats one it does not know.
  const std::string_view format = pluginFormatText(instrument.plugin.format);
  if (!format.empty()) plugin.emplace("format", json::Value::string(std::string(format)));
  plugin.emplace("id", json::Value::string(instrument.plugin.id));
  plugin.emplace("name", json::Value::string(instrument.plugin.name));
  plugin.emplace("vendor", json::Value::string(instrument.plugin.vendor));
  plugin.emplace("path_hint", json::Value::string(instrument.plugin.path_hint));

  json::Array routing;
  routing.reserve(instrument.routing.size());
  for (const OutputRoute& route : instrument.routing) {
    // An object rather than a bare ID: the port is part of the routing, and an
    // array position standing in for it would be exactly the index-based
    // routing D-M1 forbids.
    json::Object entry;
    entry.emplace("port", json::Value::integer(route.port));
    entry.emplace("track_id", json::Value::string(route.track.str()));
    routing.push_back(json::Value::object(std::move(entry)));
  }

  json::Object defaults;
  defaults.emplace("velocity", json::Value::integer(instrument.note_defaults.velocity));
  defaults.emplace("pan", json::Value::real(instrument.note_defaults.pan));
  defaults.emplace("pitch_offset", json::Value::integer(instrument.note_defaults.pitch_offset));

  const std::string state_ref =
      state_override != nullptr ? state_override->state_ref : instrument.plugin.state_ref;
  const std::string state_sha =
      state_override != nullptr ? state_override->sha256 : instrument.plugin.state_sha256;

  json::Object out;
  out.emplace("name", json::Value::string(instrument.name));
  out.emplace("color", json::Value::string(instrument.color));
  out.emplace("order", json::Value::integer(instrument.order));
  out.emplace("muted", json::Value::boolean(instrument.muted));
  out.emplace("plugin", json::Value::object(std::move(plugin)));
  out.emplace("note_defaults", json::Value::object(std::move(defaults)));
  out.emplace("routing", json::Value::array(std::move(routing)));
  out.emplace("state_ref",
              state_ref.empty() ? json::Value::null() : json::Value::string(state_ref));
  out.emplace("state_sha256",
              state_sha.empty() ? json::Value::null() : json::Value::string(state_sha));
  return json::Value::object(std::move(out));
}

json::Value writePattern(const Pattern& pattern, const Residue& residue) {
  json::Object sequences;
  for (const auto& [instrument_id, sequence] : pattern.sequences) {
    json::Array notes;
    notes.reserve(sequence.size());
    for (const Note& note : sequence.notes()) {
      json::Array record{json::Value::integer(note.start), json::Value::integer(note.length),
                         json::Value::integer(note.key), json::Value::integer(note.velocity)};
      const auto properties =
          residue.note_properties.find(Residue::noteKey(pattern.id, instrument_id, note));
      if (properties != residue.note_properties.end()) record.push_back(properties->second);
      notes.push_back(json::Value::array(std::move(record)));
    }
    sequences.emplace(instrument_id.str(), json::Value::array(std::move(notes)));
  }

  json::Object out;
  out.emplace("name", json::Value::string(pattern.name));
  out.emplace("color", json::Value::string(pattern.color));
  out.emplace("length", json::Value::integer(pattern.length));
  out.emplace("swing", json::Value::real(pattern.swing));
  out.emplace("sequences", json::Value::object(std::move(sequences)));
  return json::Value::object(std::move(out));
}

json::Value writeLane(const ArrangementLane& lane) {
  json::Object out;
  out.emplace("name", json::Value::string(lane.name));
  out.emplace("color", json::Value::string(lane.color));
  out.emplace("height", json::Value::integer(lane.height));
  out.emplace("order", json::Value::integer(lane.order));
  out.emplace("collapsed", json::Value::boolean(lane.collapsed));
  out.emplace("muted", json::Value::boolean(lane.muted));
  out.emplace("soloed", json::Value::boolean(lane.soloed));
  out.emplace("group_id", lane.group_id.has_value() ? json::Value::string(lane.group_id->str())
                                                    : json::Value::null());
  return json::Value::object(std::move(out));
}

json::Value writeClipSource(const Clip& clip) {
  json::Object out;
  if (const PatternSource* source = clip.pattern()) {
    out.emplace("type", json::Value::string("pattern"));
    out.emplace("pattern_id", json::Value::string(source->pattern.str()));
    return json::Value::object(std::move(out));
  }
  if (const AudioSource* source = clip.audio()) {
    out.emplace("type", json::Value::string("audio"));
    out.emplace("path", json::Value::string(source->path));
    out.emplace("source_offset", json::Value::integer(source->source_offset));
    out.emplace("gain", json::Value::real(source->gain));
    out.emplace("reversed", json::Value::boolean(source->reversed));
    out.emplace("destination_id", json::Value::string(source->destination.str()));
    return json::Value::object(std::move(out));
  }
  const AutomationSource* source = clip.automation();
  out.emplace("type", json::Value::string("automation"));
  const bool to_instrument = source->target_kind == AutomationSource::TargetKind::Instrument;
  out.emplace("target_kind", json::Value::string(to_instrument ? "instrument" : "mixer_track"));
  out.emplace("target_id", json::Value::string(to_instrument ? source->instrument.str()
                                                             : source->mixer_track.str()));
  out.emplace("parameter", json::Value::integer(source->parameter));
  json::Array points;
  points.reserve(source->points.size());
  for (const AutomationPoint& point : source->points) {
    points.push_back(
        json::Value::array({json::Value::integer(point.position), json::Value::real(point.value)}));
  }
  out.emplace("points", json::Value::array(std::move(points)));
  return json::Value::object(std::move(out));
}

json::Value writeClip(const Clip& clip) {
  json::Object transforms;
  transforms.emplace("transpose", json::Value::integer(clip.transforms.transpose));
  transforms.emplace("loop", json::Value::boolean(clip.transforms.loop));
  transforms.emplace("window_start", json::Value::integer(clip.transforms.window_start));
  transforms.emplace("velocity_scale", json::Value::real(clip.transforms.velocity_scale));
  transforms.emplace("time_nudge", json::Value::integer(clip.transforms.time_nudge));
  transforms.emplace("probability", json::Value::real(clip.transforms.probability));

  json::Object out;
  out.emplace("lane_id", json::Value::string(clip.lane.str()));
  out.emplace("start", json::Value::integer(clip.start));
  out.emplace("length", json::Value::integer(clip.length));
  out.emplace("muted", json::Value::boolean(clip.muted));
  out.emplace("source", writeClipSource(clip));
  out.emplace("transforms", json::Value::object(std::move(transforms)));
  return json::Value::object(std::move(out));
}

json::Value writeMixerTrack(const MixerTrack& track) {
  json::Object out;
  out.emplace("name", json::Value::string(track.name));
  out.emplace("gain", json::Value::real(track.gain));
  out.emplace("pan", json::Value::real(track.pan));
  out.emplace("muted", json::Value::boolean(track.muted));
  out.emplace("soloed", json::Value::boolean(track.soloed));
  out.emplace("output_id", track.output.has_value() ? json::Value::string(track.output->str())
                                                    : json::Value::null());
  out.emplace("chain", json::Value::array({}));  // Stage 4
  out.emplace("sends", json::Value::array({}));  // Stage 4
  return json::Value::object(std::move(out));
}

}  // namespace

std::string writeProjectJson(const Project& project, const Residue& residue,
                             const std::string& created_with,
                             const std::map<InstrumentId, SaveReport::StateRecord>& state) {
  json::Object meta;
  meta.emplace("name", json::Value::string(project.meta().name));
  meta.emplace(
      "created_with",
      json::Value::string(created_with.empty() ? project.meta().created_with : created_with));
  meta.emplace("ticks_per_quarter", json::Value::integer(TicksPerQuarter));

  json::Object instruments;
  for (const auto& [id, instrument] : project.instruments()) {
    const auto record = state.find(id);
    instruments.emplace(
        id.str(), writeInstrument(instrument, record == state.end() ? nullptr : &record->second));
  }

  json::Object patterns;
  for (const auto& [id, pattern] : project.patterns()) {
    patterns.emplace(id.str(), writePattern(pattern, residue));
  }

  json::Object lanes;
  for (const auto& [id, lane] : project.lanes()) lanes.emplace(id.str(), writeLane(lane));

  json::Object clips;
  for (const auto& [id, clip] : project.clips()) clips.emplace(id.str(), writeClip(clip));

  json::Object tracks;
  for (const auto& [id, track] : project.mixerTracks()) {
    tracks.emplace(id.str(), writeMixerTrack(track));
  }

  json::Object root;
  root.emplace("format", json::Value::string(std::string(FormatTag)));
  root.emplace("version", json::Value::integer(FormatVersion));
  root.emplace("meta", json::Value::object(std::move(meta)));
  root.emplace("transport", writeTransport(project.transport()));
  root.emplace("instruments", json::Value::object(std::move(instruments)));
  root.emplace("patterns", json::Value::object(std::move(patterns)));
  root.emplace("lanes", json::Value::object(std::move(lanes)));
  root.emplace("clips", json::Value::object(std::move(clips)));
  root.emplace("mixer_tracks", json::Value::object(std::move(tracks)));

  if (const json::Object* extra = residue.document.asObject()) mergeResidue(root, *extra);

  const std::optional<std::string> text =
      json::writeCanonical(json::Value::object(std::move(root)), {"format", "version"});
  // Only a non-finite number can fail the writer, and every float reaching it
  // has been through the model's setters. Returning empty rather than throwing
  // keeps the failure on the `SaveReport` path, where the caller checks it.
  return text.value_or(std::string{});
}

// --------------------------------------------------------------------------
// Loading
// --------------------------------------------------------------------------

namespace {

class Loader {
 public:
  Loader(Project& project, Residue& residue, LoadReport& report)
      : project_(project), residue_(residue), report_(report) {}

  bool run(std::string_view text) {
    json::ParseError parse_error;
    std::optional<json::Value> document = json::parse(text, parse_error);
    if (!document) {
      error("This does not look like a OneBeat project: " + parse_error.describe() + ".");
      return false;
    }
    json::Object* root = document->asObject();
    if (root == nullptr) {
      error("This does not look like a OneBeat project: the file is not a JSON object.");
      return false;
    }

    const std::string format = takeString(*root, "format");
    if (format != FormatTag) {
      error("This is not a OneBeat project file.");
      return false;
    }
    const json::Value version = take(*root, "version");
    if (!version.isInt()) {
      error("This project file does not say which format version it uses.");
      return false;
    }
    if (version.asInt() > FormatVersion) {
      // §7: never partially load, and never overwrite, a newer project.
      error("This project was saved by a newer version of OneBeat (project format " +
            std::to_string(version.asInt()) + "; this version reads " +
            std::to_string(FormatVersion) + "). Update OneBeat to open it.");
      return false;
    }
    if (version.asInt() < FormatVersion) {
      // The migration hook. v1 is the first version, so the only migration
      // that exists is the identity — but the branch exists so that adding a
      // real one is an edit here rather than a new concept.
      note("Project written with format version " + std::to_string(version.asInt()) +
           "; migrated to " + std::to_string(FormatVersion) + ".");
    }

    // Said before anything is read, because each reader puts the unconsumed
    // remainder of its own map back for the residue — after which "what is
    // still at the top level" no longer means "what we never recognised".
    for (const auto& [key, value] : *root) {
      static constexpr std::array<std::string_view, 7> Known = {
          "meta", "transport", "instruments", "patterns", "lanes", "clips", "mixer_tracks"};
      if (std::find(Known.begin(), Known.end(), key) == Known.end()) {
        note("Kept, not understood: top-level '" + key + "'.");
      }
    }

    readMeta(*root);
    readTransport(*root);
    readMixerTracks(*root);
    readInstruments(*root);
    readPatterns(*root);
    readLanes(*root);
    readClips(*root);

    resolveReferences();

    pruneEmpty(*document);
    residue_.document = *document;
    project_.adopt(std::move(tables_));

    // The belt to the braces: the loader validates as it goes, and then the
    // model's own checker validates what the loader produced. A disagreement
    // between them is a bug in the loader, and finding it here beats finding it
    // when the next mutation aborts on a debug assert.
    for (const Violation& violation : checkReferentialIntegrity(project_)) {
      error("Internal: " + violation.message);
    }
    return true;
  }

 private:
  void error(std::string message) {
    report_.issues.push_back({LoadIssue::Severity::Error, std::move(message)});
  }
  void warn(std::string message) {
    report_.issues.push_back({LoadIssue::Severity::Warning, std::move(message)});
  }
  void note(std::string message) {
    report_.issues.push_back({LoadIssue::Severity::Info, std::move(message)});
  }

  // A named reference: parses, checks the prefix, and reports in the format's
  // own words when either fails (§4.3).
  template <EntityKind K>
  std::optional<TypedId<K>> reference(const std::string& text, const std::string& owner,
                                      const std::string& field) {
    if (text.empty()) return std::nullopt;
    std::optional<TypedId<K>> id = TypedId<K>::parse(text);
    if (!id) {
      error(owner + " has an unusable " + field + " ('" + text + "') — dropped.");
      return std::nullopt;
    }
    return id;
  }

  void readMeta(json::Object& root) {
    json::Value value = take(root, "meta");
    json::Object* meta = value.asObject();
    ProjectMeta parsed;
    if (meta != nullptr) {
      parsed.name = takeString(*meta, "name", "Untitled");
      parsed.created_with = takeString(*meta, "created_with");
      const int64_t ticks = takeInt(*meta, "ticks_per_quarter", TicksPerQuarter);
      if (ticks != TicksPerQuarter) {
        // Honouring a different resolution would mean rescaling every tick in
        // the file, and a rounding error there moves notes. Refusing is the
        // kinder failure (docs/project-format.md §3).
        error("This project uses " + std::to_string(ticks) +
              " ticks per quarter note; OneBeat reads 960.");
        ticks_ok_ = false;
      }
      root.emplace("meta", std::move(value));  // put the remainder back for the residue
    }
    tables_.meta = parsed;
  }

  void readTransport(json::Object& root) {
    json::Value value = take(root, "transport");
    json::Object* transport = value.asObject();
    TransportState parsed;
    if (transport != nullptr) {
      parsed.tempo = takeDouble(*transport, "tempo", 120.0);
      if (!(parsed.tempo > 0.0) || parsed.tempo > 1000.0) {
        warn("Tempo of " + json::formatReal(parsed.tempo) + " BPM is out of range; using 120.");
        parsed.tempo = 120.0;
      }
      const json::Value signature = take(*transport, "time_signature");
      if (const json::Array* pair = signature.asArray(); pair != nullptr && pair->size() == 2) {
        parsed.time_signature.numerator = static_cast<int32_t>((*pair)[0].asInt(4));
        parsed.time_signature.denominator = static_cast<int32_t>((*pair)[1].asInt(4));
      }
      if (parsed.time_signature.numerator <= 0 || parsed.time_signature.denominator <= 0) {
        warn("Time signature is not usable; using 4/4.");
        parsed.time_signature = TimeSignature{};
      }
      json::Value loop_value = take(*transport, "loop");
      if (json::Object* loop = loop_value.asObject(); loop != nullptr) {
        parsed.loop_enabled = takeBool(*loop, "enabled");
        parsed.loop_start = takeInt(*loop, "start");
        parsed.loop_end = takeInt(*loop, "end", parsed.loop_start);
        transport->emplace("loop", std::move(loop_value));
      }
      if (parsed.loop_end < parsed.loop_start) std::swap(parsed.loop_start, parsed.loop_end);
      root.emplace("transport", std::move(value));
    }
    tables_.transport = parsed;
  }

  void readMixerTracks(json::Object& root) {
    json::Value value = take(root, "mixer_tracks");
    json::Object* map = value.asObject();
    if (map == nullptr) {
      warn("Project has no mixer; a master track was created.");
      return;
    }
    for (auto& [key, entry] : *map) {
      json::Object* fields = entry.asObject();
      if (fields == nullptr) continue;
      const std::optional<MixerTrackId> id = MixerTrackId::parse(key);
      if (!id) {
        note("Kept, not understood: mixer track '" + key + "'.");
        continue;
      }
      MixerTrack track;
      track.id = *id;
      track.name = takeString(*fields, "name", "Track");
      track.gain = takeFloat(*fields, "gain", 1.0F);
      track.pan = takeFloat(*fields, "pan", 0.0F);
      track.muted = takeBool(*fields, "muted");
      track.soloed = takeBool(*fields, "soloed");
      // A null (or absent) `output_id` is what marks the master; anything else
      // is resolved once every track has been read.
      const std::string output = takeString(*fields, "output_id");
      if (!output.empty()) pending_track_output_.emplace(*id, output);
      // Stage 4 owns these; consuming them keeps two empty arrays out of the
      // residue and out of every diff.
      if (const json::Value* chain = entry.find("chain");
          chain != nullptr && chain->isArray() && chain->asArray()->empty()) {
        take(*fields, "chain");
      }
      if (const json::Value* sends = entry.find("sends");
          sends != nullptr && sends->isArray() && sends->asArray()->empty()) {
        take(*fields, "sends");
      }
      tables_.mixer_tracks.emplace(*id, std::move(track));
    }
    root.emplace("mixer_tracks", std::move(value));
  }

  void readInstruments(json::Object& root) {
    json::Value value = take(root, "instruments");
    json::Object* map = value.asObject();
    if (map == nullptr) return;
    int32_t fallback_order = 0;
    for (auto& [key, entry] : *map) {
      json::Object* fields = entry.asObject();
      if (fields == nullptr) continue;
      const std::optional<InstrumentId> id = InstrumentId::parse(key);
      if (!id) {
        note("Kept, not understood: instrument '" + key + "'.");
        continue;
      }
      Instrument instrument;
      instrument.id = *id;
      instrument.name = takeString(*fields, "name", "Instrument");
      instrument.color = takeString(*fields, "color", "#6C8CFF");
      instrument.order = static_cast<int32_t>(takeInt(*fields, "order", fallback_order));
      ++fallback_order;
      instrument.muted = takeBool(*fields, "muted");

      json::Value plugin_value = take(*fields, "plugin");
      if (json::Object* plugin = plugin_value.asObject(); plugin != nullptr) {
        const json::Value* format = plugin_value.find("format");
        const std::string* format_text = format == nullptr ? nullptr : format->asString();
        instrument.plugin.format =
            format_text == nullptr ? PluginFormat::Unknown : pluginFormatFrom(*format_text);
        if (instrument.plugin.format != PluginFormat::Unknown) {
          take(*plugin, "format");
        } else if (format_text != nullptr) {
          // Left in the residue on purpose: we cannot model it, so the file
          // keeps its own word for it and a newer build still understands it.
          note("Kept, not understood: plug-in format '" + *format_text + "' on '" +
               instrument.name + "'.");
        }
        instrument.plugin.id = takeString(*plugin, "id");
        instrument.plugin.name = takeString(*plugin, "name");
        instrument.plugin.vendor = takeString(*plugin, "vendor");
        instrument.plugin.path_hint = takeString(*plugin, "path_hint");
        fields->emplace("plugin", std::move(plugin_value));
      }
      instrument.plugin.state_ref = takeString(*fields, "state_ref");
      instrument.plugin.state_sha256 = takeString(*fields, "state_sha256");

      json::Value defaults_value = take(*fields, "note_defaults");
      if (json::Object* defaults = defaults_value.asObject(); defaults != nullptr) {
        instrument.note_defaults.velocity =
            clampVelocity(takeInt(*defaults, "velocity", DefaultVelocity),
                          "note defaults of '" + instrument.name + "'");
        instrument.note_defaults.pan = takeFloat(*defaults, "pan", 0.0F);
        instrument.note_defaults.pitch_offset =
            static_cast<int16_t>(takeInt(*defaults, "pitch_offset"));
        fields->emplace("note_defaults", std::move(defaults_value));
      }

      json::Value routing_value = take(*fields, "routing");
      if (const json::Array* routing = routing_value.asArray(); routing != nullptr) {
        int32_t position = 0;
        for (const json::Value& route : *routing) {
          std::string track_text;
          plugin::PortId port = static_cast<plugin::PortId>(position);
          if (const std::string* bare = route.asString(); bare != nullptr) {
            track_text = *bare;  // the shorthand: one ID, port by position
          } else if (route.isObject()) {
            const json::Value* track = route.find("track_id");
            if (track != nullptr && track->asString() != nullptr) track_text = *track->asString();
            const json::Value* port_value = route.find("port");
            if (port_value != nullptr && port_value->isNumber()) {
              port = static_cast<plugin::PortId>(port_value->asInt());
            }
          }
          const std::optional<MixerTrackId> track = reference<EntityKind::MixerTrack>(
              track_text, "Instrument '" + instrument.name + "'", "routing destination");
          if (track) pending_routing_[*id].push_back(OutputRoute{port, *track});
          ++position;
        }
      }
      tables_.instruments.emplace(*id, std::move(instrument));
    }
    root.emplace("instruments", std::move(value));
  }

  void readPatterns(json::Object& root) {
    json::Value value = take(root, "patterns");
    json::Object* map = value.asObject();
    if (map == nullptr) return;
    for (auto& [key, entry] : *map) {
      json::Object* fields = entry.asObject();
      if (fields == nullptr) continue;
      const std::optional<PatternId> id = PatternId::parse(key);
      if (!id) {
        note("Kept, not understood: pattern '" + key + "'.");
        continue;
      }
      Pattern pattern;
      pattern.id = *id;
      pattern.name = takeString(*fields, "name", "Pattern");
      pattern.color = takeString(*fields, "color", "#6C8CFF");
      pattern.length = takeInt(*fields, "length", TicksPerBarFourFour * 4);
      if (pattern.length <= 0) {
        warn("Pattern '" + pattern.name + "' has no length; using one bar.");
        pattern.length = TicksPerBarFourFour;
      }
      pattern.swing = takeDouble(*fields, "swing", 0.0);
      if (pattern.swing < 0.0 || pattern.swing > 1.0) {
        warn("Pattern '" + pattern.name + "' has invalid swing; using none.");
        pattern.swing = 0.0;
      }

      json::Value sequences_value = take(*fields, "sequences");
      if (json::Object* sequences = sequences_value.asObject(); sequences != nullptr) {
        for (auto& [instrument_key, notes_value] : *sequences) {
          const std::optional<InstrumentId> instrument = InstrumentId::parse(instrument_key);
          if (!instrument) {
            note("Kept, not understood: sequence key '" + instrument_key + "' in pattern '" +
                 pattern.name + "'.");
            continue;
          }
          const json::Array* notes = notes_value.asArray();
          if (notes == nullptr) continue;
          pattern.sequences.emplace(*instrument,
                                    readSequence(*notes, *id, *instrument, pattern.name));
          notes_value = json::Value::array({});  // consumed; pruned below
        }
        // Sequences we understood are now empty arrays; drop the whole map if
        // nothing is left in it.
        for (auto sequence = sequences->begin(); sequence != sequences->end();) {
          const json::Array* remaining = sequence->second.asArray();
          sequence = (remaining != nullptr && remaining->empty()) ? sequences->erase(sequence)
                                                                  : std::next(sequence);
        }
        if (!sequences->empty()) fields->emplace("sequences", std::move(sequences_value));
      }
      tables_.patterns.emplace(*id, std::move(pattern));
    }
    root.emplace("patterns", std::move(value));
  }

  NoteSequence readSequence(const json::Array& records, PatternId pattern, InstrumentId instrument,
                            const std::string& pattern_name) {
    std::vector<Note> notes;
    notes.reserve(records.size());
    size_t malformed = 0;
    for (const json::Value& record : records) {
      const json::Array* fields = record.asArray();
      if (fields == nullptr || fields->size() < 4) {
        ++malformed;
        continue;
      }
      Note note;
      note.start = (*fields)[0].asInt();
      note.length = (*fields)[1].asInt();
      note.key = static_cast<int16_t>((*fields)[2].asInt(60));
      note.velocity = clampVelocity((*fields)[3].asInt(DefaultVelocity),
                                    "a note in pattern '" + pattern_name + "'");
      if (note.length <= 0 || note.start < 0) {
        ++malformed;
        continue;
      }
      if (note.key < 0 || note.key > 127) {
        warn("A note in pattern '" + pattern_name + "' is outside the key range; clamped.");
        note.key = static_cast<int16_t>(std::clamp<int32_t>(note.key, 0, 127));
      }
      if (fields->size() >= 5 && (*fields)[4].isObject()) {
        residue_.note_properties.emplace(Residue::noteKey(pattern, instrument, note), (*fields)[4]);
      }
      notes.push_back(note);
    }
    if (malformed > 0) {
      warn("Pattern '" + pattern_name + "' has " + std::to_string(malformed) +
           " unusable note record(s) — dropped.");
    }

    NoteSequence sequence;
    sequence.assignSorted(std::move(notes));
    return sequence;
  }

  void readLanes(json::Object& root) {
    json::Value value = take(root, "lanes");
    json::Object* map = value.asObject();
    if (map == nullptr) return;
    for (auto& [key, entry] : *map) {
      json::Object* fields = entry.asObject();
      if (fields == nullptr) continue;
      const std::optional<ArrangementLaneId> id = ArrangementLaneId::parse(key);
      if (!id) {
        note("Kept, not understood: lane '" + key + "'.");
        continue;
      }
      ArrangementLane lane;
      lane.id = *id;
      lane.name = takeString(*fields, "name", "Lane");
      lane.color = takeString(*fields, "color", "#6C8CFF");
      lane.height = static_cast<int32_t>(takeInt(*fields, "height", 88));
      lane.order = static_cast<int32_t>(takeInt(*fields, "order"));
      lane.collapsed = takeBool(*fields, "collapsed");
      lane.muted = takeBool(*fields, "muted");
      lane.soloed = takeBool(*fields, "soloed");
      const std::string group = takeString(*fields, "group_id");
      if (!group.empty()) pending_lane_group_.emplace(*id, group);
      tables_.lanes.emplace(*id, std::move(lane));
    }
    root.emplace("lanes", std::move(value));
  }

  void readClips(json::Object& root) {
    json::Value value = take(root, "clips");
    json::Object* map = value.asObject();
    if (map == nullptr) return;
    // Keys of clips that could not be modelled *and* must not come back: their
    // leftover fields are erased from the residue, or the next save would write
    // a broken clip out again from a partial record.
    std::vector<std::string> unusable;
    for (auto& [key, entry] : *map) {
      json::Object* fields = entry.asObject();
      if (fields == nullptr) continue;
      const std::optional<ClipId> id = ClipId::parse(key);
      if (!id) {
        note("Kept, not understood: clip '" + key + "'.");
        continue;
      }
      // By value: the string this points at lives inside the source object, and
      // the type is taken out of that object a few lines below.
      const json::Value* source_value = entry.find("source");
      const json::Value* type_value =
          source_value == nullptr ? nullptr : source_value->find("type");
      const std::string* type_text = type_value == nullptr ? nullptr : type_value->asString();
      if (type_text == nullptr) {
        error("Clip '" + key + "' does not say what it plays — dropped.");
        unusable.push_back(key);
        continue;
      }
      const std::string type = *type_text;
      if (type != "pattern" && type != "audio" && type != "automation") {
        // §7: an entity we cannot model stays in the file untouched rather
        // than being modelled wrongly or thrown away. It is not in the session
        // and not playable, and the next save writes it back as it was.
        std::string message = "Kept, not understood: clip '";
        message.append(key).append("' plays a '").append(type).append("' source.");
        note(std::move(message));
        continue;
      }

      Clip clip;
      clip.id = *id;
      clip.start = takeInt(*fields, "start");
      clip.length = takeInt(*fields, "length");
      clip.muted = takeBool(*fields, "muted");
      if (clip.length <= 0) {
        error("Clip '" + key + "' has no length — dropped.");
        unusable.push_back(key);
        continue;
      }

      const std::string lane_text = takeString(*fields, "lane_id");
      const std::optional<ArrangementLaneId> lane =
          reference<EntityKind::ArrangementLane>(lane_text, "Clip '" + key + "'", "lane");
      if (!lane) {
        error("Clip '" + key + "' names no lane — dropped.");
        unusable.push_back(key);
        continue;
      }
      clip.lane = *lane;

      json::Value transforms_value = take(*fields, "transforms");
      if (json::Object* transforms = transforms_value.asObject(); transforms != nullptr) {
        clip.transforms.transpose = static_cast<int16_t>(takeInt(*transforms, "transpose"));
        clip.transforms.loop = takeBool(*transforms, "loop", true);
        clip.transforms.window_start = takeInt(*transforms, "window_start");
        clip.transforms.velocity_scale = takeFloat(*transforms, "velocity_scale", 1.0F);
        clip.transforms.time_nudge = takeInt(*transforms, "time_nudge");
        clip.transforms.probability = takeFloat(*transforms, "probability", 1.0F);
        fields->emplace("transforms", std::move(transforms_value));
      }

      json::Value source_owned = take(*fields, "source");
      json::Object* source = source_owned.asObject();
      take(*source, "type");
      bool usable = true;
      if (type == "pattern") {
        const std::string pattern_text = takeString(*source, "pattern_id");
        const std::optional<PatternId> pattern =
            reference<EntityKind::Pattern>(pattern_text, "Clip '" + key + "'", "pattern");
        if (!pattern) {
          usable = false;
        } else {
          clip.source = PatternSource{*pattern};
          pending_clip_pattern_.emplace(*id, *pattern);
        }
      } else if (type == "audio") {
        AudioSource audio;
        audio.path = takeString(*source, "path");
        audio.source_offset = takeInt(*source, "source_offset");
        audio.gain = takeFloat(*source, "gain", 1.0F);
        audio.reversed = takeBool(*source, "reversed");
        const std::string destination = takeString(*source, "destination_id");
        const std::optional<MixerTrackId> track =
            reference<EntityKind::MixerTrack>(destination, "Clip '" + key + "'", "destination");
        if (!track) {
          usable = false;
        } else {
          audio.destination = *track;
          clip.source = audio;
          pending_clip_track_.emplace(*id, *track);
        }
      } else {
        AutomationSource automation;
        const std::string target_kind = takeString(*source, "target_kind", "instrument");
        const std::string target = takeString(*source, "target_id");
        automation.parameter =
            static_cast<plugin::ParamId>(takeInt(*source, "parameter", plugin::InvalidParamId));
        if (target_kind == "mixer_track") {
          automation.target_kind = AutomationSource::TargetKind::MixerTrack;
          const std::optional<MixerTrackId> track =
              reference<EntityKind::MixerTrack>(target, "Clip '" + key + "'", "target");
          if (!track) {
            usable = false;
          } else {
            automation.mixer_track = *track;
            pending_clip_track_.emplace(*id, *track);
          }
        } else {
          const std::optional<InstrumentId> instrument =
              reference<EntityKind::Instrument>(target, "Clip '" + key + "'", "target");
          if (!instrument) {
            usable = false;
          } else {
            automation.instrument = *instrument;
            pending_clip_instrument_.emplace(*id, *instrument);
          }
        }
        const json::Value points = take(*source, "points");
        if (const json::Array* array = points.asArray(); array != nullptr) {
          for (const json::Value& point : *array) {
            const json::Array* pair = point.asArray();
            if (pair == nullptr || pair->size() < 2) continue;
            automation.points.push_back(
                AutomationPoint{(*pair)[0].asInt(), static_cast<float>((*pair)[1].asDouble())});
          }
          std::stable_sort(automation.points.begin(), automation.points.end(),
                           [](const AutomationPoint& a, const AutomationPoint& b) {
                             return a.position < b.position;
                           });
        }
        if (usable) clip.source = automation;
      }
      if (!usable) {
        // The reference() call already said which reference was unusable.
        unusable.push_back(key);
        continue;
      }
      if (!source->empty()) fields->emplace("source", std::move(source_owned));
      tables_.clips.emplace(*id, std::move(clip));
    }
    for (const std::string& key : unusable) map->erase(key);
    root.emplace("clips", std::move(value));
  }

  // Everything that names another entity is resolved in one pass at the end,
  // because a file is a map and not a dependency order: a clip may be written
  // before the pattern it plays, and a track before its output.
  void resolveReferences() {
    // The master is elected *before* outputs are resolved. A track whose output
    // is missing gets routed to the master, and if that repair ran first, a
    // broken track could be elected master itself simply by sorting earlier.
    chooseMaster();

    for (auto& [id, track] : tables_.mixer_tracks) {
      const auto pending = pending_track_output_.find(id);
      if (pending == pending_track_output_.end()) continue;
      const std::optional<MixerTrackId> output = reference<EntityKind::MixerTrack>(
          pending->second, "Mixer track '" + track.name + "'", "output");
      if (output && tables_.mixer_tracks.count(*output) > 0 && *output != id) {
        track.output = *output;
      } else {
        warn("Mixer track '" + track.name +
             "' routed to a track that is not there; routed to the master.");
        if (id != tables_.master) track.output = tables_.master;
      }
    }

    // A cycle in the mixer graph is silence at best and a stack overflow at
    // worst; it cannot survive the load.
    breakMixerCycles();

    for (auto& [id, instrument] : tables_.instruments) {
      const auto pending = pending_routing_.find(id);
      std::vector<OutputRoute> routes;
      if (pending != pending_routing_.end()) {
        for (const OutputRoute& route : pending->second) {
          if (tables_.mixer_tracks.count(route.track) > 0) {
            routes.push_back(route);
          } else {
            warn("Instrument '" + instrument.name +
                 "' was routed to a mixer track that is not there; routed to the master.");
          }
        }
      }
      if (routes.empty()) routes.push_back(OutputRoute{0, tables_.master});
      instrument.routing = std::move(routes);
    }

    for (auto& [id, lane] : tables_.lanes) {
      const auto pending = pending_lane_group_.find(id);
      if (pending == pending_lane_group_.end()) continue;
      const std::optional<ArrangementLaneId> group = ArrangementLaneId::parse(pending->second);
      if (group && tables_.lanes.count(*group) > 0 && *group != id) {
        lane.group_id = *group;
      } else {
        warn("Lane '" + lane.name + "' is grouped under a lane that is not there; ungrouped.");
      }
    }

    // Sequences for instruments that are gone: the notes cannot sound and
    // nothing can address them, so they go, with a count of what was lost.
    for (auto& [pattern_id, pattern] : tables_.patterns) {
      for (auto sequence = pattern.sequences.begin(); sequence != pattern.sequences.end();) {
        if (tables_.instruments.count(sequence->first) > 0) {
          ++sequence;
          continue;
        }
        error("Pattern '" + pattern.name + "' has " + std::to_string(sequence->second.size()) +
              " note(s) for an instrument that is not in this project — removed.");
        sequence = pattern.sequences.erase(sequence);
      }
    }

    dropDanglingClips();
    fixLaneOrder();
  }

  void chooseMaster() {
    // Exactly one track has no output. Anything else is repaired here rather
    // than left for the invariant checker to abort on. A root is a track whose
    // file record carried no `output_id` at all — not one whose output failed
    // to resolve, which is a different problem with a different repair.
    std::vector<MixerTrackId> roots;
    for (const auto& [id, track] : tables_.mixer_tracks) {
      if (pending_track_output_.count(id) == 0) roots.push_back(id);
    }
    if (roots.empty()) {
      MixerTrack master;
      master.id = project_.mintId<EntityKind::MixerTrack>();
      master.name = "Master";
      tables_.master = master.id;
      tables_.mixer_tracks.emplace(master.id, master);
      warn("Project had no master track; one was created.");
      return;
    }
    // The first in ULID order is the oldest, which is the one the project was
    // built around.
    tables_.master = roots.front();
    for (size_t i = 1; i < roots.size(); ++i) {
      tables_.mixer_tracks[roots[i]].output = tables_.master;
      warn("Mixer track '" + tables_.mixer_tracks[roots[i]].name +
           "' had no output; routed to the master.");
    }
  }

  void breakMixerCycles() {
    for (auto& [id, track] : tables_.mixer_tracks) {
      MixerTrackId walker = id;
      size_t steps = 0;
      while (true) {
        const auto entry = tables_.mixer_tracks.find(walker);
        if (entry == tables_.mixer_tracks.end()) break;
        const std::optional<MixerTrackId> output = entry->second.output;
        if (!output.has_value()) break;
        walker = *output;
        if (walker == id || ++steps > tables_.mixer_tracks.size()) {
          warn("Mixer track '" + track.name + "' fed back into itself; routed to the master.");
          track.output = tables_.master;
          break;
        }
      }
    }
  }

  void dropDanglingClips() {
    for (auto clip = tables_.clips.begin(); clip != tables_.clips.end();) {
      std::string reason;
      if (tables_.lanes.count(clip->second.lane) == 0) {
        reason = "its lane is not in this project";
      } else if (const auto pattern = pending_clip_pattern_.find(clip->first);
                 pattern != pending_clip_pattern_.end() &&
                 tables_.patterns.count(pattern->second) == 0) {
        reason = "the pattern it plays is not in this project";
      } else if (const auto instrument = pending_clip_instrument_.find(clip->first);
                 instrument != pending_clip_instrument_.end() &&
                 tables_.instruments.count(instrument->second) == 0) {
        reason = "the instrument it automates is not in this project";
      } else if (const auto track = pending_clip_track_.find(clip->first);
                 track != pending_clip_track_.end() &&
                 tables_.mixer_tracks.count(track->second) == 0) {
        reason = "the mixer track it targets is not in this project";
      }
      if (reason.empty()) {
        ++clip;
        continue;
      }
      // FR-UX-12 in one sentence: which clip, what is missing, what happened.
      error("Clip " + clip->first.str() + " was removed because " + reason + ".");
      dropped_clips_.push_back(clip->first);
      clip = tables_.clips.erase(clip);
    }
  }

  // Lane order is a display field, and two lanes claiming the same position is
  // a model the UI cannot render deterministically.
  void fixLaneOrder() {
    std::vector<std::pair<int32_t, ArrangementLaneId>> ordered;
    ordered.reserve(tables_.lanes.size());
    for (const auto& [id, lane] : tables_.lanes) ordered.emplace_back(lane.order, id);
    std::stable_sort(ordered.begin(), ordered.end(),
                     [](const auto& a, const auto& b) { return a.first < b.first; });
    bool changed = false;
    for (size_t i = 0; i < ordered.size(); ++i) {
      const auto position = static_cast<int32_t>(i);
      ArrangementLane& lane = tables_.lanes[ordered[i].second];
      if (lane.order != position) {
        lane.order = position;
        changed = true;
      }
    }
    if (changed) warn("Lane order was ambiguous; lanes were renumbered in their saved order.");
  }

  Velocity clampVelocity(int64_t value, const std::string& owner) {
    if (value < 0 || value > MaxVelocity) {
      warn("Velocity " + std::to_string(value) + " in " + owner + " is out of range; clamped.");
      value = std::clamp<int64_t>(value, 0, MaxVelocity);
    }
    return static_cast<Velocity>(value);
  }

 public:
  // The loader drops a clip's residue along with the clip: preserving fields of
  // an entity that no longer exists would resurrect it on the next save.
  void purgeDroppedResidue() {
    json::Object* root = residue_.document.asObject();
    if (root == nullptr) return;
    const auto clips = root->find("clips");
    if (clips == root->end()) return;
    json::Object* map = clips->second.asObject();
    if (map == nullptr) return;
    for (const ClipId& id : dropped_clips_) map->erase(id.str());
    if (map->empty()) root->erase(clips);
  }

  bool ticksOk() const { return ticks_ok_; }

 private:
  Project& project_;
  Residue& residue_;
  LoadReport& report_;
  Project::Tables tables_;

  bool ticks_ok_ = true;
  std::vector<ClipId> dropped_clips_;
  std::map<MixerTrackId, std::string> pending_track_output_;
  std::map<InstrumentId, std::vector<OutputRoute>> pending_routing_;
  std::map<ArrangementLaneId, std::string> pending_lane_group_;
  std::map<ClipId, PatternId> pending_clip_pattern_;
  std::map<ClipId, InstrumentId> pending_clip_instrument_;
  std::map<ClipId, MixerTrackId> pending_clip_track_;
};

}  // namespace

LoadReport loadProjectJson(std::string_view text, Project& project, Residue& residue) {
  LoadReport report;
  Residue parsed;
  // Built in a project of its own: a file that turns out to be unreadable
  // halfway through must not cost the caller the session they already have
  // open. Only when the whole thing has parsed and validated do the tables
  // move across — by `adopt`, not by assigning the `Project`, because
  // assigning it would replace the caller's change bus and silently
  // disconnect everything subscribed to it (the flattener, the UI).
  Project staged;
  staged.setDebugChecks(false);  // the loader validates the whole model itself

  Loader loader(staged, parsed, report);
  if (!loader.run(text) || !loader.ticksOk()) {
    report.ok = false;
    return report;
  }
  loader.purgeDroppedResidue();

  project.adopt(staged.copyTables());
  residue = std::move(parsed);
  report.ok = true;
  return report;
}

LoadReport loadProject(const std::filesystem::path& bundle, Project& project, Residue& residue,
                       const LoadOptions& options) {
  LoadReport report;
  const std::filesystem::path document = bundle / "project.json";

  std::error_code code;
  if (!std::filesystem::exists(document, code)) {
    report.issues.push_back(
        {LoadIssue::Severity::Error,
         "'" + bundle.filename().string() + "' is not a OneBeat project: it has no project.json."});
    return report;
  }

  std::string text;
  std::string error;
  if (!readFile(document, text, error)) {
    report.issues.push_back({LoadIssue::Severity::Error, "Could not read " + error + "."});
    return report;
  }

  report = loadProjectJson(text, project, residue);
  if (!report.ok || !options.load_state) return report;

  for (const auto& [id, instrument] : project.instruments()) {
    if (instrument.plugin.state_ref.empty()) continue;
    const std::filesystem::path sidecar = bundle / instrument.plugin.state_ref;
    std::string chunk;
    if (!readFile(sidecar, chunk, error)) {
      report.issues.push_back(
          {LoadIssue::Severity::Warning,
           "'" + instrument.name + "' could not restore its settings: the file " +
               instrument.plugin.state_ref + " is missing. It loads with its defaults."});
      continue;
    }
    const std::string digest = sha256Hex(chunk);
    if (!instrument.plugin.state_sha256.empty() && digest != instrument.plugin.state_sha256) {
      // Loud, and not applied: handing a plugin a chunk that is not the chunk
      // it wrote is how a plugin crashes on load (OB-2-03's whole subject).
      report.issues.push_back({LoadIssue::Severity::Error,
                               "'" + instrument.name +
                                   "' has damaged settings (the saved checksum does not match). "
                                   "It loads with its defaults."});
      continue;
    }
    if (options.state_sink) {
      std::vector<std::byte> bytes(chunk.size());
      std::memcpy(bytes.data(), chunk.data(), chunk.size());
      options.state_sink(id, bytes);
    }
  }
  return report;
}

// --------------------------------------------------------------------------
// Saving
// --------------------------------------------------------------------------

SaveReport saveProject(const std::filesystem::path& bundle, const Project& project,
                       const Residue& residue, const SaveOptions& options) {
  SaveReport report;
  std::error_code code;

  const std::filesystem::path parent =
      bundle.parent_path().empty() ? std::filesystem::path(".") : bundle.parent_path();
  std::filesystem::create_directories(parent, code);

  // Staged beside the destination, never in a temp directory elsewhere: the
  // swap at the end has to be a rename within one filesystem, and /tmp is not
  // guaranteed to be on the same one as the user's project.
  const std::filesystem::path staging =
      parent / ("." + bundle.filename().string() + ".saving-" + std::to_string(::getpid()));
  std::filesystem::remove_all(staging, code);
  if (!std::filesystem::create_directory(staging, code)) {
    report.error = "Could not prepare a temporary folder next to '" + bundle.string() + "'.";
    return report;
  }

  const auto abandon = [&](std::string message) {
    std::error_code ignored;
    std::filesystem::remove_all(staging, ignored);
    report.error = std::move(message);
    report.ok = false;
    return report;
  };

  // Sidecars first: their digests go into project.json, so the document cannot
  // be written until the chunks it describes exist.
  const std::filesystem::path state_dir = staging / "state";
  for (const auto& [id, instrument] : project.instruments()) {
    std::vector<std::byte> chunk;
    if (options.state_provider) chunk = options.state_provider(id);

    if (!chunk.empty()) {
      // Named by ULID rather than by the instrument's name: two instruments
      // called "Bass" are ordinary, and a filename collision would have one
      // silently loading the other's settings.
      const std::string ref = "state/" + id.str() + ".bin";
      std::filesystem::create_directories(state_dir, code);
      std::string error;
      if (!writeFileSynced(staging / ref, chunk.data(), chunk.size(), error)) {
        return abandon(error);
      }
      report.state_written.emplace(
          id, SaveReport::StateRecord{ref, sha256Hex(chunk.data(), chunk.size())});
      report.bytes_written += chunk.size();
      continue;
    }

    // No provider, or nothing to say: carry across whatever the bundle already
    // has, so that a Save As does not quietly strip every plugin's settings.
    if (instrument.plugin.state_ref.empty() || options.copy_state_from.empty()) continue;
    const std::filesystem::path source = options.copy_state_from / instrument.plugin.state_ref;
    if (!std::filesystem::exists(source, code)) continue;
    std::filesystem::create_directories(
        staging / std::filesystem::path(instrument.plugin.state_ref).parent_path(), code);
    std::filesystem::copy_file(source, staging / instrument.plugin.state_ref,
                               std::filesystem::copy_options::overwrite_existing, code);
    if (code) {
      return abandon("Could not copy the settings of '" + instrument.name + "' into the save.");
    }
  }

  const std::string text =
      writeProjectJson(project, residue, options.created_with, report.state_written);
  if (text.empty()) {
    return abandon("This project contains a value that cannot be written (not a finite number).");
  }
  std::string error;
  if (!writeFileSynced(staging / "project.json", text.data(), text.size(), error)) {
    return abandon(error);
  }
  report.bytes_written += text.size();
  syncDirectory(staging);

  if (options.crash_hook) options.crash_hook();

  // The atomic step. `RENAME_SWAP` exchanges the two directory entries in one
  // operation, so there is no instant at which the destination does not exist:
  // a crash before it leaves the old bundle, a crash after leaves the new one.
  // The staging directory then holds the *previous* save, which is removed
  // last — and if that removal never happens, all that is left behind is a
  // hidden folder, not a lost project.
  if (std::filesystem::exists(bundle, code)) {
    if (::renamex_np(staging.c_str(), bundle.c_str(), RENAME_SWAP) != 0) {
      return abandon("Could not replace '" + bundle.filename().string() +
                     "': " + std::strerror(errno));
    }
    std::filesystem::remove_all(staging, code);
  } else {
    std::filesystem::rename(staging, bundle, code);
    if (code) {
      return abandon("Could not create '" + bundle.filename().string() + "'.");
    }
  }
  syncDirectory(parent);

  report.ok = true;
  return report;
}

}  // namespace onebeat::model
