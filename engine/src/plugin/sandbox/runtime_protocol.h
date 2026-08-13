// Fixed-layout host/helper wire format (ADR-003, OB-2-05).
#pragma once

#include <mach/mach.h>

#include <array>
#include <atomic>
#include <cstdint>

#include "plugin/event.h"

namespace onebeat::plugin::sandbox {

inline constexpr uint32_t RuntimeMagic = 0x4F425254;  // OBRT
inline constexpr uint32_t RuntimeVersion = 1;
inline constexpr uint32_t RuntimeMaxFrames = 2048;
inline constexpr uint32_t RuntimeMaxChannels = 2;
inline constexpr uint32_t RuntimeMaxEvents = 2048;
inline constexpr uint32_t RuntimeMaxParams = 1024;
inline constexpr uint32_t RuntimeMaxPorts = 32;
inline constexpr int RuntimeControlFd = 4;
inline constexpr size_t CacheLine = 128;

struct RuntimeParamInfo {
  uint32_t id = InvalidParamId;
  uint32_t flags = 0;
  double min_value = 0.0;
  double max_value = 1.0;
  double default_value = 0.0;
  char name[128]{};
  char module[128]{};
};

struct RuntimePortInfo {
  uint32_t id = InvalidPortId;
  uint32_t channel_count = 0;
  uint32_t flags = 0;
  uint32_t dialects = 0;
  uint32_t preferred_dialect = 0;
  char name[128]{};
};

struct RuntimeShared {
  uint32_t magic = RuntimeMagic;
  uint32_t version = RuntimeVersion;
  uint32_t max_frames = RuntimeMaxFrames;
  uint32_t reserved = 0;
  double sample_rate = 48000.0;
  uint32_t configured_max_frames = 128;
  uint32_t configured_reserved = 0;

  alignas(CacheLine) std::atomic<uint32_t> ready{0};  // 1 ready, 2 failed
  std::atomic<uint32_t> quit{0};
  std::atomic<uint32_t> request{0};
  std::atomic<uint32_t> response{0};

  alignas(CacheLine) uint32_t frames = 0;
  uint32_t input_channels = 0;
  uint32_t output_channels = 0;
  uint32_t event_count = 0;
  int64_t steady_time = -1;
  TransportInfo transport{};
  PluginEvent events[RuntimeMaxEvents]{};

  alignas(CacheLine) float audio_in[RuntimeMaxChannels][RuntimeMaxFrames]{};
  alignas(CacheLine) float audio_out[RuntimeMaxChannels][RuntimeMaxFrames]{};

  alignas(CacheLine) uint32_t param_count = 0;
  uint32_t audio_input_count = 0;
  uint32_t audio_output_count = 0;
  uint32_t note_input_count = 0;
  uint32_t note_output_count = 0;
  uint32_t latency_frames = 0;
  uint32_t has_gui = 0;
  char plugin_name[128]{};
  char error[256]{};
  RuntimeParamInfo params[RuntimeMaxParams]{};
  RuntimePortInfo audio_inputs[RuntimeMaxPorts]{};
  RuntimePortInfo audio_outputs[RuntimeMaxPorts]{};
  RuntimePortInfo note_inputs[RuntimeMaxPorts]{};
  RuntimePortInfo note_outputs[RuntimeMaxPorts]{};
};

enum class ControlCommand : uint32_t {
  GetParam = 1,
  ValueToText = 2,
  TextToValue = 3,
  SaveState = 4,
  LoadState = 5,
  MainThread = 6,
  Shutdown = 7,
  OpenEditor = 8,
  CloseEditor = 9,
};

struct ControlRequest {
  uint32_t magic = RuntimeMagic;
  uint32_t command = 0;
  uint32_t id = 0;
  uint32_t size = 0;
  double value = 0.0;
  char text[128]{};
};

struct ControlResponse {
  uint32_t magic = RuntimeMagic;
  uint32_t ok = 0;
  uint32_t size = 0;
  uint32_t reserved = 0;
  double value = 0.0;
  char text[128]{};
};

struct PortMessage {
  mach_msg_header_t header;
  mach_msg_body_t body;
  mach_msg_port_descriptor_t to_helper;
  mach_msg_port_descriptor_t to_host;
};

struct PortMessageReceive {
  PortMessage message;
  mach_msg_trailer_t trailer;
};

}  // namespace onebeat::plugin::sandbox
