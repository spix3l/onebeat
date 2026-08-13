// What a scan produces: one row per plugin, per OB-2-02 scope §3.
//
// A descriptor is what the host knows about a plugin *without having loaded
// it*. That distinction is the whole point of the scan cache: loading a plugin
// costs tens of milliseconds and can crash (OB-2-03), so the browser, the
// project loader and the missing-plugin placeholder (OB-2-10) all work from
// descriptors and never from live instances.
//
// Deliberately a trivially-copyable POD with fixed-capacity text, like
// everything else in `plugin/` (OB-2-01). That is what lets the cache be an
// array written with one write() and read with one read(), and what will let a
// descriptor cross the helper-process boundary in OB-2-05 without a serialiser.
// The cost is truncation, which is silent and bounded — see `PluginName`.
#pragma once

#include <cstdint>
#include <type_traits>

#include "plugin/plugin_types.h"

namespace onebeat::plugin::scan {

// Paths are their own capacity because a bundle inside a user's home directory
// with a long name routinely exceeds the 128 bytes a display name gets. 512 is
// four times the longest plugin path observed on a machine with every major
// vendor installed; PATH_MAX (1024) would double the cache for nothing.
using PluginPath = FixedText<512>;
using PluginId = FixedText<128>;  // CLAP's reverse-DNS id, VST3's 128-bit as hex
using VendorName = FixedText<128>;
using VersionText = FixedText<32>;  // vendor-formatted; never parsed, only shown

enum class PluginFormat : uint8_t {
  Unknown = 0,
  Builtin = 1,  // ships inside OneBeat; never scanned from disk, but listed alike
  Clap = 2,
  // Stage 5 (EPIC-5). Present in the enum from the start so that a cache
  // written today stays readable when the adapters land: adding an enumerator
  // is not a schema change, but *renumbering* one would silently reinterpret
  // every cached row.
  Vst3 = 3,
  AudioUnit = 4,
};

const char* formatName(PluginFormat format) noexcept;

// The coarse "what is this thing" classification the browser filters on.
// CLAP carries free-form feature strings; this is the subset every format can
// answer, with the raw list kept alongside so nothing is lost.
enum PluginFeatures : uint32_t {
  PluginFeatureNone = 0,
  PluginFeatureInstrument = 1U << 0U,
  PluginFeatureAudioEffect = 1U << 1U,
  PluginFeatureNoteEffect = 1U << 2U,
  PluginFeatureAnalyzer = 1U << 3U,
};

// How much of a descriptor is actually known.
//
// Discovery and introspection are separate acts. Finding `Diva.clap` on disk
// tells you its name and its path; it tells you nothing about its ports, its
// parameters or its real identity, and finding out means loading code that may
// crash (OB-2-03). So a descriptor records what has been established, and a
// probe declares what it is able to establish — which is what lets a cache
// written by a weak probe be re-probed by a stronger one instead of being
// reused forever because its fingerprint happens to match.
enum DescriptorFlags : uint32_t {
  DescriptorFlagNone = 0,
  // The plugin was loaded and asked. Without this, `id`, `vendor`, `version`,
  // the port counts and `param_count` are all placeholders, and the UI must
  // present the row as "found, not yet inspected" rather than as a fact.
  DescriptorFlagIntrospected = 1U << 0U,
};

// Why a plugin is not available. Stored in the cache so that a quarantined
// plugin stays quarantined across restarts without being re-probed — which is
// the point, since re-probing it is what crashes (OB-2-03).
enum class ScanOutcome : uint8_t {
  // The probe succeeded and this row describes a usable plugin.
  Ok = 0,
  // The bundle exists but contains no plugin we can host: wrong architecture,
  // an unreadable binary, an entry point that returned nothing.
  NotAPlugin = 1,
  // The probe process died while loading, enumerating or instantiating.
  // OB-2-03 fills in the phase and signal; OB-2-02 only reserves the state.
  Crashed = 2,
  // The probe exceeded its watchdog. A hang is not a crash and the user-facing
  // copy differs ("stopped responding" vs "crashed"), so it is not folded in.
  TimedOut = 3,
};

const char* outcomeName(ScanOutcome outcome) noexcept;

// How far the probe got before it died (OB-2-03 scope §1).
//
// The phase is what makes the user-facing sentence specific: "Diva stopped
// responding while OneBeat was opening it" is actionable in a way that "the
// scan failed" is not, and the phase is also the first thing a vendor asks for
// in a bug report. It is recorded by the *parent*, from the last phase the
// helper announced before it went away — a process that just took SIGSEGV
// cannot be relied on to report anything.
enum class ScanPhase : uint8_t {
  // Never probed out of process — an in-process probe, or a row that predates
  // the helper. Not a failure.
  None = 0,
  // The helper was being started. A failure here is ours, not the plugin's:
  // a missing or unrunnable helper binary.
  Spawn = 1,
  // `dlopen`. Where the overwhelming majority of scan crashes happen, because
  // this is where a plugin's static initialisers and its licence check run.
  Load = 2,
  // Asking the entry point what the bundle contains.
  Enumerate = 3,
  // Creating an instance to read its ports and parameters. Not reached until
  // OB-2-07; the enumerator exists now so the copy table is written once.
  Instantiate = 4,
  // Finished cleanly. Recorded so "died after reporting everything" is
  // distinguishable from "died silently".
  Done = 5,
};

// Log and crash-report wording only. The *user-facing* sentence is composed in
// the UI from (outcome, phase), because `docs/errors.md` rule 1 puts the copy
// with the person and the code with the log — and because a phase name that has
// to satisfy both ends up serving neither.
const char* scanPhaseName(ScanPhase phase) noexcept;

// What makes a bundle "unchanged" for incremental scanning (scope §2).
//
// Content hashing a 200 MB bundle to decide whether to skip a 20 ms probe is
// the wrong trade, so this is (size, mtime) of the two files that actually
// change when a plugin is updated: the executable and the Info.plist. An
// installer that rewrites a bundle without touching either would be missed —
// but every installer sets mtime, and the user can always force a rescan.
struct BundleFingerprint {
  uint64_t binary_size = 0;
  int64_t binary_mtime_nanos = 0;
  uint64_t plist_size = 0;
  int64_t plist_mtime_nanos = 0;

