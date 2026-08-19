#include "guitar_engine.h"

#include <algorithm>
#include <cmath>
#include <cstring>

namespace onebeat::stock::guitar {
namespace {

constexpr double TwoPi = 6.28318530717958647692;

[[nodiscard]] double midiFrequency(int key) noexcept {
  return 440.0 * std::pow(2.0, (static_cast<double>(key) - 69.0) / 12.0);
}

}  // namespace

void GuitarEngine::Biquad::setPeaking(double freq, double q, double gain_db, double sr) noexcept {
  const double w0 = TwoPi * std::clamp(freq, 20.0, sr * 0.48) / sr;
  const double cos_w0 = std::cos(w0);
  const double sin_w0 = std::sin(w0);
  const double alpha = sin_w0 / (2.0 * std::max(0.1, q));
  const double A = std::pow(10.0, gain_db / 40.0);

  const double a0_val = 1.0 + alpha / A;
  b0 = static_cast<float>((1.0 + alpha * A) / a0_val);
  b1 = static_cast<float>((-2.0 * cos_w0) / a0_val);
  b2 = static_cast<float>((1.0 - alpha * A) / a0_val);
  a1 = static_cast<float>((-2.0 * cos_w0) / a0_val);
  a2 = static_cast<float>((1.0 - alpha / A) / a0_val);
}

void GuitarEngine::Biquad::setLowpass(double freq, double q, double sr) noexcept {
  const double w0 = TwoPi * std::clamp(freq, 20.0, sr * 0.48) / sr;
  const double cos_w0 = std::cos(w0);
  const double sin_w0 = std::sin(w0);
  const double alpha = sin_w0 / (2.0 * std::max(0.1, q));

  const double a0_val = 1.0 + alpha;
  b0 = static_cast<float>(((1.0 - cos_w0) * 0.5) / a0_val);
  b1 = static_cast<float>((1.0 - cos_w0) / a0_val);
  b2 = static_cast<float>(((1.0 - cos_w0) * 0.5) / a0_val);
  a1 = static_cast<float>((-2.0 * cos_w0) / a0_val);
  a2 = static_cast<float>((1.0 - alpha) / a0_val);
}

void GuitarEngine::Biquad::setHighpass(double freq, double q, double sr) noexcept {
  const double w0 = TwoPi * std::clamp(freq, 20.0, sr * 0.48) / sr;
  const double cos_w0 = std::cos(w0);
  const double sin_w0 = std::sin(w0);
  const double alpha = sin_w0 / (2.0 * std::max(0.1, q));

  const double a0_val = 1.0 + alpha;
  b0 = static_cast<float>(((1.0 + cos_w0) * 0.5) / a0_val);
  b1 = static_cast<float>(-(1.0 + cos_w0) / a0_val);
  b2 = static_cast<float>(((1.0 + cos_w0) * 0.5) / a0_val);
  a1 = static_cast<float>((-2.0 * cos_w0) / a0_val);
  a2 = static_cast<float>((1.0 - alpha) / a0_val);
}

const char* presetName(uint32_t index) noexcept {
  switch (index) {
    case PresetAcousticSteel:
      return "Acoustic: Steel String";
    case PresetAcousticNylon:
      return "Acoustic: Nylon Fingerstyle";
    case PresetAcoustic12String:
      return "Acoustic: 12-String Shimmer";
    case PresetAcousticMuted:
      return "Acoustic: Muted Folk";
    case PresetAcousticResonator:
      return "Acoustic: Resonator Slide";
    case PresetElectricCleanStrat:
      return "Electric: Clean Strat";
    case PresetElectricWarmJazz:
      return "Electric: Warm Jazz Archtop";
    case PresetElectricOverdriven:
      return "Electric: Overdriven Lead";
    case PresetElectric80sChorus:
      return "Electric: 80s Chorus Dream";
    case PresetElectricAmbientSlide:
      return "Electric: Ambient Slide";
    case PresetElectricFlamenco:
      return "Electric: Flamenco Passion";
    case PresetElectricLoFi:
      return "Electric: Lo-Fi Muted";
    default:
      return "Acoustic: Steel String";
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

GuitarEngine::GuitarEngine() noexcept {
  for (size_t index = 0; index < ParameterSpecs.size(); ++index) {
    parameters_[index].store(ParameterSpecs[index].default_value, std::memory_order_relaxed);
  }
  initFilters();
  initReverbTuning();
}

void GuitarEngine::setSampleRate(double sample_rate) noexcept {
  sample_rate_ = std::clamp(sample_rate, 8000.0, 192000.0);
  initFilters();
  initReverbTuning();
}

void GuitarEngine::initFilters() noexcept {
  // Acoustic guitar body formants:
  // Mode 1: Helmholtz air resonance at ~105 Hz
  body_filter1_l_.setPeaking(105.0, 3.5, 7.0, sample_rate_);
  body_filter1_r_.setPeaking(105.0, 3.5, 7.0, sample_rate_);
  // Mode 2: Main wood soundboard resonance at ~215 Hz
  body_filter2_l_.setPeaking(215.0, 4.0, 8.5, sample_rate_);
  body_filter2_r_.setPeaking(215.0, 4.0, 8.5, sample_rate_);
  // Mode 3: Bridge/rib high-wood presence at ~440 Hz
  body_filter3_l_.setPeaking(440.0, 3.0, 5.0, sample_rate_);
  body_filter3_r_.setPeaking(440.0, 3.0, 5.0, sample_rate_);

  // Cab speaker filter: lowpass at ~5200 Hz
  cab_filter_l_.setLowpass(5200.0, 0.707, sample_rate_);
  cab_filter_r_.setLowpass(5200.0, 0.707, sample_rate_);
}

void GuitarEngine::initReverbTuning() noexcept {
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

  chorus_l_.buffer.fill(0.0f);
  chorus_l_.write_pos = 0;
  chorus_l_.lfo_phase = 0.0;

  chorus_r_.buffer.fill(0.0f);
  chorus_r_.write_pos = 0;
  chorus_r_.lfo_phase = 0.25;  // 90-degree stereo phase offset
}

void GuitarEngine::reset() noexcept {
  for (auto& voice : voices_) {
    voice.active = false;
    voice.age = 0.0;
    voice.stage = EnvStage::Off;
    voice.delay_line.clear();
    voice.delay_line_secondary.clear();
    voice.filter_prev = 0.0f;
    voice.filter_prev_secondary = 0.0f;
    voice.dispersion_prev = 0.0f;
    voice.pickup_filter_state = 0.0f;
  }
  body_filter1_l_.reset();
  body_filter1_r_.reset();
  body_filter2_l_.reset();
  body_filter2_r_.reset();
  body_filter3_l_.reset();
  body_filter3_r_.reset();
  cab_filter_l_.reset();
  cab_filter_r_.reset();
  initReverbTuning();
}

double GuitarEngine::parameter(uint32_t id) const noexcept {
  const size_t index = parameterIndex(id);
  if (index >= parameters_.size()) {
    return 0.0;
  }
  return parameters_[index].load(std::memory_order_relaxed);
}

void GuitarEngine::setParameter(uint32_t id, double value) noexcept {
  const size_t index = parameterIndex(id);
  if (index >= parameters_.size()) {
    return;
  }
  parameters_[index].store(clampParameter(value), std::memory_order_relaxed);
}

bool GuitarEngine::voiceMatches(const Voice& voice, int note_id, int channel, int key) noexcept {
  if (!voice.active) return false;
  if (note_id >= 0 && voice.note_id >= 0) return voice.note_id == note_id;
  return voice.channel == channel && voice.key == key;
}

bool GuitarEngine::keySounding(int key) const noexcept {
  for (const Voice& voice : voices_) {
    if (voice.active && !voice.released && voice.key == key) return true;
  }
  return false;
}

void GuitarEngine::noteOn(int note_id, int channel, int key, double velocity) noexcept {
  if (velocity <= 0.0) {
    noteOff(note_id, channel, key, false);
    return;
  }

  // Find voice: prefer inactive, else the one furthest into its release, else
  // the oldest still being held.
  //
  // A voice that has not been rendered yet is never stolen. A chord is several
  // note-ons at the same frame, all applied before a sample goes out, so every
  // voice it claims still has `age == 0`. The previous version fell through to
  // index 0 whenever nothing had been released, which put every note of a
  // held chord on the same voice and left only the last note-on sounding —
  // the top of the chord and nothing under it.
  size_t target_idx = VoiceCount;
  for (size_t i = 0; i < VoiceCount; ++i) {
    if (!voices_[i].active) {
      target_idx = i;
      break;
    }
  }

  if (target_idx == VoiceCount) {
    double max_release = -1.0;
    for (size_t i = 0; i < VoiceCount; ++i) {
      if (voices_[i].age > 0.0 && voices_[i].released && voices_[i].release_time > max_release) {
        max_release = voices_[i].release_time;
        target_idx = i;
      }
    }
  }

  if (target_idx == VoiceCount) {
    double max_age = 0.0;
    for (size_t i = 0; i < VoiceCount; ++i) {
      if (voices_[i].age > max_age) {
        max_age = voices_[i].age;
        target_idx = i;
      }
    }
  }

  // Every voice belongs to the chord starting right now: drop this note rather
  // than cut one of its neighbours to make room.
  if (target_idx == VoiceCount) {
    return;
  }

  Voice& v = voices_[target_idx];
  v.active = true;
  v.released = false;
  v.note_id = static_cast<int16_t>(note_id);
  v.channel = static_cast<int16_t>(channel);
  v.key = static_cast<int16_t>(key);

  const double pitch_param = parameter(ParamPitch);
  const double pitch_shift_semitones = (pitch_param - 0.5) * 24.0;  // +/- 12 semitones
  v.frequency = midiFrequency(key) * std::pow(2.0, pitch_shift_semitones / 12.0);

  const double dyn_param = parameter(ParamDynamics);
  v.velocity = std::clamp(std::pow(velocity, 1.5 - dyn_param * 0.8), 0.01, 1.0);
  v.release_time = 0.0;
  v.age = 0.0;
  v.stage = EnvStage::Excitation;

  // Excitation length in samples based on pitch & attack
  const double attack_param = parameter(ParamAttack);
  const double period_samples = sample_rate_ / std::max(20.0, v.frequency);
  v.excitation_length = std::clamp(static_cast<size_t>(period_samples * (0.4 + attack_param * 0.6)),
                                   size_t{4}, size_t{256});
  v.excitation_counter = 0;

  v.delay_line.clear();
  v.delay_line_secondary.clear();
  v.filter_prev = 0.0f;
  v.filter_prev_secondary = 0.0f;
  v.dispersion_prev = 0.0f;
  v.pickup_filter_state = 0.0f;
}

void GuitarEngine::noteOff(int note_id, int channel, int key, bool choke) noexcept {
  for (auto& voice : voices_) {
    if (voiceMatches(voice, note_id, channel, key)) {
      voice.released = true;
      voice.stage = choke ? EnvStage::Off : EnvStage::Release;
      if (choke) {
        voice.active = false;
      }
    }
  }
}

void GuitarEngine::render(float** outputs, uint32_t channel_count, uint32_t offset,
                          uint32_t frame_count) noexcept {
  if (outputs == nullptr || channel_count == 0 || frame_count == 0) return;

  const double tone_param = parameter(ParamTone);
  const double body_param = parameter(ParamBody);
  const double decay_param = parameter(ParamDecay);
  const double release_param = parameter(ParamRelease);
  const double room_param = parameter(ParamRoom);
  const double width_param = parameter(ParamWidth);
  const double output_param = parameter(ParamOutput);
  const double pick_pos_param = parameter(ParamPickPos);
  const double damping_param = parameter(ParamDamping);
  const double pickup_param = parameter(ParamPickup);
  const double drive_param = parameter(ParamDrive);
  const double chorus_param = parameter(ParamChorus);
  const double reverb_size_param = parameter(ParamReverbSize);
  const double mod_rate_param = parameter(ParamModRate);

  // String feedback loop gain based on decay
  const float base_feedback = static_cast<float>(0.965 + decay_param * 0.033);
  // Release damping factor
  const float release_damping = static_cast<float>(0.80 - release_param * 0.45);
  // Damping coefficient for loop filter
  const float tone_cutoff_coef =
      static_cast<float>(0.10 + tone_param * 0.75 - damping_param * 0.45);
  const float loop_filter_a = std::clamp(tone_cutoff_coef, 0.05f, 0.88f);

  // Reverb parameters
  const float rev_feedback =
      static_cast<float>(std::clamp(0.65 + reverb_size_param * 0.28, 0.5, 0.96));
  const float rev_damp = 0.35f;

  for (uint32_t frame = 0; frame < frame_count; ++frame) {
    float mix_l = 0.0f;
    float mix_r = 0.0f;

    for (auto& v : voices_) {
      if (!v.active) continue;
      v.age += 1.0 / sample_rate_;

      const double delay_len = (sample_rate_ / std::max(20.0, v.frequency)) - 0.5;
      const double pick_comb_delay =
          std::clamp(delay_len * (0.05 + pick_pos_param * 0.45), 1.0, delay_len * 0.5);

      float excitation = 0.0f;
      if (v.stage == EnvStage::Excitation) {
        if (v.excitation_counter < v.excitation_length) {
          // LFSR white noise shaped with pick impulse
          v.rng_state = v.rng_state * 1664525u + 1013904223u;
          const float raw_noise =
              static_cast<float>(static_cast<int32_t>(v.rng_state >> 16)) / 32768.0f;
          const float phase_norm =
              static_cast<float>(v.excitation_counter) / static_cast<float>(v.excitation_length);
          const float window = std::sin(phase_norm * 3.14159265f);
          excitation = raw_noise * window * static_cast<float>(v.velocity) * 1.5f;

          ++v.excitation_counter;
        } else {
          v.stage = EnvStage::Sustain;
        }
      }

      // Read from delay line
      const float delayed_sample = v.delay_line.readFractional(delay_len);
      // Secondary delay line for 12-string detuning (1.0025x pitch)
      const float delayed_sample_sec = v.delay_line_secondary.readFractional(delay_len * 0.9975);

      // Lowpass loss filter in loop
      const float filtered =
          v.filter_prev * (1.0f - loop_filter_a) + delayed_sample * loop_filter_a;
      v.filter_prev = filtered;

      const float filtered_sec =
          v.filter_prev_secondary * (1.0f - loop_filter_a) + delayed_sample_sec * loop_filter_a;
      v.filter_prev_secondary = filtered_sec;

      // Dispersion (inharmonicity / string stiffness)
      constexpr float dispersion_c = 0.15f;
      const float dispersed =
          -dispersion_c * filtered + v.dispersion_prev + dispersion_c * filtered;
      v.dispersion_prev = filtered;

      // Loop gain calculation
      float current_feedback = base_feedback;
      if (v.released) {
        v.release_time += 1.0 / sample_rate_;
        current_feedback *= std::max(
            0.0f, 1.0f - static_cast<float>(v.release_time) * (1.0f + release_damping * 8.0f));
        if (current_feedback <= 0.0001f || v.release_time > 2.0) {
          v.active = false;
          continue;
        }
      }

      // Pick position comb filter: subtract delayed excitation
      float pick_filtered_excitation = excitation;
      if (v.stage == EnvStage::Excitation && pick_comb_delay > 1.0) {
        pick_filtered_excitation = excitation - 0.7f * v.delay_line.readFractional(pick_comb_delay);
      }

      // Feed back into delay lines
      const float next_in = pick_filtered_excitation + dispersed * current_feedback;
      v.delay_line.push(next_in);

      const float next_in_sec = pick_filtered_excitation * 0.7f + filtered_sec * current_feedback;
      v.delay_line_secondary.push(next_in_sec);

      // Voice output: direct pick excitation transient + circulating string waveguide
      float voice_out = delayed_sample + pick_filtered_excitation * 0.35f;
      if (chorus_param > 0.05) {
        voice_out = voice_out * 0.7f + delayed_sample_sec * 0.5f;
      }

      // Voice pan spread based on note key (lower strings left, higher strings right)
      const float note_pan =
          static_cast<float>(v.key - 60) / 48.0f * static_cast<float>(width_param) * 0.5f;
      const float pan_l = std::clamp(0.5f - note_pan, 0.05f, 0.95f);
      const float pan_r = std::clamp(0.5f + note_pan, 0.05f, 0.95f);

      mix_l += voice_out * pan_l;
      mix_r += voice_out * pan_r;
    }

    // Acoustic Body Resonance Formants (Helmholtz + Soundboard peaks)
    if (body_param > 0.01) {
      const float body_l1 = body_filter1_l_.process(mix_l);
      const float body_r1 = body_filter1_r_.process(mix_r);
      const float body_l2 = body_filter2_l_.process(body_l1);
      const float body_r2 = body_filter2_r_.process(body_r1);
      const float body_l3 = body_filter3_l_.process(body_l2);
      const float body_r3 = body_filter3_r_.process(body_r2);

      const float body_blend = static_cast<float>(body_param);
      mix_l = mix_l * (1.0f - body_blend * 0.6f) + body_l3 * (body_blend * 0.6f);
      mix_r = mix_r * (1.0f - body_blend * 0.6f) + body_r3 * (body_blend * 0.6f);
    }

    // Electric Pickup & Amp Drive
    if (drive_param > 0.01 || pickup_param > 0.01) {
      const float drive_val = static_cast<float>(1.0 + drive_param * 12.0);
      const float sat_l = std::tanh(mix_l * drive_val) / std::tanh(drive_val);
      const float sat_r = std::tanh(mix_r * drive_val) / std::tanh(drive_val);

      // Cab speaker filter
      const float cab_l = cab_filter_l_.process(sat_l);
      const float cab_r = cab_filter_r_.process(sat_r);

      const float drive_mix = static_cast<float>(std::max(drive_param, pickup_param * 0.7));
      mix_l = mix_l * (1.0f - drive_mix) + cab_l * drive_mix;
      mix_r = mix_r * (1.0f - drive_mix) + cab_r * drive_mix;
    }

    // Stereo Chorus
    if (chorus_param > 0.02) {
      chorus_l_.buffer[chorus_l_.write_pos] = mix_l;
      chorus_r_.buffer[chorus_r_.write_pos] = mix_r;

      const double lfo_rate = 0.2 + mod_rate_param * 3.0;
      chorus_l_.lfo_phase += (TwoPi * lfo_rate) / sample_rate_;
      chorus_r_.lfo_phase += (TwoPi * lfo_rate) / sample_rate_;
      if (chorus_l_.lfo_phase > TwoPi) chorus_l_.lfo_phase -= TwoPi;
      if (chorus_r_.lfo_phase > TwoPi) chorus_r_.lfo_phase -= TwoPi;

      const double mod_depth_samples = 40.0 * chorus_param;
      const double delay_samples_l = 180.0 + std::sin(chorus_l_.lfo_phase) * mod_depth_samples;
      const double delay_samples_r = 180.0 + std::cos(chorus_r_.lfo_phase) * mod_depth_samples;

      const size_t read_idx_l =
          (chorus_l_.write_pos + MaxChorusSize - static_cast<size_t>(delay_samples_l)) %
          MaxChorusSize;
      const size_t read_idx_r =
          (chorus_r_.write_pos + MaxChorusSize - static_cast<size_t>(delay_samples_r)) %
          MaxChorusSize;

      chorus_l_.write_pos = (chorus_l_.write_pos + 1) % MaxChorusSize;
      chorus_r_.write_pos = (chorus_r_.write_pos + 1) % MaxChorusSize;

      const float chorus_out_l = chorus_l_.buffer[read_idx_l];
      const float chorus_out_r = chorus_r_.buffer[read_idx_r];

      const float ch_blend = static_cast<float>(chorus_param * 0.5);
      mix_l = mix_l * (1.0f - ch_blend) + chorus_out_l * ch_blend;
      mix_r = mix_r * (1.0f - ch_blend) + chorus_out_r * ch_blend;
    }

    // Plate/Room Reverb (Comb + AllPass network)
    float rev_mix_l = 0.0f;
    float rev_mix_r = 0.0f;
    if (room_param > 0.01) {
      const float rev_in_l = mix_l * 0.4f;
      const float rev_in_r = mix_r * 0.4f;

      for (size_t c = 0; c < CombCount; ++c) {
        CombFilter& cl = comb_left_[c];
        const float out_cl = cl.buffer[cl.cursor];
        cl.filter_store = out_cl * (1.0f - rev_damp) + cl.filter_store * rev_damp;
        cl.buffer[cl.cursor] = rev_in_l + cl.filter_store * rev_feedback;
        cl.cursor = (cl.cursor + 1) % cl.size;
        rev_mix_l += out_cl;

        CombFilter& cr = comb_right_[c];
        const float out_cr = cr.buffer[cr.cursor];
        cr.filter_store = out_cr * (1.0f - rev_damp) + cr.filter_store * rev_damp;
        cr.buffer[cr.cursor] = rev_in_r + cr.filter_store * rev_feedback;
        cr.cursor = (cr.cursor + 1) % cr.size;
        rev_mix_r += out_cr;
      }

      for (size_t a = 0; a < AllPassCount; ++a) {
        AllPassFilter& al = allpass_left_[a];
        const float buf_out_l = al.buffer[al.cursor];
        const float out_al = -rev_mix_l + buf_out_l;
        al.buffer[al.cursor] = rev_mix_l + buf_out_l * 0.5f;
        al.cursor = (al.cursor + 1) % al.size;
        rev_mix_l = out_al;

        AllPassFilter& ar = allpass_right_[a];
        const float buf_out_r = ar.buffer[ar.cursor];
        const float out_ar = -rev_mix_r + buf_out_r;
        ar.buffer[ar.cursor] = rev_mix_r + buf_out_r * 0.5f;
        ar.cursor = (ar.cursor + 1) % ar.size;
        rev_mix_r = out_ar;
      }
    }

    const float room_wet = static_cast<float>(room_param);
    const float out_l = (mix_l * (1.0f - room_wet * 0.3f) + rev_mix_l * room_wet * 0.25f) *
                        static_cast<float>(output_param);
    const float out_r = (mix_r * (1.0f - room_wet * 0.3f) + rev_mix_r * room_wet * 0.25f) *
                        static_cast<float>(output_param);

    outputs[0][offset + frame] = out_l;
    if (channel_count > 1) {
      outputs[1][offset + frame] = out_r;
    }
  }
}

}  // namespace onebeat::stock::guitar
