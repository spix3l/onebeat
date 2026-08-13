#include "model/commands.h"

#include <map>
#include <utility>

namespace onebeat::model {
namespace {

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
    });
  }
};

// --------------------------------------------------------------------------
// Notes
// --------------------------------------------------------------------------

class NoteCommand : public Command {
 public:
  NoteCommand(PatternId pattern, InstrumentId instrument, std::vector<Note> removed,
              std::vector<Note> added, std::string name)
      : pattern_(pattern),
        instrument_(instrument),
        removed_(std::move(removed)),
        added_(std::move(added)),
        name_(std::move(name)) {}

  bool apply(Project& project) override { return edit(project, removed_, added_); }
  bool revert(Project& project) override { return edit(project, added_, removed_); }
  std::string name() const override { return name_; }

 private:
  // One pass: take out what this direction removes, put in what it adds. A
  // move is expressed as both, which is why dragging notes does not have to
  // copy the sequence.
  bool edit(Project& project, const std::vector<Note>& take, const std::vector<Note>& give) {
    return project.updateSequence(pattern_, instrument_, [&take, &give](NoteSequence& sequence) {
      for (const Note& note : take) sequence.erase(note);
      for (const Note& note : give) sequence.insert(note);
    });
  }

  PatternId pattern_;
  InstrumentId instrument_;
  std::vector<Note> removed_;
  std::vector<Note> added_;
  std::string name_;
};

class TransportCommand : public Command {
 public:
  TransportCommand(TransportState before, TransportState after) : before_(before), after_(after) {}

  bool apply(Project& project) override {
    project.setTransport(after_);
    return true;
  }
  bool revert(Project& project) override {
    project.setTransport(before_);
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
  TransportState before_;
  TransportState after_;
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

CommandPtr addPattern(Project& project, const std::string& name, Ticks length) {
  Pattern pattern;
  pattern.id = project.mintId<EntityKind::Pattern>();
  pattern.name = name;
  pattern.length = length;
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
  const std::string name =
      "Edit " + std::to_string(before.size()) + (before.size() == 1 ? " note" : " notes");
  return std::make_unique<NoteCommand>(pattern, instrument, std::move(before), std::move(after),
                                       name);
}

CommandPtr setTransport(const Project& project, const TransportState& transport) {
  return std::make_unique<TransportCommand>(project.transport(), transport);
}

CommandPtr setProjectMeta(const Project& project, const ProjectMeta& meta) {
  return std::make_unique<MetaCommand>(project.meta(), meta);
}

}  // namespace onebeat::model
