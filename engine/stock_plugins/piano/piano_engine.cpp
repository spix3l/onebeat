#include "piano_engine.h"

#include <algorithm>
#include <cmath>
#include <cstring>

namespace onebeat::stock::piano {
namespace {

constexpr double TwoPi = 6.28318530717958647692;

[[nodiscard]] double midiFrequency(int key) noexcept {
  return 440.0 * std::pow(2.0, (static_cast<double>(key) - 69.0) / 12.0);
}

}  // namespace

const char* presetName(uint32_t index) noexcept {
  switch (index) {
    case PresetConcertGrand:
      return "Concert Grand";
    case PresetFeltUpright:
      return "Felt Upright";
    case PresetClassicRhodes:
      return "Classic Rhodes";
    case PresetFmDxTines:
      return "FM DX Tines";
    case PresetVintageWurlitzer:
      return "Vintage Wurlitzer";
    case PresetHonkyTonk:
      return "Honky-Tonk";
    case PresetDreamCloud:
      return "Dream Cloud";
    case PresetPopStudioGrand:
      return "Pop Studio Grand";
    case PresetHarpsichord:
      return "Harpsichord";
    case PresetSynthKeys:
      return "Synth Keys";
    default:
      return "Concert Grand";
  }
}

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
  initReverbTuning();
}

void PianoEngine::setSampleRate(double sample_rate) noexcept {
  sample_rate_ = std::clamp(sample_rate, 8000.0, 192000.0);
  initReverbTuning();
}

void PianoEngine::initReverbTuning() noexcept {
  // Prime delay lengths scaled to sample rate
  const double scale = sample_rate_ / 44100.0;
  constexpr std::array<double, CombCount> CombDelaysL = {1116.0, 1188.0, 1277.0, 1356.0};
  constexpr std::array<double, CombCount> CombDelaysR = {1139.0, 1211.0, 1301.0, 1378.0};
  constexpr std::array<double, AllPassCount> AllPassDelaysL = {225.0, 341.0};
  constexpr std::array<double, AllPassCount> AllPassDelaysR = {256.0, 373.0};

  for (size_t i = 0; i < CombCount; ++i) {
    comb_left_[i].size =
        std::clamp(static_cast<size_t>(CombDelaysL[i] * scale), size_t{16}, MaxCombSize - 1);
    comb_left_[i].cursor = 0;
    comb_left_[i].filter_store = 0.0f;
    comb_left_[i].buffer.fill(0.0f);

    comb_right_[i].size =
        std::clamp(static_cast<size_t>(CombDelaysR[i] * scale), size_t{16}, MaxCombSize - 1);
    comb_right_[i].cursor = 0;
    comb_right_[i].filter_store = 0.0f;
    comb_right_[i].buffer.fill(0.0f);
  }

  for (size_t i = 0; i < AllPassCount; ++i) {
    allpass_left_[i].size =
        std::clamp(static_cast<size_t>(AllPassDelaysL[i] * scale), size_t{8}, MaxAllPassSize - 1);
    allpass_left_[i].cursor = 0;
    allpass_left_[i].buffer.fill(0.0f);

    allpass_right_[i].size =
        std::clamp(static_cast<size_t>(AllPassDelaysR[i] * scale), size_t{8}, MaxAllPassSize - 1);
    allpass_right_[i].cursor = 0;
    allpass_right_[i].buffer.fill(0.0f);
  }
}

void PianoEngine::reset() noexcept {
  voices_.fill(Voice{});
  initReverbTuning();
  mod_lfo_phase_ = 0.0;
  tremolo_lfo_phase_ = 0.0;
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
  selected->phase2 = 0.0;
  selected->phase3 = 0.0;
  selected->fm_phase = 0.0;
  selected->envelope = 0.0001;
  selected->env_stage = EnvStage::Attack;
  selected->age = 0.0;
  selected->velocity = std::clamp(velocity, 0.01, 1.0);
  selected->noise = static_cast<uint32_t>(key) * 2654435761U ^ 0x9e3779b9U;
  selected->damper_noise = 0.0;
  selected->filter_state = 0.0;
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
      voice.env_stage = EnvStage::Off;
    } else {
      voice.released = true;
      voice.env_stage = EnvStage::Release;
      // Excite damper noise on key release
      voice.damper_noise = 0.08 * (1.0 - static_cast<double>(voice.key) / 127.0);
    }
  }
}

