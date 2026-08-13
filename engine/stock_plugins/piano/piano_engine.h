#pragma once

#include <array>
#include <atomic>
#include <cstddef>
#include <cstdint>

namespace onebeat::stock::piano {

struct ParameterSpec {
  uint32_t id;
  const char* name;
  const char* module;
  double default_value;
};

inline constexpr std::array<ParameterSpec, 7> ParameterSpecs{{
    {100, "Tone", "Piano", 0.56},
    {101, "Body", "Piano", 0.62},
    {102, "Decay", "Envelope", 0.58},
    {103, "Release", "Envelope", 0.42},
    {104, "Room", "Space", 0.24},
    {105, "Width", "Space", 0.68},
    {106, "Output", "Master", 0.72},
}};

[[nodiscard]] size_t parameterIndex(uint32_t id) noexcept;
[[nodiscard]] double clampParameter(double value) noexcept;

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
  void noteOff(int note_id, int channel, int key, bool choke) noexcept;
  void render(float** outputs, uint32_t channel_count, uint32_t offset,
              uint32_t frame_count) noexcept;

 private:
  static constexpr uint32_t DelaySize = 32768;

  struct Voice {
    bool active = false;
    bool released = false;
    int16_t note_id = -1;
    int16_t channel = 0;
    int16_t key = 60;
    double frequency = 261.625565;
    double phase = 0.0;
    double envelope = 0.0;
    double age = 0.0;
    double velocity = 0.0;
    uint32_t noise = 1;
  };

  [[nodiscard]] static bool voiceMatches(const Voice& voice, int note_id, int channel,
                                         int key) noexcept;

  double sample_rate_ = 48000.0;
  std::array<std::atomic<double>, ParameterSpecs.size()> parameters_{};
  std::array<Voice, VoiceCount> voices_{};
  std::array<float, DelaySize> delay_left_{};
  std::array<float, DelaySize> delay_right_{};
  uint32_t delay_cursor_ = 0;
};

}  // namespace onebeat::stock::piano
