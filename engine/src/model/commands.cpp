#include "model/commands.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <map>
#include <set>
#include <utility>

namespace onebeat::model {
namespace {

constexpr std::array<const char*, 8> KInstrumentColors = {
    "#6C8CFF", "#B779F2", "#EF6F91", "#F59E5B", "#E7C75F", "#66C58F", "#50B8C6", "#8294B8"};

std::string uniqueInstrumentName(const Project& project, std::string base) {
  if (base.empty()) base = "Instrument";
  std::set<std::string> names;
  for (const auto& [instrument_id, instrument] : project.instruments()) {
    (void)instrument_id;
    names.insert(instrument.name);
  }
  if (names.count(base) == 0) return base;
  for (size_t suffix = 2;; ++suffix) {
    std::string candidate = base + " " + std::to_string(suffix);
    if (names.count(candidate) == 0) return candidate;
  }
}

int32_t nextInstrumentOrder(const Project& project) {
  int32_t highest = -1;
  for (const auto& [instrument_id, instrument] : project.instruments()) {
    (void)instrument_id;
    highest = std::max(highest, instrument.order);
  }
  return highest + 1;
}

ColorHex nextInstrumentColor(const Project& project) {
  return KInstrumentColors[project.instruments().size() % KInstrumentColors.size()];
}

// --------------------------------------------------------------------------
// Create / delete
// --------------------------------------------------------------------------

// Creation is "restore something that has never existed yet": the entity,
// including its ID, is built before apply, so apply → revert → re-apply is
// idempotent in the only sense that matters — the same ID comes back.
template <typename Entity>
class AddCommand : public Command {
 public:
  AddCommand(Entity entity, std::string name)
      : entity_(std::move(entity)), name_(std::move(name)) {}

  bool apply(Project& project) override;
  bool revert(Project& project) override;
  std::string name() const override { return name_; }

 private:
  Entity entity_;
  std::string name_;
};

template <>
bool AddCommand<Instrument>::apply(Project& project) {
  return project.restoreInstrument(entity_);
}
template <>
bool AddCommand<Instrument>::revert(Project& project) {
  return project.deleteInstrument(entity_.id);
}
template <>
bool AddCommand<Pattern>::apply(Project& project) {
  return project.restorePattern(entity_);
}
template <>
bool AddCommand<Pattern>::revert(Project& project) {
  return project.deletePattern(entity_.id);
}
template <>
bool AddCommand<ArrangementLane>::apply(Project& project) {
  return project.restoreLane(entity_);
}
template <>
bool AddCommand<ArrangementLane>::revert(Project& project) {
  return project.deleteLane(entity_.id);
}
template <>
bool AddCommand<Clip>::apply(Project& project) {
  return project.restoreClip(entity_);
}
template <>
bool AddCommand<Clip>::revert(Project& project) {
  return project.deleteClip(entity_.id);
}
template <>
bool AddCommand<MixerTrack>::apply(Project& project) {
  return project.restoreMixerTrack(entity_);
}
template <>
bool AddCommand<MixerTrack>::revert(Project& project) {
  return project.deleteMixerTrack(entity_.id);
}

// Deleting an instrument is the cascade ARCHITECTURE.md §3.1 warns about, so
// this is the command with the most inverse to capture: the instrument, every
// sequence it had in every pattern, and the automation clips that die with it.
class RemoveInstrumentCommand : public Command {
 public:
  explicit RemoveInstrumentCommand(InstrumentId id) : id_(id) {}

  bool apply(Project& project) override {
    const Instrument* instrument = project.findInstrument(id_);
    if (instrument == nullptr) return false;
    instrument_ = *instrument;

    sequences_.clear();
    for (const auto& [pattern_id, pattern] : project.patterns()) {
      const auto sequence = pattern.sequences.find(id_);
      if (sequence != pattern.sequences.end()) sequences_.emplace(pattern_id, sequence->second);
    }

    clips_.clear();
    for (const ClipId clip_id : project.instrumentImpact(id_).clips) {
      if (const Clip* clip = project.findClip(clip_id)) clips_.push_back(*clip);
    }

    return project.deleteInstrument(id_);
  }

  bool revert(Project& project) override {
    if (!project.restoreInstrument(instrument_)) return false;
    for (const auto& [pattern_id, sequence] : sequences_) {
      project.restoreSequence(pattern_id, id_, sequence);
    }
    for (const Clip& clip : clips_) project.restoreClip(clip);
    return true;
  }

  std::string name() const override { return "Delete instrument"; }

 private:
  InstrumentId id_;
  Instrument instrument_;
  std::map<PatternId, NoteSequence> sequences_;
  std::vector<Clip> clips_;
};

class RemovePatternCommand : public Command {
 public:
  explicit RemovePatternCommand(PatternId id) : id_(id) {}

  bool apply(Project& project) override {
    const Pattern* pattern = project.findPattern(id_);
    if (pattern == nullptr) return false;
    pattern_ = *pattern;

    clips_.clear();
    for (const ClipId clip_id : project.clipsUsingPattern(id_)) {
      if (const Clip* clip = project.findClip(clip_id)) clips_.push_back(*clip);
    }
    return project.deletePattern(id_);
  }

  bool revert(Project& project) override {
    if (!project.restorePattern(pattern_)) return false;
    for (const Clip& clip : clips_) project.restoreClip(clip);
    return true;
  }

  std::string name() const override { return "Delete pattern"; }

