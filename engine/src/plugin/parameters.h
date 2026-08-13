// Parameters (OB-2-01 scope §4).
//
// The three format families disagree about almost everything here — VST3
// normalises every parameter to 0..1 and loses the real range, AU carries units
// and a native range, CLAP carries a native range plus explicit automation and
// modulation capability flags. We model CLAP's: a native `[min, max]` with real
// units, plus flags. The VST3 adapter (Stage 5) reconstitutes a range from the
// plugin's own text conversion and documents the rounding it costs.
#pragma once

#include <cstdint>

#include "core/rt/rt.h"
#include "plugin/plugin_types.h"

namespace onebeat::plugin {

enum ParamFlags : uint32_t {
  ParamFlagNone = 0,

  // Value semantics.
  ParamFlagIsStepped = 1U << 0U,   // integral values only; enums and switches
  ParamFlagIsPeriodic = 1U << 1U,  // wraps at the range ends (phase, pan law angle)
  ParamFlagIsHidden = 1U << 2U,    // not offered in generic UI or automation lists
  ParamFlagIsReadOnly = 1U << 3U,  // a meter or a computed readout
  ParamFlagIsBypass = 1U << 4U,    // *the* bypass; the host binds its own control to it

  // Automation: the host may write a recorded value.
  ParamFlagIsAutomatable = 1U << 5U,
  ParamFlagIsAutomatablePerNoteId = 1U << 6U,
  ParamFlagIsAutomatablePerKey = 1U << 7U,
  ParamFlagIsAutomatablePerChannel = 1U << 8U,
  ParamFlagIsAutomatablePerPort = 1U << 9U,

  // Modulation: the host may apply a *non-destructive offset* (D5's reason for
  // existing). A parameter can be modulatable without being automatable and
  // vice versa; VST3/AU adapters never set these.
  ParamFlagIsModulatable = 1U << 10U,
  ParamFlagIsModulatablePerNoteId = 1U << 11U,
  ParamFlagIsModulatablePerKey = 1U << 12U,
  ParamFlagIsModulatablePerChannel = 1U << 13U,
  ParamFlagIsModulatablePerPort = 1U << 14U,

  // Changing this value requires an active process() call to take effect — the
  // plugin cannot apply it from flush(). Host must not assume flush suffices.
  ParamFlagRequiresProcess = 1U << 15U,
  // The value is an index into a fixed enumeration whose entries may change
  // between versions; the host stores the *text* alongside the value so a
  // renumbered enum degrades to a warning rather than a silently wrong preset.
  ParamFlagIsEnum = 1U << 16U,
};

struct ParamInfo {
  // Stable forever. Never an index: automation, MIDI learn and saved projects
  // all key off this, so renumbering breaks user data (FR-PLG-09).
  ParamId id = InvalidParamId;
  PluginName name;
  // Where the parameter sits in the plugin's own tree, "/" separated, e.g.
  // "/osc1/filter". Purely presentational — the generic editor (OB-2-08) groups
  // by it, and nothing in the engine depends on it.
  ModulePath module;

  double min_value = 0.0;
  double max_value = 1.0;
  double default_value = 0.0;

  uint32_t flags = ParamFlagIsAutomatable;

  // An opaque token the plugin may hand back with every event addressed to this
  // parameter, so it can skip its own ID lookup on the audio thread. CLAP's
  // cookie. The host must treat it as meaningless and must not persist it.
  void* cookie = nullptr;

  bool has(ParamFlags flag) const noexcept OB_NONBLOCKING { return (flags & flag) != 0U; }

  double clamp(double value) const noexcept OB_NONBLOCKING {
    if (value < min_value) {
      return min_value;
    }
    return value > max_value ? max_value : value;
  }
};

// The result of applying modulation to a value. Kept as a named type because
// the distinction is the whole point: `base` is what the user set and what gets
// saved; `effective` is what the DSP should use this block and is never written
// back. Collapsing the two is the bug D5 is designed to prevent.
struct ModulatedValue {
  double base = 0.0;
  double modulation = 0.0;

  double effective(const ParamInfo& info) const noexcept OB_NONBLOCKING {
    return info.clamp(base + modulation);
  }
};

// What a parameter rescan invalidates. Mirrors CLAP's flags, and the host acts
// on the cheapest sufficient one — a name change must not drop automation.
enum ParamRescanFlags : uint32_t {
  ParamRescanValues = 1U << 0U,  // values changed; re-read them
  ParamRescanText = 1U << 1U,    // value→text mapping changed; re-render displays
  ParamRescanInfo = 1U << 2U,    // ranges, flags or names changed
  ParamRescanAll = 1U << 3U,     // the parameter *list* changed; requires deactivation
};

// What to discard for a parameter whose state the plugin says is stale.
enum ParamClearFlags : uint32_t {
  ParamClearAutomations = 1U << 0U,
  ParamClearModulations = 1U << 1U,
  ParamClearAll = ParamClearAutomations | ParamClearModulations,
};

}  // namespace onebeat::plugin
