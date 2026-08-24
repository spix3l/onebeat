#include "audio_io/wasapi/wasapi_device.h"

// These three groups are separate blocks on purpose: clang-format sorts within
// a block, and the alphabetical order is the broken one here. <windows.h> has
// to be first, and <mmdeviceapi.h> pulls in the propsys header that defines
// DEFINE_PROPERTYKEY, which <functiondiscoverykeys_devpkey.h> is nothing but a
// long list of uses of. Sorted together, the property keys expand before the
// macro exists and every one of them is an undeclared identifier.
#define NOMINMAX
#include <windows.h>

#include <mmdeviceapi.h>

#include <audioclient.h>
#include <avrt.h>
#include <functiondiscoverykeys_devpkey.h>
#include <ks.h>
#include <ksmedia.h>

#include <algorithm>
#include <array>
#include <cmath>
#include <cstring>
#include <cwchar>
#include <thread>

#include "core/rt/rt.h"
#include "plugin/plugin_types.h"

namespace onebeat::audio_io {
namespace {

template <typename T>
void releaseCom(T*& value) {
  if (value != nullptr) {
    value->Release();
    value = nullptr;
  }
}

std::string utf8(const wchar_t* value) {
  if (value == nullptr || value[0] == L'\0') return {};
  const int size = WideCharToMultiByte(CP_UTF8, 0, value, -1, nullptr, 0, nullptr, nullptr);
  if (size <= 1) return {};
  std::string result(static_cast<size_t>(size), '\0');
  WideCharToMultiByte(CP_UTF8, 0, value, -1, result.data(), size, nullptr, nullptr);
  result.resize(static_cast<size_t>(size - 1));
  return result;
}

std::string friendlyName(IMMDevice* device) {
  IPropertyStore* properties = nullptr;
  if (FAILED(device->OpenPropertyStore(STGM_READ, &properties))) return "Windows audio device";
  PROPVARIANT value;
  PropVariantInit(&value);
  const HRESULT read = properties->GetValue(PKEY_Device_FriendlyName, &value);
  const std::string result =
      SUCCEEDED(read) && value.vt == VT_LPWSTR ? utf8(value.pwszVal) : "Windows audio device";
  PropVariantClear(&value);
  properties->Release();
  return result;
}

WAVEFORMATEXTENSIBLE floatFormat(double sample_rate, int channels) {
  WAVEFORMATEXTENSIBLE format{};
  format.Format.wFormatTag = WAVE_FORMAT_EXTENSIBLE;
  format.Format.nChannels = static_cast<WORD>(channels);
  format.Format.nSamplesPerSec = static_cast<DWORD>(std::lround(sample_rate));
  format.Format.wBitsPerSample = 32;
  format.Format.nBlockAlign = static_cast<WORD>(channels * 4);
  format.Format.nAvgBytesPerSec = format.Format.nSamplesPerSec * format.Format.nBlockAlign;
  format.Format.cbSize = sizeof(WAVEFORMATEXTENSIBLE) - sizeof(WAVEFORMATEX);
  format.Samples.wValidBitsPerSample = 32;
  format.dwChannelMask =
      channels == 1 ? SPEAKER_FRONT_CENTER : SPEAKER_FRONT_LEFT | SPEAKER_FRONT_RIGHT;
  format.SubFormat = KSDATAFORMAT_SUBTYPE_IEEE_FLOAT;
  return format;
}

}  // namespace

struct WasapiDevice::Impl {
  IMMDeviceEnumerator* enumerator = nullptr;
  IMMDevice* device = nullptr;
  IAudioClient* client = nullptr;
  IAudioRenderClient* renderer = nullptr;
  HANDLE event = nullptr;
  std::thread thread;
  UINT32 buffer_frames = 0;
  uint64_t stream_time_frames = 0;
  std::array<std::vector<float>, 2> planar;
  std::array<float*, 2> planar_ptrs{};
  bool com_initialized = false;
};

WasapiDevice::WasapiDevice() : impl_(std::make_unique<Impl>()) {}

WasapiDevice::~WasapiDevice() {
  stop();
  close();
}

std::vector<DeviceInfo> WasapiDevice::enumerateOutputDevices() {
  const HRESULT initialized = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
  const bool uninitialize = SUCCEEDED(initialized);
  IMMDeviceEnumerator* enumerator = nullptr;
  IMMDeviceCollection* collection = nullptr;
  std::vector<DeviceInfo> devices;
  if (SUCCEEDED(CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr, CLSCTX_ALL,
                                 IID_PPV_ARGS(&enumerator))) &&
      SUCCEEDED(enumerator->EnumAudioEndpoints(eRender, DEVICE_STATE_ACTIVE, &collection))) {
    IMMDevice* default_device = nullptr;
    LPWSTR default_id = nullptr;
    if (SUCCEEDED(enumerator->GetDefaultAudioEndpoint(eRender, eConsole, &default_device))) {
      default_device->GetId(&default_id);
    }
    UINT count = 0;
    collection->GetCount(&count);
    for (UINT index = 0; index < count; ++index) {
      IMMDevice* device = nullptr;
      LPWSTR id = nullptr;
      if (FAILED(collection->Item(index, &device)) || FAILED(device->GetId(&id))) {
        releaseCom(device);
        continue;
      }
      DeviceInfo info;
      info.id = utf8(id);
      info.name = friendlyName(device);
      info.max_output_channels = 2;
      info.sample_rates = {44100.0, 48000.0, 88200.0, 96000.0};
      info.is_default_output = default_id != nullptr && std::wcscmp(id, default_id) == 0;
      devices.push_back(std::move(info));
      CoTaskMemFree(id);
      device->Release();
    }
    if (default_id != nullptr) CoTaskMemFree(default_id);
    releaseCom(default_device);
  }
  releaseCom(collection);
  releaseCom(enumerator);
  if (uninitialize) CoUninitialize();
  return devices;
}