 private:
  PatternId id_;
  Pattern pattern_;
  std::vector<Clip> clips_;
};

class RemoveLaneCommand : public Command {
 public:
  explicit RemoveLaneCommand(ArrangementLaneId id) : id_(id) {}

  bool apply(Project& project) override {
    const ArrangementLane* lane = project.findLane(id_);
    if (lane == nullptr) return false;
    lane_ = *lane;

    clips_.clear();
    for (const ClipId clip_id : project.clipsOnLane(id_)) {
      if (const Clip* clip = project.findClip(clip_id)) clips_.push_back(*clip);
    }
    // Lanes this one grouped are released rather than deleted, so the inverse
    // is the list of lanes whose group_id has to be put back.
    grouped_.clear();
    for (const auto& [lane_id, other] : project.lanes()) {
      if (other.group_id.has_value() && *other.group_id == id_) grouped_.push_back(lane_id);
    }
    return project.deleteLane(id_);
  }

  bool revert(Project& project) override {
    if (!project.restoreLane(lane_)) return false;
    for (const ArrangementLaneId lane_id : grouped_) {
      project.updateLane(lane_id, ChangeField::Group,
                         [this](ArrangementLane& lane) { lane.group_id = id_; });
    }
    for (const Clip& clip : clips_) project.restoreClip(clip);
    return true;
  }

  std::string name() const override { return "Delete lane"; }

 private:
  ArrangementLaneId id_;
  ArrangementLane lane_;
  std::vector<Clip> clips_;
  std::vector<ArrangementLaneId> grouped_;
};

class RemoveClipCommand : public Command {
 public:
  explicit RemoveClipCommand(ClipId id) : id_(id) {}

  bool apply(Project& project) override {
    const Clip* clip = project.findClip(id_);
    if (clip == nullptr) return false;
    clip_ = *clip;
    return project.deleteClip(id_);
  }

  bool revert(Project& project) override { return project.restoreClip(clip_); }
  std::string name() const override { return "Delete clip"; }

 private:
  ClipId id_;
  Clip clip_;
};

// Deleting a track re-points everything that fed it at Master and deletes the
// automation that targeted it. All four of those are captured.
class RemoveMixerTrackCommand : public Command {
 public:
  explicit RemoveMixerTrackCommand(MixerTrackId id) : id_(id) {}

  bool apply(Project& project) override {
    const MixerTrack* track = project.findMixerTrack(id_);
    if (track == nullptr) return false;
    track_ = *track;

    const MixerTrackImpact impact = project.mixerTrackImpact(id_);
    routings_.clear();
    for (const InstrumentId instrument_id : impact.instruments) {
      if (const Instrument* instrument = project.findInstrument(instrument_id)) {
        routings_.emplace_back(instrument_id, instrument->routing);
      }
    }
    inputs_ = impact.inputs;
    clips_.clear();
    audio_clips_.clear();
    for (const ClipId clip_id : impact.clips) {
      const Clip* clip = project.findClip(clip_id);
      if (clip == nullptr) continue;
      if (clip->audio() != nullptr) {
        audio_clips_.push_back(*clip);  // re-pointed, not deleted
      } else {
        clips_.push_back(*clip);  // automation: deleted with its target
      }
    }
    return project.deleteMixerTrack(id_);
  }

  bool revert(Project& project) override {
    if (!project.restoreMixerTrack(track_)) return false;
    for (const auto& [instrument_id, routing] : routings_) {
      project.updateInstrument(
          instrument_id, ChangeField::Routing,
          [&routing](Instrument& instrument) { instrument.routing = routing; });
    }
    for (const MixerTrackId input : inputs_) {
      project.updateMixerTrack(input, ChangeField::Output,
                               [this](MixerTrack& track) { track.output = id_; });
    }
    for (const Clip& clip : audio_clips_) {
      project.updateClip(clip.id, ChangeField::Source, [&clip](Clip& live) { live = clip; });
    }
    for (const Clip& clip : clips_) project.restoreClip(clip);
    return true;
  }

  std::string name() const override { return "Delete mixer track"; }

 private:
  MixerTrackId id_;
  MixerTrack track_;
  std::vector<std::pair<InstrumentId, std::vector<OutputRoute>>> routings_;
  std::vector<MixerTrackId> inputs_;
  std::vector<Clip> clips_;
  std::vector<Clip> audio_clips_;
};

// --------------------------------------------------------------------------
// Edits
// --------------------------------------------------------------------------

// One template, five entity kinds, distinguished by a traits struct that knows
// how to write a whole entity back. Whole-entity because the entities are
// small; patterns are the exception and use PatternMeta instead of copying
// their notes (see EditPatternMetaCommand).
template <typename Traits>
class EditCommand : public Command {
 public:
  using Id = typename Traits::Id;
  using Value = typename Traits::Value;

  EditCommand(Id id, ChangeField field, Value before, Value after, std::string name)
      : id_(id),
        field_(field),
        before_(std::move(before)),
        after_(std::move(after)),
        name_(std::move(name)) {}

  bool apply(Project& project) override { return Traits::write(project, id_, field_, after_); }
  bool revert(Project& project) override { return Traits::write(project, id_, field_, before_); }
  std::string name() const override { return name_; }

  bool coalesceWith(const Command& next) override {
    const auto* other = dynamic_cast<const EditCommand*>(&next);
    if (other == nullptr || other->id_ != id_ || other->field_ != field_) return false;
    // Keep this command's "before" — the state the gesture started from — and
    // take the newest "after". One drag, one entry, correct in both directions.
    after_ = other->after_;
    return true;
  }

