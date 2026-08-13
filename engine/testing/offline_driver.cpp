#include "testing/offline_driver.h"

#include <cmath>
#include <cstdio>

#include "audio_io/null/null_device.h"
#include "core/rt/rt.h"
#include "core/time_map.h"

namespace onebeat::testing {

float RenderResult::peak() const {
  float peak = 0.0F;
  for (size_t index = 0; index < left.size(); ++index) {
    peak = std::max(peak, std::abs(left[index]));
    peak = std::max(peak, std::abs(right[index]));
  }
  return peak;
}

float RenderResult::rms() const {
  if (left.empty()) {
    return 0.0F;
  }
  double sum = 0.0;
  for (size_t index = 0; index < left.size(); ++index) {
    sum += static_cast<double>(left[index]) * static_cast<double>(left[index]);
    sum += static_cast<double>(right[index]) * static_cast<double>(right[index]);
  }
  return static_cast<float>(std::sqrt(sum / static_cast<double>(left.size() * 2)));
}

float RenderResult::maxDelta() const {
  float worst = 0.0F;
  for (size_t index = 1; index < left.size(); ++index) {
    worst = std::max(worst, std::abs(left[index] - left[index - 1]));
    worst = std::max(worst, std::abs(right[index] - right[index - 1]));
  }
  return worst;
}

RenderResult renderOffline(core::Engine& engine, int64_t frames, int block_frames) {
  rt::enableFlushToZero();

  auto* device = dynamic_cast<audio_io::NullAudioDevice*>(engine.device());
  RenderResult result;
  result.sample_rate = engine.config().sample_rate;
  if (device == nullptr) {
    return result;  // offline rendering requires the null backend
  }

  result.left.reserve(static_cast<size_t>(frames));
  result.right.reserve(static_cast<size_t>(frames));

  int64_t remaining = frames;
  while (remaining > 0) {
    const auto chunk = static_cast<int>(std::min<int64_t>(remaining, block_frames));
    const std::vector<float*>& channels = device->renderOnce(chunk);
    for (int frame = 0; frame < chunk; ++frame) {
      result.left.push_back(channels[0][frame]);
      result.right.push_back(channels.size() > 1 ? channels[1][frame] : channels[0][frame]);
    }
    remaining -= chunk;
  }
  return result;
}

bool sameSamples(const RenderResult& lhs, const RenderResult& rhs) {
  if (lhs.left.size() != rhs.left.size() || lhs.right.size() != rhs.right.size()) {
    return false;
  }
  for (size_t index = 0; index < lhs.left.size(); ++index) {
    if (lhs.left[index] != rhs.left[index] || lhs.right[index] != rhs.right[index]) {
      return false;
    }
  }
  return true;
}

bool writeWav(const RenderResult& result, const std::string& path) {
  std::FILE* file = std::fopen(path.c_str(), "wbe");
  if (file == nullptr) {
    return false;
  }
  const auto frames = static_cast<uint32_t>(result.frames());
  const uint32_t data_bytes = frames * 2 * 4;
  const uint32_t sample_rate = static_cast<uint32_t>(result.sample_rate);

  auto writeU32 = [file](uint32_t value) { std::fwrite(&value, 4, 1, file); };
  auto writeU16 = [file](uint16_t value) { std::fwrite(&value, 2, 1, file); };

  std::fwrite("RIFF", 1, 4, file);
  writeU32(36 + data_bytes);
  std::fwrite("WAVEfmt ", 1, 8, file);
  writeU32(16);
  writeU16(3);  // IEEE float
  writeU16(2);
  writeU32(sample_rate);
  writeU32(sample_rate * 2 * 4);
  writeU16(8);
  writeU16(32);
  std::fwrite("data", 1, 4, file);
  writeU32(data_bytes);
  for (size_t index = 0; index < result.frames(); ++index) {
    std::fwrite(&result.left[index], 4, 1, file);
    std::fwrite(&result.right[index], 4, 1, file);
  }
  std::fclose(file);
  return true;
}

std::unique_ptr<core::Schedule> makeGridSchedule(int note_count, int16_t note, double sample_rate,
                                                 double step_beats, double tempo_bpm,
                                                 float velocity) {
  const core::TimeMap time_map(sample_rate, tempo_bpm);
  const int64_t step_frames = time_map.beatsToFrames(step_beats);
  core::ScheduleBuilder builder;
  for (int index = 0; index < note_count; ++index) {
    builder.addNote(core::DefaultInstrument, note, velocity,
                    static_cast<int64_t>(index) * step_frames, step_frames);
  }
  builder.setLengthFrames(static_cast<int64_t>(note_count) * step_frames);
  return builder.build(sample_rate, 1);
}

// Storage is a fixed array so that recording an event on the audio thread is
// provably allocation-free; overflow is counted, not grown.
void EventCapturePlugin::record(Captured event) noexcept OB_NONBLOCKING {
  if (count_ < Capacity) {
    storage_[count_++] = event;
  } else {
    ++overflowed_;
  }
}

bool EventCapturePlugin::audioPortInfo(plugin::PortDirection direction, uint32_t index,
                                       plugin::AudioPortInfo& out) const {
  if (direction != plugin::PortDirection::Output || index != 0) {
    return false;
  }
  out = plugin::AudioPortInfo{};
  out.id = 0;
  out.name.assign("Main");
  out.is_main = true;
  return true;
}

plugin::ProcessStatus EventCapturePlugin::process(
    const plugin::ProcessBlock& block) noexcept OB_NONBLOCKING {
  for (const plugin::PluginEvent& event : block.in_events) {
    const int64_t absolute = frame_ + static_cast<int64_t>(event.time);
    switch (event.kind()) {
      case plugin::EventType::NoteOn:
        record(Captured{Captured::Kind::NoteOn, event.key, static_cast<float>(event.value()),
                        absolute});
        break;
      case plugin::EventType::NoteOff:
        // A wildcarded key is the model's "all notes off" (see event.h).
        record(Captured{event.key == plugin::AnyKey ? Captured::Kind::AllNotesOff
                                                    : Captured::Kind::NoteOff,
                        event.key, 0.0F, absolute});
        break;
      default:
        break;
    }
  }
  frame_ += static_cast<int64_t>(block.frames);
  return plugin::ProcessStatus::Sleep;  // silence: this one never writes audio
}

}  // namespace onebeat::testing