bool WasapiDevice::open(const StreamFormat& requested, StreamFormat& granted, std::string& error) {
  close();
  const HRESULT initialized = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
  if (FAILED(initialized) && initialized != RPC_E_CHANGED_MODE) {
    error = "Windows could not initialise its audio services.";
    return false;
  }
  impl_->com_initialized = SUCCEEDED(initialized);
  if (FAILED(CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr, CLSCTX_ALL,
                              IID_PPV_ARGS(&impl_->enumerator))) ||
      FAILED(impl_->enumerator->GetDefaultAudioEndpoint(eRender, eConsole, &impl_->device)) ||
      FAILED(impl_->device->Activate(__uuidof(IAudioClient), CLSCTX_ALL, nullptr,
                                     reinterpret_cast<void**>(&impl_->client)))) {
    error = "No Windows output device is available.";
    close();
    return false;
  }

  StreamFormat wanted = requested;
  wanted.sample_rate = wanted.sample_rate > 0.0 ? wanted.sample_rate : 48000.0;
  wanted.block_frames = std::clamp(wanted.block_frames > 0 ? wanted.block_frames : 512, 64, 2048);
  wanted.output_channels = 2;
  WAVEFORMATEXTENSIBLE format = floatFormat(wanted.sample_rate, wanted.output_channels);
  WAVEFORMATEX* closest = nullptr;
  HRESULT support =
      impl_->client->IsFormatSupported(AUDCLNT_SHAREMODE_SHARED, &format.Format, &closest);
  if (support != S_OK) {
    if (closest != nullptr && closest->wFormatTag == WAVE_FORMAT_EXTENSIBLE &&
        IsEqualGUID(reinterpret_cast<WAVEFORMATEXTENSIBLE*>(closest)->SubFormat,
                    KSDATAFORMAT_SUBTYPE_IEEE_FLOAT) &&
        closest->nChannels >= 2) {
      wanted.sample_rate = static_cast<double>(closest->nSamplesPerSec);
      format = floatFormat(wanted.sample_rate, wanted.output_channels);
    } else {
      if (closest != nullptr) CoTaskMemFree(closest);
      error = "The default Windows device does not support shared-mode float audio.";
      close();
      return false;
    }
  }
  if (closest != nullptr) CoTaskMemFree(closest);

  const REFERENCE_TIME duration = static_cast<REFERENCE_TIME>(
      std::ceil(10000000.0 * static_cast<double>(wanted.block_frames) / wanted.sample_rate));
  if (FAILED(impl_->client->Initialize(
          AUDCLNT_SHAREMODE_SHARED,
          AUDCLNT_STREAMFLAGS_EVENTCALLBACK | AUDCLNT_STREAMFLAGS_NOPERSIST, duration, 0,
          &format.Format, nullptr)) ||
      FAILED(impl_->client->GetBufferSize(&impl_->buffer_frames))) {
    error = "The default Windows output device could not be opened.";
    close();
    return false;
  }
  impl_->event = CreateEventW(nullptr, FALSE, FALSE, nullptr);
  if (impl_->event == nullptr || FAILED(impl_->client->SetEventHandle(impl_->event)) ||
      FAILED(impl_->client->GetService(IID_PPV_ARGS(&impl_->renderer)))) {
    error = "Windows could not create the audio render callback.";
    close();
    return false;
  }

  for (auto& channel : impl_->planar) channel.resize(impl_->buffer_frames);
  impl_->planar_ptrs = {impl_->planar[0].data(), impl_->planar[1].data()};
  wanted.block_frames = static_cast<int>(impl_->buffer_frames);
  format_ = wanted;
  granted = wanted;
  output_latency_frames_ = wanted.block_frames;
  impl_->stream_time_frames = 0;
  {
    std::lock_guard<std::mutex> lock(state_mutex_);
    device_name_ = friendlyName(impl_->device);
  }
  return true;
}