 private:
  Id id_;
  ChangeField field_;
  Value before_;
  Value after_;
  std::string name_;
};

struct InstrumentTraits {
  using Id = InstrumentId;
  using Value = Instrument;
  static bool write(Project& project, Id id, ChangeField field, const Value& value) {
    return project.updateInstrument(id, field, [&value](Instrument& live) { live = value; });
  }
};

struct LaneTraits {
  using Id = ArrangementLaneId;
  using Value = ArrangementLane;
  static bool write(Project& project, Id id, ChangeField field, const Value& value) {
    return project.updateLane(id, field, [&value](ArrangementLane& live) { live = value; });
  }
};

struct ClipTraits {
  using Id = ClipId;
  using Value = Clip;
  static bool write(Project& project, Id id, ChangeField field, const Value& value) {
    return project.updateClip(id, field, [&value](Clip& live) { live = value; });
  }
};

struct MixerTrackTraits {
  using Id = MixerTrackId;
  using Value = MixerTrack;
  static bool write(Project& project, Id id, ChangeField field, const Value& value) {
    return project.updateMixerTrack(id, field, [&value](MixerTrack& live) { live = value; });
  }
};

struct PatternMetaTraits {
  using Id = PatternId;
  using Value = PatternMeta;
  static bool write(Project& project, Id id, ChangeField field, const Value& value) {
    return project.updatePattern(id, field, [&value](Pattern& live) {
      live.name = value.name;
      live.color = value.color;
      live.length = value.length;
      live.order = value.order;
      live.group = value.group;
      live.time_signature = value.time_signature;
      live.swing = value.swing;
    });
  }
};

// --------------------------------------------------------------------------
// Notes
// --------------------------------------------------------------------------

class NoteCommand : public Command {
 public:
  NoteCommand(PatternId pattern, InstrumentId instrument, std::vector<Note> removed,
              std::vector<Note> added, std::string name, bool coalescable = false)
      : pattern_(pattern),
        instrument_(instrument),
        removed_(std::move(removed)),
        added_(std::move(added)),
        name_(std::move(name)),
        coalescable_(coalescable) {}

  bool apply(Project& project) override { return edit(project, removed_, added_); }
  bool revert(Project& project) override { return edit(project, added_, removed_); }
  std::string name() const override { return name_; }

  bool coalesceWith(const Command& next) override {
    const auto* other = dynamic_cast<const NoteCommand*>(&next);
    if (!coalescable_ || other == nullptr || !other->coalescable_ || other->pattern_ != pattern_ ||
        other->instrument_ != instrument_ || added_ != other->removed_) {
      return false;
    }
    // A -> B followed by B -> C becomes A -> C. The second command has already
    // applied; only history is folded, exactly like EditCommand above.
    added_ = other->added_;
    return true;
  }

 private:
  // One pass: take out what this direction removes, put in what it adds. A
  // move is expressed as both, which is why dragging notes does not have to
  // snapshot the project. Removal counts are indexed so a 10k-note selection
  // stays O(n log n), rather than erasing 10k vector elements one at a time.
  bool edit(Project& project, const std::vector<Note>& take, const std::vector<Note>& give) {
    const Pattern* pattern = project.findPattern(pattern_);
    if (pattern == nullptr || project.findInstrument(instrument_) == nullptr) return false;

    const auto existing = pattern->sequences.find(instrument_);
    const std::vector<Note> empty;
    const std::vector<Note>& current =
        existing == pattern->sequences.end() ? empty : existing->second.notes();

    // Piano-roll "select all" operations are a common 10k-note path. When the
    // command replaces the entire canonical sequence, no removal index or
    // merge is needed: validate once and adopt the already ordered result.
    if (take == current) {
      if (!std::all_of(give.begin(), give.end(), isValidNote)) return false;
      NoteSequence edited;
      edited.assignSorted(give);
      return project.restoreSequence(pattern_, instrument_, std::move(edited));
    }

    const auto fullOrder = [](const Note& left, const Note& right) {
      if (noteOrderBefore(left, right)) return true;
      if (noteOrderBefore(right, left)) return false;
      return left.velocity < right.velocity;
    };
    std::map<Note, size_t, decltype(fullOrder)> removals(fullOrder);
    for (const Note& note : take) ++removals[note];

    std::vector<Note> result;
    result.reserve(current.size() - std::min(current.size(), take.size()) + give.size());
    for (const Note& note : current) {
      auto removal = removals.find(note);
      if (removal == removals.end() || removal->second == 0) {
        result.push_back(note);
      } else {
        --removal->second;
      }
    }
    for (const auto& [note, count] : removals) {
      if (count != 0) return false;
    }
    for (const Note& note : give) {
      if (!isValidNote(note)) return false;
      result.push_back(note);
    }
    NoteSequence edited;
    edited.assignSorted(std::move(result));
    return project.restoreSequence(pattern_, instrument_, std::move(edited));
  }

  PatternId pattern_;
  InstrumentId instrument_;
  std::vector<Note> removed_;
  std::vector<Note> added_;
  std::string name_;
  bool coalescable_ = false;
};

class TransportCommand : public Command {
 public:
  TransportCommand(TransportState before, TransportState after) : before_(before), after_(after) {}

  bool apply(Project& project) override {
    project.setTransport(after_);
    rescaleAudioClips(project, before_.tempo, after_.tempo);
    return true;
  }
  bool revert(Project& project) override {
    project.setTransport(before_);
    restoreAudioClips(project);
    return true;
  }
  std::string name() const override { return "Change transport"; }

