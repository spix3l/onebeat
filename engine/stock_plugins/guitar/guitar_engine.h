#pragma once

#include <array>
#include <atomic>
#include <cstddef>
#include <cstdint>

namespace onebeat::stock::guitar {

enum ParameterId : uint32_t {
  ParamTone = 100,
  ParamBody = 101,
  ParamDecay = 102,
  ParamRelease = 103,
  ParamRoom = 104,
  ParamWidth = 105,
  ParamOutput = 106,
  ParamPreset = 107,
  ParamPickPos = 108,
  ParamDamping = 109,
  ParamPickup = 110,
  ParamDrive = 111,
  ParamChorus = 112,
  ParamReverbSize = 113,
  ParamDynamics = 114,
  ParamPitch = 115,
  ParamModRate = 116,
  ParamAttack = 117,
};

enum GuitarPresetIndex : uint32_t {
  PresetAcousticSteel = 0,
  PresetAcousticNylon = 1,
  PresetAcoustic12String = 2,
  PresetAcousticMuted = 3,
  PresetAcousticResonator = 4,
  PresetElectricCleanStrat = 5,
  PresetElectricWarmJazz = 6,
  PresetElectricOverdriven = 7,
  PresetElectric80sChorus = 8,
  PresetElectricAmbientSlide = 9,
  PresetElectricFlamenco = 10,
  PresetElectricLoFi = 11,
  PresetCount = 12,
};

struct ParameterSpec {
  uint32_t id;
  const char* name;
  const char* module;
  double default_value;
};

inline constexpr std::array<ParameterSpec, 18> ParameterSpecs{{
    {ParamTone, "Tone", "String", 0.70},
    {ParamBody, "Body", "Resonance", 0.65},
    {ParamDecay, "Decay", "Envelope", 0.65},
    {ParamRelease, "Release", "Envelope", 0.35},
    {ParamRoom, "Room", "Space", 0.30},
    {ParamWidth, "Width", "Space", 0.60},
    {ParamOutput, "Output", "Master", 0.80},
    {ParamPreset, "Preset", "Model", 0.00},
    {ParamPickPos, "Pick Position", "Excitation", 0.25},
    {ParamDamping, "Damping", "String", 0.20},
    {ParamPickup, "Pickup", "Guitar", 0.00},
    {ParamDrive, "Drive", "Amp", 0.00},
    {ParamChorus, "Chorus", "Modulation", 0.00},
    {ParamReverbSize, "Reverb Size", "Space", 0.50},
    {ParamDynamics, "Dynamics", "Dynamics", 0.80},
    {ParamPitch, "Pitch", "Guitar", 0.50},
    {ParamModRate, "Mod Rate", "Modulation", 0.30},
    {ParamAttack, "Attack", "Excitation", 0.60},
}};

[[nodiscard]] size_t parameterIndex(uint32_t id) noexcept;
[[nodiscard]] double clampParameter(double value) noexcept;
[[nodiscard]] const char* presetName(uint32_t index) noexcept;

class GuitarEngine {
 public:
  static constexpr uint32_t VoiceCount = 32;

  GuitarEngine() noexcept;

  void setSampleRate(double sample_rate) noexcept;
  [[nodiscard]] double sampleRate() const noexcept { return sample_rate_; }
  void reset() noexcept;

  [[nodiscard]] double parameter(uint32_t id) const noexcept;
  void setParameter(uint32_t id, double value) noexcept;

  void noteOn(int note_id, int channel, int key, double velocity) noexcept;
  void noteOff(int note_id, int channel, int key, bool choke) noexcept;
  void render(float** outputs, uint32_t channel_count, uint32_t offset,
              uint32_t frame_count) noexcept;

 private:
  enum class EnvStage : uint8_t {
    Off = 0,
    Excitation,
    Sustain,
    Release,
  };

  static constexpr size_t MaxDelayLine = 4096;

  struct DelayLine {
    std::array<float, MaxDelayLine> buffer{};
    size_t write_pos = 0;