void PianoEngine::processReverb(double in_left, double in_right, double& out_left,
                                double& out_right, double room_mix, double room_size,
                                double damping) noexcept {
  if (room_mix <= 0.001) {
    out_left = in_left;
    out_right = in_right;
    return;
  }

  const float feedback = static_cast<float>(0.68 + room_size * 0.28);
  const float damp = static_cast<float>(0.20 + damping * 0.60);
  const float input = static_cast<float>((in_left + in_right) * 0.18);

  float comb_sum_l = 0.0f;
  float comb_sum_r = 0.0f;

  for (size_t i = 0; i < CombCount; ++i) {
    // Left comb
    CombFilter& cl = comb_left_[i];
    const float out_l = cl.buffer[cl.cursor];
    cl.filter_store = out_l * (1.0f - damp) + cl.filter_store * damp;
    cl.buffer[cl.cursor] = input + cl.filter_store * feedback;
    cl.cursor = (cl.cursor + 1) % cl.size;
    comb_sum_l += out_l;

    // Right comb
    CombFilter& cr = comb_right_[i];
    const float out_r = cr.buffer[cr.cursor];
    cr.filter_store = out_r * (1.0f - damp) + cr.filter_store * damp;
    cr.buffer[cr.cursor] = input + cr.filter_store * feedback;
    cr.cursor = (cr.cursor + 1) % cr.size;
    comb_sum_r += out_r;
  }

  // Allpass filters
  float ap_l = comb_sum_l * 0.25f;
  float ap_r = comb_sum_r * 0.25f;

  for (size_t i = 0; i < AllPassCount; ++i) {
    // Left allpass
    AllPassFilter& apl = allpass_left_[i];
    const float buf_out_l = apl.buffer[apl.cursor];
    const float new_buf_l = ap_l + buf_out_l * 0.5f;
    ap_l = buf_out_l - ap_l * 0.5f;
    apl.buffer[apl.cursor] = new_buf_l;
    apl.cursor = (apl.cursor + 1) % apl.size;

    // Right allpass
    AllPassFilter& apr = allpass_right_[i];
    const float buf_out_r = apr.buffer[apr.cursor];
    const float new_buf_r = ap_r + buf_out_r * 0.5f;
    ap_r = buf_out_r - ap_r * 0.5f;
    apr.buffer[apr.cursor] = new_buf_r;
    apr.cursor = (apr.cursor + 1) % apr.size;
  }

  out_left = in_left + static_cast<double>(ap_l) * room_mix * 1.2;
  out_right = in_right + static_cast<double>(ap_r) * room_mix * 1.2;
}