  bool coalesceWith(const Command& next) override {
    const auto* other = dynamic_cast<const TransportCommand*>(&next);
    if (other == nullptr) return false;
    after_ = other->after_;
    return true;
  }

 private:
  // An audio clip is anchored in real time: the file lasts as many seconds at
  // 90 BPM as it does at 180. Its length in ticks was derived from the tempo in
  // force when it was placed, so leaving it alone across a tempo change makes
  // the block on the timeline stop describing what is heard — the clip after
  // it looks adjacent while the audio runs under or short of it. Rescaling by
  // the tempo ratio keeps the block over exactly the bars it sounds across.
  // Clip *starts* are musical and deliberately left where they are.
  void rescaleAudioClips(Project& project, double from_tempo, double to_tempo) {
    original_lengths_.clear();
    if (from_tempo <= 0.0 || to_tempo <= 0.0 || from_tempo == to_tempo) return;

    const double ratio = to_tempo / from_tempo;
    std::vector<std::pair<ClipId, Ticks>> resized;
    for (const auto& [id, clip] : project.clips()) {
      if (clip.audio() == nullptr || clip.length <= 0) continue;
      // Every audio clip is recorded, not only the ones that moved: a tempo
      // drag coalesces into this one command, and a clip too short to change
      // on the first step may well change on the tenth.
      original_lengths_.emplace_back(id, clip.length);
      const auto scaled =
          static_cast<Ticks>(std::llround(static_cast<double>(clip.length) * ratio));
      const Ticks length = std::max<Ticks>(1, scaled);
      if (length == clip.length) continue;
      resized.emplace_back(id, length);
    }
    for (const auto& [id, length] : resized) {
      project.updateClip(id, ChangeField::Length, [length](Clip& clip) { clip.length = length; });
    }
  }

  // Undo puts the lengths back verbatim rather than dividing the ratio out:
  // rounding a tick count twice does not always land where it started.
  void restoreAudioClips(Project& project) {
    for (const auto& [id, length] : original_lengths_) {
      const Ticks restored = length;
      project.updateClip(id, ChangeField::Length,
                         [restored](Clip& clip) { clip.length = restored; });
    }
    original_lengths_.clear();
  }

  TransportState before_;
  TransportState after_;
  std::vector<std::pair<ClipId, Ticks>> original_lengths_;
};

class MetaCommand : public Command {
 public:
  MetaCommand(ProjectMeta before, ProjectMeta after)
      : before_(std::move(before)), after_(std::move(after)) {}

  bool apply(Project& project) override {
    project.setMeta(after_);
    return true;
  }
  bool revert(Project& project) override {
    project.setMeta(before_);
    return true;
  }
  std::string name() const override { return "Change project details"; }

