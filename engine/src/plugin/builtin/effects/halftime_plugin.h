// OneBeat Halftime — slows the incoming audio without moving its pitch.
//
// The problem an insert effect has with slowing audio down is arithmetic:
// output consumes input more slowly than the track supplies it, so the read
// head falls further behind every block and the effect would drift out of the
// song forever. Every halftime plug-in solves this the same way, and so does
// this one: it plays from a capture ring at the slowed rate and jumps the read
// head back up to the write head at a fixed musical interval. Between resyncs
// you hear genuine half-speed audio; at each resync you hear the effect catch
// up, which is exactly the stutter the sound is known for.
//
// Pitch is held by the same WSOLA stretcher the clip editor uses (see
// core/time_stretch.h), or dropped entirely when `ParamRepitch` is on — which
// gives the tape-speed octave-down instead, and is the other half of what
// people mean by halftime.
#pragma once

#include <array>
#include <cstdint>
#include <vector>

#include "core/time_stretch.h"
#include "plugin/builtin/effects/effect_plugin.h"

namespace onebeat::plugin::builtin {

class HalftimePlugin final : public EffectPlugin {
 public:
  enum : ParamId {
    ParamRate = EffectParamFirst,  // 2 — 0.5 is halftime
    ParamResync = 3,               // seconds between catch-ups
    ParamRepitch = 4,              // let the speed move the pitch
    ParamMix = 5,
  };

  static constexpr const char* Identifier = "dev.onebeat.fx.halftime";
  static constexpr double MaxResyncSeconds = 8.0;

  explicit HalftimePlugin(PluginHost* host);

  PluginName name() const override { return PluginName("OneBeat Halftime"); }

 protected:
  bool onConfigure(const ProcessSetup& setup) override;
  bool onActivate() override { return true; }
  void onDeactivate() override {}
  void processAudio(const core::AudioBufferView& io, int start_frame,
                    int num_frames) noexcept OB_NONBLOCKING override;
  void clearTail() noexcept OB_NONBLOCKING override;

 private:
  static constexpr int Channels = 2;
  // The crossfade at a resync, in frames. Without it the jump is a click; with
  // it the jump is the percussive edge the effect is supposed to have.
  static constexpr int ResyncFadeFrames = 192;

  // The capture ring, presented as something `TimeStretch` can read. Satisfies
  // `core::StretchSource`, which is why the pitch-preserving path here is the
  // same WSOLA the clip editor uses rather than a second copy of it.
  struct CaptureReader {
    const HalftimePlugin* owner = nullptr;
    float read(double position, int channel) const noexcept OB_NONBLOCKING {
      return owner->readCapture(position, channel);
    }
    // A live ring has no end. Reporting an effectively infinite length is how
    // the stretcher is told never to declare itself finished — the effect, not
    // the material, decides when to stop.
    int64_t sourceFrames() const noexcept OB_NONBLOCKING { return INT64_MAX; }
  };

  float readCapture(double position, int channel) const noexcept OB_NONBLOCKING;

  // Interleaved-by-plane capture ring, one plane per channel.
  std::array<std::vector<float>, Channels> capture_{};
  size_t capture_size_ = 0;
  // Frames written since the effect was reset. Absolute, so the distance
  // between the read head and the write head is a subtraction rather than a
  // modular comparison that has to worry about which side of the wrap it is on.
  int64_t written_ = 0;
  double read_position_ = 0.0;
  int64_t frames_since_resync_ = 0;
  int resync_fade_ = 0;
  double sample_rate_ = 48000.0;
  // Used only while `ParamRepitch` is off. Holding it unconditionally costs a
  // few kilobytes and saves an allocation the first time the user turns the
  // switch, which would be an allocation on the audio thread.
  core::TimeStretch stretch_;
  // Scratch the stretcher writes into before the mix, sized in onConfigure.
  std::vector<float> stretch_scratch_;
  int max_block_frames_ = 0;
  bool last_repitch_ = false;
};

}  // namespace onebeat::plugin::builtin
