// Audio file decoding — worker thread only, never the audio thread (OB-1-08 §1).
#pragma once

#include <memory>
#include <string>
#include <vector>

namespace onebeat::core {

// Immutable once built; handed to the RT side through the publish/retire
// pattern exactly like the schedule.
struct SampleData {
  std::vector<float> samples;  // interleaved, `channels` per frame
  int channels = 0;
  int64_t frames = 0;
  double sample_rate = 0.0;
  std::string name;

  float sampleAt(int64_t frame, int channel) const noexcept {
    return samples[static_cast<size_t>(frame) * static_cast<size_t>(channels) +
                   static_cast<size_t>(channel)];
  }
};

// Decodes a WAV file to float32. dr_wav today; AIFF/FLAC/MP3 join in Stage 7
// per FR-SND-02, behind this same function.
// Returns nullptr and fills `error` on failure. Worker thread only.
std::unique_ptr<SampleData> loadAudioFile(const std::string& path, std::string& error);

// The fallback one-shot: a short synthesised percussive blip. Used when the
// bundled default sound is missing, so the engine always makes sound.
std::unique_ptr<SampleData> makeFallbackSample(double sample_rate);

}  // namespace onebeat::core
