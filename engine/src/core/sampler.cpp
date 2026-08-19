#include "core/sampler.h"

#include <cmath>

namespace onebeat::core {

void Sampler::prepare(double sample_rate, int max_block_frames) {
  sample_rate_ = sample_rate;
  max_block_frames_ = max_block_frames > 0 ? max_block_frames : 1;
  release_step_ = static_cast<float>(1.0 / (ReleaseSeconds * sample_rate));
  steal_step_ = static_cast<float>(1.0 / (StealSeconds * sample_rate));
  for (Voice& voice : voices_) {
    voice = Voice{};
  }
  // Every allocation the stretch path will ever make, made here.
  stretch_.prepare(TimeStretch::MaxChannels);
  stretch_scratch_.assign(
      static_cast<size_t>(TimeStretch::MaxChannels) * static_cast<size_t>(max_block_frames_), 0.0F);
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
  voice.stretching = false;

  const double source_rate = sample != nullptr ? sample->sample_rate : sample_rate_;
  const int64_t source_frames = sample != nullptr ? sample->frames : 0;

  // A note voice reads the whole file forwards and pitches by playback rate.
  // A clip voice reads its own window, in its own direction, at its own rate —
  // and the two cases meet in `SourceWindow` so there is one interpolator.
  voice.window.sample = sample;
  voice.window.reversed = false;
  voice.window.start = 0;
  voice.window.length = source_frames;

  if (!clip_.enabled) {
    const double semitones = static_cast<double>(note - RootNote);
    voice.rate = std::pow(2.0, semitones / 12.0) * (source_rate / sample_rate_);
    return;
  }

  const int64_t start = clip_.start_frame < 0 ? 0 : clip_.start_frame;
  const int64_t remaining = source_frames > start ? source_frames - start : 0;
  const int64_t length =
      clip_.length_frames > 0 && clip_.length_frames < remaining ? clip_.length_frames : remaining;
  voice.window.start = start;
  voice.window.length = length;
  voice.window.reversed = clip_.reversed;

  // The file's own rate against the device's is a resample either way; the
  // clip's rate multiplies it. Keeping the two separate is what lets a 44.1 kHz
  // file sit in a 48 kHz project without the clip claiming to be stretched.
  const double device_ratio = source_rate / sample_rate_;
  voice.rate = clip_.rate * device_ratio;
  // Pitch-preserving mode hands the *clip's* ratio to the stretcher and lets
  // the resampler keep doing the sample-rate conversion, so the two corrections
  // do not fight over one number.
  voice.stretching = clip_.pitch_preserving && clip_.rate != 1.0;
  if (voice.stretching) {
    voice.rate = device_ratio;
    stretch_.reset();
  }
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

void Sampler::renderStretchedVoice(Voice& voice, const AudioBufferView& output, int start_frame,
                                   int num_frames) noexcept OB_NONBLOCKING {
  const int out_channels = output.numChannels();
  const int planes =
      out_channels < TimeStretch::MaxChannels ? out_channels : TimeStretch::MaxChannels;
  const int frames = num_frames < max_block_frames_ ? num_frames : max_block_frames_;
  if (frames <= 0 || planes <= 0) return;

  // Pre-sized in prepare(); the pointers are stack storage, the samples are not.
  float* channels[TimeStretch::MaxChannels] = {nullptr};
  for (int channel = 0; channel < planes; ++channel) {
    channels[channel] = stretch_scratch_.data() +
                        (static_cast<size_t>(channel) * static_cast<size_t>(max_block_frames_));
  }

  const int64_t produced = stretch_.render(voice.window, clip_.rate, channels, planes, frames);

  for (int64_t frame = 0; frame < produced; ++frame) {
    const float amplitude = voice.gain * voice.fade;
    for (int channel = 0; channel < out_channels; ++channel) {
      const int plane = channel < planes ? channel : planes - 1;
      output.channel(channel)[start_frame + frame] += channels[plane][frame] * amplitude;
    }
    if (!voice.releasing) continue;
    voice.fade -= voice.fade_step;
    if (voice.fade > 0.0F) continue;
    voice.fade = 0.0F;
    voice.active = false;
    if (voice.pending_note >= 0) {
      const int16_t note = voice.pending_note;
      const float velocity = voice.pending_velocity;
      startVoice(voice, note, velocity);
    }
    return;
  }
  // A short block means the window is spent. Ending here rather than on the
  // next call is what stops a stretched clip from holding its last grain.
  if (produced < frames || stretch_.finished()) voice.active = false;
}

void Sampler::render(const AudioBufferView& output, int start_frame,
                     int num_frames) noexcept OB_NONBLOCKING {
  const int out_channels = output.numChannels();

  for (Voice& voice : voices_) {
    if (!voice.active) {
      continue;
    }
    // A voice started before its sample finished decoding has nothing to read.
    if (!voice.window.valid()) {
      voice.active = false;
      continue;
    }
    if (voice.stretching) {
      renderStretchedVoice(voice, output, start_frame, num_frames);
      continue;
    }

    for (int frame = 0; frame < num_frames; ++frame) {
      // One frame of headroom: `SourceWindow::read` interpolates towards the
      // next position, and the last one has no next.
      if (voice.position >= static_cast<double>(voice.window.length - 1)) {
        voice.active = false;
        break;
      }
      const float amplitude = voice.gain * voice.fade;
      for (int channel = 0; channel < out_channels; ++channel) {
        output.channel(channel)[start_frame + frame] +=
            voice.window.read(voice.position, channel) * amplitude;
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
