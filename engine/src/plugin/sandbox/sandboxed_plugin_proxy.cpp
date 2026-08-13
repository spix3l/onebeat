#include "plugin/sandbox/sandboxed_plugin_proxy.h"

#include <fcntl.h>
#include <mach/mach.h>
#include <signal.h>
#include <spawn.h>
#include <sys/mman.h>
#include <sys/socket.h>
#include <sys/wait.h>
#include <unistd.h>

#include <algorithm>
#include <atomic>
#include <cerrno>
#include <chrono>
#include <cstring>
#include <new>
#include <thread>
#include <vector>

#include "core/rt/rt.h"
#include "plugin/scan/subprocess_probe.h"

extern char** environ;

namespace onebeat::plugin::sandbox {
namespace {

std::atomic<uint32_t> NextRuntimeId{1};  // NOLINT(*-avoid-non-const-global-variables)

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

bool sendAll(int fd, const void* data, size_t size) {
  const auto* cursor = static_cast<const uint8_t*>(data);
  while (size > 0) {
    const ssize_t count = ::send(fd, cursor, size, MSG_NOSIGNAL);
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
  const size_t size = std::min(std::strlen(safe), capacity - 1);
  std::memcpy(destination, safe, size);
  destination[size] = '\0';
}

mach_timespec_t relativeDeadline(uint64_t nanos) noexcept OB_NONBLOCKING {
  return mach_timespec_t{static_cast<unsigned int>(nanos / 1'000'000'000ULL),
                         static_cast<clock_res_t>(nanos % 1'000'000'000ULL)};
}

}  // namespace

SandboxedPluginProxy::SandboxedPluginProxy(PluginHost* host, std::string bundle_path,
                                           std::string plugin_id, std::string helper_path)
    : PluginInstance(host),
      bundle_path_(std::move(bundle_path)),
      plugin_id_(std::move(plugin_id)),
      helper_path_(std::move(helper_path)) {}

SandboxedPluginProxy::~SandboxedPluginProxy() {
  shutdown();
}

PluginName SandboxedPluginProxy::name() const {
  if (shared_ != nullptr && shared_->plugin_name[0] != '\0')
    return PluginName(shared_->plugin_name);
  return PluginName(plugin_id_.c_str());
}

bool SandboxedPluginProxy::onConfigure(const ProcessSetup& setup) {
  shutdown();
  return launch(setup);
}
bool SandboxedPluginProxy::onActivate() {
  return shared_ != nullptr && healthy();
}
void SandboxedPluginProxy::onDeactivate() {}
bool SandboxedPluginProxy::onStartProcessing() noexcept OB_NONBLOCKING {
  return healthy();
}
void SandboxedPluginProxy::onStopProcessing() noexcept OB_NONBLOCKING {}
void SandboxedPluginProxy::reset() noexcept OB_NONBLOCKING {}

bool SandboxedPluginProxy::launch(const ProcessSetup& setup) {
  if (helper_path_.empty()) helper_path_ = scan::SubprocessProbe::discoverHelperPath();
  if (helper_path_.empty()) {
    last_error_ = "onebeat-plugin-host was not found.";
    return false;
  }

  shm_name_ = "/onebeat.runtime." + std::to_string(::getpid()) + "." +
              std::to_string(NextRuntimeId.fetch_add(1));
  ::shm_unlink(shm_name_.c_str());
  const int shared_fd = ::shm_open(shm_name_.c_str(), O_CREAT | O_EXCL | O_RDWR, 0600);
  if (shared_fd < 0 || ::ftruncate(shared_fd, sizeof(RuntimeShared)) != 0) {
    const int failure = errno;
    if (shared_fd >= 0) ::close(shared_fd);
    last_error_ = "The plug-in shared memory could not be created: ";
    last_error_ += std::strerror(failure);
    return false;
  }
  void* mapping =
      ::mmap(nullptr, sizeof(RuntimeShared), PROT_READ | PROT_WRITE, MAP_SHARED, shared_fd, 0);
  ::close(shared_fd);
  if (mapping == MAP_FAILED) {
    last_error_ = "The plug-in shared memory could not be mapped.";
    ::shm_unlink(shm_name_.c_str());
    return false;
  }
  shared_ = new (mapping) RuntimeShared;
  shared_->sample_rate = setup.sample_rate;
  shared_->configured_max_frames = std::min(setup.max_block_frames, RuntimeMaxFrames);
  std::memset(shared_->audio_in, 0, sizeof(shared_->audio_in));
  std::memset(shared_->audio_out, 0, sizeof(shared_->audio_out));
  ::mlock(mapping, sizeof(RuntimeShared));

  int sockets[2]{};
  if (::socketpair(AF_UNIX, SOCK_STREAM, 0, sockets) != 0) {
    last_error_ = "The plug-in control channel could not be created.";
    shutdown();
    return false;
  }
  // The child endpoint is duplicated to fd 4. If the parent endpoint already
  // landed on 4 (common once diagnostics owns fd 3), a naive spawn action would
  // dup the child endpoint onto 4 and then close 4 while "closing the parent".
  // Move that endpoint out of the reserved slot before constructing actions.
  if (sockets[0] == RuntimeControlFd) {
    const int moved = ::fcntl(sockets[0], F_DUPFD_CLOEXEC, RuntimeControlFd + 1);
    if (moved < 0) {
      ::close(sockets[0]);
      ::close(sockets[1]);
      last_error_ = "The plug-in control channel could not reserve its child descriptor.";
      shutdown();
      return false;
    }
    ::close(sockets[0]);
    sockets[0] = moved;
  }
  int no_sigpipe = 1;
  ::setsockopt(sockets[0], SOL_SOCKET, SO_NOSIGPIPE, &no_sigpipe, sizeof(no_sigpipe));

  mach_port_t bootstrap = MACH_PORT_NULL;
  if (::mach_port_allocate(mach_task_self(), MACH_PORT_RIGHT_RECEIVE, &bootstrap) != KERN_SUCCESS ||
      ::mach_port_insert_right(mach_task_self(), bootstrap, bootstrap, MACH_MSG_TYPE_MAKE_SEND) !=
          KERN_SUCCESS) {
    ::close(sockets[0]);
    ::close(sockets[1]);
    last_error_ = "The plug-in bootstrap port could not be created.";
    shutdown();
    return false;
  }

  posix_spawn_file_actions_t actions;
  posix_spawn_file_actions_init(&actions);
  posix_spawn_file_actions_adddup2(&actions, sockets[1], RuntimeControlFd);
  posix_spawn_file_actions_addclose(&actions, sockets[0]);
  if (sockets[1] != RuntimeControlFd) posix_spawn_file_actions_addclose(&actions, sockets[1]);
  posix_spawnattr_t attributes;
  posix_spawnattr_init(&attributes);
  posix_spawnattr_setspecialport_np(&attributes, bootstrap, TASK_BOOTSTRAP_PORT);

  char* const arguments[] = {
      const_cast<char*>(helper_path_.c_str()), const_cast<char*>("--host"),
      const_cast<char*>(bundle_path_.c_str()), const_cast<char*>("--plugin-id"),
      const_cast<char*>(plugin_id_.c_str()),   const_cast<char*>("--shm-name"),
      const_cast<char*>(shm_name_.c_str()),    nullptr};
  const int spawned =
      ::posix_spawn(&child_pid_, helper_path_.c_str(), &actions, &attributes, arguments, environ);
  posix_spawnattr_destroy(&attributes);
  posix_spawn_file_actions_destroy(&actions);
  ::close(sockets[1]);
  if (spawned != 0) {
    ::close(sockets[0]);
    child_pid_ = -1;
    last_error_ = "The plug-in host process could not be launched.";
    shutdown();
    return false;
  }
  control_fd_ = sockets[0];

  PortMessageReceive receive{};
  const mach_msg_return_t received =
      ::mach_msg(&receive.message.header, MACH_RCV_MSG | MACH_RCV_TIMEOUT, 0, sizeof(receive),
                 bootstrap, 5000, MACH_PORT_NULL);
  ::mach_port_deallocate(mach_task_self(), bootstrap);
  ::mach_port_mod_refs(mach_task_self(), bootstrap, MACH_PORT_RIGHT_RECEIVE, -1);
  if (received != MACH_MSG_SUCCESS) {
    last_error_ = "The plug-in host did not establish its audio transport.";
    shutdown();
    return false;
  }
  to_helper_ = receive.message.to_helper.name;
  to_host_ = receive.message.to_host.name;

  const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(5);
  while (shared_->ready.load(std::memory_order_acquire) == 0 &&
         std::chrono::steady_clock::now() < deadline) {
    std::this_thread::sleep_for(std::chrono::milliseconds(1));
  }
  if (shared_->ready.load(std::memory_order_acquire) != 1) {
    last_error_ =
        shared_->error[0] != '\0' ? shared_->error : "The plug-in host did not become ready.";
    shutdown();
    return false;
  }
  ::shm_unlink(shm_name_.c_str());
  dead_.store(false, std::memory_order_release);
  consecutive_misses_ = 0;
  in_flight_ = 0;
  return true;
}

void SandboxedPluginProxy::shutdown() {
  if (control_fd_ >= 0) {
    ControlRequest request;
    request.command = static_cast<uint32_t>(ControlCommand::Shutdown);
    ControlResponse response;
    control(request, response);
    ::close(control_fd_);
    control_fd_ = -1;
  }
  if (shared_ != nullptr) {
    shared_->quit.store(1, std::memory_order_release);
    if (to_helper_ != MACH_PORT_NULL) ::semaphore_signal(to_helper_);
  }
  if (child_pid_ > 0) {
    int status = 0;
    pid_t result = ::waitpid(child_pid_, &status, WNOHANG);
    if (result == 0) {
      ::kill(child_pid_, SIGTERM);
      while (::waitpid(child_pid_, &status, 0) < 0 && errno == EINTR) {
      }
    }
    child_pid_ = -1;
  }
  if (shared_ != nullptr) {
    ::munlock(shared_, sizeof(RuntimeShared));
    ::munmap(shared_, sizeof(RuntimeShared));
    shared_ = nullptr;
  }
  if (!shm_name_.empty()) ::shm_unlink(shm_name_.c_str());
  to_helper_ = MACH_PORT_NULL;
  to_host_ = MACH_PORT_NULL;
  dead_.store(true, std::memory_order_release);
}

void SandboxedPluginProxy::silence(const ProcessBlock& block) const noexcept OB_NONBLOCKING {
  for (uint32_t port = 0; port < block.audio_output_count; ++port)
    block.audio_outputs[port].clear();
}

ProcessStatus SandboxedPluginProxy::process(const ProcessBlock& block) noexcept OB_NONBLOCKING {
  if (shared_ == nullptr || dead_.load(std::memory_order_acquire) ||
      block.frames > RuntimeMaxFrames) {
    silence(block);
    return ProcessStatus::Error;
  }

  // Never overwrite a block the helper may still be reading. If the first
  // deadline elapsed, the next callback only observes whether that request
  // eventually completed; a second miss declares the helper dead.
  if (in_flight_ != 0 && shared_->response.load(std::memory_order_acquire) != in_flight_) {
    silence(block);
    if (++consecutive_misses_ >= 2) dead_.store(true, std::memory_order_release);
    return ProcessStatus::Error;
  }
  in_flight_ = 0;
  consecutive_misses_ = 0;

  shared_->frames = block.frames;
  shared_->input_channels =
      block.audio_input_count > 0
          ? std::min(static_cast<uint32_t>(block.audio_inputs[0].numChannels()), RuntimeMaxChannels)
          : 0U;
  shared_->output_channels =
      block.audio_output_count > 0
          ? std::min(static_cast<uint32_t>(block.audio_outputs[0].numChannels()),
                     RuntimeMaxChannels)
          : 0U;
  for (uint32_t channel = 0; channel < shared_->input_channels; ++channel) {
    for (uint32_t frame = 0; frame < block.frames; ++frame) {
      shared_->audio_in[channel][frame] =
          block.audio_inputs[0].channel(static_cast<int>(channel))[frame];
    }
  }
  shared_->event_count = 0;
  for (uint32_t index = 0;
       index < block.in_events.size() && shared_->event_count < RuntimeMaxEvents; ++index) {
    if (block.in_events[index].kind() == EventType::MidiSysex) continue;
    shared_->events[shared_->event_count++] = block.in_events[index];
  }
  shared_->transport = block.transport;
  shared_->steady_time = block.steady_time_frames;

  const uint32_t request = ++sequence_;
  shared_->request.store(request, std::memory_order_release);
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wfunction-effects"
  ::semaphore_signal(to_helper_);
  const uint64_t period_nanos = static_cast<uint64_t>(
      (static_cast<double>(block.frames) * 1'000'000'000.0) / setup().sample_rate);
  uint64_t deadline_nanos = period_nanos * 3U / 5U;
#ifdef ONEBEAT_SANITIZER_BUILD
  // Instrumented helper processes are intentionally much slower. Preserve the
  // real 60%-of-block production deadline while giving sanitizer builds enough
  // wall time to inspect the same IPC and rendering paths without timing out.
  deadline_nanos = std::max(deadline_nanos, 100'000'000ULL);
#endif
  const kern_return_t waited = ::semaphore_timedwait(to_host_, relativeDeadline(deadline_nanos));
#pragma clang diagnostic pop
  const bool answered =
      waited == KERN_SUCCESS && shared_->response.load(std::memory_order_acquire) == request;
  if (!answered) {
    in_flight_ = request;
    consecutive_misses_ = 1;
    silence(block);
    return ProcessStatus::Error;
  }

  for (uint32_t channel = 0; channel < shared_->output_channels; ++channel) {
    for (uint32_t frame = 0; frame < block.frames; ++frame) {
      block.audio_outputs[0].channel(static_cast<int>(channel))[frame] =
          shared_->audio_out[channel][frame];
    }
  }
  return ProcessStatus::Continue;
}

bool SandboxedPluginProxy::control(const ControlRequest& request, ControlResponse& response,
                                   const uint8_t* payload) const {
  if (control_fd_ < 0 || !sendAll(control_fd_, &request, sizeof(request))) return false;
  if (request.size > 0 && payload != nullptr && !sendAll(control_fd_, payload, request.size))
    return false;
  return readAll(control_fd_, &response, sizeof(response)) && response.magic == RuntimeMagic;
}

uint32_t SandboxedPluginProxy::paramCount() const {
  return shared_ != nullptr ? shared_->param_count : 0;
}
bool SandboxedPluginProxy::paramInfo(uint32_t index, ParamInfo& out) const {
  if (shared_ == nullptr || index >= shared_->param_count) return false;
  const RuntimeParamInfo& source = shared_->params[index];
  out.id = source.id;
  out.flags = source.flags;
  out.min_value = source.min_value;
  out.max_value = source.max_value;
  out.default_value = source.default_value;
  out.name.assign(source.name);
  out.module.assign(source.module);
  return true;
}
bool SandboxedPluginProxy::paramValue(ParamId param, double& out) const {
  ControlRequest request;
  request.command = static_cast<uint32_t>(ControlCommand::GetParam);
  request.id = param;
  ControlResponse response;
  if (!control(request, response) || response.ok == 0) return false;
  out = response.value;
  return true;
}
bool SandboxedPluginProxy::paramValueToText(ParamId param, double value, char* out,
                                            size_t out_size) const {
  ControlRequest request;
  request.command = static_cast<uint32_t>(ControlCommand::ValueToText);
  request.id = param;
  request.value = value;
  ControlResponse response;
  if (!control(request, response) || response.ok == 0) return false;
  copyText(out, out_size, response.text);
  return true;
}
bool SandboxedPluginProxy::paramTextToValue(ParamId param, const char* text, double& out) const {
  ControlRequest request;
  request.command = static_cast<uint32_t>(ControlCommand::TextToValue);
  request.id = param;
  copyText(request.text, sizeof(request.text), text);
  ControlResponse response;
  if (!control(request, response) || response.ok == 0) return false;
  out = response.value;
  return true;
}

uint32_t SandboxedPluginProxy::audioPortCount(PortDirection direction) const {
  if (shared_ == nullptr) return 0;
  return direction == PortDirection::Input ? shared_->audio_input_count
                                           : shared_->audio_output_count;
}
bool SandboxedPluginProxy::audioPortInfo(PortDirection direction, uint32_t index,
                                         AudioPortInfo& out) const {
  if (shared_ == nullptr || index >= audioPortCount(direction)) return false;
  const RuntimePortInfo& source = direction == PortDirection::Input ? shared_->audio_inputs[index]
                                                                    : shared_->audio_outputs[index];
  out.id = source.id;
  out.channel_count = source.channel_count;
  out.name.assign(source.name);
  out.layout = source.channel_count == 1   ? ChannelLayout::Mono
               : source.channel_count == 2 ? ChannelLayout::Stereo
                                           : ChannelLayout::Unspecified;
  out.is_main = (source.flags & 1U) != 0U;
  out.supports_in_place = (source.flags & 2U) != 0U;
  return true;
}
uint32_t SandboxedPluginProxy::notePortCount(PortDirection direction) const {
  if (shared_ == nullptr) return 0;
  return direction == PortDirection::Input ? shared_->note_input_count : shared_->note_output_count;
}
bool SandboxedPluginProxy::notePortInfo(PortDirection direction, uint32_t index,
                                        NotePortInfo& out) const {
  if (shared_ == nullptr || index >= notePortCount(direction)) return false;
  const RuntimePortInfo& source = direction == PortDirection::Input ? shared_->note_inputs[index]
                                                                    : shared_->note_outputs[index];
  out.id = source.id;
  out.name.assign(source.name);
  out.supported_dialects = source.dialects;
  out.preferred_dialect = static_cast<NoteDialect>(source.preferred_dialect);
  return true;
}

bool SandboxedPluginProxy::saveState(StateWriter& writer) const {
  ControlRequest request;
  request.command = static_cast<uint32_t>(ControlCommand::SaveState);
  ControlResponse response;
  if (!control(request, response)) {
    int status = 0;
    const pid_t reaped = child_pid_ > 0 ? ::waitpid(child_pid_, &status, WNOHANG) : -1;
    if (reaped == child_pid_) {
      last_error_ = WIFSIGNALED(status)
                        ? "The plug-in helper exited on signal " +
                              std::to_string(WTERMSIG(status)) + " while saving state."
                        : "The plug-in helper exited with status " +
                              std::to_string(WEXITSTATUS(status)) + " while saving state.";
      child_pid_ = -1;
    } else {
      last_error_ = "The plug-in helper disconnected while saving state.";
    }
    return false;
  }
  if (response.ok == 0) {
    last_error_ = "The plug-in rejected its state-save request.";
    return false;
  }
  std::vector<uint8_t> bytes(response.size);
  if (response.size > 0 && !readAll(control_fd_, bytes.data(), bytes.size())) {
    last_error_ = "The plug-in helper returned a truncated state chunk.";
    return false;
  }
  checkpoint_ = bytes;
  return response.size == 0 || writer.write(bytes.data(), bytes.size());
}
bool SandboxedPluginProxy::loadState(StateReader& reader) {
  std::vector<uint8_t> bytes(reader.remaining());
  if (!bytes.empty() && reader.read(bytes.data(), bytes.size()) != bytes.size()) return false;
  ControlRequest request;
  request.command = static_cast<uint32_t>(ControlCommand::LoadState);
  request.size = static_cast<uint32_t>(bytes.size());
  ControlResponse response;
  const bool loaded = control(request, response, bytes.data()) && response.ok != 0;
  if (loaded) checkpoint_ = std::move(bytes);
  return loaded;
}
void SandboxedPluginProxy::onMainThread() {
  ControlRequest request;
  request.command = static_cast<uint32_t>(ControlCommand::MainThread);
  ControlResponse response;
  control(request, response);
}
uint32_t SandboxedPluginProxy::latencyFrames() const {
  return shared_ != nullptr ? shared_->latency_frames : 0;
}

bool SandboxedPluginProxy::restartHost() {
  const bool reopen_editor = editor_open_;
  shutdown();
  if (!launch(setup())) return false;
  if (!checkpoint_.empty()) {
    ControlRequest request;
    request.command = static_cast<uint32_t>(ControlCommand::LoadState);
    request.size = static_cast<uint32_t>(checkpoint_.size());
    ControlResponse response;
    if (!control(request, response, checkpoint_.data()) || response.ok == 0) {
      last_error_ = "The plug-in restarted, but its saved state could not be restored.";
      shutdown();
      return false;
    }
  }
  if (reopen_editor && !openEditor()) {
    last_error_ = "The plug-in restarted, but its editor could not be reopened.";
    return false;
  }
  return true;
}

bool SandboxedPluginProxy::openEditor() {
  ControlRequest request;
  request.command = static_cast<uint32_t>(ControlCommand::OpenEditor);
  ControlResponse response;
  editor_open_ = control(request, response) && response.ok != 0;
  return editor_open_;
}

void SandboxedPluginProxy::closeEditor() {
  ControlRequest request;
  request.command = static_cast<uint32_t>(ControlCommand::CloseEditor);
  ControlResponse response;
  control(request, response);
  editor_open_ = false;
}

}  // namespace onebeat::plugin::sandbox
