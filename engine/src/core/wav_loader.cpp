#include "core/wav_loader.h"

#include <cmath>

#define DR_WAV_IMPLEMENTATION
#define DR_WAV_NO_STDIO_WCHAR
#include "dr_wav.h"

namespace onebeat::core {
namespace {

std::string fileName(const std::string& path) {
  const size_t slash = path.find_last_of('/');
  return slash == std::string::npos ? path : path.substr(slash + 1);
}

}  // namespace

std::unique_ptr<SampleData> loadAudioFile(const std::string& path, std::string& error) {
  drwav wav;
  if (drwav_init_file(&wav, path.c_str(), nullptr) == DRWAV_FALSE) {
    error = "Could not open '" + fileName(path) + "'. It may be missing or not a WAV file.";
    return nullptr;
  }

  auto data = std::make_unique<SampleData>();
  data->channels = static_cast<int>(wav.channels);
  data->sample_rate = static_cast<double>(wav.sampleRate);
  data->name = fileName(path);

  const auto total = static_cast<size_t>(wav.totalPCMFrameCount) * wav.channels;
  data->samples.resize(total);
  const drwav_uint64 read =
      drwav_read_pcm_frames_f32(&wav, wav.totalPCMFrameCount, data->samples.data());
  drwav_uninit(&wav);

  data->frames = static_cast<int64_t>(read);
  data->samples.resize(static_cast<size_t>(read) * static_cast<size_t>(data->channels));

  if (data->frames == 0 || data->channels <= 0) {
    error = "'" + fileName(path) + "' contains no audio.";
    return nullptr;
  }
  return data;
}

std::unique_ptr<SampleData> makeFallbackSample(double sample_rate) {
  auto data = std::make_unique<SampleData>();
  data->channels = 1;
  data->sample_rate = sample_rate;
  data->name = "built-in blip";
  const auto frames = static_cast<int64_t>(sample_rate * 0.25);
  data->frames = frames;
  data->samples.resize(static_cast<size_t>(frames));

  // A short pitched blip with an exponential decay: enough to hear pitch,
  // velocity and voice-stealing behaviour without shipping a file.
  constexpr double BaseHz = 220.0;
  for (int64_t frame = 0; frame < frames; ++frame) {
    const double time = static_cast<double>(frame) / sample_rate;
    const double envelope = std::exp(-time * 18.0);
    const double phase = 2.0 * M_PI * BaseHz * time;
    data->samples[static_cast<size_t>(frame)] =
        static_cast<float>(envelope * (std::sin(phase) + 0.3 * std::sin(2.0 * phase)) * 0.7);
  }
  return data;
}

}  // namespace onebeat::core