  bool operator==(const BundleFingerprint& other) const noexcept {
    return binary_size == other.binary_size && binary_mtime_nanos == other.binary_mtime_nanos &&
           plist_size == other.plist_size && plist_mtime_nanos == other.plist_mtime_nanos;
  }
  bool operator!=(const BundleFingerprint& other) const noexcept { return !(*this == other); }

  // A fingerprint with nothing in it means "we could not stat the bundle".
  // Never equal to itself for scanning purposes: an unreadable bundle is
  // re-probed rather than cached as unchanged forever.
  bool valid() const noexcept { return binary_size != 0 || plist_size != 0; }
};

// One row of the cache.
//
// The member order is not cosmetic: it is chosen so the struct has **no padding
// at all**, interior or trailing, which is what makes it safe to write the raw
// bytes to a file. Padding bytes are uninitialised, so a checksum over a padded
// struct is unstable between two logically identical rows, and the file would
// carry whatever the stack happened to hold. `has_unique_object_representations`
// below is the assertion that keeps this true as fields are added — if it ever
// fires, add to `reserved` rather than reordering, which would invalidate every
// cache written so far.
struct PluginDescriptor {
  // --- identity (all fixed-capacity text, alignment 1) ---
  PluginId id;      // stable across versions; what projects reference
  PluginName name;  // display name
  VendorName vendor;
  VersionText version;
  PluginPath path;  // the bundle, not the executable inside it
  // The plugin's own feature list, verbatim and comma-separated
  // ("instrument,synthesizer,stereo"). Kept because the bitmask below is lossy
  // and the browser (FR-PLG-13) will want vendor-specific tags.
  FixedText<256> feature_text;

  // --- provenance (8-byte members first, so the text block's size is the only
  //     thing that has to stay a multiple of 8) ---
  BundleFingerprint fingerprint;
  // Unix nanoseconds. Used to show "last scanned" and to age out rows whose
  // bundle has vanished; never used for ordering, which is by name.
  int64_t scanned_at_nanos = 0;

  uint32_t features = PluginFeatureNone;
  // A summary, not the layout: the real port list is dynamic and only knowable
  // from a live instance (ports.h, DM-Q5). These exist so the browser can say
  // "stereo instrument" without loading anything, and the project loader can
  // warn before it instantiates.
  uint32_t param_count = 0;
  uint16_t audio_input_count = 0;
  uint16_t audio_output_count = 0;
  uint16_t note_input_count = 0;
  uint16_t note_output_count = 0;
  // Index of this plugin within its bundle. A CLAP bundle is a *factory*: one
  // file can contain a dozen plugins, so the cache key is (path, index), never
  // path alone.
  uint16_t index_in_bundle = 0;

  PluginFormat format = PluginFormat::Unknown;
  ScanOutcome outcome = ScanOutcome::Ok;

  // `DescriptorFlags`. Sits before the failure block because it is 4-byte
  // aligned and the block below is byte-aligned filler: together they make a
  // clean 8, which is what keeps the struct free of trailing padding.
  uint32_t flags = DescriptorFlagNone;

  // --- why it failed (OB-2-03), meaningful only when `quarantined()` ---
  ScanPhase failure_phase = ScanPhase::None;
  // The signal that killed the helper, or 0. Not always available: under a
  // sanitizer the runtime intercepts the fault and exits, so a real crash can
  // arrive as a non-zero exit code with no signal. Both are recorded; neither
  // alone is sufficient evidence.
  uint8_t failure_signal = 0;
  uint8_t failure_exit_code = 0;
  // Manual retries the user has spent on this row since it was quarantined.
  // Persisted so that "I already tried this three times" survives a restart,
  // and so a future version can stop offering *Retry* on a hopeless plugin.
  // The *automatic* retry needs no counter: it is triggered by the fingerprint
  // changing, which by definition happens once per new version.
  uint8_t retry_count = 0;
  // The growth point. Adding a field here moves nothing and reintroduces no
  // padding — unlike reordering, which invalidates every cache on disk.
  uint32_t reserved_ = 0;

  bool usable() const noexcept { return outcome == ScanOutcome::Ok; }
  bool introspected() const noexcept { return (flags & DescriptorFlagIntrospected) != 0; }

  // Crashed or hung: the plugin is not offered, is not re-probed on the next
  // launch, and is shown in the quarantined section with a *Retry* action.
  // `NotAPlugin` is deliberately *not* quarantine — a bundle for another
  // architecture is not a fault the user needs to be told about repeatedly.
  bool quarantined() const noexcept {
    return outcome == ScanOutcome::Crashed || outcome == ScanOutcome::TimedOut;
  }
};

static_assert(std::is_trivially_copyable_v<PluginDescriptor>,
              "the cache writes descriptors as raw bytes");
static_assert(std::has_unique_object_representations_v<PluginDescriptor>,
              "PluginDescriptor has padding: its unwritten bytes would make the cache checksum "
              "unstable and leak stack contents into the file. Fill `reserved` instead of "
              "reordering fields — reordering invalidates every cache already on disk.");

}  // namespace onebeat::plugin::scan
