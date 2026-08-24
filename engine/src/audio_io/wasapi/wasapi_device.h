// WASAPI shared-mode output backend. Windows SDK types stay behind Impl.
#pragma once

#include <atomic>
#include <memory>
#include <mutex>
#include <string>
#include <vector>

#include "audio_io/audio_device.h"

namespace onebeat::audio_io {

class WasapiDevice final : public AudioDevice {
 public:
  WasapiDevice();
  ~WasapiDevice() override;

  std::vector<DeviceInfo> enumerateOutputDevices() override;
  bool open(const StreamFormat& requested, StreamFormat& granted, std::string& error) override;
  void close() override;
  bool start(std::string& error) override;
  void stop() override;
  bool isRunning() const override { return running_.load(std::memory_order_acquire); }

  StreamFormat format() const override { return format_; }
  std::string deviceName() const override;
  int outputLatencyFrames() const override { return output_latency_frames_; }
  int roundTripLatencyFrames() const override { return output_latency_frames_; }

 private:
  struct Impl;
  void renderLoop() noexcept;

  std::unique_ptr<Impl> impl_;
  StreamFormat format_;
  std::atomic<bool> running_{false};
  int output_latency_frames_ = 0;
  mutable std::mutex state_mutex_;
  std::string device_name_;
};

}  // namespace onebeat::audio_io