 private:
  ProjectMeta before_;
  ProjectMeta after_;
};

}  // namespace

// --------------------------------------------------------------------------
// Factories
// --------------------------------------------------------------------------

CommandPtr addInstrument(Project& project, const std::string& name, const PluginRef& plugin) {
  auto composite = std::make_unique<CompositeCommand>("Add instrument");

  Instrument instrument;
  instrument.id = project.mintId<EntityKind::Instrument>();
  instrument.name = name;
  instrument.color = nextInstrumentColor(project);
  instrument.order = nextInstrumentOrder(project);
  instrument.plugin = plugin;

  MixerTrackId destination = project.masterTrack();
  if (project.preferences().auto_create_mixer_track) {
    MixerTrack track;
    track.id = project.mintId<EntityKind::MixerTrack>();
    track.name = name;
    track.output = project.masterTrack();
    destination = track.id;
    composite->add(std::make_unique<AddCommand<MixerTrack>>(std::move(track), "Add mixer track"));
  }
  instrument.routing.push_back(OutputRoute{0, destination});
  composite->add(std::make_unique<AddCommand<Instrument>>(std::move(instrument), "Add instrument"));
  return composite;
}

CommandPtr addInstrument(Project& project, const PluginRef& plugin) {
  return addInstrument(project, uniqueInstrumentName(project, plugin.name), plugin);
}

CommandPtr duplicateInstrument(Project& project, InstrumentId id) {
  const Instrument* source = project.findInstrument(id);
  if (source == nullptr) return nullptr;

  auto composite = std::make_unique<CompositeCommand>("Duplicate instrument");
  MixerTrack track;
  track.id = project.mintId<EntityKind::MixerTrack>();
  track.name = uniqueInstrumentName(project, source->name);
  track.output = project.masterTrack();

  Instrument copy = *source;
  copy.id = project.mintId<EntityKind::Instrument>();
  copy.name = track.name;
  copy.order = nextInstrumentOrder(project);
  copy.routing = {OutputRoute{0, track.id}};

  composite->add(std::make_unique<AddCommand<MixerTrack>>(std::move(track), "Add mixer track"));
  composite->add(std::make_unique<AddCommand<Instrument>>(std::move(copy), "Add instrument"));
  return composite;
}

CommandPtr replaceInstrument(const Project& project, InstrumentId id, const PluginRef& plugin) {
  return editInstrument(
      project, id, ChangeField::Plugin,
      [&plugin](Instrument& instrument) { instrument.plugin = plugin; }, "Replace instrument");
}

CommandPtr reorderInstrument(const Project& project, InstrumentId id, int32_t target_order) {
  const Instrument* moving = project.findInstrument(id);
  if (moving == nullptr || project.instruments().empty()) return nullptr;

  const int32_t maximum = static_cast<int32_t>(project.instruments().size() - 1);
  target_order = std::clamp(target_order, int32_t{0}, maximum);
  if (moving->order == target_order) return nullptr;

  auto command = std::make_unique<CompositeCommand>("Reorder instrument");
  const int32_t source_order = moving->order;
  for (const auto& [other_id, other] : project.instruments()) {
    int32_t next = other.order;
    if (other_id == id) {
      next = target_order;
    } else if (source_order < target_order && other.order > source_order &&
               other.order <= target_order) {
      --next;
    } else if (source_order > target_order && other.order >= target_order &&
               other.order < source_order) {
      ++next;
    }
    if (next == other.order) continue;
    command->add(editInstrument(
        project, other_id, ChangeField::Order,
        [next](Instrument& instrument) { instrument.order = next; }, "Reorder instrument"));
  }
  return command;
}

CommandPtr addPattern(Project& project, const std::string& name, Ticks length) {
  Pattern pattern;
  pattern.id = project.mintId<EntityKind::Pattern>();
  pattern.name = name;
  pattern.length = length;
  int32_t highest = -1;
  for (const auto& [pattern_id, existing] : project.patterns()) {
    (void)pattern_id;
    highest = std::max(highest, existing.order);
  }
  pattern.order = highest + 1;
  return std::make_unique<AddCommand<Pattern>>(std::move(pattern), "Add pattern");
}

CommandPtr addLane(Project& project, const std::string& name) {
  ArrangementLane lane;
  lane.id = project.mintId<EntityKind::ArrangementLane>();
  lane.name = name;
  int32_t highest = -1;
  for (const auto& [lane_id, existing] : project.lanes()) {
    highest = existing.order > highest ? existing.order : highest;
  }
  lane.order = highest + 1;
  return std::make_unique<AddCommand<ArrangementLane>>(std::move(lane), "Add lane");
}

CommandPtr addMixerTrack(Project& project, const std::string& name) {
  MixerTrack track;
  track.id = project.mintId<EntityKind::MixerTrack>();
  track.name = name;
  track.output = project.masterTrack();
  return std::make_unique<AddCommand<MixerTrack>>(std::move(track), "Add mixer track");
}

CommandPtr addClip(Project& project, ArrangementLaneId lane, const ClipSource& source, Ticks start,
                   Ticks length) {
  Clip clip;
  clip.id = project.mintId<EntityKind::Clip>();
  clip.lane = lane;
  clip.source = source;
  clip.start = start;
  clip.length = length;
  return std::make_unique<AddCommand<Clip>>(std::move(clip), "Add clip");
}

CommandPtr removeInstrument(InstrumentId id) {
  return std::make_unique<RemoveInstrumentCommand>(id);
}
CommandPtr removePattern(PatternId id) {
  return std::make_unique<RemovePatternCommand>(id);
}
CommandPtr removeLane(ArrangementLaneId id) {
  return std::make_unique<RemoveLaneCommand>(id);
}
CommandPtr removeClip(ClipId id) {
  return std::make_unique<RemoveClipCommand>(id);
}
CommandPtr removeMixerTrack(MixerTrackId id) {
  return std::make_unique<RemoveMixerTrackCommand>(id);
}

CommandPtr editInstrument(const Project& project, InstrumentId id, ChangeField field,
                          const std::function<void(Instrument&)>& mutator, std::string name) {
  const Instrument* instrument = project.findInstrument(id);
  if (instrument == nullptr) return nullptr;
  Instrument after = *instrument;
  mutator(after);
  return std::make_unique<EditCommand<InstrumentTraits>>(id, field, *instrument, std::move(after),
                                                         std::move(name));
}

CommandPtr editPatternMeta(const Project& project, PatternId id, ChangeField field,
                           const std::function<void(PatternMeta&)>& mutator, std::string name) {
  const Pattern* pattern = project.findPattern(id);
  if (pattern == nullptr) return nullptr;
  const PatternMeta before = PatternMeta::from(*pattern);
  PatternMeta after = before;
  mutator(after);
  return std::make_unique<EditCommand<PatternMetaTraits>>(id, field, before, std::move(after),
                                                          std::move(name));
}

CommandPtr editLane(const Project& project, ArrangementLaneId id, ChangeField field,
                    const std::function<void(ArrangementLane&)>& mutator, std::string name) {
  const ArrangementLane* lane = project.findLane(id);
  if (lane == nullptr) return nullptr;
  ArrangementLane after = *lane;
  mutator(after);
  return std::make_unique<EditCommand<LaneTraits>>(id, field, *lane, std::move(after),
                                                   std::move(name));
}

CommandPtr editClip(const Project& project, ClipId id, ChangeField field,
                    const std::function<void(Clip&)>& mutator, std::string name) {
  const Clip* clip = project.findClip(id);
  if (clip == nullptr) return nullptr;
  Clip after = *clip;
  mutator(after);
  return std::make_unique<EditCommand<ClipTraits>>(id, field, *clip, std::move(after),
                                                   std::move(name));
}

CommandPtr editMixerTrack(const Project& project, MixerTrackId id, ChangeField field,
                          const std::function<void(MixerTrack&)>& mutator, std::string name) {
  const MixerTrack* track = project.findMixerTrack(id);
  if (track == nullptr) return nullptr;
  MixerTrack after = *track;
  mutator(after);
  return std::make_unique<EditCommand<MixerTrackTraits>>(id, field, *track, std::move(after),
                                                         std::move(name));
}

CommandPtr insertNotes(PatternId pattern, InstrumentId instrument, std::vector<Note> notes) {
  const std::string name =
      "Add " + std::to_string(notes.size()) + (notes.size() == 1 ? " note" : " notes");
  return std::make_unique<NoteCommand>(pattern, instrument, std::vector<Note>{}, std::move(notes),
                                       name);
}

CommandPtr removeNotes(PatternId pattern, InstrumentId instrument, std::vector<Note> notes) {
  const std::string name =
      "Delete " + std::to_string(notes.size()) + (notes.size() == 1 ? " note" : " notes");
  return std::make_unique<NoteCommand>(pattern, instrument, std::move(notes), std::vector<Note>{},
                                       name);
}

CommandPtr replaceNotes(PatternId pattern, InstrumentId instrument, std::vector<Note> before,
                        std::vector<Note> after) {
  if (before.size() != after.size()) return nullptr;
  std::stable_sort(before.begin(), before.end(), noteOrderBefore);
  std::stable_sort(after.begin(), after.end(), noteOrderBefore);
  const std::string name =
      "Edit " + std::to_string(before.size()) + (before.size() == 1 ? " note" : " notes");
  return std::make_unique<NoteCommand>(pattern, instrument, std::move(before), std::move(after),
                                       name, true);
}

// --------------------------------------------------------------------------
// Audio clips
// --------------------------------------------------------------------------

namespace {

// Every audio-clip command edits the same field of the same variant, so they
// all funnel through here: find the clip, prove it is audio, mutate a copy of
// its source. A clip of the wrong kind returns null rather than being coerced.
CommandPtr editAudio(const Project& project, ClipId id,
                     const std::function<void(AudioSource&)>& mutator, std::string name) {
  const Clip* clip = project.findClip(id);
  if (clip == nullptr || clip->audio() == nullptr) return nullptr;
  return editClip(
      project, id, ChangeField::Source,
      [&mutator](Clip& live) {
        if (AudioSource* audio = std::get_if<AudioSource>(&live.source)) mutator(*audio);
      },
      std::move(name));
}

}  // namespace

CommandPtr setAudioClipWindow(const Project& project, ClipId id, Ticks source_offset,
                              Ticks source_length) {
  if (source_offset < 0 || source_length < 0) return nullptr;
  return editAudio(
      project, id,
      [source_offset, source_length](AudioSource& audio) {
        audio.source_offset = source_offset;
        audio.source_length = source_length;
      },
      "Trim clip");
}

CommandPtr setAudioClipStretchMode(const Project& project, ClipId id, StretchMode mode) {
  return editAudio(
      project, id, [mode](AudioSource& audio) { audio.stretch_mode = mode; }, "Set clip stretch");
}

CommandPtr setAudioClipSourceBpm(const Project& project, ClipId id, double bpm) {
  if (bpm < 0.0) return nullptr;
  return editAudio(
      project, id, [bpm](AudioSource& audio) { audio.source_bpm = bpm; }, "Set clip tempo");
}

CommandPtr setAudioClipReversed(const Project& project, ClipId id, bool reversed) {
  return editAudio(
      project, id, [reversed](AudioSource& audio) { audio.reversed = reversed; }, "Reverse clip");
}

CommandPtr setAudioClipGain(const Project& project, ClipId id, float gain) {
  if (gain < 0.0F) return nullptr;
  return editAudio(project, id, [gain](AudioSource& audio) { audio.gain = gain; }, "Set clip gain");
}

CommandPtr resizeAudioClip(const Project& project, ClipId id, Ticks length) {
  if (length <= 0) return nullptr;
  const Clip* clip = project.findClip(id);
  if (clip == nullptr) return nullptr;
  const AudioSource* audio = clip->audio();
  // A pattern or automation clip has no window to keep in step; a plain resize
  // is the whole of the edit.
  if (audio == nullptr) {
    return editClip(
        project, id, ChangeField::Length, [length](Clip& live) { live.length = length; },
        "Resize clip");
  }

  const bool stretching = audio->stretch_mode != StretchMode::Off;
  const Ticks source_length = audio->source_length;
  return editClip(
      project, id, ChangeField::Length,
      [length, stretching, source_length](Clip& live) {
        live.length = length;
        if (stretching) return;  // the window stands and the ratio moves with it
        // Not stretching: the clip is a window onto the source, so dragging the
        // edge is a trim. A window of 0 stays 0 — it already means "the rest of
        // the file", which is exactly what an untrimmed clip wants to keep
        // meaning as it grows.
        if (source_length <= 0) return;
        if (AudioSource* live_audio = std::get_if<AudioSource>(&live.source)) {
          live_audio->source_length = length;
        }
      },
      stretching ? "Stretch clip" : "Resize clip");
}

CommandPtr splitClip(Project& project, ClipId id, Ticks at) {
  const Clip* clip = project.findClip(id);
  if (clip == nullptr) return nullptr;
  // Strictly inside: a cut on either edge produces the clip you already have
  // and an empty one, which is not an edit worth an undo entry.
  if (at <= clip->start || at >= clip->start + clip->length) return nullptr;

  const Ticks left_length = at - clip->start;
  const Ticks right_length = clip->start + clip->length - at;

  Clip right = *clip;
  right.id = project.mintId<EntityKind::Clip>();
  right.start = at;
  right.length = right_length;

  if (AudioSource* audio = std::get_if<AudioSource>(&right.source)) {
    // The right half must resume where the left half stopped, not restart the
    // file — that is the difference between cutting a sample and duplicating
    // it. How far into the source the cut lands depends on how the clip maps
    // timeline time onto source time, so the stretch ratio is what converts it.
    const double ratio = audioStretchRatio(*audio, clip->length);
    const Ticks consumed = static_cast<Ticks>(static_cast<double>(left_length) * ratio);
    audio->source_offset += consumed;
    if (audio->source_length > 0) {
      audio->source_length = audio->source_length > consumed ? audio->source_length - consumed : 0;
    }
  } else if (AutomationSource* automation = std::get_if<AutomationSource>(&right.source)) {
    // Points are clip-relative, so each half keeps the points that fall in it,
    // rebased onto its own origin.
    std::vector<AutomationPoint> kept;
    for (const AutomationPoint& point : automation->points) {
      if (point.position < left_length) continue;
      kept.push_back(AutomationPoint{point.position - left_length, point.value});
    }
    automation->points = std::move(kept);
  }

  auto composite = std::make_unique<CompositeCommand>("Cut clip");
  // The left half keeps the original ID, so anything already referring to this
  // clip keeps referring to the part the user cut off *from*.
  CommandPtr shorten = editClip(
      project, id, ChangeField::Length,
      [left_length](Clip& live) {
        live.length = left_length;
        if (AudioSource* audio = std::get_if<AudioSource>(&live.source)) {
          // The left half now ends early; its window has to end with it, or the
          // two halves overlap in source time and the cut is inaudible.
          const double ratio = audioStretchRatio(*audio, live.length);
          const Ticks consumed = static_cast<Ticks>(static_cast<double>(left_length) * ratio);
          audio->source_length = consumed > 0 ? consumed : audio->source_length;
        }
      },
      "Cut clip");
  if (shorten == nullptr) return nullptr;
  composite->add(std::move(shorten));

  composite->add(std::make_unique<AddCommand<Clip>>(std::move(right), "Cut clip"));
  return composite;
}

CommandPtr fitAudioClipToTempo(const Project& project, ClipId id, double project_bpm,
                               Ticks source_duration) {
  const Clip* clip = project.findClip(id);
  if (clip == nullptr) return nullptr;
  const AudioSource* audio = clip->audio();
  if (audio == nullptr) return nullptr;
  const Ticks length = audioLengthAtTempo(*audio, clip->length, project_bpm, source_duration);
  if (length <= 0) return nullptr;

  // One command, not a composite of two.
  //
  // `editClip` captures the whole `Clip` before and after, so two of them built
  // from the same starting state each carry a copy of the *original* clip with
  // one field changed — and applying them in sequence makes the second silently
  // undo the first. Anything that changes two fields of one entity has to be a
  // single mutation.
  const Ticks clip_length = clip->length;
  return editClip(
      project, id, ChangeField::Length,
      [length, clip_length, source_duration](Clip& live) {
        live.length = length;
        AudioSource* live_audio = std::get_if<AudioSource>(&live.source);
        if (live_audio == nullptr) return;
        // Stretch, not resample: fitting a loop to the project is the case
        // where holding the pitch is the entire point.
        live_audio->stretch_mode = StretchMode::Stretch;
        // Pin the window now. "To the end of the file" is a length the model
        // cannot resolve on its own, and a stretch ratio needs a real one.
        if (live_audio->source_length <= 0) {
          live_audio->source_length = audioSourceSpan(*live_audio, clip_length, source_duration);
        }
      },
      "Fit clip to tempo");
}

// --------------------------------------------------------------------------
// Mixer effects
// --------------------------------------------------------------------------

namespace {

CommandPtr editChain(const Project& project, MixerTrackId track,
                     const std::function<void(std::vector<EffectSlot>&)>& mutator,
                     std::string name) {
  return editMixerTrack(
      project, track, ChangeField::Effects, [&mutator](MixerTrack& live) { mutator(live.effects); },
      std::move(name));
}

size_t indexOfEffect(const std::vector<EffectSlot>& effects, EffectId effect) {
  for (size_t i = 0; i < effects.size(); ++i) {
    if (effects[i].id == effect) return i;
  }
  return SIZE_MAX;
}

// A short display name for the undo menu. The plug-in's own name where it has
// one, because "Add Reverb" reads better than "Add effect".
std::string effectLabel(const PluginRef& plugin) {
  return plugin.name.empty() ? std::string("effect") : plugin.name;
}

}  // namespace

CommandPtr addEffect(Project& project, MixerTrackId track, const PluginRef& plugin, size_t index) {
  const MixerTrack* live = project.findMixerTrack(track);
  if (live == nullptr) return nullptr;

  EffectSlot slot;
  slot.id = project.mintId<EntityKind::Effect>();
  slot.plugin = plugin;
  return editChain(
      project, track,
      [slot = std::move(slot), index](std::vector<EffectSlot>& effects) {
        const size_t at = index < effects.size() ? index : effects.size();
        effects.insert(effects.begin() + static_cast<std::ptrdiff_t>(at), slot);
      },
      "Add " + effectLabel(plugin));
}

CommandPtr removeEffect(Project& project, MixerTrackId track, EffectId effect) {
  const MixerTrack* live = project.findMixerTrack(track);
  if (live == nullptr) return nullptr;
  const EffectSlot* slot = live->findEffect(effect);
  if (slot == nullptr) return nullptr;

  auto composite = std::make_unique<CompositeCommand>("Remove " + effectLabel(slot->plugin));
  // Automation first. A curve whose target has already gone is a dangling
  // reference the invariant checker is right to abort on, so the clips leave
  // before the slot they point at does.
  for (const ClipId clip : project.effectImpact(track, effect).clips) {
    composite->add(removeClip(clip));
  }
  CommandPtr drop = editChain(
      project, track,
      [effect](std::vector<EffectSlot>& effects) {
        const size_t at = indexOfEffect(effects, effect);
        if (at != SIZE_MAX) effects.erase(effects.begin() + static_cast<std::ptrdiff_t>(at));
      },
      "Remove " + effectLabel(slot->plugin));
  if (drop == nullptr) return nullptr;
  composite->add(std::move(drop));
  return composite;
}

CommandPtr moveEffect(const Project& project, MixerTrackId track, EffectId effect, size_t index) {
  const MixerTrack* live = project.findMixerTrack(track);
  if (live == nullptr) return nullptr;
  const size_t from = indexOfEffect(live->effects, effect);
  if (from == SIZE_MAX) return nullptr;
  const size_t to = index < live->effects.size() ? index : live->effects.size() - 1;
  if (from == to) return nullptr;

  return editChain(
      project, track,
      [effect, index](std::vector<EffectSlot>& effects) {
        const size_t from = indexOfEffect(effects, effect);
        if (from == SIZE_MAX || effects.empty()) return;
        const size_t to = index < effects.size() ? index : effects.size() - 1;
        if (from == to) return;
        EffectSlot moved = effects[from];
        effects.erase(effects.begin() + static_cast<std::ptrdiff_t>(from));
        effects.insert(effects.begin() + static_cast<std::ptrdiff_t>(to), std::move(moved));
      },
      "Reorder effects");
}

namespace {

// A parameter change is not a chain change, and it needs its own coalescing
// rule: one knob drag is one undo entry, but two different knobs on the same
// effect are two. `EditCommand` keys coalescing on (entity, field), which
// cannot tell those apart, so this carries the parameter as well.
class EffectParamCommand : public Command {
 public:
  EffectParamCommand(MixerTrackId track, EffectId effect, plugin::ParamId parameter,
                     std::optional<float> before, float after, std::string name)
      : track_(track),
        effect_(effect),
        parameter_(parameter),
        before_(before),
        after_(after),
        name_(std::move(name)) {}

