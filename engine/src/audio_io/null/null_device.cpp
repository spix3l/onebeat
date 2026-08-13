#include "audio_io/null/null_device.h"

#include <chrono>

#include "core/rt/rt.h"

namespace onebeat::audio_io {

NullAudioDevice::~NullAudioDevice() {
  stop();
  close();
}

std::vector<DeviceInfo> NullAudioDevice::enumerateOutputDevices() {
  DeviceInfo info;
  info.id = "null";
  info.name = "Null Output (headless)";
  info.max_output_channels = 2;
  info.sample_rates = {44100.0, 48000.0, 88200.0, 96000.0};
  info.is_default_output = true;
  return {info};
}

bool NullAudioDevice::open(const StreamFormat& requested, StreamFormat& granted,
                           std::string& /*error*/) {
  format_ = requested;
  if (format_.sample_rate <= 0.0) {
    format_.sample_rate = 48000.0;
  }
  if (format_.block_frames <= 0) {
    format_.block_frames = 512;
  }
  format_.output_channels = 2;

  storage_.assign(
      static_cast<size_t>(format_.output_channels) * static_cast<size_t>(format_.block_frames),
      0.0F);
  channels_.resize(static_cast<size_t>(format_.output_channels));
  for (int channel = 0; channel < format_.output_channels; ++channel) {
    channels_[static_cast<size_t>(channel)] =
        storage_.data() +
        (static_cast<size_t>(channel) * static_cast<size_t>(format_.block_frames));
  }
  granted = format_;
  return true;
}

void NullAudioDevice::close() {
  storage_.clear();
  channels_.clear();
}

bool NullAudioDevice::start(std::string& /*error*/) {
  if (running_.exchange(true)) {
    return true;
  }
  if (free_running_) {
    thread_ = std::thread([this] { threadMain(); });
  }
  return true;
}

void NullAudioDevice::stop() {
  if (!running_.exchange(false)) {
    return;
  }
  if (thread_.joinable()) {
    thread_.join();
  }
}

void NullAudioDevice::renderBlock(int frames) {
  for (float*& channel : channels_) {
    for (int frame = 0; frame < frames; ++frame) {
      channel[frame] = 0.0F;
    }
  }
  if (render_callback_ != nullptr) {
    RenderBlock block;
    block.outputs = channels_.data();
    block.num_channels = static_cast<int>(channels_.size());
    block.num_frames = frames;
    block.stream_time_frames = stream_time_frames_;
    block.host_time_ns = rt::monotonicNanos();
    render_callback_->renderAudio(block);
  }
  stream_time_frames_ += static_cast<uint64_t>(frames);
  blocks_.fetch_add(1, std::memory_order_relaxed);
}

const std::vector<float*>& NullAudioDevice::renderOnce(int frames) {
  renderBlock(frames > format_.block_frames ? format_.block_frames : frames);
  return channels_;
}

void NullAudioDevice::threadMain() {
  rt::enableFlushToZero();
  const auto block_duration = std::chrono::duration<double>(
      static_cast<double>(format_.block_frames) / format_.sample_rate);
  auto next = std::chrono::steady_clock::now();
  while (running_.load(std::memory_order_acquire)) {
    renderBlock(format_.block_frames);
    next += std::chrono::duration_cast<std::chrono::steady_clock::duration>(block_duration);
    std::this_thread::sleep_until(next);
  }
}

std::unique_ptr<AudioDevice> createNullAudioDevice(bool free_running) {
  return std::make_unique<NullAudioDevice>(free_running);
}

}  // namespace onebeat::audio_io
