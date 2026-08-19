// The clip and effect commands: what each one does, what it undoes to, and the
// cascades that must travel with them.
#include <memory>

#include "doctest.h"
#include "model/command.h"
#include "model/commands.h"
#include "model/flattener.h"
#include "model/project.h"

using namespace onebeat::model;

namespace {

// A project with one lane, one mixer track and one audio clip on it.
struct Rig {
  Rig() : project(IdGenerator::deterministic(7)) {
    lane = project.createLane("Lane");
    AudioSource source;
    source.path = "/samples/loop.wav";
    source.destination = project.masterTrack();
    source.source_length = TicksPerBarFourFour;  // one bar of source
    clip = project.createClip(lane, source, 0, TicksPerBarFourFour);
  }

  const AudioSource& audio() const { return *project.findClip(clip)->audio(); }
  const Clip& clipRef() const { return *project.findClip(clip); }

  Project project;
  CommandBus commands{project};
  ArrangementLaneId lane;
  ClipId clip;
};

}  // namespace

TEST_SUITE("unit") {
  TEST_CASE("Resizing an unstretched clip trims it and a stretched one does not") {
    Rig rig;

    // Not stretching: the clip is a window, so its window follows the edge.
    REQUIRE(rig.commands.execute(resizeAudioClip(rig.project, rig.clip, TicksPerBarFourFour / 2)));
    CHECK(rig.clipRef().length == TicksPerBarFourFour / 2);
    CHECK(rig.audio().source_length == TicksPerBarFourFour / 2);

    REQUIRE(
        rig.commands.execute(setAudioClipStretchMode(rig.project, rig.clip, StretchMode::Stretch)));
    const Ticks window_before = rig.audio().source_length;

    // Stretching: the window stands and the ratio moves with the length.
    REQUIRE(rig.commands.execute(resizeAudioClip(rig.project, rig.clip, TicksPerBarFourFour * 2)));
    CHECK(rig.clipRef().length == TicksPerBarFourFour * 2);
    CHECK(rig.audio().source_length == window_before);
    // Four times the timeline for the same source: a quarter of the rate.
    CHECK(audioStretchRatio(rig.audio(), rig.clipRef().length) == doctest::Approx(0.25));
  }

  TEST_CASE("A clip that is not stretched has a ratio of exactly one") {
    Rig rig;
    CHECK(audioStretchRatio(rig.audio(), rig.clipRef().length) == doctest::Approx(1.0));
    // Even after a resize: an unstretched clip is never resampled, whatever its
    // length ends up being relative to its source.
    REQUIRE(rig.commands.execute(resizeAudioClip(rig.project, rig.clip, TicksPerBarFourFour * 3)));
    CHECK(audioStretchRatio(rig.audio(), rig.clipRef().length) == doctest::Approx(1.0));
  }

  TEST_CASE("Cutting an audio clip resumes the right half where the left stopped") {
    Rig rig;
    const Ticks at = TicksPerBarFourFour / 4;
    REQUIRE(rig.commands.execute(splitClip(rig.project, rig.clip, at)));

    REQUIRE(rig.project.clips().size() == 2);
    const Clip& left = rig.clipRef();
    CHECK(left.start == 0);
    CHECK(left.length == at);

    // The right half is the other clip. It must start a quarter-bar into the
    // source, not at the beginning — that is the difference between cutting a
    // sample and duplicating it.
    const Clip* right = nullptr;
    for (const auto& [id, clip] : rig.project.clips()) {
      if (id != rig.clip) right = &clip;
    }
    REQUIRE(right != nullptr);
    CHECK(right->start == at);
    CHECK(right->length == TicksPerBarFourFour - at);
    CHECK(right->audio()->source_offset == at);
  }

  TEST_CASE("A cut on an edge is not an edit") {
    Rig rig;
    CHECK(splitClip(rig.project, rig.clip, 0) == nullptr);
    CHECK(splitClip(rig.project, rig.clip, TicksPerBarFourFour) == nullptr);
    CHECK(splitClip(rig.project, rig.clip, -10) == nullptr);
    CHECK(rig.project.clips().size() == 1);
  }

  TEST_CASE("Undoing a cut restores one clip with its original length") {
    Rig rig;
    REQUIRE(rig.commands.execute(splitClip(rig.project, rig.clip, TicksPerBarFourFour / 2)));
    REQUIRE(rig.project.clips().size() == 2);

    REQUIRE(rig.commands.undo());
    CHECK(rig.project.clips().size() == 1);
    CHECK(rig.clipRef().length == TicksPerBarFourFour);
    CHECK(rig.audio().source_offset == 0);
  }

  TEST_CASE("Fit to tempo needs a source tempo and refuses to guess one") {
    Rig rig;
    CHECK(fitAudioClipToTempo(rig.project, rig.clip, 120.0) == nullptr);

    REQUIRE(rig.commands.execute(setAudioClipSourceBpm(rig.project, rig.clip, 240.0)));
    // Material recorded at 240 played in a 120 project takes twice as long.
    REQUIRE(rig.commands.execute(fitAudioClipToTempo(rig.project, rig.clip, 120.0)));
    CHECK(rig.clipRef().length == TicksPerBarFourFour * 2);
    CHECK(rig.audio().stretch_mode == StretchMode::Stretch);
  }

  TEST_CASE("Adding an effect mints an identity that survives a reorder") {
    Rig rig;
    const MixerTrackId master = rig.project.masterTrack();
    PluginRef reverb;
    reverb.format = PluginFormat::Builtin;
    reverb.id = "dev.onebeat.fx.reverb";
    reverb.name = "Reverb";
    PluginRef delay = reverb;
    delay.id = "dev.onebeat.fx.delay";
    delay.name = "Delay";

    REQUIRE(rig.commands.execute(addEffect(rig.project, master, reverb)));
    REQUIRE(rig.commands.execute(addEffect(rig.project, master, delay)));

    const MixerTrack* track = rig.project.findMixerTrack(master);
    REQUIRE(track->effects.size() == 2);
    const EffectId first = track->effects[0].id;
    const EffectId second = track->effects[1].id;
    CHECK(first != second);

    REQUIRE(rig.commands.execute(moveEffect(rig.project, master, first, 1)));
    track = rig.project.findMixerTrack(master);
    // Same identities, new order. Automation written against `first` still
    // resolves, which is the whole reason a slot has an ID at all.
    CHECK(track->effects[0].id == second);
    CHECK(track->effects[1].id == first);
    CHECK(track->findEffect(first) != nullptr);
  }

  TEST_CASE("Removing an effect takes its automation with it, as one undo entry") {
    Rig rig;
    const MixerTrackId master = rig.project.masterTrack();
    PluginRef reverb;
    reverb.format = PluginFormat::Builtin;
    reverb.id = "dev.onebeat.fx.reverb";
    REQUIRE(rig.commands.execute(addEffect(rig.project, master, reverb)));
    const EffectId slot = rig.project.findMixerTrack(master)->effects[0].id;

    AutomationSource curve;
    curve.target_kind = AutomationSource::TargetKind::Effect;
    curve.mixer_track = master;
    curve.effect = slot;
    curve.parameter = 5;
    curve.points.push_back(AutomationPoint{0, 0.5F});
    REQUIRE(rig.commands.execute(addClip(rig.project, rig.lane, curve, 0, TicksPerBarFourFour)));
    const size_t before = rig.project.clips().size();
    CHECK(rig.project.effectImpact(master, slot).clips.size() == 1);

    REQUIRE(rig.commands.execute(removeEffect(rig.project, master, slot)));
    CHECK(rig.project.findMixerTrack(master)->effects.empty());
    // The curve went with it: a curve whose target has gone is a dangling
    // reference, and the invariant checker is right to abort on one.
    CHECK(rig.project.clips().size() == before - 1);

    REQUIRE(rig.commands.undo());
    CHECK(rig.project.findMixerTrack(master)->effects.size() == 1);
    CHECK(rig.project.clips().size() == before);
  }

  TEST_CASE("Effect parameter edits coalesce per parameter, not per effect") {
    Rig rig;
    const MixerTrackId master = rig.project.masterTrack();
    PluginRef reverb;
    reverb.format = PluginFormat::Builtin;
    reverb.id = "dev.onebeat.fx.reverb";
    REQUIRE(rig.commands.execute(addEffect(rig.project, master, reverb)));
    const EffectId slot = rig.project.findMixerTrack(master)->effects[0].id;

    CommandPtr first = setEffectParam(rig.project, master, slot, 5, 0.2F);
    CommandPtr again = setEffectParam(rig.project, master, slot, 5, 0.8F);
    CommandPtr other = setEffectParam(rig.project, master, slot, 6, 0.4F);
    REQUIRE(first != nullptr);
    // One knob dragged is one entry...
    CHECK(first->coalesceWith(*again));
    // ...and a different knob is a different entry.
    CHECK_FALSE(first->coalesceWith(*other));
  }

  TEST_CASE("Undoing a parameter edit returns it to unset, not to the default") {
    Rig rig;
    const MixerTrackId master = rig.project.masterTrack();
    PluginRef reverb;
    reverb.format = PluginFormat::Builtin;
    reverb.id = "dev.onebeat.fx.reverb";
    REQUIRE(rig.commands.execute(addEffect(rig.project, master, reverb)));
    const EffectId slot = rig.project.findMixerTrack(master)->effects[0].id;

    REQUIRE(rig.project.findMixerTrack(master)->findEffect(slot)->params.empty());
    REQUIRE(rig.commands.execute(setEffectParam(rig.project, master, slot, 5, 0.8F)));
    CHECK(rig.project.findMixerTrack(master)->findEffect(slot)->params.size() == 1);

    REQUIRE(rig.commands.undo());
    // Back to absent. A project that pins a value it never chose is a project
    // that stops following the plug-in the day it ships a better default.
    CHECK(rig.project.findMixerTrack(master)->findEffect(slot)->params.empty());
  }

  TEST_CASE("Effect automation flattens to events addressed to the insert") {
    Rig rig;
    const MixerTrackId master = rig.project.masterTrack();
    PluginRef reverb;
    reverb.format = PluginFormat::Builtin;
    reverb.id = "dev.onebeat.fx.reverb";
    REQUIRE(rig.commands.execute(addEffect(rig.project, master, reverb)));
    const EffectId slot = rig.project.findMixerTrack(master)->effects[0].id;

    AutomationSource curve;
    curve.target_kind = AutomationSource::TargetKind::Effect;
    curve.mixer_track = master;
    curve.effect = slot;
    curve.parameter = 5;
    curve.points.push_back(AutomationPoint{0, 0.25F});
    curve.points.push_back(AutomationPoint{TicksPerQuarter, 0.75F});
    REQUIRE(rig.commands.execute(addClip(rig.project, rig.lane, curve, 0, TicksPerBarFourFour)));

    const FlattenResult result = flatten(rig.project, FlattenOptions{48000.0, 1});
    REQUIRE(result.schedule != nullptr);
    // The insert has a dense index of its own, in its own address space.
    const auto index = result.effect_index.find(std::make_pair(master, slot));
    REQUIRE(index != result.effect_index.end());

    int found = 0;
    for (int32_t i = 0; i < result.schedule->eventCount(); ++i) {
      const onebeat::core::ScheduleEvent& event = result.schedule->events()[i];
      if (static_cast<onebeat::core::EventType>(event.type) !=
          onebeat::core::EventType::EffectParam) {
        continue;
      }
      CHECK(static_cast<int32_t>(event.instrument) == index->second);
      CHECK(event.reserved == 5U);
      ++found;
    }
    CHECK(found == 2);
  }

  TEST_CASE("The same project always flattens to the same bytes") {
    Rig rig;
    const MixerTrackId master = rig.project.masterTrack();
    PluginRef reverb;
    reverb.format = PluginFormat::Builtin;
    reverb.id = "dev.onebeat.fx.reverb";
    REQUIRE(rig.commands.execute(addEffect(rig.project, master, reverb)));
    const EffectId slot = rig.project.findMixerTrack(master)->effects[0].id;

    AutomationSource curve;
    curve.target_kind = AutomationSource::TargetKind::Effect;
    curve.mixer_track = master;
    curve.effect = slot;
    curve.parameter = 5;
    for (int i = 0; i < 8; ++i) {
      curve.points.push_back(AutomationPoint{i * TicksPerQuarter, 0.1F * static_cast<float>(i)});
    }
    REQUIRE(
        rig.commands.execute(addClip(rig.project, rig.lane, curve, 0, TicksPerBarFourFour * 2)));

    const FlattenResult a = flatten(rig.project, FlattenOptions{48000.0, 1});
    const FlattenResult b = flatten(rig.project, FlattenOptions{48000.0, 1});
    CHECK(a.hash == b.hash);
    CHECK(a.event_count == b.event_count);
  }

}  // TEST_SUITE
