#include "audio_io/coreaudio/coreaudio_device.h"

#include <AudioToolbox/AudioToolbox.h>
#include <CoreAudio/CoreAudio.h>
#include <CoreFoundation/CoreFoundation.h>

#include <algorithm>
#include <array>
#include <chrono>
#include <cmath>
#include <thread>

#include "core/rt/rt.h"

namespace onebeat::audio_io {
namespace {

constexpr int MaxRenderChannels = 8;

AudioObjectPropertyAddress addressOf(AudioObjectPropertySelector selector,
                                     AudioObjectPropertyScope scope) {
  return AudioObjectPropertyAddress{selector, scope, kAudioObjectPropertyElementMain};
}

std::string cfStringToUtf8(CFStringRef string) {
  if (string == nullptr) {
    return {};
  }
  const CFIndex length = CFStringGetLength(string);
  const CFIndex max_bytes = CFStringGetMaximumSizeForEncoding(length, kCFStringEncodingUTF8) + 1;
  std::string out(static_cast<size_t>(max_bytes), '\0');
  if (CFStringGetCString(string, out.data(), max_bytes, kCFStringEncodingUTF8) == 0) {
    return {};
  }
  out.resize(std::char_traits<char>::length(out.c_str()));
  return out;
}

std::string deviceNameFor(AudioObjectID device) {
  CFStringRef name = nullptr;
  UInt32 size = sizeof(name);
  auto address = addressOf(kAudioObjectPropertyName, kAudioObjectPropertyScopeGlobal);
  if (AudioObjectGetPropertyData(device, &address, 0, nullptr, &size, &name) != noErr) {
    return "Unknown device";
  }
  std::string result = cfStringToUtf8(name);
  if (name != nullptr) {
    CFRelease(name);
  }
  return result.empty() ? "Unknown device" : result;
}

AudioObjectID defaultOutputDevice() {
  AudioObjectID device = kAudioObjectUnknown;
  UInt32 size = sizeof(device);
  auto address =
      addressOf(kAudioHardwarePropertyDefaultOutputDevice, kAudioObjectPropertyScopeGlobal);
  AudioObjectGetPropertyData(kAudioObjectSystemObject, &address, 0, nullptr, &size, &device);
  return device;
}

int outputChannelCount(AudioObjectID device) {
  auto address =
      addressOf(kAudioDevicePropertyStreamConfiguration, kAudioDevicePropertyScopeOutput);
  UInt32 size = 0;
  if (AudioObjectGetPropertyDataSize(device, &address, 0, nullptr, &size) != noErr || size == 0) {
    return 0;
  }
  std::vector<uint8_t> storage(size);
  auto* list = reinterpret_cast<AudioBufferList*>(storage.data());
  if (AudioObjectGetPropertyData(device, &address, 0, nullptr, &size, list) != noErr) {
    return 0;
  }
  int channels = 0;
  for (UInt32 index = 0; index < list->mNumberBuffers; ++index) {
    channels += static_cast<int>(list->mBuffers[index].mNumberChannels);
  }
  return channels;
}

std::vector<double> supportedSampleRates(AudioObjectID device) {
  auto address =
      addressOf(kAudioDevicePropertyAvailableNominalSampleRates, kAudioDevicePropertyScopeOutput);
  UInt32 size = 0;
  if (AudioObjectGetPropertyDataSize(device, &address, 0, nullptr, &size) != noErr || size == 0) {
    return {44100.0, 48000.0};
  }
  std::vector<AudioValueRange> ranges(size / sizeof(AudioValueRange));
  if (AudioObjectGetPropertyData(device, &address, 0, nullptr, &size, ranges.data()) != noErr) {
    return {44100.0, 48000.0};
  }
  std::vector<double> rates;
  for (const AudioValueRange& range : ranges) {
    for (const double candidate : {44100.0, 48000.0, 88200.0, 96000.0}) {
      if (candidate >= range.mMinimum - 1.0 && candidate <= range.mMaximum + 1.0 &&
          std::find(rates.begin(), rates.end(), candidate) == rates.end()) {
        rates.push_back(candidate);
      }
    }
  }
  if (rates.empty()) {
    rates.push_back(48000.0);
  }
  return rates;
}

// CoreAudio applies a nominal-rate change asynchronously. Reading the rate back
// immediately returns the *old* value, and then the buffer size we set lands on
// a device that is still switching — which is how a 44.1 kHz request ends up
// reported as 48 kHz with a 69-frame buffer. Wait for the device to settle.
bool waitForSampleRate(AudioObjectID device, double target) {
  auto address = addressOf(kAudioDevicePropertyNominalSampleRate, kAudioObjectPropertyScopeGlobal);
  for (int attempt = 0; attempt < 100; ++attempt) {
    Float64 current = 0.0;
    UInt32 size = sizeof(current);
    if (AudioObjectGetPropertyData(device, &address, 0, nullptr, &size, &current) == noErr &&
        std::abs(static_cast<double>(current) - target) < 1.0) {
      return true;
    }
    std::this_thread::sleep_for(std::chrono::milliseconds(20));
  }
  return false;
}

UInt32 deviceUInt32(AudioObjectID device, AudioObjectPropertySelector selector) {
  UInt32 value = 0;
  UInt32 size = sizeof(value);
  auto address = addressOf(selector, kAudioDevicePropertyScopeOutput);
  AudioObjectGetPropertyData(device, &address, 0, nullptr, &size, &value);
  return value;
}

}  // namespace

// Every Apple type in the backend is confined to this struct.
struct CoreAudioDevice::Impl {
  AudioUnit unit = nullptr;
  AudioObjectID device = kAudioObjectUnknown;
  CoreAudioDevice* owner = nullptr;
  bool listeners_installed = false;
  bool flush_to_zero_set = false;
  uint64_t stream_time_frames = 0;
};

namespace {

OSStatus defaultDeviceListener(AudioObjectID /*object*/, UInt32 /*count*/,
                               const AudioObjectPropertyAddress* /*addresses*/, void* context) {
  static_cast<CoreAudioDevice*>(context)->handleDefaultDeviceChanged();
  return noErr;
}

OSStatus deviceAliveListener(AudioObjectID /*object*/, UInt32 /*count*/,
                             const AudioObjectPropertyAddress* /*addresses*/, void* context) {
  static_cast<CoreAudioDevice*>(context)->handleDeviceLost();
  return noErr;
}

// The last non-engine frame on the audio thread: unpack CoreAudio's buffer list
// into planar pointers, zero them, and hand off. No allocation, no locks.
// AURenderCallback is itself declared nonblocking by the SDK, so the attribute
// here is required, not decorative: it makes the compiler check this hop too.
OSStatus renderTrampoline(void* context, AudioUnitRenderActionFlags* /*flags*/,
                          const AudioTimeStamp* /*timestamp*/, UInt32 /*bus*/, UInt32 frame_count,
                          AudioBufferList* buffers) noexcept OB_NONBLOCKING {
  std::array<float*, MaxRenderChannels> channels{};
  const UInt32 channel_count =
      std::min<UInt32>(buffers->mNumberBuffers, static_cast<UInt32>(MaxRenderChannels));
  for (UInt32 index = 0; index < channel_count; ++index) {
    channels[index] = static_cast<float*>(buffers->mBuffers[index].mData);
    for (UInt32 frame = 0; frame < frame_count; ++frame) {
      channels[index][frame] = 0.0F;
    }
  }
  static_cast<CoreAudioDevice*>(context)->handleRender(
      channels.data(), static_cast<int>(channel_count), static_cast<int>(frame_count));
  return noErr;
}

}  // namespace

CoreAudioDevice::CoreAudioDevice() : impl_(std::make_unique<Impl>()) {
  impl_->owner = this;
}

CoreAudioDevice::~CoreAudioDevice() {
  stop();
  close();
}

std::string CoreAudioDevice::deviceName() const {
  std::lock_guard<std::mutex> lock(state_mutex_);
  return device_name_;
}

std::vector<DeviceInfo> CoreAudioDevice::enumerateOutputDevices() {
  auto address = addressOf(kAudioHardwarePropertyDevices, kAudioObjectPropertyScopeGlobal);
  UInt32 size = 0;
  if (AudioObjectGetPropertyDataSize(kAudioObjectSystemObject, &address, 0, nullptr, &size) !=
      noErr) {
    return {};
  }
  std::vector<AudioObjectID> devices(size / sizeof(AudioObjectID));
  if (AudioObjectGetPropertyData(kAudioObjectSystemObject, &address, 0, nullptr, &size,
                                 devices.data()) != noErr) {
    return {};
  }

  const AudioObjectID default_device = defaultOutputDevice();
  std::vector<DeviceInfo> result;
  for (const AudioObjectID device : devices) {
    const int channels = outputChannelCount(device);
    if (channels <= 0) {
      continue;  // input-only device
    }
    DeviceInfo info;
    info.id = std::to_string(device);
    info.name = deviceNameFor(device);
    info.max_output_channels = channels;
    info.sample_rates = supportedSampleRates(device);
    info.is_default_output = device == default_device;
    result.push_back(std::move(info));
  }
  return result;
}

bool CoreAudioDevice::open(const StreamFormat& requested, StreamFormat& granted,
                           std::string& error) {
  const AudioObjectID device = defaultOutputDevice();
  if (device == kAudioObjectUnknown) {
    error = "No output device is available. Connect an output device and try again.";
    return false;
  }
  return openDevice(device, requested, granted, error);
}

bool CoreAudioDevice::openDevice(uint32_t device_id, const StreamFormat& requested,
                                 StreamFormat& granted, std::string& error) {
  close();

  const auto device = static_cast<AudioObjectID>(device_id);
  impl_->device = device;

  StreamFormat wanted = requested;
  if (wanted.sample_rate <= 0.0) {
    wanted.sample_rate = 48000.0;
  }
  if (wanted.block_frames <= 0) {
    wanted.block_frames = 512;
  }
  wanted.block_frames = std::clamp(wanted.block_frames, 64, 2048);
  wanted.output_channels = 2;

  // Ask the device for the rate and buffer size; it decides, we report back.
  {
    Float64 rate = wanted.sample_rate;
    auto address =
        addressOf(kAudioDevicePropertyNominalSampleRate, kAudioObjectPropertyScopeGlobal);
    AudioObjectSetPropertyData(device, &address, 0, nullptr, sizeof(rate), &rate);
    waitForSampleRate(device, wanted.sample_rate);
    UInt32 size = sizeof(rate);
    if (AudioObjectGetPropertyData(device, &address, 0, nullptr, &size, &rate) == noErr) {
      wanted.sample_rate = static_cast<double>(rate);
    }
  }
  {
    auto frames = static_cast<UInt32>(wanted.block_frames);
    auto address = addressOf(kAudioDevicePropertyBufferFrameSize, kAudioDevicePropertyScopeOutput);
    AudioObjectSetPropertyData(device, &address, 0, nullptr, sizeof(frames), &frames);
    UInt32 size = sizeof(frames);
    if (AudioObjectGetPropertyData(device, &address, 0, nullptr, &size, &frames) == noErr) {
      wanted.block_frames = static_cast<int>(frames);
    }
  }

  AudioComponentDescription description{};
  description.componentType = kAudioUnitType_Output;
  description.componentSubType = kAudioUnitSubType_HALOutput;
  description.componentManufacturer = kAudioUnitManufacturer_Apple;
  AudioComponent component = AudioComponentFindNext(nullptr, &description);
  if (component == nullptr) {
    error = "The system audio component could not be found.";
    return false;
  }
  if (AudioComponentInstanceNew(component, &impl_->unit) != noErr || impl_->unit == nullptr) {
    error = "The system audio unit could not be created.";
    return false;
  }

  UInt32 enable = 1;
  AudioUnitSetProperty(impl_->unit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output, 0,
                       &enable, sizeof(enable));
  UInt32 disable = 0;
  AudioUnitSetProperty(impl_->unit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, 1,
                       &disable, sizeof(disable));

  if (AudioUnitSetProperty(impl_->unit, kAudioOutputUnitProperty_CurrentDevice,
                           kAudioUnitScope_Global, 0, &impl_->device,
                           sizeof(impl_->device)) != noErr) {
    error = "The output device could not be selected.";
    close();
    return false;
  }

  AudioStreamBasicDescription asbd{};
  asbd.mSampleRate = wanted.sample_rate;
  asbd.mFormatID = kAudioFormatLinearPCM;
  asbd.mFormatFlags =
      kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked | kAudioFormatFlagIsNonInterleaved;
  asbd.mFramesPerPacket = 1;
  asbd.mChannelsPerFrame = static_cast<UInt32>(wanted.output_channels);
  asbd.mBitsPerChannel = 32;
  asbd.mBytesPerFrame = 4;
  asbd.mBytesPerPacket = 4;
  if (AudioUnitSetProperty(impl_->unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0,
                           &asbd, sizeof(asbd)) != noErr) {
    error = "This device does not support 32-bit float output at the requested rate.";
    close();
    return false;
  }

  auto max_frames = static_cast<UInt32>(wanted.block_frames);
  AudioUnitSetProperty(impl_->unit, kAudioUnitProperty_MaximumFramesPerSlice,
                       kAudioUnitScope_Global, 0, &max_frames, sizeof(max_frames));

  AURenderCallbackStruct callback{};
  callback.inputProc = &renderTrampoline;
  callback.inputProcRefCon = this;
  if (AudioUnitSetProperty(impl_->unit, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input,
                           0, &callback, sizeof(callback)) != noErr) {
    error = "The render callback could not be installed.";
    close();
    return false;
  }

  if (AudioUnitInitialize(impl_->unit) != noErr) {
    error = "The audio unit could not be initialised.";
    close();
    return false;
  }

  const auto device_latency = static_cast<int>(deviceUInt32(device, kAudioDevicePropertyLatency));
  const auto safety_offset =
      static_cast<int>(deviceUInt32(device, kAudioDevicePropertySafetyOffset));
  output_latency_frames_ = wanted.block_frames + device_latency + safety_offset;
  // Output-only in v0.1; input latency joins this when recording lands (FR-AUD-01).
  round_trip_latency_frames_ = output_latency_frames_;

  {
    std::lock_guard<std::mutex> lock(state_mutex_);
    device_name_ = deviceNameFor(device);
  }

  if (!impl_->listeners_installed) {
    auto default_address =
        addressOf(kAudioHardwarePropertyDefaultOutputDevice, kAudioObjectPropertyScopeGlobal);
    AudioObjectAddPropertyListener(kAudioObjectSystemObject, &default_address,
                                   &defaultDeviceListener, this);
    auto alive_address =
        addressOf(kAudioDevicePropertyDeviceIsAlive, kAudioObjectPropertyScopeGlobal);
    AudioObjectAddPropertyListener(device, &alive_address, &deviceAliveListener, this);
    impl_->listeners_installed = true;
  }

  format_ = wanted;
  granted = wanted;
  impl_->stream_time_frames = 0;
  impl_->flush_to_zero_set = false;
  return true;
}

void CoreAudioDevice::close() {
  if (impl_->listeners_installed) {
    auto default_address =
        addressOf(kAudioHardwarePropertyDefaultOutputDevice, kAudioObjectPropertyScopeGlobal);
    AudioObjectRemovePropertyListener(kAudioObjectSystemObject, &default_address,
                                      &defaultDeviceListener, this);
    auto alive_address =
        addressOf(kAudioDevicePropertyDeviceIsAlive, kAudioObjectPropertyScopeGlobal);
    AudioObjectRemovePropertyListener(impl_->device, &alive_address, &deviceAliveListener, this);
    impl_->listeners_installed = false;
  }
  if (impl_->unit != nullptr) {
    AudioUnitUninitialize(impl_->unit);
    AudioComponentInstanceDispose(impl_->unit);
    impl_->unit = nullptr;
  }
  impl_->device = kAudioObjectUnknown;
}

bool CoreAudioDevice::start(std::string& error) {
  if (impl_->unit == nullptr) {
    error = "The audio device is not open.";
    return false;
  }
  if (running_.load(std::memory_order_acquire)) {
    return true;
  }
  if (AudioOutputUnitStart(impl_->unit) != noErr) {
    error = "The audio device refused to start. Another application may have exclusive use of it.";
    return false;
  }
  running_.store(true, std::memory_order_release);
  return true;
}

void CoreAudioDevice::stop() {
  if (!running_.exchange(false)) {
    return;
  }
  if (impl_->unit != nullptr) {
    AudioOutputUnitStop(impl_->unit);
  }
}

void CoreAudioDevice::handleDefaultDeviceChanged() {
  const AudioObjectID current = impl_->device;
  const AudioObjectID next = defaultOutputDevice();
  if (next == kAudioObjectUnknown || next == current) {
    return;
  }
  reopenOnDefaultDevice();
  notify(DeviceNotification::DefaultDeviceChanged, deviceName());
}

void CoreAudioDevice::handleDeviceLost() {
  const std::string lost = deviceName();
  reopenOnDefaultDevice();
  notify(DeviceNotification::DeviceLost, lost);
}

// Runs on a CoreAudio property-listener thread, never on the RT thread.
void CoreAudioDevice::reopenOnDefaultDevice() {
  if (reopening_.exchange(true)) {
    return;
  }
  const bool was_running = running_.load(std::memory_order_acquire);
  const StreamFormat wanted = format_;
  stop();
  close();

  StreamFormat granted;
  std::string error;
  const AudioObjectID device = defaultOutputDevice();
  if (device != kAudioObjectUnknown && openDevice(device, wanted, granted, error)) {
    if (granted.sample_rate != wanted.sample_rate || granted.block_frames != wanted.block_frames) {
      notify(DeviceNotification::FormatChanged, deviceName());
    }
    if (was_running) {
      std::string start_error;
      start(start_error);
    }
  }
  reopening_.store(false, std::memory_order_release);
}

void CoreAudioDevice::handleRender(float* const* channels, int num_channels,
                                   int num_frames) noexcept OB_NONBLOCKING {
  if (!impl_->flush_to_zero_set) {
    rt::enableFlushToZero();
    impl_->flush_to_zero_set = true;
  }
  if (render_callback_ != nullptr && num_channels > 0) {
    RenderBlock block;
    block.outputs = channels;
    block.num_channels = num_channels;
    block.num_frames = num_frames;
    block.stream_time_frames = impl_->stream_time_frames;
    block.host_time_ns = rt::monotonicNanos();
    render_callback_->renderAudio(block);
  }
  impl_->stream_time_frames += static_cast<uint64_t>(num_frames);
}

std::unique_ptr<AudioDevice> createPlatformAudioDevice() {
  return std::make_unique<CoreAudioDevice>();
}

}  // namespace onebeat::audio_io
