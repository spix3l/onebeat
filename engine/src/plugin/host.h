// The host side of the contract — what a plugin may ask OneBeat to do.
//
// This is the mirror of PluginInstance and it matters just as much: a model with
// no host callbacks can only host plugins that never change their own mind,
// which is roughly none of them. Modelled on `clap_host` plus the extensions
// that carry a host obligation.
//
// Every method is annotated with the thread it may be called from. The two
// audio-thread-callable ones are the only ones marked OB_NONBLOCKING, and the
// engine's implementation of them must stay that way.
#pragma once

#include <cstdint>

#include "core/rt/rt.h"
#include "plugin/plugin_types.h"

// The rescan/clear flag words below are the bitmasks declared in parameters.h
// (ParamRescanFlags, ParamClearFlags) and ports.h (PortRescanFlags). They are
// passed as plain uint32_t because they are masks, not single values; callers
// include those headers for the constants.

namespace onebeat::plugin {

class PluginHost {
 public:
  virtual ~PluginHost() = default;

  // --- lifecycle requests --------------------------------------------------

  // [thread-safe] "Deactivate and reactivate me." The plugin's sample rate,
  // block size or port layout no longer suits it. The host honours this at a
  // safe point, never inside process().
  virtual void requestRestart() noexcept = 0;

  // [thread-safe] "Start calling process() again" — the plugin was sleeping
  // (returned ProcessStatus::Sleep) and now has something to render.
  virtual void requestProcess() noexcept = 0;

  // [thread-safe] "Call my onMainThread() soon." The plugin needs to do
  // something it may not do where it currently is.
  virtual void requestCallback() noexcept = 0;

  // --- parameters ----------------------------------------------------------

  // [main-thread] Something about the parameter set changed. The host does the
  // cheapest correct thing per flag; ParamRescanAll requires deactivation and
  // may invalidate automation, so a plugin that over-reports it destroys user
  // work.
  virtual void paramsRescan(uint32_t flags) noexcept = 0;

  // [main-thread] Drop the host's automation and/or modulation for one
  // parameter — the plugin has taken authority over it.
  virtual void paramsClear(ParamId param, uint32_t flags) noexcept = 0;

  // --- ports ---------------------------------------------------------------

  // [main-thread] Audio or note port lists changed (FR-PLG-12: a multi-out
  // plugin gaining outputs). The host re-reads the lists and re-derives
  // routing, preserving what it can by PortId.
  virtual void audioPortsRescan(uint32_t flags) noexcept = 0;
  virtual void notePortsRescan(uint32_t flags) noexcept = 0;

  // --- latency and tail ----------------------------------------------------

  // [main-thread] The plugin's reported latency changed; the host recomputes
  // delay compensation across the graph (FR-ENG-04).
  virtual void latencyChanged() noexcept = 0;

  // [main-thread] The plugin's release tail length changed; the host adjusts how
  // long it keeps calling process() after the last note (offline render tails).
  virtual void tailChanged() noexcept = 0;

  // --- thread pool ---------------------------------------------------------

  // [audio-thread] The hook point FR-ENG-05 is about: a plugin with internally
  // parallel work asks the host to run `num_tasks` of it across the host's own
  // worker pool, so plugin and host do not each spawn threads and fight for
  // cores. The host calls PluginInstance::threadPoolExec() once per task index
  // and returns only when all have completed.
  //
  // Returns false if the host declines — it is always legal to decline, and the
  // plugin must then do the work itself on the calling thread. OneBeat declines
  // for the whole of Stage 2; the pool arrives with the graph in Stage 4. The
  // seat exists now so that adopting it later is not a model change.
  virtual bool requestThreadPoolExec(uint32_t num_tasks) noexcept OB_NONBLOCKING = 0;
};

// A host that grants nothing. Every request is recorded as ignored rather than
// silently dropped, which keeps tests and the offline driver honest about what
// they are not providing.
class NullPluginHost final : public PluginHost {
 public:
  void requestRestart() noexcept override { ++restart_requests_; }
  void requestProcess() noexcept override { ++process_requests_; }
  void requestCallback() noexcept override { ++callback_requests_; }
  void paramsRescan(uint32_t flags) noexcept override { params_rescan_flags_ |= flags; }
  void paramsClear(ParamId /*param*/, uint32_t /*flags*/) noexcept override {}
  void audioPortsRescan(uint32_t flags) noexcept override { audio_ports_rescan_flags_ |= flags; }
  void notePortsRescan(uint32_t flags) noexcept override { note_ports_rescan_flags_ |= flags; }
  void latencyChanged() noexcept override { ++latency_changes_; }
  void tailChanged() noexcept override { ++tail_changes_; }
  bool requestThreadPoolExec(uint32_t /*num_tasks*/) noexcept OB_NONBLOCKING override {
    return false;
  }

  uint32_t restartRequests() const noexcept { return restart_requests_; }
  uint32_t processRequests() const noexcept { return process_requests_; }
  uint32_t callbackRequests() const noexcept { return callback_requests_; }
  uint32_t paramsRescanFlags() const noexcept { return params_rescan_flags_; }
  uint32_t audioPortsRescanFlags() const noexcept { return audio_ports_rescan_flags_; }
  uint32_t notePortsRescanFlags() const noexcept { return note_ports_rescan_flags_; }
  uint32_t latencyChanges() const noexcept { return latency_changes_; }
  uint32_t tailChanges() const noexcept { return tail_changes_; }

 private:
  uint32_t restart_requests_ = 0;
  uint32_t process_requests_ = 0;
  uint32_t callback_requests_ = 0;
  uint32_t params_rescan_flags_ = 0;
  uint32_t audio_ports_rescan_flags_ = 0;
  uint32_t note_ports_rescan_flags_ = 0;
  uint32_t latency_changes_ = 0;
  uint32_t tail_changes_ = 0;
};

}  // namespace onebeat::plugin
