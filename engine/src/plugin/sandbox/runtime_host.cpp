#include "plugin/sandbox/runtime_host.h"

#include <fcntl.h>
#include <mach/mach.h>
#include <mach/mach_time.h>
#include <mach/thread_policy.h>
#include <poll.h>
#include <pthread.h>
#include <sys/mman.h>
#include <unistd.h>

#include <algorithm>
#include <array>
#include <cerrno>
#include <cstring>
#include <memory>
#include <thread>
#include <vector>

#include "core/audio_buffer.h"
#include "plugin/clap/clap_plugin_instance.h"
#include "plugin/host.h"
#include "plugin/sandbox/runtime_protocol.h"
#include "plugin/state.h"

namespace onebeat::plugin::sandbox {
namespace {

bool readAll(int fd, void* data, size_t size) {
  auto* cursor = static_cast<uint8_t*>(data);
  while (size > 0) {
    const ssize_t count = ::read(fd, cursor, size);
    if (count == 0) return false;
    if (count < 0) {
      if (errno == EINTR) continue;
      return false;
    }
    cursor += count;
    size -= static_cast<size_t>(count);
  }
  return true;
}

bool writeAll(int fd, const void* data, size_t size) {
  const auto* cursor = static_cast<const uint8_t*>(data);
  while (size > 0) {
    const ssize_t count = ::write(fd, cursor, size);
    if (count < 0) {
      if (errno == EINTR) continue;
      return false;
    }
    cursor += count;
    size -= static_cast<size_t>(count);
  }
  return true;
}

void copyText(char* destination, size_t capacity, const char* source) {
  if (capacity == 0) return;
  const char* safe = source != nullptr ? source : "";
  const size_t count = std::min(std::strlen(safe), capacity - 1);
  std::memcpy(destination, safe, count);
  destination[count] = '\0';
}

bool publishSemaphores(semaphore_t to_helper, semaphore_t to_host) {
  mach_port_t reply = MACH_PORT_NULL;
  if (::task_get_special_port(mach_task_self(), TASK_BOOTSTRAP_PORT, &reply) != KERN_SUCCESS ||
      reply == MACH_PORT_NULL) {
    return false;
  }
  PortMessage message{};
  message.header.msgh_bits = MACH_MSGH_BITS(MACH_MSG_TYPE_COPY_SEND, 0) | MACH_MSGH_BITS_COMPLEX;
  message.header.msgh_size = sizeof(message);
  message.header.msgh_remote_port = reply;
  message.header.msgh_id = 0x0B205;
  message.body.msgh_descriptor_count = 2;
  message.to_helper.name = to_helper;
  message.to_helper.disposition = MACH_MSG_TYPE_COPY_SEND;
  message.to_helper.type = MACH_MSG_PORT_DESCRIPTOR;
  message.to_host.name = to_host;
  message.to_host.disposition = MACH_MSG_TYPE_COPY_SEND;
  message.to_host.type = MACH_MSG_PORT_DESCRIPTOR;
  return ::mach_msg(&message.header, MACH_SEND_MSG, sizeof(message), 0, MACH_PORT_NULL,
                    MACH_MSG_TIMEOUT_NONE, MACH_PORT_NULL) == MACH_MSG_SUCCESS;
}

uint64_t nanosToTicks(uint64_t nanos) {
  mach_timebase_info_data_t info{};
  mach_timebase_info(&info);
  return nanos * info.denom / info.numer;
}

void makeRealtime(uint32_t frames, double sample_rate) {
  const uint64_t period_nanos =
      static_cast<uint64_t>((static_cast<double>(frames) * 1'000'000'000.0) / sample_rate);
  const uint64_t period = nanosToTicks(period_nanos);
  thread_time_constraint_policy_data_t policy{};
  policy.period = static_cast<uint32_t>(period);
  policy.computation = static_cast<uint32_t>(period / 2U);
  policy.constraint = static_cast<uint32_t>(period);
  policy.preemptible = 0;
  thread_policy_set(pthread_mach_thread_np(pthread_self()), THREAD_TIME_CONSTRAINT_POLICY,
                    reinterpret_cast<thread_policy_t>(&policy),
                    THREAD_TIME_CONSTRAINT_POLICY_COUNT);
}

void fillPort(RuntimePortInfo& target, const AudioPortInfo& source) {
  target.id = source.id;
  target.channel_count = source.channel_count;
  target.flags = (source.is_main ? 1U : 0U) | (source.supports_in_place ? 2U : 0U);
  copyText(target.name, sizeof(target.name), source.name.text());
}

void fillPort(RuntimePortInfo& target, const NotePortInfo& source) {
  target.id = source.id;
  target.dialects = source.supported_dialects;
  target.preferred_dialect = source.preferred_dialect;
  copyText(target.name, sizeof(target.name), source.name.text());
}

}  // namespace

int runRuntimeHost(const std::string& bundle_path, const std::string& plugin_id,
                   const std::string& shared_memory_name) {
  const int descriptor = ::shm_open(shared_memory_name.c_str(), O_RDWR, 0600);
  if (descriptor < 0) return 20;
  void* mapping =
      ::mmap(nullptr, sizeof(RuntimeShared), PROT_READ | PROT_WRITE, MAP_SHARED, descriptor, 0);
  ::close(descriptor);
  if (mapping == MAP_FAILED) return 21;
  auto* shared = static_cast<RuntimeShared*>(mapping);
  if (shared->magic != RuntimeMagic || shared->version != RuntimeVersion) return 22;

  // The helper is its own process with its own ThreadCheck statics, and the
  // engine only registers a main thread in the app process. Register this
  // process's main thread before the plug-in is created so CLAP plug-ins that
  // consult the thread-check extension see `init()` on the main thread.
  ThreadCheck::enterMainThread();

  NullPluginHost host;
  std::string error;
  auto plugin = clap::ClapPluginInstance::create(&host, bundle_path, plugin_id, error);
  if (plugin == nullptr) {
    copyText(shared->error, sizeof(shared->error), error.c_str());
    shared->ready.store(2, std::memory_order_release);
    return 23;
  }

  ProcessSetup setup;
  setup.sample_rate = shared->sample_rate;
  setup.max_block_frames = std::min(shared->configured_max_frames, RuntimeMaxFrames);
  if (!plugin->configure(setup) || !plugin->activate()) {
    copyText(shared->error, sizeof(shared->error), "The plug-in could not be activated.");
    shared->ready.store(2, std::memory_order_release);
    return 24;
  }

  copyText(shared->plugin_name, sizeof(shared->plugin_name), plugin->name().text());
  shared->param_count = std::min(plugin->paramCount(), RuntimeMaxParams);
  for (uint32_t index = 0; index < shared->param_count; ++index) {
    ParamInfo info;
    if (!plugin->paramInfo(index, info)) continue;
    RuntimeParamInfo& target = shared->params[index];
    target.id = info.id;
    target.flags = info.flags;
    target.min_value = info.min_value;
    target.max_value = info.max_value;
    target.default_value = info.default_value;
    copyText(target.name, sizeof(target.name), info.name.text());
    copyText(target.module, sizeof(target.module), info.module.text());
  }
  shared->audio_input_count =
      std::min(plugin->audioPortCount(PortDirection::Input), RuntimeMaxPorts);
  shared->audio_output_count =
      std::min(plugin->audioPortCount(PortDirection::Output), RuntimeMaxPorts);
  shared->note_input_count = std::min(plugin->notePortCount(PortDirection::Input), RuntimeMaxPorts);
  shared->note_output_count =
      std::min(plugin->notePortCount(PortDirection::Output), RuntimeMaxPorts);
  for (uint32_t index = 0; index < shared->audio_input_count; ++index) {
    AudioPortInfo info;
    if (plugin->audioPortInfo(PortDirection::Input, index, info))
      fillPort(shared->audio_inputs[index], info);
  }
  for (uint32_t index = 0; index < shared->audio_output_count; ++index) {
    AudioPortInfo info;
    if (plugin->audioPortInfo(PortDirection::Output, index, info))
      fillPort(shared->audio_outputs[index], info);
  }
  for (uint32_t index = 0; index < shared->note_input_count; ++index) {
    NotePortInfo info;
    if (plugin->notePortInfo(PortDirection::Input, index, info))
      fillPort(shared->note_inputs[index], info);
  }
  for (uint32_t index = 0; index < shared->note_output_count; ++index) {
    NotePortInfo info;
    if (plugin->notePortInfo(PortDirection::Output, index, info))
      fillPort(shared->note_outputs[index], info);
  }
  shared->latency_frames = plugin->latencyFrames();
  shared->has_gui = plugin->guiExtension() != nullptr ? 1U : 0U;

  semaphore_t to_helper = MACH_PORT_NULL;
  semaphore_t to_host = MACH_PORT_NULL;
  if (::semaphore_create(mach_task_self(), &to_helper, SYNC_POLICY_FIFO, 0) != KERN_SUCCESS ||
      ::semaphore_create(mach_task_self(), &to_host, SYNC_POLICY_FIFO, 0) != KERN_SUCCESS ||
      !publishSemaphores(to_helper, to_host)) {
    copyText(shared->error, sizeof(shared->error), "The IPC semaphores could not be created.");
    shared->ready.store(2, std::memory_order_release);
    return 25;
  }

  std::thread audio([&] {
    ThreadCheck::enterAudioThread();
    makeRealtime(128, setup.sample_rate);
    bool processing = false;
    float* input_pointers[RuntimeMaxChannels]{shared->audio_in[0], shared->audio_in[1]};
    float* output_pointers[RuntimeMaxChannels]{shared->audio_out[0], shared->audio_out[1]};
    uint32_t seen = 0;
    while (shared->quit.load(std::memory_order_acquire) == 0) {
      if (::semaphore_wait(to_helper) != KERN_SUCCESS) continue;
      if (shared->quit.load(std::memory_order_acquire) != 0) break;
      const uint32_t request = shared->request.load(std::memory_order_acquire);
      if (request == seen) continue;
      seen = request;
      if (!processing) {
        processing = plugin->startProcessing();
        if (!processing) {
          shared->quit.store(1, std::memory_order_release);
          break;
        }
      }
      const uint32_t frames = std::min(shared->frames, RuntimeMaxFrames);
      const core::AudioBufferView input(input_pointers, static_cast<int>(shared->input_channels),
                                        static_cast<int>(frames));
      const core::AudioBufferView output(output_pointers, static_cast<int>(shared->output_channels),
                                         static_cast<int>(frames));
      ProcessBlock block;
      block.frames = frames;
      block.audio_inputs = &input;
      block.audio_input_count = shared->audio_input_count > 0 ? 1U : 0U;
      block.audio_outputs = &output;
      block.audio_output_count = shared->audio_output_count > 0 ? 1U : 0U;
      block.in_events =
          EventListView(shared->events, std::min(shared->event_count, RuntimeMaxEvents));
      block.transport = shared->transport;
      block.steady_time_frames = shared->steady_time;
      const ProcessStatus status = plugin->process(block);
      if (status == ProcessStatus::Error) output.clear();
      shared->response.store(seen, std::memory_order_release);
      ::semaphore_signal(to_host);
    }
    if (processing) plugin->stopProcessing();
    ThreadCheck::leaveAudioThread();
  });

  shared->ready.store(1, std::memory_order_release);

  bool serving = true;
  bool parent_disconnected = false;
  while (serving) {
    pollfd control_poll{RuntimeControlFd, POLLIN, 0};
    const int polled = ::poll(&control_poll, 1, 16);
    plugin->pumpEditorEvents();
    if (polled == 0) continue;
    if (polled < 0) {
      if (errno == EINTR) continue;
      parent_disconnected = true;
      break;
    }
    ControlRequest request{};
    if (!readAll(RuntimeControlFd, &request, sizeof(request)) || request.magic != RuntimeMagic) {
      parent_disconnected = true;
      break;
    }
    ControlResponse response;
    response.magic = RuntimeMagic;
    const auto command = static_cast<ControlCommand>(request.command);
    switch (command) {
      case ControlCommand::GetParam:
        response.ok = plugin->paramValue(request.id, response.value) ? 1U : 0U;
        break;
      case ControlCommand::ValueToText:
        response.ok = plugin->paramValueToText(request.id, request.value, response.text,
                                               sizeof(response.text))
                          ? 1U
                          : 0U;
        break;
      case ControlCommand::TextToValue:
        response.ok = plugin->paramTextToValue(request.id, request.text, response.value) ? 1U : 0U;
        break;
      case ControlCommand::SaveState: {
        MemoryStateWriter writer;
        response.ok = plugin->saveState(writer) ? 1U : 0U;
        response.size = response.ok != 0U ? static_cast<uint32_t>(writer.bytes().size()) : 0U;
        if (!writeAll(RuntimeControlFd, &response, sizeof(response))) serving = false;
        if (serving && response.size > 0 &&
            !writeAll(RuntimeControlFd, writer.bytes().data(), writer.bytes().size()))
          serving = false;
        continue;
      }
      case ControlCommand::LoadState: {
        std::vector<uint8_t> bytes(request.size);
        if (request.size > 0 && !readAll(RuntimeControlFd, bytes.data(), bytes.size())) {
          serving = false;
          continue;
        }
        MemoryStateReader reader(std::move(bytes));
        response.ok = plugin->loadState(reader) ? 1U : 0U;
        break;
      }
      case ControlCommand::MainThread:
        plugin->onMainThread();
        response.ok = 1;
        break;
      case ControlCommand::Shutdown:
        response.ok = 1;
        serving = false;
        break;
      case ControlCommand::OpenEditor:
        response.ok = plugin->showEditor() ? 1U : 0U;
        break;
      case ControlCommand::CloseEditor:
        plugin->hideEditor();
        response.ok = 1;
        break;
    }
    if (!writeAll(RuntimeControlFd, &response, sizeof(response))) break;
  }

  // The control socket is inherited only by the app-side proxy. EOF without a
  // Shutdown command means the app was killed or crashed. Do not try to join a
  // vendor audio thread here: a plug-in may be the very thing that is hung.
  // `_exit` tears down every thread and prevents an orphan helper surviving a
  // hard app kill.
  if (parent_disconnected) ::_exit(0);

  shared->quit.store(1, std::memory_order_release);
  ::semaphore_signal(to_helper);
  if (audio.joinable()) audio.join();
  plugin->deactivate();
  ::munmap(mapping, sizeof(RuntimeShared));
  return 0;
}

}  // namespace onebeat::plugin::sandbox
