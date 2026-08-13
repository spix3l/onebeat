// The project: the entity maps, the operations that keep them consistent, and
// the change events those operations emit (OB-3-02 §1–§7).
//
// `Project` owns every entity. Nothing else holds one by pointer across an
// edit — the UI and the flattener hold IDs and look them up, because an edit
// may delete the thing they were looking at and an ID lookup fails safely where
// a dangling pointer does not.
//
// Every mutation goes through a method here. That is what makes three promises
// keepable at once: change events cannot be forgotten, referential integrity is
// checked after each one in debug builds, and OB-3-03's undo system has exactly
// one surface to record.
//
// This is off-audio-thread code. The audio thread sees only the flattened
// schedule (ARCHITECTURE.md §7).
#pragma once

#include <cstddef>
#include <map>
#include <optional>
#include <string>
#include <vector>

#include "model/changes.h"
#include "model/entities.h"
#include "model/ids.h"

namespace onebeat::model {

// What the UI must be able to say *before* the user confirms a delete.
// Deleting an instrument removes its notes from every pattern at once, which is
// correct and deeply surprising (ARCHITECTURE.md §3.1) — so the confirmation
// has to state the damage rather than discover it afterwards.
struct InstrumentImpact {
  std::vector<PatternId> patterns;   // patterns holding a sequence for it
  size_t note_count = 0;             // notes that would be deleted
  std::vector<ClipId> clips;         // automation clips targeting it
  std::vector<MixerTrackId> tracks;  // tracks it currently routes into
};

struct PatternImpact {
  std::vector<ClipId> clips;  // placements that would be deleted with it
  size_t note_count = 0;
};

struct LaneImpact {
  std::vector<ClipId> clips;  // clips that live on the lane
};

struct MixerTrackImpact {
  std::vector<InstrumentId> instruments;  // routed here, would be re-pointed
  std::vector<MixerTrackId> inputs;       // tracks whose output is this track
  std::vector<ClipId> clips;              // audio/automation clips targeting it
};

struct Preferences {
  // D-M2: a new instrument gets its own mixer track, named after it, so a
  // beginner can EQ their kick without first learning a routing system. Users
  // who prefer to build routing by hand turn this off.
  bool auto_create_mixer_track = true;
};

class Project {
 public:
  Project();
  explicit Project(IdGenerator generator);

  // ----- read access -------------------------------------------------------
  // Maps, not vectors: keyed by ID, iterating in ULID order, which is creation
  // order, which is the order the canonical writer needs (ADR-004).
  const std::map<InstrumentId, Instrument>& instruments() const { return instruments_; }
  const std::map<PatternId, Pattern>& patterns() const { return patterns_; }
  const std::map<ArrangementLaneId, ArrangementLane>& lanes() const { return lanes_; }
  const std::map<ClipId, Clip>& clips() const { return clips_; }
  const std::map<MixerTrackId, MixerTrack>& mixerTracks() const { return mixer_tracks_; }

  const Instrument* findInstrument(InstrumentId id) const;
  const Pattern* findPattern(PatternId id) const;
  const ArrangementLane* findLane(ArrangementLaneId id) const;
  const Clip* findClip(ClipId id) const;
  const MixerTrack* findMixerTrack(MixerTrackId id) const;

  MixerTrackId masterTrack() const { return master_; }
  const TransportState& transport() const { return transport_; }
  const ProjectMeta& meta() const { return meta_; }
  const Preferences& preferences() const { return preferences_; }
  void setPreferences(const Preferences& preferences) { preferences_ = preferences; }

  // Derived, not stored: a stored count is a second source of truth that goes
  // stale (D-M6 needs it to be right, not fast).
  size_t patternUsageCount(PatternId id) const;
  std::vector<ClipId> clipsOnLane(ArrangementLaneId id) const;
  std::vector<ClipId> clipsUsingPattern(PatternId id) const;

  ChangeBus& changes() { return changes_; }

  // ----- create ------------------------------------------------------------
  // Creates the instrument and, unless preferences say otherwise, its mixer
  // track; routes port 0 to that track (or to Master).
  InstrumentId createInstrument(const std::string& name, const PluginRef& plugin);
  PatternId createPattern(const std::string& name, Ticks length = TicksPerBarFourFour * 4);
  ArrangementLaneId createLane(const std::string& name);
  MixerTrackId createMixerTrack(const std::string& name,
                                std::optional<MixerTrackId> output = std::nullopt);
  // Returns an invalid ID if the lane, or the clip's source target, is absent:
  // a clip that references nothing must never enter the model.
  ClipId createClip(ArrangementLaneId lane, const ClipSource& source, Ticks start, Ticks length);

  // ----- impact reports ----------------------------------------------------
  InstrumentImpact instrumentImpact(InstrumentId id) const;
  PatternImpact patternImpact(PatternId id) const;
  LaneImpact laneImpact(ArrangementLaneId id) const;
  MixerTrackImpact mixerTrackImpact(MixerTrackId id) const;

  // ----- delete ------------------------------------------------------------
  // Each of these cascades exactly as far as referential integrity requires and
  // no further. They return false only when the entity does not exist, or for
  // the one deletion the model forbids: Master.
  bool deleteInstrument(InstrumentId id);
  bool deletePattern(PatternId id);
  bool deleteLane(ArrangementLaneId id);
  bool deleteClip(ClipId id);
  bool deleteMixerTrack(MixerTrackId id);