  bool apply(Project& project) override { return write(project, after_); }

  // `before_` is empty when the user had never touched this parameter, and
  // undoing back to "absent" rather than to the default is the difference
  // between a project that pins a value and one that follows the plug-in.
  bool revert(Project& project) override { return write(project, before_); }

  std::string name() const override { return name_; }

  bool coalesceWith(const Command& next) override {
    const auto* other = dynamic_cast<const EffectParamCommand*>(&next);
    if (other == nullptr) return false;
    if (other->track_ != track_ || other->effect_ != effect_ || other->parameter_ != parameter_) {
      return false;
    }
    after_ = other->after_;
    return true;
  }

 private:
  bool write(Project& project, std::optional<float> value) {
    return project.updateMixerTrack(track_, ChangeField::EffectParam,
                                    [this, value](MixerTrack& live) {
                                      const size_t at = indexOfEffect(live.effects, effect_);
                                      if (at == SIZE_MAX) return;
                                      if (value.has_value()) {
                                        live.effects[at].params[parameter_] = *value;
                                      } else {
                                        live.effects[at].params.erase(parameter_);
                                      }
                                    });
  }

  MixerTrackId track_;
  EffectId effect_;
  plugin::ParamId parameter_;
  std::optional<float> before_;
  float after_;
  std::string name_;
};

}  // namespace

CommandPtr setEffectParam(const Project& project, MixerTrackId track, EffectId effect,
                          plugin::ParamId parameter, float value) {
  const MixerTrack* live = project.findMixerTrack(track);
  if (live == nullptr) return nullptr;
  const EffectSlot* slot = live->findEffect(effect);
  if (slot == nullptr) return nullptr;

  std::optional<float> before;
  if (const auto found = slot->params.find(parameter); found != slot->params.end()) {
    before = found->second;
  }
  return std::make_unique<EffectParamCommand>(track, effect, parameter, before, value,
                                              "Adjust " + effectLabel(slot->plugin));
}

CommandPtr setEffectBypassed(const Project& project, MixerTrackId track, EffectId effect,
                             bool bypassed) {
  const MixerTrack* live = project.findMixerTrack(track);
  if (live == nullptr) return nullptr;
  const EffectSlot* slot = live->findEffect(effect);
  if (slot == nullptr) return nullptr;
  const std::string label = effectLabel(slot->plugin);
  return editChain(
      project, track,
      [effect, bypassed](std::vector<EffectSlot>& effects) {
        const size_t at = indexOfEffect(effects, effect);
        if (at != SIZE_MAX) effects[at].bypassed = bypassed;
      },
      (bypassed ? "Bypass " : "Enable ") + label);
}

CommandPtr setTransport(const Project& project, const TransportState& transport) {
  return std::make_unique<TransportCommand>(project.transport(), transport);
}

CommandPtr setProjectMeta(const Project& project, const ProjectMeta& meta) {
  return std::make_unique<MetaCommand>(project.meta(), meta);
}

}  // namespace onebeat::model
