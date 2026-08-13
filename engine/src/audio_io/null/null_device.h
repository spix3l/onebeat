// Null audio backend (OB-1-05 §3).
//
// Two modes:
//   free-running — a timed thread calls the engine at roughly real time, so the
//                  full engine (including the soak and stress tests) runs in CI
//                  on machines with no audio hardware;
//   on-demand    — renderOnce() drives exactly one block, which is how the
//                  offline driver (OB-1-13) renders faster than real time
//                  through the *same* Engine::process path.
#pragma once

#include <atomic>
#include <thread>
#include <vector>

#include "audio_io/audio_device.h"

namespace onebeat::audio_io {

class NullAudioDevice final : public AudioDevice {
 public:
  explicit NullAudioDevice(bool free_running) : free_running_(free_running) {}
  ~NullAudioDevice() override;

  std::vector<DeviceInfo> enumerateOutputDevices() override;
  bool open(const StreamFormat& requested, StreamFormat& granted, std::string& error) override;
  void close() override;
  bool start(std::string& error) override;
  void stop() override;
  bool isRunning() const override { return running_.load(std::memory_order_acquire); }

  StreamFormat format() const override { return format_; }
  std::string deviceName() const override { return "Null Output (headless)"; }
  int outputLatencyFrames() const override { return format_.block_frames; }
  int roundTripLatencyFrames() const override { return format_.block_frames * 2; }

  // On-demand mode: render exactly one block of `frames` (<= block_frames).
  // Returns planar output channels valid until the next call.
  const std::vector<float*>& renderOnce(int frames);

  uint64_t blocksRendered() const { return blocks_.load(std::memory_order_relaxed); }

 private:
  void renderBlock(int frames);
  void threadMain();

  bool free_running_;
  StreamFormat format_;
  std::vector<float> storage_;
  std::vector<float*> channels_;
  std::atomic<bool> running_{false};
  std::atomic<uint64_t> blocks_{0};
  uint64_t stream_time_frames_ = 0;
  std::thread thread_;
};

}  // namespace onebeat::audio_io