  // ----- modify ------------------------------------------------------------
  // One mutation surface per entity kind. The caller names the field it
  // touched, which is what makes change events fine-grained (OB-3-02 §7) and
  // what OB-3-03 will record for undo. `mutator` runs on the live entity.
  template <typename Mutator>
  bool updateInstrument(InstrumentId id, ChangeField field, Mutator mutator) {
    return update(instruments_, id, EntityKind::Instrument, field, mutator);
  }
  template <typename Mutator>
  bool updatePattern(PatternId id, ChangeField field, Mutator mutator) {
    return update(patterns_, id, EntityKind::Pattern, field, mutator);
  }
  template <typename Mutator>
  bool updateLane(ArrangementLaneId id, ChangeField field, Mutator mutator) {
    return update(lanes_, id, EntityKind::ArrangementLane, field, mutator);
  }
  template <typename Mutator>
  bool updateClip(ClipId id, ChangeField field, Mutator mutator) {
    return update(clips_, id, EntityKind::Clip, field, mutator);
  }
  template <typename Mutator>
  bool updateMixerTrack(MixerTrackId id, ChangeField field, Mutator mutator) {
    return update(mixer_tracks_, id, EntityKind::MixerTrack, field, mutator);
  }

  // Notes live in a pattern's sparse sequence map, so editing them is addressed
  // by (pattern, instrument) rather than by a single ID. The sequence is created
  // on first use and erased when it becomes empty — that is what keeps the map
  // sparse without a separate compaction step.
  template <typename Mutator>
  bool updateSequence(PatternId pattern_id, InstrumentId instrument_id, Mutator mutator) {
    auto pattern = patterns_.find(pattern_id);
    if (pattern == patterns_.end()) return false;
    if (instruments_.find(instrument_id) == instruments_.end()) return false;

    NoteSequence& sequence = pattern->second.sequences[instrument_id];
    mutator(sequence);
    if (sequence.empty()) pattern->second.sequences.erase(instrument_id);

    emit(ChangeType::Modified, EntityKind::Pattern, pattern_id.raw(), ChangeField::Notes,
         instrument_id.raw());
    checkInvariants();
    return true;
  }

  void setTransport(const TransportState& transport);
  void setMeta(const ProjectMeta& meta);

  // ----- restore: the undo path -------------------------------------------
  // Re-inserts an entity with **the ID it had**, which is the whole reason IDs
  // are never reused: undoing a delete has to make every reference that
  // survived in other commands valid again, and a fresh ID would not.
  //
  // These are the command layer's half of the mutation API (OB-3-03) — nothing
  // outside `model/commands.cpp` and tests may call them, which
  // `tools/seam_check.sh` enforces. Each returns false when the ID is already
  // present, because silently overwriting a live entity is how undo turns into
  // data loss.
  bool restoreInstrument(const Instrument& instrument);
  bool restorePattern(const Pattern& pattern);
  bool restoreLane(const ArrangementLane& lane);
  bool restoreClip(const Clip& clip);
  bool restoreMixerTrack(const MixerTrack& track);
  // Replaces (or, when empty, erases) one instrument's sequence in a pattern.
  bool restoreSequence(PatternId pattern_id, InstrumentId instrument_id, NoteSequence sequence);

  // Commands mint their IDs up front so that apply/revert/re-apply all use the
  // same one and the history stays referentially stable.
  template <EntityKind K>
  TypedId<K> mintId() {
    return generator_.next<K>();
  }

  // ----- bulk load / save seam --------------------------------------------
  // Everything above maintains its own invariants. This pair does not, on
  // purpose: the load path (OB-3-05) parses a file that may be hand-edited or
  // written by another version, and it must be able to build the model, run
  // `checkReferentialIntegrity` and *report* — not abort inside a setter on the
  // way in. No change events are emitted; the caller has just replaced
  // everything, so "what changed" is "all of it".
  struct Tables {
    std::map<InstrumentId, Instrument> instruments;
    std::map<PatternId, Pattern> patterns;
    std::map<ArrangementLaneId, ArrangementLane> lanes;
    std::map<ClipId, Clip> clips;
    std::map<MixerTrackId, MixerTrack> mixer_tracks;
    MixerTrackId master;
    TransportState transport;
    ProjectMeta meta;
  };
  void adopt(Tables tables);
  Tables copyTables() const;

  // Debug/CI safety net (OB-3-02 §6): after every mutation, every reference in
  // the model resolves. Compiled out of release builds; failures abort loudly
  // in debug because a dangling reference is a data-loss bug, not a warning.
  void checkInvariants() const;

  // Turns the per-mutation check off for bulk work that validates itself.
  // It is an O(model) walk on every single mutation, which is the right trade
  // for interactive editing and the wrong one for a 100,000-command fuzz run or
  // a large load: both check the result themselves, and leaving it on made the
  // undo fuzz 30x slower. Off is a deliberate, local decision — never a global
  // default. No effect in release builds, where the check is compiled out.
  void setDebugChecks(bool enabled) { debug_checks_ = enabled; }
  bool debugChecks() const { return debug_checks_; }

 private:
  template <typename Map, typename Id, typename Mutator>
  bool update(Map& map, Id id, EntityKind kind, ChangeField field, Mutator& mutator) {
    auto entry = map.find(id);
    if (entry == map.end()) return false;
    mutator(entry->second);
    emit(ChangeType::Modified, kind, id.raw(), field, RawId{});
    checkInvariants();
    return true;
  }

  void emit(ChangeType type, EntityKind kind, RawId id, ChangeField field, RawId related) const;

  IdGenerator generator_;
  ChangeBus changes_;
  Preferences preferences_;

  std::map<InstrumentId, Instrument> instruments_;
  std::map<PatternId, Pattern> patterns_;
  std::map<ArrangementLaneId, ArrangementLane> lanes_;
  std::map<ClipId, Clip> clips_;
  std::map<MixerTrackId, MixerTrack> mixer_tracks_;

  bool debug_checks_ = true;
  MixerTrackId master_;
  TransportState transport_;
  ProjectMeta meta_;
};

}  // namespace onebeat::model
