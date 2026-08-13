// The probe that runs plugins in another process, and quarantines the ones that
// do not come back (OB-2-03 §1, §2, §4; FR-PLG-06; G3).
//
// `ScanProbe` was left as an interface by OB-2-02 precisely so this could
// arrive without touching the scanner. Everything the scanner does — walking
// folders, fingerprinting, deciding what changed, streaming results — is
// unchanged. What changes is that the act of opening a bundle now happens in
// `onebeat-plugin-host`, so that when it goes wrong the thing that dies is a
// process whose entire job was to find out.
//
// Three outcomes, and the difference between them is what the user is told:
//
//   normal exit, `Done` seen   → the descriptors it sent
//   died, or stopped early     → `ScanOutcome::Crashed` + the phase and signal
//   outlived the watchdog      → `ScanOutcome::TimedOut` + the phase
//
// A hang is not folded into a crash. "Diva crashed" and "Diva stopped
// responding" are different sentences, they point at different vendor bugs, and
// one of them is much more likely to be fixed by trying again.
#pragma once

#include <chrono>
#include <string>
#include <vector>

#include "plugin/scan/scanner.h"

namespace onebeat::core {
class Diagnostics;
}

namespace onebeat::plugin::scan {

struct SubprocessProbeOptions {
  // Empty => `discoverHelperPath()`.
  std::string helper_path;
  // Where the crash-context file goes (OB-2-03 §4). Empty => none written,
  // which is the right default for tests and the wrong one for a shipped build.
  std::string crash_log_directory;
  // The watchdog. Generous on purpose: a first-run licence check that talks to
  // a dongle can legitimately take seconds, and a false quarantine is worse
  // than a slow scan — it hides a working plugin behind an error the user has
  // to notice and undo. A genuinely hung plugin costs this much once, in the
  // background, and never again.
  std::chrono::milliseconds timeout{15000};
};

class SubprocessProbe : public ScanProbe {
 public:
  explicit SubprocessProbe(SubprocessProbeOptions options,
                           core::Diagnostics* diagnostics = nullptr);

  // [scanner-thread] Spawns the helper, reads its stream, and returns either
  // what it reported or a single quarantined row explaining why it did not. A
  // plugin's failure never propagates into this process — it arrives as a wait
  // status. (Not `noexcept`: it allocates, so `bad_alloc` can still escape, and
  // the scanner's thread guard is what catches that.)
  void probe(const BundleRef& bundle, std::vector<PluginDescriptor>& out) override;

  // The OB-2-07 helper walks the real factory and temporarily instantiates each
  // entry, so IDs, features, ports and parameter counts are authoritative.
  uint32_t capabilities() const override { return DescriptorFlagIntrospected; }

  // False when the helper binary is not where it should be — a broken build or
  // a bundle assembled wrongly. The library falls back to `BundleNameProbe`,
  // which cannot crash because it never opens anything.
  bool available() const;

  const std::string& helperPath() const noexcept { return options_.helper_path; }

  // OB_PLUGIN_HOST, then next to the engine dylib, then the app bundle's
  // MacOS/ directory. Returns empty if none of those exist.
  static std::string discoverHelperPath();

 private:
  SubprocessProbeOptions options_;
  core::Diagnostics* diagnostics_ = nullptr;
};

}  // namespace onebeat::plugin::scan
