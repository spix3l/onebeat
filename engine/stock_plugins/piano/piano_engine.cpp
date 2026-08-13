#include "piano_engine.h"

#include <algorithm>
#include <cmath>

namespace onebeat::stock::piano {
namespace {

constexpr double TwoPi = 6.28318530717958647692;

[[nodiscard]] double midiFrequency(int key) noexcept {
  return 440.0 * std::pow(2.0, (static_cast<double>(key) - 69.0) / 12.0);
}

}  // namespace

size_t parameterIndex(uint32_t id) noexcept {
  for (size_t index = 0; index < ParameterSpecs.size(); ++index) {
    if (ParameterSpecs[index].id == id) {
      return index;
    }
  }
  return ParameterSpecs.size();
}

double clampParameter(double value) noexcept {
  return std::clamp(value, 0.0, 1.0);
}

PianoEngine::PianoEngine() noexcept {
  for (size_t index = 0; index < ParameterSpecs.size(); ++index) {
    parameters_[index].store(ParameterSpecs[index].default_value, std::memory_order_relaxed);
  }
}

void PianoEngine::setSampleRate(double sample_rate) noexcept {
  sample_rate_ = std::clamp(sample_rate, 8000.0, 192000.0);
}

void PianoEngine::reset() noexcept {
  voices_.fill(Voice{});
  delay_left_.fill(0.0F);
  delay_right_.fill(0.0F);
  delay_cursor_ = 0;
}

double PianoEngine::parameter(uint32_t id) const noexcept {
  const size_t index = parameterIndex(id);
  return index < ParameterSpecs.size() ? parameters_[index].load(std::memory_order_relaxed) : 0.0;
}

void PianoEngine::setParameter(uint32_t id, double value) noexcept {
  const size_t index = parameterIndex(id);
  if (index < ParameterSpecs.size()) {
    parameters_[index].store(clampParameter(value), std::memory_order_relaxed);
  }
}

void PianoEngine::noteOn(int note_id, int channel, int key, double velocity) noexcept {
  Voice* selected = nullptr;
  for (Voice& voice : voices_) {
    if (!voice.active) {
      selected = &voice;
      break;
    }
    if (selected == nullptr || voice.envelope < selected->envelope) {
      selected = &voice;
    }
  }
  if (selected == nullptr) {
    return;
  }
  selected->active = true;
  selected->released = false;
  selected->note_id = static_cast<int16_t>(note_id);
  selected->channel = static_cast<int16_t>(channel);
  selected->key = static_cast<int16_t>(key);
  selected->frequency = midiFrequency(key);
  selected->phase = 0.0;
  selected->envelope = 0.0001;
  selected->age = 0.0;
  selected->velocity = std::clamp(velocity, 0.0, 1.0);
  selected->noise = static_cast<uint32_t>(key) * 2654435761U ^ 0x9e3779b9U;
}

bool PianoEngine::voiceMatches(const Voice& voice, int note_id, int channel, int key) noexcept {
  if (!voice.active) {
    return false;
  }
  if (note_id >= 0 && voice.note_id != note_id) {
    return false;
  }
  if (channel >= 0 && voice.channel != channel) {
    return false;
  }
  return key < 0 || voice.key == key;
}

void PianoEngine::noteOff(int note_id, int channel, int key, bool choke) noexcept {
  for (Voice& voice : voices_) {
    if (!voiceMatches(voice, note_id, channel, key)) {
      continue;
    }
    if (choke) {
      voice.active = false;
      voice.envelope = 0.0;
    } else {
      voice.released = true;
    }
  }
}

void PianoEngine::render(float** outputs, uint32_t channel_count, uint32_t offset,
                         uint32_t frame_count) noexcept {
  if (channel_count == 0 || outputs == nullptr || outputs[0] == nullptr) {
    return;
  }

  const double tone = parameter(100);
  const double body = parameter(101);
  const double decay_seconds = 0.7 + parameter(102) * 7.3;
  const double release_seconds = 0.05 + parameter(103) * 2.2;
  const double room = parameter(104);
  const double width = parameter(105);
  const double output_gain = parameter(106) * 0.72;
  const double natural_decay = std::exp(-1.0 / (sample_rate_ * decay_seconds));
  const double release_decay = std::exp(-1.0 / (sample_rate_ * release_seconds));
  const uint32_t room_offset = static_cast<uint32_t>(sample_rate_ * 0.071) % DelaySize;

  for (uint32_t relative_frame = 0; relative_frame < frame_count; ++relative_frame) {
    const uint32_t frame = offset + relative_frame;
    double left = 0.0;
    double right = 0.0;
    for (Voice& voice : voices_) {
      if (!voice.active) {
        continue;
      }
      voice.age += 1.0 / sample_rate_;
      if (voice.age < 0.006) {
        voice.envelope = std::min(1.0, voice.envelope + 1.0 / (sample_rate_ * 0.006));
      } else {
        voice.envelope *= voice.released ? release_decay : natural_decay;
      }
      if (voice.envelope < 0.00004 || voice.age > 24.0) {
        voice.active = false;
        continue;
      }

      const double brightness = 0.14 + tone * 0.62 + voice.velocity * 0.18;
      const double fundamental = std::sin(voice.phase);
      const double second = std::sin(voice.phase * 2.006) * (0.18 + body * 0.20);
      const double third = std::sin(voice.phase * 3.018) * brightness * 0.16;
      const double fourth = std::sin(voice.phase * 4.041) * brightness * brightness * 0.08;
      voice.noise = voice.noise * 1664525U + 1013904223U;
      const double noise =
          (static_cast<double>((voice.noise >> 9U) & 0x7fffffU) / 4194304.0 - 1.0) *
          std::exp(-voice.age * (18.0 - tone * 8.0)) * (0.02 + tone * 0.035);
      const double sample = (fundamental + second + third + fourth + noise) * voice.envelope *
                            (0.08 + voice.velocity * voice.velocity * 0.22);
      const double pan =
          std::clamp((static_cast<double>(voice.key) - 60.0) / 38.0, -1.0, 1.0) * width * 0.72;
      left += sample * std::sqrt((1.0 - pan) * 0.5);
      right += sample * std::sqrt((1.0 + pan) * 0.5);
      voice.phase += TwoPi * voice.frequency / sample_rate_;
      if (voice.phase >= TwoPi) {
        voice.phase -= TwoPi;
      }
    }

    const uint32_t tap = (delay_cursor_ + DelaySize - room_offset) % DelaySize;
    const double wet_left = static_cast<double>(delay_left_[tap]);
    const double wet_right = static_cast<double>(delay_right_[tap]);
    delay_left_[delay_cursor_] = static_cast<float>(left + wet_right * 0.36);
    delay_right_[delay_cursor_] = static_cast<float>(right + wet_left * 0.36);
    delay_cursor_ = (delay_cursor_ + 1U) % DelaySize;
    left = (left + wet_left * room * 0.55) * output_gain;
    right = (right + wet_right * room * 0.55) * output_gain;
    outputs[0][frame] = static_cast<float>(std::tanh(left));
    if (channel_count > 1 && outputs[1] != nullptr) {
      outputs[1][frame] = static_cast<float>(std::tanh(right));
    }
    for (uint32_t channel = 2; channel < channel_count; ++channel) {
      if (outputs[channel] != nullptr) {
        outputs[channel][frame] = 0.0F;
      }
    }
  }
}

}  // namespace onebeat::stock::piano
