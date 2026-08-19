#include "model/invariants.h"

#include <set>
#include <string>

#include "model/project.h"

namespace onebeat::model {
namespace {

std::string describe(EntityKind kind, RawId id) {
  return std::string(entityNoun(kind)) + " " + std::string(entityPrefix(kind)) + "_" +
         encodeUlid(id);
}

}  // namespace

std::vector<Violation> checkReferentialIntegrity(const Project& project) {
  std::vector<Violation> violations;
  const auto fail = [&violations](std::string message) {
    violations.push_back(Violation{std::move(message)});
  };

  // --- instruments: routing resolves, and routes to distinct ports ---------
  for (const auto& [instrument_id, instrument] : project.instruments()) {
    std::set<plugin::PortId> ports;
    for (const OutputRoute& route : instrument.routing) {
      if (project.findMixerTrack(route.track) == nullptr) {
        fail(describe(EntityKind::Instrument, instrument_id.raw()) + " routes port " +
             std::to_string(route.port) + " to missing " +
             describe(EntityKind::MixerTrack, route.track.raw()));
      }
      if (!ports.insert(route.port).second) {
        fail(describe(EntityKind::Instrument, instrument_id.raw()) + " routes port " +
             std::to_string(route.port) + " twice");
      }
    }
  }

  // --- patterns: sequences key on live instruments, notes stay ordered -----
  for (const auto& [pattern_id, pattern] : project.patterns()) {
    for (const auto& [instrument_id, sequence] : pattern.sequences) {
      if (project.findInstrument(instrument_id) == nullptr) {
        fail(describe(EntityKind::Pattern, pattern_id.raw()) + " holds a sequence for missing " +
             describe(EntityKind::Instrument, instrument_id.raw()));
      }
      // Sparseness is an invariant, not a tidiness preference: an empty
      // sequence is an instrument the pattern claims to use and does not.
      if (sequence.empty()) {
        fail(describe(EntityKind::Pattern, pattern_id.raw()) + " keeps an empty sequence for " +
             describe(EntityKind::Instrument, instrument_id.raw()));
      }
      if (!sequence.isSorted()) {
        fail(describe(EntityKind::Pattern, pattern_id.raw()) + " has an unsorted sequence for " +
             describe(EntityKind::Instrument, instrument_id.raw()));
      }
      for (const Note& note : sequence.notes()) {
        if (!isValidNote(note)) {
          fail(describe(EntityKind::Pattern, pattern_id.raw()) + " has an out-of-range note");
          break;
        }
      }
    }
  }

  // --- lanes: order is unique, groups resolve and do not cycle -------------
  std::set<int32_t> orders;
  for (const auto& [lane_id, lane] : project.lanes()) {
    if (!orders.insert(lane.order).second) {
      fail(describe(EntityKind::ArrangementLane, lane_id.raw()) + " shares order " +
           std::to_string(lane.order) + " with another lane");
    }
    if (lane.group_id.has_value()) {
      if (*lane.group_id == lane_id) {
        fail(describe(EntityKind::ArrangementLane, lane_id.raw()) + " is its own group");
      } else if (project.findLane(*lane.group_id) == nullptr) {
        fail(describe(EntityKind::ArrangementLane, lane_id.raw()) + " belongs to missing " +
             describe(EntityKind::ArrangementLane, lane.group_id->raw()));
      }
    }
  }

  // --- clips: lane and source resolve -------------------------------------
  for (const auto& [clip_id, clip] : project.clips()) {
    if (project.findLane(clip.lane) == nullptr) {
      fail(describe(EntityKind::Clip, clip_id.raw()) + " sits on missing " +
           describe(EntityKind::ArrangementLane, clip.lane.raw()));
    }
    if (clip.length < 0 || clip.start < 0) {
      fail(describe(EntityKind::Clip, clip_id.raw()) + " has a negative start or length");
    }
    if (const PatternSource* source = clip.pattern()) {
      if (project.findPattern(source->pattern) == nullptr) {
        fail(describe(EntityKind::Clip, clip_id.raw()) + " references missing " +
             describe(EntityKind::Pattern, source->pattern.raw()));
      }
    } else if (const AudioSource* audio = clip.audio()) {
      if (project.findMixerTrack(audio->destination) == nullptr) {
        fail(describe(EntityKind::Clip, clip_id.raw()) + " plays into missing " +
             describe(EntityKind::MixerTrack, audio->destination.raw()));
      }
      if (audio->source_offset < 0 || audio->source_length < 0) {
        fail(describe(EntityKind::Clip, clip_id.raw()) + " has a negative source window");
      }
      // A stretched clip with no source to stretch has no ratio, and the
      // flattener would divide by it.
      if (audio->stretch_mode != StretchMode::Off && audio->source_length <= 0 &&
          clip.length <= 0) {
        fail(describe(EntityKind::Clip, clip_id.raw()) + " is stretched with no length to stretch");
      }
    } else if (const AutomationSource* automation = clip.automation()) {
      bool resolves = false;
      switch (automation->target_kind) {
        case AutomationSource::TargetKind::Instrument:
          resolves = project.findInstrument(automation->instrument) != nullptr;
          break;
        case AutomationSource::TargetKind::MixerTrack:
          resolves = project.findMixerTrack(automation->mixer_track) != nullptr;
          break;
        case AutomationSource::TargetKind::Effect: {
          // Both ends must resolve: the track, and the slot still in its chain.
          const MixerTrack* track = project.findMixerTrack(automation->mixer_track);
          resolves = track != nullptr && track->findEffect(automation->effect) != nullptr;
          break;
        }
      }
      if (!resolves) {
        fail(describe(EntityKind::Clip, clip_id.raw()) + " automates a missing target");
      }
    }
  }

  // --- mixer: exactly one Master, and no routing cycles --------------------
  size_t masters = 0;
  for (const auto& [track_id, track] : project.mixerTracks()) {
    // Chain slots: every one identified, and no two alike. A duplicate would
    // make `findEffect` — and therefore every automation curve pointing at
    // either slot — resolve to whichever came first.
    std::set<EffectId> effect_ids;
    for (const EffectSlot& slot : track.effects) {
      if (!slot.id.valid()) {
        fail(describe(EntityKind::MixerTrack, track_id.raw()) + " has an unidentified effect slot");
      } else if (!effect_ids.insert(slot.id).second) {
        fail(describe(EntityKind::MixerTrack, track_id.raw()) + " has two slots sharing " +
             describe(EntityKind::Effect, slot.id.raw()));
      }
    }
    if (!track.output.has_value()) {
      ++masters;
      continue;
    }
    if (*track.output == track_id) {
      fail(describe(EntityKind::MixerTrack, track_id.raw()) + " outputs into itself");
      continue;
    }
    if (project.findMixerTrack(*track.output) == nullptr) {
      fail(describe(EntityKind::MixerTrack, track_id.raw()) + " outputs into missing " +
           describe(EntityKind::MixerTrack, track.output->raw()));
      continue;
    }
    // Walk to Master. A cycle would otherwise be found later, in the mixer's
    // graph traversal, where the symptom is a hang rather than a message.
    std::set<MixerTrackId> seen{track_id};
    MixerTrackId walker = *track.output;
    while (true) {
      const MixerTrack* next = project.findMixerTrack(walker);
      if (next == nullptr || !next->output.has_value()) break;
      if (!seen.insert(walker).second) {
        fail(describe(EntityKind::MixerTrack, track_id.raw()) + " is part of a routing cycle");
        break;
      }
      walker = *next->output;
    }
  }
  if (masters != 1) {
    fail("the project has " + std::to_string(masters) + " master tracks; it must have exactly 1");
  }
  if (project.findMixerTrack(project.masterTrack()) == nullptr) {
    fail("the master track is missing");
  }

  return violations;
}

}  // namespace onebeat::model
