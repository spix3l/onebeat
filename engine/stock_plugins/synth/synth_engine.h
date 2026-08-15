#pragma once

#include <array>
#include <atomic>
#include <cstddef>
#include <cstdint>

namespace onebeat::stock::synth {

enum ParameterId : uint32_t {
  ParamOscShape = 100,
  ParamOscMix = 101,
  ParamDetune = 102,
  ParamSub = 103,
  ParamCutoff = 104,
  ParamResonance = 105,
  ParamFilterEnv = 106,
  ParamAttack = 107,
  ParamDecay = 108,
  ParamSustain = 109,
  ParamRelease = 110,
  ParamDrive = 111,
  ParamDelay = 112,
  ParamWidth = 113,
  ParamOutput = 114,
  ParamPreset = 115,
  ParamLfoRate = 116,
  ParamLfoDepth = 117,
  ParamGlide = 118,
  ParamNoise = 119,
};

enum SynthPresetIndex : uint32_t {
  PresetDrillSub = 0,
  PresetFrostedBell = 1,
  PresetDarkPluck = 2,
  Preset808Glide = 3,
  PresetHollowPad = 4,
  PresetColdKeys = 5,
  PresetSirenLead = 6,
  PresetChoirMist = 7,
  PresetCount = 8,
};

struct ParameterSpec {
  uint32_t id;
  const char* name;
  const char* module;
  double default_value;
};

inline constexpr std::array<ParameterSpec, 20> ParameterSpecs{{
    {ParamOscShape, "Osc Shape", "Oscillators", 0.08},
    {ParamOscMix, "Osc Mix", "Oscillators", 0.35},
    {ParamDetune, "Detune", "Oscillators", 0.50},
    {ParamSub, "Sub", "Oscillators", 0.72},
    {ParamCutoff, "Cutoff", "Filter", 0.24},
    {ParamResonance, "Resonance", "Filter", 0.18},
    {ParamFilterEnv, "Filter Env", "Filter", 0.62},
    {ParamAttack, "Attack", "Envelope", 0.01},
    {ParamDecay, "Decay", "Envelope", 0.42},
    {ParamSustain, "Sustain", "Envelope", 0.30},
    {ParamRelease, "Release", "Envelope", 0.24},
    {ParamDrive, "Drive", "Tone", 0.20},
    {ParamDelay, "Delay", "Space", 0.04},
    {ParamWidth, "Width", "Space", 0.28},
    {ParamOutput, "Output", "Master", 0.78},
    {ParamPreset, "Preset", "Factory", 0.00},
    {ParamLfoRate, "LFO Rate", "Modulation", 0.18},
    {ParamLfoDepth, "LFO Depth", "Modulation", 0.08},
    {ParamGlide, "Glide", "Voicing", 0.00},
    {ParamNoise, "Noise", "Oscillators", 0.02},
}};

[[nodiscard]] size_t parameterIndex(uint32_t id) noexcept;
[[nodiscard]] double clampParameter(double value) noexcept;
[[nodiscard]] const char* presetName(uint32_t index) noexcept;

class SynthEngine {
 public:
  static constexpr uint32_t VoiceCount = 32;

  SynthEngine() noexcept;

  void setSampleRate(double sample_rate) noexcept;
  void reset() noexcept;

  [[nodiscard]] double parameter(uint32_t id) const noexcept;
  void setParameter(uint32_t id, double value) noexcept;
  void selectPreset(double normalized) noexcept;

  void noteOn(int note_id, int channel, int key, double velocity) noexcept;
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
    double target_frequency = 261.625565;
    double phase = 0.0;
    double phase_secondary = 0.0;
    double envelope = 0.0;
    double age = 0.0;
    double velocity = 0.0;
    EnvStage env_stage = EnvStage::Off;
    uint32_t noise_state = 1;
    float filter_low = 0.0F;
    float filter_band = 0.0F;
  };

  struct DelayLine {
    static constexpr size_t Size = 24000;
    std::array<float, Size> buffer{};
    size_t cursor = 0;

    void clear() noexcept {
      buffer.fill(0.0F);
      cursor = 0;
    }
    void push(float value) noexcept {
      buffer[cursor] = value;
      cursor = (cursor + 1) % Size;
    }
    [[nodiscard]] float read(size_t delay) const noexcept {
      const size_t safe_delay = delay >= Size ? Size - 1 : delay;
      return buffer[(cursor + Size - safe_delay) % Size];
    }
  };

  [[nodiscard]] static bool voiceMatches(const Voice& voice, int note_id, int channel,
                                         int key) noexcept;
  void applyPreset(uint32_t index) noexcept;
  void applyFactoryDefaults() noexcept;

  double sample_rate_ = 48000.0;
  double lfo_phase_ = 0.0;
  std::array<std::atomic<double>, ParameterSpecs.size()> parameters_{};
  std::array<Voice, VoiceCount> voices_{};
  DelayLine delay_left_{};
  DelayLine delay_right_{};
};

}  // namespace onebeat::stock::synth
