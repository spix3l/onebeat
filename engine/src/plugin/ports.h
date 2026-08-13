// Audio and note ports (OB-2-01 scope §2, FR-PLG-12, DM-Q5).
//
// Port lists are **dynamic**. DM-Q5 settles this: a drum plugin may offer one
// stereo out today and sixteen tomorrow, and the answer is not "fix the layout
// at instantiation" but "reconfigure while deactivated", which is CLAP's rule.
// Every function here that changes a layout is therefore legal only in the
// Deactivated state, and PluginInstance asserts it.
#pragma once

#include <cstdint>

#include "core/rt/rt.h"
#include "plugin/plugin_types.h"

namespace onebeat::plugin {

enum class PortDirection : uint8_t { Input = 0, Output = 1 };

// The channel meaning of an audio port. Deliberately an enum plus an explicit
// count rather than a count alone: "2 channels" is ambiguous between stereo and
// two unrelated mono signals, and mixer routing (Stage 4) needs the difference.
enum class ChannelLayout : uint8_t {
  Mono = 0,
  Stereo = 1,
  // Known channel count, unknown semantics. Surround layouts land in Stage 4
  // (EPIC-4); until then an adapter that meets one reports Unspecified rather
  // than lying about it being stereo.
  Unspecified = 2,
};

inline constexpr uint32_t channelCountFor(ChannelLayout layout) noexcept OB_NONBLOCKING {
  switch (layout) {
    case ChannelLayout::Mono:
      return 1;
    case ChannelLayout::Stereo:
      return 2;
    case ChannelLayout::Unspecified:
      return 0;  // the port's own channel_count is authoritative
  }
  return 0;
}

struct AudioPortInfo {
  // Stable across a reconfiguration: routing is stored against this, so a port
  // that keeps its ID keeps its mixer assignment when the layout changes.
  PortId id = InvalidPortId;
  PluginName name;
  uint32_t channel_count = 2;
  ChannelLayout layout = ChannelLayout::Stereo;
  // Exactly one input and one output port may be "main". The main output is
  // what an instrument's default routing follows; aux outputs are the multi-out
  // case FR-PLG-12 is about.
  bool is_main = false;
  // The plugin can process this port in place — its input buffer may be the
  // same memory as the paired output. Set only when the pairing is exact.
  bool supports_in_place = false;
  PortId in_place_pair = InvalidPortId;
};

// Which note encoding a port speaks. A bitmask because ports commonly accept
// several and prefer one; the host picks the richest both sides support.
enum NoteDialect : uint32_t {
  NoteDialectNone = 0,
  // CLAP's own note events: carries note_id, so per-note expression and per-note
  // modulation survive. Always preferred when available — this is the dialect
  // that makes D5 worth having.
  NoteDialectClap = 1U << 0U,
  NoteDialectMidi = 1U << 1U,
  NoteDialectMidiMpe = 1U << 2U,
  NoteDialectMidi2 = 1U << 3U,
};

struct NotePortInfo {
  PortId id = InvalidPortId;
  PluginName name;
  uint32_t supported_dialects = NoteDialectClap | NoteDialectMidi;
  NoteDialect preferred_dialect = NoteDialectClap;
};

// What the host promises about the stream. Fixed for the duration of an
// activation; changing any field means deactivate → configure → activate.
struct ProcessSetup {
  double sample_rate = 48000.0;
  uint32_t min_block_frames = 1;
  uint32_t max_block_frames = 512;
  // Offline renders may take a slower, higher-quality path (CLAP's render
  // extension). FR-ENG-06 requires the *code path* to be shared, not that the
  // plugin must behave identically — a plugin is entitled to know.
  bool is_offline = false;
};

// What changed about a port list, so the host can do the cheapest correct thing
// rather than tearing down every routing it holds. Mirrors CLAP's rescan flags.
enum PortRescanFlags : uint32_t {
  PortRescanNames = 1U << 0U,       // cosmetic; keep all routing
  PortRescanFlagsChanged = 1U << 1U,
  PortRescanChannelCount = 1U << 2U,
  PortRescanPortList = 1U << 3U,    // ports appeared or vanished; requires deactivation
};

}  // namespace onebeat::plugin
