#pragma once

#include <array>
#include <atomic>
#include <cstddef>
#include <cstdint>

namespace onebeat::stock::piano {

enum ParameterId : uint32_t {
  ParamTone = 100,
  ParamBody = 101,
  ParamDecay = 102,
  ParamRelease = 103,
  ParamRoom = 104,
  ParamWidth = 105,
  ParamOutput = 106,
  ParamPreset = 107,
  ParamAttack = 108,
  ParamSustain = 109,
  ParamHammer = 110,
  ParamDamper = 111,
  ParamDetune = 112,
  ParamVelocitySens = 113,
  ParamReverbSize = 114,
  ParamModDepth = 115,
  ParamModRate = 116,
  ParamDrive = 117,
  ParamPitch = 118,
};

enum PianoPresetIndex : uint32_t {
  PresetConcertGrand = 0,
  PresetFeltUpright = 1,
  PresetClassicRhodes = 2,
  PresetFmDxTines = 3,
  PresetVintageWurlitzer = 4,
  PresetHonkyTonk = 5,
  PresetDreamCloud = 6,
  PresetPopStudioGrand = 7,
  PresetHarpsichord = 8,
  PresetSynthKeys = 9,
  PresetCount = 10,
};

struct ParameterSpec {
  uint32_t id;
  const char* name;
  const char* module;
  double default_value;
};

inline constexpr std::array<ParameterSpec, 19> ParameterSpecs{{
    {ParamTone, "Tone", "Piano", 0.65},
    {ParamBody, "Body", "Piano", 0.60},
    {ParamDecay, "Decay", "Envelope", 0.60},
    {ParamRelease, "Release", "Envelope", 0.40},
    {ParamRoom, "Room", "Space", 0.35},
    {ParamWidth, "Width", "Space", 0.70},
    {ParamOutput, "Output", "Master", 0.75},
    {ParamPreset, "Preset", "Model", 0.00},
    {ParamAttack, "Attack", "Envelope", 0.05},
    {ParamSustain, "Sustain", "Envelope", 0.00},
    {ParamHammer, "Hammer", "Piano", 0.50},
    {ParamDamper, "Damper", "Piano", 0.30},
    {ParamDetune, "Detune", "Piano", 0.20},
    {ParamVelocitySens, "Velocity Sens", "Dynamics", 0.75},
    {ParamReverbSize, "Reverb Size", "Space", 0.55},
    {ParamModDepth, "Mod Depth", "Modulation", 0.00},
    {ParamModRate, "Mod Rate", "Modulation", 0.30},
    {ParamDrive, "Drive", "Master", 0.00},
    {ParamPitch, "Pitch", "Piano", 0.50},
}};

[[nodiscard]] size_t parameterIndex(uint32_t id) noexcept;
[[nodiscard]] double clampParameter(double value) noexcept;
[[nodiscard]] const char* presetName(uint32_t index) noexcept;

class PianoEngine {
 public:
  static constexpr uint32_t VoiceCount = 32;

  PianoEngine() noexcept;

  void setSampleRate(double sample_rate) noexcept;
  [[nodiscard]] double sampleRate() const noexcept { return sample_rate_; }
  void reset() noexcept;

  [[nodiscard]] double parameter(uint32_t id) const noexcept;
  void setParameter(uint32_t id, double value) noexcept;

  void noteOn(int note_id, int channel, int key, double velocity) noexcept;
  // Whether a voice is currently holding `key`. The one window onto the voice
  // allocator: a chord is only correct if every key in it is sounding at once,
  // and nothing else here can show that.
  [[nodiscard]] bool keySounding(int key) const noexcept;
  void noteOff(int note_id, int channel, int key, bool choke) noexcept;
  void render(float** outputs, uint32_t channel_count, uint32_t offset,
              uint32_t frame_count) noexcept;

 private:
  enum class EnvStage : uint8_t {
    Off = 0,
    Attack,
    Decay,
    Sustain,
    Release,
  };

  struct Voice {
    bool active = false;
    bool released = false;
    int16_t note_id = -1;
    int16_t channel = 0;
    int16_t key = 60;
    double frequency = 261.625565;
    double phase = 0.0;
    double phase2 = 0.0;
    double phase3 = 0.0;
    double fm_phase = 0.0;
    double envelope = 0.0;
    EnvStage env_stage = EnvStage::Off;
    double age = 0.0;
    double velocity = 0.0;
    uint32_t noise = 1;
    double damper_noise = 0.0;
    double filter_state = 0.0;
  };

  // Reverb comb & all-pass filter delay line sizes
  static constexpr size_t CombCount = 4;
  static constexpr size_t AllPassCount = 2;
  static constexpr size_t MaxCombSize = 4096;
  static constexpr size_t MaxAllPassSize = 1024;

  struct CombFilter {
    std::array<float, MaxCombSize> buffer{};
    size_t size = 1116;
    size_t cursor = 0;
    float filter_store = 0.0f;
  };

  struct AllPassFilter {
    std::array<float, MaxAllPassSize> buffer{};
    size_t size = 225;
    size_t cursor = 0;
  };

  [[nodiscard]] static bool voiceMatches(const Voice& voice, int note_id, int channel,
                                         int key) noexcept;

  double sample_rate_ = 48000.0;
  std::array<std::atomic<double>, ParameterSpecs.size()> parameters_{};
  std::array<Voice, VoiceCount> voices_{};

  // Schroeder Diffusion Reverb Engine
  std::array<CombFilter, CombCount> comb_left_{};
  std::array<CombFilter, CombCount> comb_right_{};
  std::array<AllPassFilter, AllPassCount> allpass_left_{};
  std::array<AllPassFilter, AllPassCount> allpass_right_{};

  // Modulation LFOs
  double mod_lfo_phase_ = 0.0;
  double tremolo_lfo_phase_ = 0.0;

  void initReverbTuning() noexcept;
  void processReverb(double in_left, double in_right, double& out_left, double& out_right,
                     double room_mix, double room_size, double damping) noexcept;
};

}  // namespace onebeat::stock::piano