void PianoEngine::render(float** outputs, uint32_t channel_count, uint32_t offset,
                         uint32_t frame_count) noexcept {
  if (channel_count == 0 || outputs == nullptr || outputs[0] == nullptr) {
    return;
  }

  // Retrieve parameters
  const double tone = parameter(ParamTone);
  const double body = parameter(ParamBody);
  const double decay_param = parameter(ParamDecay);
  const double release_param = parameter(ParamRelease);
  const double room_mix = parameter(ParamRoom);
  const double width_param = parameter(ParamWidth);
  const double output_gain = parameter(ParamOutput) * 0.82;
  const double preset_param = parameter(ParamPreset);
  const double attack_param = parameter(ParamAttack);
  const double sustain_param = parameter(ParamSustain);
  const double hammer_param = parameter(ParamHammer);
  const double damper_param = parameter(ParamDamper);
  const double detune_param = parameter(ParamDetune);
  const double vel_sens = parameter(ParamVelocitySens);
  const double reverb_size = parameter(ParamReverbSize);
  const double mod_depth = parameter(ParamModDepth);
  const double mod_rate = parameter(ParamModRate);
  const double drive = parameter(ParamDrive);

  // Derive preset index
  const uint32_t preset = std::clamp(
      static_cast<uint32_t>(preset_param * static_cast<double>(PresetCount)), 0U,
      static_cast<uint32_t>(PresetCount - 1));

  // Time constants
  const double attack_sec =
      preset == PresetHarpsichord
          ? 0.0005
          : (preset == PresetDreamCloud || preset == PresetSynthKeys
                 ? (0.002 + attack_param * attack_param * 0.8)
                 : (0.001 + attack_param * attack_param * 0.4));
  const double attack_rate = 1.0 / (sample_rate_ * std::max(0.0005, attack_sec));

  const double decay_sec = 0.12 + decay_param * decay_param * 12.0;
  const double decay_rate = std::exp(-1.0 / (sample_rate_ * decay_sec));

  const double release_sec = 0.03 + release_param * release_param * 5.0;
  const double release_rate = std::exp(-1.0 / (sample_rate_ * release_sec));

  const double mod_freq = 0.2 + mod_rate * 7.8;
  const double mod_phase_inc = TwoPi * mod_freq / sample_rate_;

  // Inharmonicity coefficient
  const double inharm_base = 0.00015 + detune_param * 0.0008;

  for (uint32_t relative_frame = 0; relative_frame < frame_count; ++relative_frame) {
    const uint32_t frame = offset + relative_frame;
    double left = 0.0;
    double right = 0.0;

    // Advance LFOs
    mod_lfo_phase_ += mod_phase_inc;
    if (mod_lfo_phase_ >= TwoPi) mod_lfo_phase_ -= TwoPi;
    tremolo_lfo_phase_ += mod_phase_inc * 1.5;
    if (tremolo_lfo_phase_ >= TwoPi) tremolo_lfo_phase_ -= TwoPi;

    const double lfo_mod = std::sin(mod_lfo_phase_);
    const double lfo_tremolo = 1.0 - mod_depth * 0.5 * (1.0 + std::sin(tremolo_lfo_phase_));

    for (Voice& voice : voices_) {
      if (!voice.active) {
        continue;
      }
      voice.age += 1.0 / sample_rate_;

      // ADSR State Machine
      switch (voice.env_stage) {
        case EnvStage::Attack:
          voice.envelope += attack_rate;
          if (voice.envelope >= 1.0) {
            voice.envelope = 1.0;
            voice.env_stage = EnvStage::Decay;
          }
          break;
        case EnvStage::Decay:
          voice.envelope = sustain_param + (voice.envelope - sustain_param) * decay_rate;
          if (voice.envelope <= sustain_param + 0.0005) {
            voice.envelope = sustain_param;
            voice.env_stage = EnvStage::Sustain;
          }
          break;
        case EnvStage::Sustain:
          // In sustain stage, acoustic pianos naturally decay slowly even while held
          if (preset == PresetClassicRhodes || preset == PresetSynthKeys ||
              preset == PresetVintageWurlitzer) {
            voice.envelope *= std::exp(-1.0 / (sample_rate_ * 18.0));
          } else {
            voice.envelope *= std::exp(-1.0 / (sample_rate_ * (3.0 + decay_sec * 0.6)));
          }
          break;
        case EnvStage::Release:
          voice.envelope *= release_rate;
          break;
        case EnvStage::Off:
          voice.envelope = 0.0;
          break;
      }

      // Check voice death
      if (voice.envelope < 0.00003 || voice.age > 28.0) {
        voice.active = false;
        voice.env_stage = EnvStage::Off;
        continue;
      }

      // Velocity scaling
      const double eff_vel = std::pow(voice.velocity, 0.4 + (1.0 - vel_sens) * 0.6);
      const double brightness =
          std::clamp(0.12 + tone * 0.65 + eff_vel * 0.28 * vel_sens, 0.05, 1.0);

      // Synthesis algorithms
      double sample = 0.0;
      const double f0 = voice.frequency;

      switch (preset) {
        case PresetConcertGrand:
        case PresetPopStudioGrand:
        case PresetFeltUpright: {
          // Acoustic Piano Model with string stiffness inharmonicity
          const double b_coeff = inharm_base * (1.0 + (voice.key > 60 ? (voice.key - 60) * 0.02 : 0.0));
          const double h2_mult = 2.0 * std::sqrt(1.0 + b_coeff * 4.0);
          const double h3_mult = 3.0 * std::sqrt(1.0 + b_coeff * 9.0);
          const double h4_mult = 4.0 * std::sqrt(1.0 + b_coeff * 16.0);
          const double h5_mult = 5.0 * std::sqrt(1.0 + b_coeff * 25.0);

          const double h1 = std::sin(voice.phase);
          const double h2 = std::sin(voice.phase * h2_mult) * (0.24 + body * 0.28);
          const double h3 = std::sin(voice.phase * h3_mult) * brightness * 0.22;
          const double h4 = std::sin(voice.phase * h4_mult) * brightness * brightness * 0.14;
          const double h5 = std::sin(voice.phase * h5_mult) * brightness * brightness * 0.08;

          // Soundboard sympathetic warmth
          const double body_sub = std::sin(voice.phase * 0.5) * body * 0.08 * (voice.key < 55 ? 1.0 : 0.2);

          // Felt / pop brightness weighting
          const double timbre_scale = (preset == PresetFeltUpright) ? 0.7 : (preset == PresetPopStudioGrand ? 1.25 : 1.0);
          sample = (h1 + h2 + h3 + h4 + h5 + body_sub) * timbre_scale;
          break;
        }

        case PresetClassicRhodes: {
          // Electric Piano: Sine core + Bell tines (7th/14th partials) + FM grit
          const double tine_decay = std::exp(-voice.age * (8.0 - tone * 3.0));
          const double fundamental = std::sin(voice.phase);
          const double second = std::sin(voice.phase * 2.0) * 0.18;
          const double tine = std::sin(voice.phase * 7.04) * tine_decay * (0.15 + hammer_param * 0.3);
          const double tine2 = std::sin(voice.phase * 14.1) * tine_decay * (0.06 + hammer_param * 0.15);
          sample = fundamental + second + tine + tine2;
          break;
        }

        case PresetFmDxTines: {
          // 2-Operator Dynamic Frequency Modulation
          const double fm_mod_index = (1.5 + eff_vel * 3.5 + hammer_param * 2.0) *
                                      std::exp(-voice.age * (12.0 - tone * 6.0));
          const double modulator = std::sin(voice.fm_phase);
          const double carrier = std::sin(voice.phase + fm_mod_index * modulator);
          const double sub_carrier = std::sin(voice.phase * 0.5) * body * 0.15;
          sample = carrier + sub_carrier;
          voice.fm_phase += TwoPi * (f0 * 14.0) / sample_rate_;
          if (voice.fm_phase >= TwoPi) voice.fm_phase -= TwoPi;
          break;
        }

        case PresetVintageWurlitzer: {
          // Reed EP: Asymmetric soft clipped reed wave
          const double reed_phase = voice.phase;
          const double fundamental = std::sin(reed_phase);
          const double h3 = std::sin(reed_phase * 3.0) * (0.35 + eff_vel * 0.25);
          const double h5 = std::sin(reed_phase * 5.0) * (0.15 + brightness * 0.15);
          const double raw_reed = fundamental + h3 * 0.4 + h5 * 0.2;
          sample = std::tanh(raw_reed * (1.2 + body * 0.8));
          break;
        }

        case PresetHonkyTonk: {
          // Saloon Piano: 3 detuned unison strings
          const double detune_cents = 0.0028 * (1.0 + detune_param * 2.5);
          const double str1 = std::sin(voice.phase);
          const double str2 = std::sin(voice.phase2);
          const double str3 = std::sin(voice.phase3);
          const double h2 = std::sin(voice.phase * 2.01) * 0.35;
          const double h3 = std::sin(voice.phase * 3.03) * 0.25 * brightness;
          sample = (str1 + str2 * 0.9 + str3 * 0.9 + h2 + h3) * 0.45;
          voice.phase2 += TwoPi * f0 * (1.0 + detune_cents) / sample_rate_;
          if (voice.phase2 >= TwoPi) voice.phase2 -= TwoPi;
          voice.phase3 += TwoPi * f0 * (1.0 - detune_cents * 0.8) / sample_rate_;
          if (voice.phase3 >= TwoPi) voice.phase3 -= TwoPi;
          break;
        }

        case PresetDreamCloud: {
          // Ethereal Soundtrack Ambient Piano
          const double h1 = std::sin(voice.phase);
          const double h2 = std::sin(voice.phase * 2.002) * 0.32;
          const double h3 = std::sin(voice.phase * 3.006) * 0.12 * brightness;
          sample = (h1 + h2 + h3) * 0.9;
          break;
        }

        case PresetHarpsichord: {
          // Plucked Baroque Harpsichord: Sawtooth-like bright overtone sequence
          const double h1 = std::sin(voice.phase);
          const double h2 = std::sin(voice.phase * 2.0) * 0.50;
          const double h3 = std::sin(voice.phase * 3.0) * 0.33;
          const double h4 = std::sin(voice.phase * 4.0) * 0.25;
          const double h5 = std::sin(voice.phase * 5.0) * 0.20 * brightness;
          sample = (h1 + h2 + h3 + h4 + h5) * 0.38;
          break;
        }

        case PresetSynthKeys: {
          // Warm Polyphonic Analog Keys
          const double saw = (voice.phase / TwoPi) * 2.0 - 1.0;
          const double sub_sine = std::sin(voice.phase);
          sample = saw * 0.4 + sub_sine * 0.6;
          break;
        }
      }

      // Hammer transient strike noise
      voice.noise = voice.noise * 1664525U + 1013904223U;
      const double raw_noise =
          static_cast<double>((voice.noise >> 9U) & 0x7fffffU) / 4194304.0 - 1.0;
      const double hammer_strike =
          raw_noise * std::exp(-voice.age * (24.0 - tone * 10.0)) * (0.04 + hammer_param * 0.12) *
          eff_vel;

      // Damper key-release noise
      if (voice.damper_noise > 0.0001) {
        voice.damper_noise *= 0.96;
      }
      const double damper_sound = raw_noise * voice.damper_noise * damper_param * 0.18;

      // One-pole lowpass filtering
      const double filter_cutoff = std::clamp(0.08 + brightness * 0.85, 0.05, 0.98);
      voice.filter_state += filter_cutoff * (sample + hammer_strike + damper_sound - voice.filter_state);

      const double voice_out = voice.filter_state * voice.envelope * (0.08 + eff_vel * eff_vel * 0.28);

      // Stereo Acoustic Panning
      const double pan =
          std::clamp((static_cast<double>(voice.key) - 60.0) / 36.0, -1.0, 1.0) * width_param * 0.75;
      left += voice_out * std::sqrt((1.0 - pan) * 0.5);
      right += voice_out * std::sqrt((1.0 + pan) * 0.5);

      // Advance fundamental phase
      voice.phase += TwoPi * f0 / sample_rate_;
      if (voice.phase >= TwoPi) {
        voice.phase -= TwoPi;
      }
    }

    // Apply Modulation (Chorus / Tremolo)
    if (mod_depth > 0.01) {
      if (preset == PresetVintageWurlitzer) {
        left *= lfo_tremolo;
        right *= (1.0 - mod_depth * 0.5 * (1.0 - std::sin(tremolo_lfo_phase_)));
      } else {
        const double chorus_l = left * (1.0 + mod_depth * 0.3 * lfo_mod);
        const double chorus_r = right * (1.0 - mod_depth * 0.3 * lfo_mod);
        left = chorus_l;
        right = chorus_r;
      }
    }

    // Process Reverb Tank
    double rev_left = left;
    double rev_right = right;
    processReverb(left, right, rev_left, rev_right, room_mix, reverb_size, 1.0 - tone * 0.7);

    // Apply Soft-Knee Drive / Saturation
    if (drive > 0.01) {
      const double drive_gain = 1.0 + drive * 3.5;
      rev_left = std::tanh(rev_left * drive_gain) / (1.0 + drive * 0.5);
      rev_right = std::tanh(rev_right * drive_gain) / (1.0 + drive * 0.5);
    }

    // Apply Master Output Gain & Soft Limiting
    outputs[0][frame] = static_cast<float>(std::tanh(rev_left * output_gain));
    if (channel_count > 1 && outputs[1] != nullptr) {
      outputs[1][frame] = static_cast<float>(std::tanh(rev_right * output_gain));
    }
    for (uint32_t channel = 2; channel < channel_count; ++channel) {
      if (outputs[channel] != nullptr) {
        outputs[channel][frame] = 0.0F;
      }
    }
  }
}

}  // namespace onebeat::stock::piano
