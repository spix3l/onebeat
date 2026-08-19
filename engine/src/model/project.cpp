#include "model/project.h"

#include <algorithm>
#include <cstdio>
#include <cstdlib>

#include "model/invariants.h"

namespace onebeat::model {
namespace {

// Debug and sanitizer builds pay for the check; release does not. A violation
// aborts rather than warns: by the time a reference dangles, the next save
// writes a project that cannot be loaded back.
#if defined(NDEBUG) && !defined(ONEBEAT_SANITIZER_BUILD)
constexpr bool CheckInvariantsEnabled = false;
#else
constexpr bool CheckInvariantsEnabled = true;
#endif

}  // namespace

Project::Project() : Project(IdGenerator{}) {}

Project::Project(IdGenerator generator) : generator_(generator) {
  // Master exists from the first moment: routing is by stable ID (D-M1), so
  // there must always be something valid to route to.
  MixerTrack master;
  master.id = generator_.next<EntityKind::MixerTrack>();
  master.name = "Master";
  master.output = std::nullopt;
  master_ = master.id;
  mixer_tracks_.emplace(master.id, master);
}

// --------------------------------------------------------------------------
// Lookups
// --------------------------------------------------------------------------

const Instrument* Project::findInstrument(InstrumentId id) const {
  const auto entry = instruments_.find(id);
  return entry == instruments_.end() ? nullptr : &entry->second;
}

const Pattern* Project::findPattern(PatternId id) const {
  const auto entry = patterns_.find(id);
  return entry == patterns_.end() ? nullptr : &entry->second;
}

const ArrangementLane* Project::findLane(ArrangementLaneId id) const {
  const auto entry = lanes_.find(id);
  return entry == lanes_.end() ? nullptr : &entry->second;
}

const Clip* Project::findClip(ClipId id) const {
  const auto entry = clips_.find(id);
  return entry == clips_.end() ? nullptr : &entry->second;
}

const MixerTrack* Project::findMixerTrack(MixerTrackId id) const {
  const auto entry = mixer_tracks_.find(id);
  return entry == mixer_tracks_.end() ? nullptr : &entry->second;
}

size_t Project::patternUsageCount(PatternId id) const {
  return clipsUsingPattern(id).size();
}

std::vector<ClipId> Project::clipsOnLane(ArrangementLaneId id) const {
  std::vector<ClipId> found;
  for (const auto& [clip_id, clip] : clips_) {
    if (clip.lane == id) found.push_back(clip_id);
  }
  return found;
}

std::vector<ClipId> Project::clipsUsingPattern(PatternId id) const {
  std::vector<ClipId> found;
  for (const auto& [clip_id, clip] : clips_) {
    const PatternSource* source = clip.pattern();
    if (source != nullptr && source->pattern == id) found.push_back(clip_id);
  }
  return found;
}

// --------------------------------------------------------------------------
// Creation
// --------------------------------------------------------------------------

InstrumentId Project::createInstrument(const std::string& name, const PluginRef& plugin) {
  Instrument instrument;
  instrument.id = generator_.next<EntityKind::Instrument>();
  instrument.name = name;
  int32_t highest = -1;
  for (const auto& [instrument_id, existing] : instruments_) {
    (void)instrument_id;
    highest = std::max(highest, existing.order);
  }
  instrument.order = highest + 1;
  instrument.plugin = plugin;

  // D-M2. The instrument's own track, or Master when the user has opted out.
  const MixerTrackId destination =
      preferences_.auto_create_mixer_track ? createMixerTrack(name, master_) : master_;
  instrument.routing.push_back(OutputRoute{0, destination});

  const InstrumentId id = instrument.id;
  instruments_.emplace(id, std::move(instrument));
  emit(ChangeType::Added, EntityKind::Instrument, id.raw(), ChangeField::All, destination.raw());
  checkInvariants();
  return id;
}

PatternId Project::createPattern(const std::string& name, Ticks length) {
  Pattern pattern;
  pattern.id = generator_.next<EntityKind::Pattern>();
  pattern.name = name;
  pattern.length = length;
  int32_t highest = -1;
  for (const auto& [pattern_id, existing] : patterns_) {
    (void)pattern_id;
    highest = std::max(highest, existing.order);
  }
  pattern.order = highest + 1;

  const PatternId id = pattern.id;
  patterns_.emplace(id, std::move(pattern));
  emit(ChangeType::Added, EntityKind::Pattern, id.raw(), ChangeField::All, RawId{});
  checkInvariants();
  return id;
}

ArrangementLaneId Project::createLane(const std::string& name) {
  ArrangementLane lane;
  lane.id = generator_.next<EntityKind::ArrangementLane>();
  lane.name = name;
  // Order is a field, so a new lane goes after the current last one rather than
  // wherever a vector happened to put it.
  int32_t highest = -1;
  for (const auto& [lane_id, existing] : lanes_) highest = std::max(highest, existing.order);
  lane.order = highest + 1;

  const ArrangementLaneId id = lane.id;
  lanes_.emplace(id, std::move(lane));
  emit(ChangeType::Added, EntityKind::ArrangementLane, id.raw(), ChangeField::All, RawId{});
  checkInvariants();
  return id;
}

MixerTrackId Project::createMixerTrack(const std::string& name,
                                       std::optional<MixerTrackId> output) {
  MixerTrack track;
  track.id = generator_.next<EntityKind::MixerTrack>();
  track.name = name;
  // Only Master has no output. Anything else defaults to Master rather than to
  // nothing, so a new track is audible instead of silently orphaned.
  track.output = output.has_value() ? output : std::optional<MixerTrackId>(master_);
  if (track.output.has_value() && mixer_tracks_.find(*track.output) == mixer_tracks_.end()) {
    track.output = master_;
  }

  const MixerTrackId id = track.id;
  mixer_tracks_.emplace(id, std::move(track));
  emit(ChangeType::Added, EntityKind::MixerTrack, id.raw(), ChangeField::All, RawId{});
  checkInvariants();
  return id;
}

ClipId Project::createClip(ArrangementLaneId lane, const ClipSource& source, Ticks start,
                           Ticks length) {
  if (lanes_.find(lane) == lanes_.end()) return ClipId{};

  // A clip that references something absent must never enter the model: the
  // invariant checker would be right to abort on it, and the user would have no
  // way to see or fix it.
  if (const auto* pattern_source = std::get_if<PatternSource>(&source)) {
    if (patterns_.find(pattern_source->pattern) == patterns_.end()) return ClipId{};
  } else if (const auto* audio_source = std::get_if<AudioSource>(&source)) {
    if (mixer_tracks_.find(audio_source->destination) == mixer_tracks_.end()) return ClipId{};
  } else if (const auto* automation = std::get_if<AutomationSource>(&source)) {
    bool resolves = false;
    switch (automation->target_kind) {
      case AutomationSource::TargetKind::Instrument:
        resolves = instruments_.find(automation->instrument) != instruments_.end();
        break;
      case AutomationSource::TargetKind::MixerTrack:
        resolves = mixer_tracks_.find(automation->mixer_track) != mixer_tracks_.end();
        break;
      case AutomationSource::TargetKind::Effect: {
        const auto track = mixer_tracks_.find(automation->mixer_track);
        resolves =
            track != mixer_tracks_.end() && track->second.findEffect(automation->effect) != nullptr;
        break;
      }
    }
    if (!resolves) return ClipId{};
  }

  Clip clip;
  clip.id = generator_.next<EntityKind::Clip>();
  clip.lane = lane;
  clip.source = source;
  clip.start = start;
  clip.length = length;

  const ClipId id = clip.id;
  clips_.emplace(id, std::move(clip));
  emit(ChangeType::Added, EntityKind::Clip, id.raw(), ChangeField::All, lane.raw());
  checkInvariants();
  return id;
}

// --------------------------------------------------------------------------
// Impact reports — what the confirmation dialog must be able to say
// --------------------------------------------------------------------------

InstrumentImpact Project::instrumentImpact(InstrumentId id) const {
  InstrumentImpact impact;
  for (const auto& [pattern_id, pattern] : patterns_) {
    const auto sequence = pattern.sequences.find(id);
    if (sequence == pattern.sequences.end()) continue;
    impact.patterns.push_back(pattern_id);
    impact.note_count += sequence->second.size();
  }
  for (const auto& [clip_id, clip] : clips_) {
    const PatternSource* pattern = clip.pattern();
    if (pattern != nullptr && std::find(impact.patterns.begin(), impact.patterns.end(),
                                        pattern->pattern) != impact.patterns.end()) {
      impact.pattern_clips.push_back(clip_id);
    }
    const AutomationSource* automation = clip.automation();
    if (automation != nullptr &&
        automation->target_kind == AutomationSource::TargetKind::Instrument &&
        automation->instrument == id) {
      impact.clips.push_back(clip_id);
    }
  }
  if (const Instrument* instrument = findInstrument(id)) {
    for (const OutputRoute& route : instrument->routing) impact.tracks.push_back(route.track);
  }
  return impact;
}

PatternImpact Project::patternImpact(PatternId id) const {
  PatternImpact impact;
  impact.clips = clipsUsingPattern(id);
  if (const Pattern* pattern = findPattern(id)) {
    for (const auto& [instrument_id, sequence] : pattern->sequences) {
      impact.note_count += sequence.size();
    }
  }
  return impact;
}

LaneImpact Project::laneImpact(ArrangementLaneId id) const {
  LaneImpact impact;
  impact.clips = clipsOnLane(id);
  return impact;
}

MixerTrackImpact Project::mixerTrackImpact(MixerTrackId id) const {
  MixerTrackImpact impact;
  for (const auto& [instrument_id, instrument] : instruments_) {
    for (const OutputRoute& route : instrument.routing) {
      if (route.track == id) {
        impact.instruments.push_back(instrument_id);
        break;
      }
    }
  }
  for (const auto& [track_id, track] : mixer_tracks_) {
    if (track.output.has_value() && *track.output == id) impact.inputs.push_back(track_id);
  }
  for (const auto& [clip_id, clip] : clips_) {
    const AudioSource* audio = clip.audio();
    const AutomationSource* automation = clip.automation();
    const bool audio_hits = audio != nullptr && audio->destination == id;
    // Both target kinds that name a track: its own parameters, and the
    // parameters of anything in its chain. Deleting the track takes the chain
    // with it, so both curves lose their target.
    const bool automation_hits =
        automation != nullptr &&
        (automation->target_kind == AutomationSource::TargetKind::MixerTrack ||
         automation->target_kind == AutomationSource::TargetKind::Effect) &&
        automation->mixer_track == id;
    if (audio_hits || automation_hits) impact.clips.push_back(clip_id);
  }
  return impact;
}

EffectImpact Project::effectImpact(MixerTrackId track, EffectId effect) const {
  EffectImpact impact;
  for (const auto& [clip_id, clip] : clips_) {
    const AutomationSource* automation = clip.automation();
    if (automation == nullptr) continue;
    if (automation->target_kind != AutomationSource::TargetKind::Effect) continue;
    if (automation->mixer_track != track || automation->effect != effect) continue;
    impact.clips.push_back(clip_id);
  }
  return impact;
}

// --------------------------------------------------------------------------
// Deletion
// --------------------------------------------------------------------------

bool Project::deleteInstrument(InstrumentId id) {
  if (instruments_.find(id) == instruments_.end()) return false;

  // The surprising half of ARCHITECTURE.md §3.1, executed: an instrument is
  // project-global, so its notes leave every pattern at once.
  for (auto& [pattern_id, pattern] : patterns_) {
    if (pattern.sequences.erase(id) > 0) {
      emit(ChangeType::Modified, EntityKind::Pattern, pattern_id.raw(), ChangeField::Notes,
           id.raw());
    }
  }

  const InstrumentImpact impact = instrumentImpact(id);
  for (const ClipId clip_id : impact.clips) deleteClip(clip_id);

  instruments_.erase(id);
  emit(ChangeType::Removed, EntityKind::Instrument, id.raw(), ChangeField::All, RawId{});
  checkInvariants();
  return true;
}

bool Project::deletePattern(PatternId id) {
  if (patterns_.find(id) == patterns_.end()) return false;

  for (const ClipId clip_id : clipsUsingPattern(id)) deleteClip(clip_id);

  patterns_.erase(id);
  emit(ChangeType::Removed, EntityKind::Pattern, id.raw(), ChangeField::All, RawId{});
  checkInvariants();
  return true;
}

bool Project::deleteLane(ArrangementLaneId id) {
  if (lanes_.find(id) == lanes_.end()) return false;

  for (const ClipId clip_id : clipsOnLane(id)) deleteClip(clip_id);

  // A lane inside a group keeps the group intact; a lane that *is* a group
  // releases its children rather than deleting them (DM-Q1 is still open, so
  // the conservative behaviour is the one that cannot lose work).
  for (auto& [lane_id, lane] : lanes_) {
    if (lane.group_id.has_value() && *lane.group_id == id) {
      lane.group_id = std::nullopt;
      emit(ChangeType::Modified, EntityKind::ArrangementLane, lane_id.raw(), ChangeField::Group,
           id.raw());
    }
  }

  lanes_.erase(id);
  emit(ChangeType::Removed, EntityKind::ArrangementLane, id.raw(), ChangeField::All, RawId{});
  checkInvariants();
  return true;
}

bool Project::deleteClip(ClipId id) {
  const auto entry = clips_.find(id);
  if (entry == clips_.end()) return false;

  const ArrangementLaneId lane = entry->second.lane;
  clips_.erase(entry);
  emit(ChangeType::Removed, EntityKind::Clip, id.raw(), ChangeField::All, lane.raw());
  checkInvariants();
  return true;
}

bool Project::deleteMixerTrack(MixerTrackId id) {
  if (id == master_) return false;  // there is always somewhere to route to
  if (mixer_tracks_.find(id) == mixer_tracks_.end()) return false;

  const MixerTrackImpact impact = mixerTrackImpact(id);

  // Re-point rather than orphan: an instrument whose track is deleted keeps
  // making sound, into Master, which is the behaviour that loses nothing.
  for (const InstrumentId instrument_id : impact.instruments) {
    auto instrument = instruments_.find(instrument_id);
    if (instrument == instruments_.end()) continue;
    for (OutputRoute& route : instrument->second.routing) {
      if (route.track == id) route.track = master_;
    }
    emit(ChangeType::Modified, EntityKind::Instrument, instrument_id.raw(), ChangeField::Routing,
         master_.raw());
  }
  for (const MixerTrackId input_id : impact.inputs) {
    auto track = mixer_tracks_.find(input_id);
    if (track == mixer_tracks_.end()) continue;
    track->second.output = master_;
    emit(ChangeType::Modified, EntityKind::MixerTrack, input_id.raw(), ChangeField::Output,
         master_.raw());
  }
  for (const ClipId clip_id : impact.clips) {
    auto clip = clips_.find(clip_id);
    if (clip == clips_.end()) continue;
    if (AudioSource* audio = std::get_if<AudioSource>(&clip->second.source)) {
      audio->destination = master_;
      emit(ChangeType::Modified, EntityKind::Clip, clip_id.raw(), ChangeField::Source,
           master_.raw());
    } else {
      // An automation clip's target is gone; there is no honest re-point for
      // "this curve drove that track's gain", so the clip goes with it.
      deleteClip(clip_id);
    }
  }

  mixer_tracks_.erase(id);
  emit(ChangeType::Removed, EntityKind::MixerTrack, id.raw(), ChangeField::All, RawId{});
  checkInvariants();
  return true;
}

// --------------------------------------------------------------------------
// Project-level state
// --------------------------------------------------------------------------

void Project::setTransport(const TransportState& transport) {
  transport_ = transport;
  emit(ChangeType::Modified, EntityKind::Project, RawId{}, ChangeField::Transport, RawId{});
}

void Project::setMeta(const ProjectMeta& meta) {
  meta_ = meta;
  emit(ChangeType::Modified, EntityKind::Project, RawId{}, ChangeField::Meta, RawId{});
}

// --------------------------------------------------------------------------
// Restore — undo's half of creation
// --------------------------------------------------------------------------

bool Project::restoreInstrument(const Instrument& instrument) {
  if (!instrument.id.valid() || instruments_.count(instrument.id) > 0) return false;
  instruments_.emplace(instrument.id, instrument);
  emit(ChangeType::Added, EntityKind::Instrument, instrument.id.raw(), ChangeField::All, RawId{});
  checkInvariants();
  return true;
}

bool Project::restorePattern(const Pattern& pattern) {
  if (!pattern.id.valid() || patterns_.count(pattern.id) > 0) return false;
  patterns_.emplace(pattern.id, pattern);
  emit(ChangeType::Added, EntityKind::Pattern, pattern.id.raw(), ChangeField::All, RawId{});
  checkInvariants();
  return true;
}

bool Project::restoreLane(const ArrangementLane& lane) {
  if (!lane.id.valid() || lanes_.count(lane.id) > 0) return false;
  lanes_.emplace(lane.id, lane);
  emit(ChangeType::Added, EntityKind::ArrangementLane, lane.id.raw(), ChangeField::All, RawId{});
  checkInvariants();
  return true;
}

bool Project::restoreClip(const Clip& clip) {
  if (!clip.id.valid() || clips_.count(clip.id) > 0) return false;
  clips_.emplace(clip.id, clip);
  emit(ChangeType::Added, EntityKind::Clip, clip.id.raw(), ChangeField::All, clip.lane.raw());
  checkInvariants();
  return true;
}

bool Project::restoreMixerTrack(const MixerTrack& track) {
  if (!track.id.valid() || mixer_tracks_.count(track.id) > 0) return false;
  mixer_tracks_.emplace(track.id, track);
  emit(ChangeType::Added, EntityKind::MixerTrack, track.id.raw(), ChangeField::All, RawId{});
  checkInvariants();
  return true;
}

bool Project::restoreSequence(PatternId pattern_id, InstrumentId instrument_id,
                              NoteSequence sequence) {
  auto pattern = patterns_.find(pattern_id);
  if (pattern == patterns_.end()) return false;
  if (instruments_.find(instrument_id) == instruments_.end()) return false;

  if (sequence.empty()) {
    pattern->second.sequences.erase(instrument_id);
  } else {
    pattern->second.sequences[instrument_id] = std::move(sequence);
  }
  emit(ChangeType::Modified, EntityKind::Pattern, pattern_id.raw(), ChangeField::Notes,
       instrument_id.raw());
  checkInvariants();
  return true;
}

void Project::adopt(Tables tables) {
  instruments_ = std::move(tables.instruments);
  patterns_ = std::move(tables.patterns);
  lanes_ = std::move(tables.lanes);
  clips_ = std::move(tables.clips);
  mixer_tracks_ = std::move(tables.mixer_tracks);
  master_ = tables.master;
  transport_ = tables.transport;
  meta_ = std::move(tables.meta);
}

Project::Tables Project::copyTables() const {
  Tables tables;
  tables.instruments = instruments_;
  tables.patterns = patterns_;
  tables.lanes = lanes_;
  tables.clips = clips_;
  tables.mixer_tracks = mixer_tracks_;
  tables.master = master_;
  tables.transport = transport_;
  tables.meta = meta_;
  return tables;
}

void Project::emit(ChangeType type, EntityKind kind, RawId id, ChangeField field,
                   RawId related) const {
  ChangeEvent event;
  event.type = type;
  event.kind = kind;
  event.id = id;
  event.field = field;
  event.related = related;
  changes_.emit(event);
}

void Project::checkInvariants() const {
  if constexpr (!CheckInvariantsEnabled) return;
  if (!debug_checks_) return;

  const std::vector<Violation> violations = checkReferentialIntegrity(*this);
  if (violations.empty()) return;

  std::fprintf(stderr, "model invariant violated (%zu):\n", violations.size());
  for (const Violation& violation : violations) {
    std::fprintf(stderr, "  %s\n", violation.message.c_str());
  }
  std::abort();
}

}  // namespace onebeat::model
