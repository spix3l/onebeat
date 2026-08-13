// Offline render driver and fixture toolkit (OB-1-13).
//
// The driver renders through the *same* Engine::process the CoreAudio backend
// calls — enforced by construction, since process() is the only entry point and
// this file simply drives the null backend. Stage 4's export feature becomes a
// consumer of this, not new machinery.
#pragma once

#include <array>
#include <cstdint>
#include <memory>
#include <string>
#include <vector>

#include "core/engine.h"
#include "core/schedule.h"
#include "plugin/plugin_instance.h"

namespace onebeat::testing {

// Captured stereo output of an offline render.
struct RenderResult {
  std::vector<float> left;
  std::vector<float> right;
  double sample_rate = 48000.0;

  size_t frames() const { return left.size(); }
  float peak() const;
  float rms() const;
  // Largest sample-to-sample jump. The click detector: a discontinuity from a
  // hard note-off or a stolen voice shows up here and nowhere else.
  float maxDelta() const;
  bool isSilent(float threshold = 1.0e-6F) const { return peak() <= threshold; }
};

// Renders `frames` through the engine in `block_frames` chunks, faster than
// real time, capturing the master output.
RenderResult renderOffline(core::Engine& engine, int64_t frames, int block_frames);

// Bit-exactness helper: two renders of the same setup must match exactly.
bool sameSamples(const RenderResult& lhs, const RenderResult& rhs);

// Writes a 32-bit float WAV, for eyeballing failures and for golden files.
bool writeWav(const RenderResult& result, const std::string& path);

// A schedule of `note_count` notes on a fixed grid — the usual fixture.
std::unique_ptr<core::Schedule> makeGridSchedule(int note_count, int16_t note, double sample_rate,
                                                 double step_beats, double tempo_bpm,
                                                 float velocity = 1.0F);

// Records the events it receives instead of rendering, and produces silence.
// Sequencer tests assert on the event stream rather than on audio (used from
// Stage 3 onwards).
//
// It is a full `PluginInstance` because after OB-2-01 there is no other kind of
// processor — which is the point: a test double that satisfies the real
// interface is a standing check that the interface is implementable.
class EventCapturePlugin final : public plugin::PluginInstance {
 public:
  struct Captured {
    enum class Kind : uint8_t { NoteOn, NoteOff, AllNotesOff };
    Kind kind;
    int16_t note;
    float velocity;
    // Absolute frame across the whole render, so a test can assert on timing
    // without tracking block boundaries itself.
    int64_t frame;
  };

  EventCapturePlugin() : PluginInstance(nullptr) {}

  plugin::PluginName name() const override { return plugin::PluginName("Event Capture"); }

  void reset() noexcept OB_NONBLOCKING override {}
  plugin::ProcessStatus process(const plugin::ProcessBlock& block) noexcept OB_NONBLOCKING override;

  uint32_t paramCount() const override { return 0; }
  bool paramInfo(uint32_t, plugin::ParamInfo&) const override { return false; }
  bool paramValue(plugin::ParamId, double&) const override { return false; }
  bool paramValueToText(plugin::ParamId, double, char*, size_t) const override { return false; }
  bool paramTextToValue(plugin::ParamId, const char*, double&) const override { return false; }

  uint32_t audioPortCount(plugin::PortDirection direction) const override {
    return direction == plugin::PortDirection::Output ? 1U : 0U;
  }
  bool audioPortInfo(plugin::PortDirection direction, uint32_t index,
                     plugin::AudioPortInfo& out) const override;

  static constexpr size_t Capacity = 8192;

  std::vector<Captured> captured() const {
    return std::vector<Captured>(storage_.begin(), storage_.begin() + count_);
  }
  size_t capturedCount() const { return count_; }
  size_t overflowed() const { return overflowed_; }
  void clear() {
    count_ = 0;
    overflowed_ = 0;
  }

 protected:
  bool onConfigure(const plugin::ProcessSetup& /*setup*/) override {
    count_ = 0;
    frame_ = 0;
    return true;
  }
  bool onActivate() override { return true; }
  void onDeactivate() override {}

 private:
  void record(Captured event) noexcept OB_NONBLOCKING;

  // Fixed storage: recording on the audio thread must not allocate, and an
  // overrun must be visible rather than silently dropped.
  std::array<Captured, Capacity> storage_{};
  size_t count_ = 0;
  size_t overflowed_ = 0;
  int64_t frame_ = 0;
};

}  // namespace onebeat::testing
