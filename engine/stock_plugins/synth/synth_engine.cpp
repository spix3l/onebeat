#include "synth_engine.h"

#include <algorithm>
#include <cmath>

namespace onebeat::stock::synth {
namespace {

constexpr double TwoPi = 6.28318530717958647692;

[[nodiscard]] double midiFrequency(int key) noexcept {
  return 440.0 * std::pow(2.0, (static_cast<double>(key) - 69.0) / 12.0);
}

struct PresetValues {
  double shape;
  double mix;
  double detune;
  double sub;
  double cutoff;
  double resonance;
  double filter_env;
  double attack;
  double decay;
  double sustain;
  double release;
  double drive;
  double delay;
  double width;
  double output;
  double lfo_rate;
  double lfo_depth;
  double glide;
  double noise;
};

constexpr std::array<PresetValues, PresetCount> FactoryPresets{{
    // A mono-friendly low sine/saw foundation that leaves kick space.
    {.05, .16, .50, .96, .15, .12, .52, .005, .48, .20, .18, .28, .02, .12, .80, .13, .03, .03, .00},
    // Short, glassy upper-register bell for the familiar drill counter melody.
    {.92, .68, .54, .18, .68, .22, .35, .002, .18, .08, .20, .08, .25, .46, .72, .26, .06, .00, .05},
    // Muted saw pluck with a controlled midrange bite.
    {.10, .36, .50, .24, .31, .18, .78, .003, .24, .06, .16, .24, .12, .28, .76, .20, .04, .00, .01},
    // Saturated sub with a long tail and portamento-ready setting.
    {.02, .10, .50, .99, .12, .08, .40, .004, .66, .22, .38, .48, .01, .10, .78, .10, .02, .16, .00},
    // Slow, dark supersaw pad for the background of an eight-bar loop.
    {.08, .72, .62, .42, .29, .20, .64, .34, .64, .74, .70, .10, .34, .92, .62, .24, .18, .00, .01},
    // Hollow digital keys that stay out of the 808's fundamental.
    {.36, .46, .48, .10, .48, .20, .48, .01, .38, .46, .32, .12, .18, .55, .70, .18, .08, .00, .00},
    // Narrow, resonant siren lead with vibrato and a little stereo movement.
    {.18, .58, .56, .12, .55, .62, .72, .025, .30, .62, .28, .14, .20, .64, .70, .42, .18, .05, .01},
    // Breath-like minor-key atmosphere: sine core plus restrained noise.
    {.98, .50, .50, .26, .38, .16, .74, .46, .70, .82, .88, .04, .52, .86, .58, .16, .12, .00, .11},
}};

[[nodiscard]] uint32_t presetIndex(double normalized) noexcept {
  return std::clamp(static_cast<uint32_t>(normalized * static_cast<double>(PresetCount)),
                    0U, static_cast<uint32_t>(PresetCount - 1));
}

[[nodiscard]] double oscillator(double phase, double shape) noexcept {
  double wrapped = phase - std::floor(phase);
  if (wrapped < 0.0) wrapped += 1.0;
  const double saw = wrapped * 2.0 - 1.0;
  const double square = wrapped < 0.5 ? 1.0 : -1.0;
  const double triangle = 1.0 - 4.0 * std::abs(wrapped - 0.5);
  const double sine = std::sin(wrapped * TwoPi);

  if (shape < 0.25) {
    return saw + (square - saw) * (shape * 4.0);
  }
  if (shape < 0.50) {
    return square + (triangle - square) * ((shape - 0.25) * 4.0);
  }
  if (shape < 0.75) {
    return triangle + (sine - triangle) * ((shape - 0.50) * 4.0);
  }
  return sine;
}

[[nodiscard]] float nextNoise(uint32_t& state) noexcept {
  state = state * 1664525U + 1013904223U;
  const uint32_t bits = (state >> 9U) & 0x7fffffU;
  return static_cast<float>(static_cast<double>(bits) / 4194304.0 - 1.0);
}

}  // namespace

const char* presetName(uint32_t index) noexcept {
  switch (index) {
    case PresetDrillSub:
      return "Drill Sub";
    case PresetFrostedBell:
      return "Frosted Bell";
    case PresetDarkPluck:
      return "Dark Pluck";
    case Preset808Glide:
      return "808 Glide";
    case PresetHollowPad:
      return "Hollow Pad";
    case PresetColdKeys:
      return "Cold Keys";
    case PresetSirenLead:
      return "Siren Lead";
    case PresetChoirMist:
      return "Choir Mist";
    default:
      return "Drill Sub";
  }
}

size_t parameterIndex(uint32_t id) noexcept {
  for (size_t index = 0; index < ParameterSpecs.size(); ++index) {
    if (ParameterSpecs[index].id == id) return index;
  }
  return ParameterSpecs.size();
}

double clampParameter(double value) noexcept {
  return std::clamp(value, 0.0, 1.0);
}

SynthEngine::SynthEngine() noexcept {
  applyFactoryDefaults();
  applyPreset(PresetDrillSub);
}

void SynthEngine::applyFactoryDefaults() noexcept {
  for (size_t index = 0; index < ParameterSpecs.size(); ++index) {
    parameters_[index].store(ParameterSpecs[index].default_value, std::memory_order_relaxed);
  }
}

void SynthEngine::applyPreset(uint32_t index) noexcept {
  const PresetValues& preset = FactoryPresets[std::min(index, static_cast<uint32_t>(PresetCount - 1))];
  parameters_[parameterIndex(ParamOscShape)].store(preset.shape, std::memory_order_relaxed);
  parameters_[parameterIndex(ParamOscMix)].store(preset.mix, std::memory_order_relaxed);
  parameters_[parameterIndex(ParamDetune)].store(preset.detune, std::memory_order_relaxed);
  parameters_[parameterIndex(ParamSub)].store(preset.sub, std::memory_order_relaxed);
  parameters_[parameterIndex(ParamCutoff)].store(preset.cutoff, std::memory_order_relaxed);
  parameters_[parameterIndex(ParamResonance)].store(preset.resonance, std::memory_order_relaxed);
  parameters_[parameterIndex(ParamFilterEnv)].store(preset.filter_env, std::memory_order_relaxed);
  parameters_[parameterIndex(ParamAttack)].store(preset.attack, std::memory_order_relaxed);
  parameters_[parameterIndex(ParamDecay)].store(preset.decay, std::memory_order_relaxed);
  parameters_[parameterIndex(ParamSustain)].store(preset.sustain, std::memory_order_relaxed);
  parameters_[parameterIndex(ParamRelease)].store(preset.release, std::memory_order_relaxed);
  parameters_[parameterIndex(ParamDrive)].store(preset.drive, std::memory_order_relaxed);
  parameters_[parameterIndex(ParamDelay)].store(preset.delay, std::memory_order_relaxed);
  parameters_[parameterIndex(ParamWidth)].store(preset.width, std::memory_order_relaxed);
  parameters_[parameterIndex(ParamOutput)].store(preset.output, std::memory_order_relaxed);
  parameters_[parameterIndex(ParamLfoRate)].store(preset.lfo_rate, std::memory_order_relaxed);
  parameters_[parameterIndex(ParamLfoDepth)].store(preset.lfo_depth, std::memory_order_relaxed);
  parameters_[parameterIndex(ParamGlide)].store(preset.glide, std::memory_order_relaxed);
  parameters_[parameterIndex(ParamNoise)].store(preset.noise, std::memory_order_relaxed);
}

void SynthEngine::setSampleRate(double sample_rate) noexcept {
  sample_rate_ = std::clamp(sample_rate, 8000.0, 192000.0);
}

void SynthEngine::reset() noexcept {
  voices_.fill(Voice{});
  delay_left_.clear();
  delay_right_.clear();
  lfo_phase_ = 0.0;
}

double SynthEngine::parameter(uint32_t id) const noexcept {
  const size_t index = parameterIndex(id);
  return index < parameters_.size() ? parameters_[index].load(std::memory_order_relaxed) : 0.0;
}

void SynthEngine::setParameter(uint32_t id, double value) noexcept {
  const size_t index = parameterIndex(id);
  if (index >= parameters_.size()) return;
  parameters_[index].store(clampParameter(value), std::memory_order_relaxed);
}

void SynthEngine::selectPreset(double normalized) noexcept {
  const double clamped = clampParameter(normalized);
  parameters_[parameterIndex(ParamPreset)].store(clamped, std::memory_order_relaxed);
  applyPreset(presetIndex(clamped));
}

bool SynthEngine::voiceMatches(const Voice& voice, int note_id, int channel, int key) noexcept {
  if (!voice.active) return false;
  // Live audition events use wildcard note IDs. Treat wildcard key/channel
  // fields the same way so a host note-off cannot strand a voice when its
  // addressing metadata is partially populated.
  if (note_id >= 0 && voice.note_id >= 0 && voice.note_id != note_id) return false;
  if (channel >= 0 && voice.channel != channel) return false;
  if (key >= 0 && voice.key != key) return false;
  return true;
}

void SynthEngine::noteOn(int note_id, int channel, int key, double velocity) noexcept {
  if (velocity <= 0.0) {
    noteOff(note_id, channel, key, false);
    return;
  }

  Voice* selected = nullptr;
  for (Voice& voice : voices_) {
    if (!voice.active) {
      selected = &voice;
      break;
    }
    if (selected == nullptr || voice.released || voice.envelope < selected->envelope) {
      selected = &voice;
    }
  }
  if (selected == nullptr) return;

  selected->active = true;
  selected->released = false;
  selected->note_id = static_cast<int16_t>(note_id);
  selected->channel = static_cast<int16_t>(channel);
  selected->key = static_cast<int16_t>(std::clamp(key, 0, 127));
  selected->target_frequency = midiFrequency(selected->key);
  selected->frequency = selected->target_frequency;
  selected->phase = 0.0;
  selected->phase_secondary = 0.0;
  selected->envelope = 0.0001;
  selected->age = 0.0;
  selected->velocity = std::clamp(velocity, 0.01, 1.0);
  selected->env_stage = EnvStage::Attack;
  selected->noise_state = static_cast<uint32_t>(selected->key) * 2654435761U + 1U;
  selected->filter_low = 0.0F;
  selected->filter_band = 0.0F;
}

void SynthEngine::noteOff(int note_id, int channel, int key, bool choke) noexcept {
  bool matched = false;
  for (Voice& voice : voices_) {
    if (!voiceMatches(voice, note_id, channel, key)) continue;
    matched = true;
    if (choke) {
      voice.active = false;
      voice.env_stage = EnvStage::Off;
      voice.envelope = 0.0;
    } else {
      voice.released = true;
      voice.env_stage = EnvStage::Release;
    }
  }

  // Some hosts omit the note address on live note-off events. A wildcard
  // release must still be safe: do not leave a voice running forever because
  // its note metadata was not echoed back by the host.
  if (!matched && note_id < 0) {
    for (Voice& voice : voices_) {
      if (!voice.active) continue;
      if (choke) {
        voice.active = false;
        voice.env_stage = EnvStage::Off;
        voice.envelope = 0.0;
      } else {
        voice.released = true;
        voice.env_stage = EnvStage::Release;
      }
    }
  }
}

void SynthEngine::render(float** outputs, uint32_t channel_count, uint32_t offset,
                         uint32_t frame_count) noexcept {
  if (outputs == nullptr || channel_count == 0 || outputs[0] == nullptr || frame_count == 0) return;

  const double shape = parameter(ParamOscShape);
  const double mix = parameter(ParamOscMix);
  const double detune = parameter(ParamDetune);
  const double sub = parameter(ParamSub);
  const double cutoff = parameter(ParamCutoff);
  const double resonance = parameter(ParamResonance);
  const double filter_env = parameter(ParamFilterEnv);
  const double attack = parameter(ParamAttack);
  const double decay = parameter(ParamDecay);
  const double sustain = parameter(ParamSustain);
  const double release = parameter(ParamRelease);
  const double drive = parameter(ParamDrive);
  const double delay = parameter(ParamDelay);
  const double width = parameter(ParamWidth);
  const double output = parameter(ParamOutput);
  const double lfo_rate = parameter(ParamLfoRate);
  const double lfo_depth = parameter(ParamLfoDepth);
  const double glide = parameter(ParamGlide);
  const double noise = parameter(ParamNoise);
  const double lfo_increment = TwoPi * (0.1 + lfo_rate * 9.9) / sample_rate_;

  const double attack_seconds = 0.001 + attack * attack * 1.5;
  const double decay_seconds = 0.03 + decay * decay * 2.5;
  const double release_seconds = 0.02 + release * release * 4.0;
  const double attack_step = 1.0 / (sample_rate_ * attack_seconds);
  const double decay_coeff = std::exp(-1.0 / (sample_rate_ * decay_seconds));
  const double release_coeff = std::exp(-1.0 / (sample_rate_ * release_seconds));
  const double detune_semitones = (detune - 0.5) * 2.0;
  const size_t delay_samples = static_cast<size_t>(0.06 * sample_rate_ + delay * 0.38 * sample_rate_);
  const float delay_feedback = static_cast<float>(0.18 + delay * 0.38);
  const float delay_mix = static_cast<float>(delay * 0.24);

  for (uint32_t frame_index = 0; frame_index < frame_count; ++frame_index) {
    lfo_phase_ += lfo_increment;
    if (lfo_phase_ >= TwoPi) lfo_phase_ -= TwoPi;
    const double lfo = std::sin(lfo_phase_);
    double left = 0.0;
    double right = 0.0;

    for (Voice& voice : voices_) {
      if (!voice.active) continue;

      switch (voice.env_stage) {
        case EnvStage::Attack:
          voice.envelope += attack_step;
          if (voice.envelope >= 1.0) {
            voice.envelope = 1.0;
            voice.env_stage = EnvStage::Decay;
          }
          break;
        case EnvStage::Decay:
          voice.envelope = sustain + (voice.envelope - sustain) * decay_coeff;
          if (std::abs(voice.envelope - sustain) < 0.0005) {
            voice.envelope = sustain;
            voice.env_stage = EnvStage::Sustain;
          }
          break;
        case EnvStage::Sustain:
          break;
        case EnvStage::Release:
          voice.envelope *= release_coeff;
          break;
        case EnvStage::Off:
          voice.envelope = 0.0;
          break;
      }
      voice.age += 1.0 / sample_rate_;
      if (voice.envelope < 0.00003 || voice.age > 45.0) {
        voice.active = false;
        voice.env_stage = EnvStage::Off;
        continue;
      }

      const double lfo_pitch = lfo * lfo_depth * 0.025;
      if (glide > 0.001) {
        const double glide_coeff = 1.0 - std::exp(-1.0 / (sample_rate_ * (0.005 + glide * 0.45)));
        voice.frequency += (voice.target_frequency - voice.frequency) * glide_coeff;
      } else {
        voice.frequency = voice.target_frequency;
      }
      const double frequency = voice.frequency * std::pow(2.0, (detune_semitones + lfo_pitch) / 12.0);
      const double secondary_frequency = frequency * std::pow(2.0, detune_semitones / 1200.0);
      const double phase_step = frequency / sample_rate_;
      const double secondary_step = secondary_frequency / sample_rate_;
      const double oscillator_a = oscillator(voice.phase, shape);
      const double oscillator_b = oscillator(voice.phase_secondary, std::min(1.0, shape + 0.07));
      const double sub_oscillator = std::sin(voice.phase * 0.5 * TwoPi);
      const double noise_sample = static_cast<double>(nextNoise(voice.noise_state)) * noise;
      const double raw = oscillator_a * (1.0 - mix) + oscillator_b * mix + sub_oscillator * sub + noise_sample;

      voice.phase += phase_step;
      if (voice.phase >= 1.0) voice.phase -= std::floor(voice.phase);
      voice.phase_secondary += secondary_step;
      if (voice.phase_secondary >= 1.0) voice.phase_secondary -= std::floor(voice.phase_secondary);

      const double envelope_cutoff = filter_env * voice.envelope;
      const double lfo_cutoff = lfo * lfo_depth * 0.14;
      const double cutoff_hz = std::clamp(35.0 * std::pow(520.0, cutoff + envelope_cutoff + lfo_cutoff),
                                          35.0, sample_rate_ * 0.44);
      const float filter_alpha = static_cast<float>(1.0 - std::exp(-TwoPi * cutoff_hz / sample_rate_));
      const float input = static_cast<float>(raw) - voice.filter_band * static_cast<float>(resonance * 0.70);
      const float high = input - voice.filter_low - voice.filter_band;
      voice.filter_band += filter_alpha * high;
      voice.filter_low += filter_alpha * voice.filter_band;
      const double filtered = static_cast<double>(voice.filter_low + voice.filter_band * static_cast<float>(resonance * 0.20));
      const double driven = std::tanh(filtered * (1.0 + drive * 7.0));
      const double voice_output = driven * voice.envelope * std::pow(voice.velocity, 0.75) * 0.18;

      const double pan = std::clamp((static_cast<double>(voice.key) - 60.0) / 48.0, -1.0, 1.0) * width * 0.55;
      left += voice_output * std::sqrt((1.0 - pan) * 0.5);
      right += voice_output * std::sqrt((1.0 + pan) * 0.5);
    }

    const float delayed_left = delay_left_.read(delay_samples);
    const float delayed_right = delay_right_.read(delay_samples);
    delay_left_.push(static_cast<float>(left) + delayed_left * delay_feedback);
    delay_right_.push(static_cast<float>(right) + delayed_right * delay_feedback);
    left += static_cast<double>(delayed_left * delay_mix);
    right += static_cast<double>(delayed_right * delay_mix);

    const double output_gain = 0.35 + output * 0.85;
    outputs[0][offset + frame_index] = static_cast<float>(std::tanh(left * output_gain));
    if (channel_count > 1 && outputs[1] != nullptr) {
      outputs[1][offset + frame_index] = static_cast<float>(std::tanh(right * output_gain));
    }
    for (uint32_t channel = 2; channel < channel_count; ++channel) {
      if (outputs[channel] != nullptr) outputs[channel][offset + frame_index] = 0.0F;
    }
  }
}

}  // namespace onebeat::stock::synth
