// CoreAudio output backend (OB-1-05 §2).
//
// THE ONLY place in the engine that knows CoreAudio exists. Nothing here leaks
// upward: the header exposes plain C++ and the implementation file is the sole
// includer of <AudioToolbox/...> in engine/src (tools/seam_check.sh enforces).
#pragma once

#include <atomic>
#include <memory>
#include <mutex>
#include <string>
#include <vector>

#include "audio_io/audio_device.h"

namespace onebeat::audio_io {

class CoreAudioDevice final : public AudioDevice {
 public:
  CoreAudioDevice();
  ~CoreAudioDevice() override;

  std::vector<DeviceInfo> enumerateOutputDevices() override;
  bool open(const StreamFormat& requested, StreamFormat& granted, std::string& error) override;
  void close() override;
  bool start(std::string& error) override;
  void stop() override;
  bool isRunning() const override { return running_.load(std::memory_order_acquire); }

  StreamFormat format() const override { return format_; }
  std::string deviceName() const override;
  int outputLatencyFrames() const override { return output_latency_frames_; }
  int roundTripLatencyFrames() const override { return round_trip_latency_frames_; }

  // Called from the CoreAudio property listener thread (non-RT).
  void handleDefaultDeviceChanged();
  void handleDeviceLost();

  // Called from the CoreAudio render thread by the file-local trampoline in the
  // implementation. Planar float32, already zeroed. This is the last hop before
  // engine code: allocation-free from here down.
  void handleRender(float* const* channels, int num_channels,
                    int num_frames) noexcept OB_NONBLOCKING;

 private:
  struct Impl;  // holds the Apple types, so they never appear in this header

  bool openDevice(uint32_t device_id, const StreamFormat& requested, StreamFormat& granted,
                  std::string& error);
  void reopenOnDefaultDevice();

  std::unique_ptr<Impl> impl_;
  StreamFormat format_;
  std::atomic<bool> running_{false};
  std::atomic<bool> reopening_{false};
  int output_latency_frames_ = 0;
  int round_trip_latency_frames_ = 0;
  mutable std::mutex state_mutex_;
  std::string device_name_;
};

}  // namespace onebeat::audio_io