void WasapiDevice::close() {
  stop();
  releaseCom(impl_->renderer);
  releaseCom(impl_->client);
  releaseCom(impl_->device);
  releaseCom(impl_->enumerator);
  if (impl_->event != nullptr) {
    CloseHandle(impl_->event);
    impl_->event = nullptr;
  }
  if (impl_->com_initialized) {
    CoUninitialize();
    impl_->com_initialized = false;
  }
}

bool WasapiDevice::start(std::string& error) {
  if (impl_->client == nullptr || impl_->renderer == nullptr) {
    error = "The Windows audio device is not open.";
    return false;
  }
  if (running_.load(std::memory_order_acquire)) return true;
  running_.store(true, std::memory_order_release);
  impl_->thread = std::thread(&WasapiDevice::renderLoop, this);
  if (FAILED(impl_->client->Start())) {
    running_.store(false, std::memory_order_release);
    SetEvent(impl_->event);
    impl_->thread.join();
    error = "The Windows audio device refused to start.";
    return false;
  }
  return true;
}

void WasapiDevice::stop() {
  if (!running_.exchange(false, std::memory_order_acq_rel)) return;
  if (impl_->event != nullptr) SetEvent(impl_->event);
  if (impl_->thread.joinable()) impl_->thread.join();
  if (impl_->client != nullptr) {
    impl_->client->Stop();
    impl_->client->Reset();
  }
}

std::string WasapiDevice::deviceName() const {
  std::lock_guard<std::mutex> lock(state_mutex_);
  return device_name_;
}

void WasapiDevice::renderLoop() noexcept {
  CoInitializeEx(nullptr, COINIT_MULTITHREADED);
  DWORD task_index = 0;
  HANDLE task = AvSetMmThreadCharacteristicsW(L"Pro Audio", &task_index);
  rt::enableFlushToZero();
  plugin::ThreadCheck::enterAudioThread();
  while (running_.load(std::memory_order_acquire)) {
    if (WaitForSingleObject(impl_->event, 2000) != WAIT_OBJECT_0) continue;
    if (!running_.load(std::memory_order_acquire)) break;
    UINT32 padding = 0;
    if (FAILED(impl_->client->GetCurrentPadding(&padding))) continue;
    const UINT32 frames = impl_->buffer_frames - padding;
    if (frames == 0) continue;
    BYTE* bytes = nullptr;
    if (FAILED(impl_->renderer->GetBuffer(frames, &bytes))) continue;
    for (int channel = 0; channel < 2; ++channel) {
      std::fill_n(impl_->planar[static_cast<size_t>(channel)].data(), frames, 0.0F);
    }
    if (render_callback_ != nullptr) {
      const RenderBlock block{impl_->planar_ptrs.data(), 2, static_cast<int>(frames),
                              impl_->stream_time_frames, rt::monotonicNanos()};
      render_callback_->renderAudio(block);
    }
    auto* interleaved = reinterpret_cast<float*>(bytes);
    for (UINT32 frame = 0; frame < frames; ++frame) {
      interleaved[frame * 2] = impl_->planar[0][frame];
      interleaved[frame * 2 + 1] = impl_->planar[1][frame];
    }
    impl_->renderer->ReleaseBuffer(frames, 0);
    impl_->stream_time_frames += frames;
  }
  plugin::ThreadCheck::leaveAudioThread();
  if (task != nullptr) AvRevertMmThreadCharacteristics(task);
  CoUninitialize();
}

std::unique_ptr<AudioDevice> createPlatformAudioDevice() {
  return std::make_unique<WasapiDevice>();
}

}  // namespace onebeat::audio_io