    void clear() noexcept {
      buffer.fill(0.0f);
      write_pos = 0;
    }

    void push(float sample) noexcept {
      buffer[write_pos] = sample;
      write_pos = (write_pos + 1) % MaxDelayLine;
    }

    [[nodiscard]] float readFractional(double delay_samples) const noexcept {
      if (delay_samples < 1.0) delay_samples = 1.0;
      if (delay_samples >= static_cast<double>(MaxDelayLine - 2)) {
        delay_samples = static_cast<double>(MaxDelayLine - 2);
      }
      const double read_pos_f = static_cast<double>(write_pos) - delay_samples;
      double read_pos = read_pos_f;
      while (read_pos < 0.0) read_pos += static_cast<double>(MaxDelayLine);
      const size_t index0 = static_cast<size_t>(read_pos) % MaxDelayLine;
      const size_t index1 = (index0 + 1) % MaxDelayLine;
      const float frac = static_cast<float>(read_pos - std::floor(read_pos));
      return buffer[index0] * (1.0f - frac) + buffer[index1] * frac;
    }
  };

  struct Voice {
    bool active = false;
    bool released = false;
    int16_t note_id = -1;
    int16_t channel = 0;
    int16_t key = 60;
    double frequency = 196.0;
    double velocity = 0.0;
    double release_time = 0.0;
    EnvStage stage = EnvStage::Off;
    size_t excitation_counter = 0;
    size_t excitation_length = 0;

    DelayLine delay_line{};
    DelayLine delay_line_secondary{};  // For 12-string / unison detuning
    float filter_prev = 0.0f;
    float filter_prev_secondary = 0.0f;
    float dispersion_prev = 0.0f;
    float pickup_filter_state = 0.0f;
    uint32_t rng_state = 12345;
  };

  // Acoustic body resonance biquad filters
  struct Biquad {
    float b0 = 1.0f, b1 = 0.0f, b2 = 0.0f, a1 = 0.0f, a2 = 0.0f;
    float x1 = 0.0f, x2 = 0.0f, y1 = 0.0f, y2 = 0.0f;

    void reset() noexcept {
      x1 = x2 = y1 = y2 = 0.0f;
    }

    [[nodiscard]] float process(float in) noexcept {
      const float out = b0 * in + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2;
      x2 = x1;
      x1 = in;
      y2 = y1;
      y1 = out;
      return out;
    }

    void setPeaking(double freq, double q, double gain_db, double sr) noexcept;
    void setLowpass(double freq, double q, double sr) noexcept;
    void setHighpass(double freq, double q, double sr) noexcept;
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

  // Stereo chorus delay
  static constexpr size_t MaxChorusSize = 2048;
  struct ChorusDelay {
    std::array<float, MaxChorusSize> buffer{};
    size_t write_pos = 0;
    double lfo_phase = 0.0;
  };

  [[nodiscard]] static bool voiceMatches(const Voice& voice, int note_id, int channel,
                                         int key) noexcept;
  void initFilters() noexcept;
  void initReverbTuning() noexcept;

  double sample_rate_ = 48000.0;
  std::array<std::atomic<double>, ParameterSpecs.size()> parameters_{};
  std::array<Voice, VoiceCount> voices_{};

  // Body formant filters for Left and Right channels
  Biquad body_filter1_l_{}, body_filter1_r_{};
  Biquad body_filter2_l_{}, body_filter2_r_{};
  Biquad body_filter3_l_{}, body_filter3_r_{};
  Biquad cab_filter_l_{}, cab_filter_r_{};

  // Chorus & Reverb
  ChorusDelay chorus_l_{}, chorus_r_{};
  std::array<CombFilter, CombCount> comb_left_{};
  std::array<CombFilter, CombCount> comb_right_{};
  std::array<AllPassFilter, AllPassCount> allpass_left_{};
  std::array<AllPassFilter, AllPassCount> allpass_right_{};
};

}  // namespace onebeat::stock::guitar
