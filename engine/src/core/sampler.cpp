#include "core/sampler.h"

#include <cmath>

namespace onebeat::core {

void Sampler::prepare(double sample_rate, int /*max_block_frames*/) {
  sample_rate_ = sample_rate;
  release_step_ = static_cast<float>(1.0 / (ReleaseSeconds * sample_rate));
  steal_step_ = static_cast<float>(1.0 / (StealSeconds * sample_rate));
  for (Voice& voice : voices_) {
    voice = Voice{};
  }
  if (sample_.acquire() == nullptr) {
    setSample(makeFallbackSample(sample_rate));
  }
}

void Sampler::release() {
  for (Voice& voice : voices_) {
    voice = Voice{};
  }
}

void Sampler::setSample(std::unique_ptr<SampleData> sample) {
  if (sample == nullptr) {
    return;
  }
  sample_.publish(std::move(sample));
}

void Sampler::reset() noexcept OB_NONBLOCKING {
  for (Voice& voice : voices_) {
    voice.active = false;
    voice.releasing = false;
    voice.pending_note = -1;
  }
}

void Sampler::startVoice(Voice& voice, int16_t note, float velocity) noexcept OB_NONBLOCKING {
  const SampleData* sample = sample_.acquire();
  voice.active = true;
  voice.releasing = false;
  voice.note = note;
  voice.gain = velocity;
  voice.position = 0.0;
  voice.fade = 1.0F;
  voice.fade_step = 0.0F;
  voice.pending_note = -1;
  voice.order = ++order_counter_;
  const double semitones = static_cast<double>(note - RootNote);
  const double source_rate = sample != nullptr ? sample->sample_rate : sample_rate_;
  voice.rate = std::pow(2.0, semitones / 12.0) * (source_rate / sample_rate_);
}

void Sampler::noteOn(int16_t note, float velocity) noexcept OB_NONBLOCKING {
  // 1. A free voice.
  for (Voice& voice : voices_) {
    if (!voice.active) {
      startVoice(voice, note, velocity);
      return;
    }
  }
  // 2. No free voice: steal the oldest one. It is not cut dead — it fades over
  //    2 ms and the new note is queued behind it, so the output never jumps.
  Voice* oldest = &voices_[0];
  for (Voice& voice : voices_) {
    if (voice.order < oldest->order) {
      oldest = &voice;
    }
  }
  if (log_ != nullptr) {
    log_->log(rt::LogLevel::Debug, rt::RtMessage::VoiceStolen, oldest->note, note);
  }
  oldest->releasing = true;
  oldest->fade_step = steal_step_;
  oldest->pending_note = note;
  oldest->pending_velocity = velocity;
}

void Sampler::noteOff(int16_t note) noexcept OB_NONBLOCKING {
  for (Voice& voice : voices_) {
    if (voice.active && !voice.releasing && voice.note == note) {
      voice.releasing = true;
      voice.fade_step = release_step_;
    }
  }
}

void Sampler::allNotesOff() noexcept OB_NONBLOCKING {
  for (Voice& voice : voices_) {
    if (voice.active && !voice.releasing) {
      voice.releasing = true;
      voice.fade_step = release_step_;
      voice.pending_note = -1;
    }
  }
}

int Sampler::activeVoices() const noexcept OB_NONBLOCKING {
  int count = 0;
  for (const Voice& voice : voices_) {
    if (voice.active) {
      ++count;
    }
  }
  return count;
}

void Sampler::render(const AudioBufferView& output, int start_frame,
                     int num_frames) noexcept OB_NONBLOCKING {
  const SampleData* sample = sample_.acquire();
  if (sample == nullptr || sample->frames <= 0) {
    return;
  }

  const int out_channels = output.numChannels();
  const int src_channels = sample->channels;
  const float* src = sample->samples.data();
  const int64_t src_frames = sample->frames;

  for (Voice& voice : voices_) {
    if (!voice.active) {
      continue;
    }
    for (int frame = 0; frame < num_frames; ++frame) {
      const auto index = static_cast<int64_t>(voice.position);
      if (index >= src_frames - 1) {
        voice.active = false;
        break;
      }
      const auto fraction = static_cast<float>(voice.position - static_cast<double>(index));
      const float amplitude = voice.gain * voice.fade;

      for (int channel = 0; channel < out_channels; ++channel) {
        const int src_channel = channel < src_channels ? channel : src_channels - 1;
        const size_t base = static_cast<size_t>(index) * static_cast<size_t>(src_channels) +
                            static_cast<size_t>(src_channel);
        const float s0 = src[base];
        const float s1 = src[base + static_cast<size_t>(src_channels)];
        const float value = s0 + ((s1 - s0) * fraction);
        output.channel(channel)[start_frame + frame] += value * amplitude;
      }

      voice.position += voice.rate;
      if (voice.releasing) {
        voice.fade -= voice.fade_step;
        if (voice.fade <= 0.0F) {
          voice.fade = 0.0F;
          voice.active = false;
          // A stolen voice restarts here, at zero amplitude: click-free.
          if (voice.pending_note >= 0) {
            const int16_t note = voice.pending_note;
            const float velocity = voice.pending_velocity;
            startVoice(voice, note, velocity);
          }
          break;
        }
      }
    }
  }
}

}  // namespace onebeat::core
