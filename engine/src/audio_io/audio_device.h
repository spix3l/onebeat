// The audio I/O seam (FR-ENG-08, NFR-11).
//
// Pure C++: no Apple types, no CoreAudio headers, nothing platform-specific may
// appear in this file or in any engine code that includes it. The CoreAudio
// implementation lives behind it in audio_io/coreaudio/ and is the only place
// in the engine allowed to include CoreAudio headers — CI greps for this
// (tools/seam_check.sh). WASAPI and ALSA in v2 are new files here, not edits
// to the engine.
#pragma once

#include <cstdint>
#include <functional>
#include <memory>
#include <string>
#include <vector>

#include "core/rt/rt.h"

namespace onebeat::audio_io {

struct DeviceInfo {
  std::string id;
  std::string name;
  int max_output_channels = 0;
  std::vector<double> sample_rates;
  int min_block_frames = 64;
  int max_block_frames = 2048;
  bool is_default_output = false;
};

struct StreamFormat {
  double sample_rate = 48000.0;
  int block_frames = 512;
  int output_channels = 2;
};

// What the backend hands the engine on the audio thread. Planar float32: this
// is what CoreAudio gives us natively and what the engine wants natively, so
// there is no interleave step anywhere in the RT path.
struct RenderBlock {
  float* const* outputs = nullptr;
  int num_channels = 0;
  int num_frames = 0;
  uint64_t stream_time_frames = 0;
  uint64_t host_time_ns = 0;
};

// Implemented by the engine. Called on the platform's real-time thread.
class RenderCallback {
 public:
  virtual ~RenderCallback() = default;
  virtual void renderAudio(const RenderBlock& block) noexcept OB_NONBLOCKING = 0;
};

enum class DeviceNotification {
  DeviceLost,            // the open device disappeared; the backend fell back
  DefaultDeviceChanged,  // the system default changed
  FormatChanged          // sample rate or granted block size changed
};

// Always delivered on a non-real-time thread. Implementations must never touch
// RT state from here — post to the engine's event queue instead.
using NotificationCallback = std::function<void(DeviceNotification, const std::string& detail)>;

class AudioDevice {
 public:
  virtual ~AudioDevice() = default;

  virtual std::vector<DeviceInfo> enumerateOutputDevices() = 0;

  // Opens the default output device. `granted` reports what the device actually
  // gave us, which may differ from `requested` (FR-ENG-02).
  virtual bool open(const StreamFormat& requested, StreamFormat& granted, std::string& error) = 0;
  virtual void close() = 0;
  virtual bool start(std::string& error) = 0;
  virtual void stop() = 0;
  virtual bool isRunning() const = 0;

  virtual StreamFormat format() const = 0;
  virtual std::string deviceName() const = 0;

  // Latency in frames at the current format. Round-trip includes the device's
  // own safety offset, which is what the user actually hears (FR-ENG-02).
  virtual int outputLatencyFrames() const = 0;
  virtual int roundTripLatencyFrames() const = 0;

  void setRenderCallback(RenderCallback* callback) { render_callback_ = callback; }
  void setNotificationCallback(NotificationCallback callback) {
    notification_callback_ = std::move(callback);
  }

 protected:
  void notify(DeviceNotification notification, const std::string& detail) const {
    if (notification_callback_) {
      notification_callback_(notification, detail);
    }
  }

  RenderCallback* render_callback_ = nullptr;

 private:
  NotificationCallback notification_callback_;
};

// Platform factory. Implemented per platform; on macOS in audio_io/coreaudio/.
std::unique_ptr<AudioDevice> createPlatformAudioDevice();

// Headless backend for tests, CI and the offline render driver. No hardware.
std::unique_ptr<AudioDevice> createNullAudioDevice(bool free_running);

}  // namespace onebeat::audio_io
