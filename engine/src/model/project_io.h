// Saving and loading the `.obt` bundle (OB-3-05; ADR-004; the normative schema
// is docs/project-format.md, which this file implements and must not diverge
// from).
//
// Three properties this file exists to keep:
//
//  1. **A save never destroys the previous save.** The bundle is staged
//     complete beside its destination and swapped in one atomic step. A crash
//     at any instant either leaves the old bundle or the new one, never a
//     half-written mixture (§1, "kill -9 during save").
//
//  2. **A load reports rather than refuses.** A project whose clip names a
//     pattern that is gone still opens; the clip is dropped and the person is
//     told which one and why (FR-UX-12). Only three things fail a load outright:
//     unreadable JSON, a foreign `format`, and a `version` from a newer build —
//     the last because partially understanding a future project and then saving
//     over it is how a user loses work they cannot get back.
//
//  3. **What we do not understand survives.** Unknown fields, unknown entities,
//     unknown top-level maps and unknown per-note properties are carried in the
//     `Residue` and written back in canonical position, so that a project
//     opened in an older build and saved is not silently stripped
//     (FR-PRJ-03, docs/project-format.md §7).
#pragma once

#include <cstddef>
#include <cstdint>
#include <filesystem>
#include <functional>
#include <map>
#include <string>
#include <vector>

#include "model/json.h"
#include "model/project.h"

namespace onebeat::model {

// --------------------------------------------------------------------------
// Reporting
// --------------------------------------------------------------------------

struct LoadIssue {
  // `Error` means the load failed or something was dropped; `Warning` means
  // something was repaired; `Info` means something was kept but not understood.
  // The UI shows errors and warnings and logs everything (docs/errors.md).
  enum class Severity : uint8_t { Info, Warning, Error };

  Severity severity = Severity::Info;
  std::string message;
};

struct LoadReport {
  bool ok = false;  // false ⇒ the project was not loaded at all
  std::vector<LoadIssue> issues;

  bool clean() const { return ok && issues.empty(); }
  size_t count(LoadIssue::Severity severity) const;
  // One line per issue, for the log and for tests.
  std::string describe() const;
};

// --------------------------------------------------------------------------
// Residue: everything the reader did not understand
// --------------------------------------------------------------------------

// Kept beside the model rather than inside it. Putting unknown fields on
// `Instrument` would mean every entity carries a JSON blob for the sake of the
// load path, and every command, copy and undo record would carry it too.
//
// Note properties are keyed by the note's own values rather than by index: a
// note that was edited is no longer the note the properties described, and
// attaching them to whatever now sits at that index would silently move
// somebody's data onto a different note. The properties of an edited or deleted
// note are dropped, which is the only honest answer a reader that does not
// understand them can give.
struct Residue {
  json::Value document;  // the parsed file with every field we consumed removed
  std::map<std::string, json::Value> note_properties;

  // "<pattern id>/<instrument id>/<start>/<length>/<key>/<velocity>"
  static std::string noteKey(PatternId pattern, InstrumentId instrument, const Note& note);
};

// --------------------------------------------------------------------------
// Loading
// --------------------------------------------------------------------------

// Receives one instrument's opaque plugin chunk during a load. The model has no
// idea what a plugin is; the host layer does. A sink that is not set means
// "read the project, skip the state", which is what the tests and any headless
// consumer want.
using StateSink = std::function<void(InstrumentId, const std::vector<std::byte>&)>;

struct LoadOptions {
  StateSink state_sink;
  // Off for a plain read of `project.json` without its sidecars.
  bool load_state = true;
};

// Replaces `project` wholesale. On failure (`report.ok == false`) the project
// is left untouched — an unreadable file must not cost the user the session
// they already have open.
LoadReport loadProject(const std::filesystem::path& bundle, Project& project, Residue& residue,
                       const LoadOptions& options = {});

// The text half, without a filesystem: used by the round-trip tests and by
// anything that already has the bytes.
LoadReport loadProjectJson(std::string_view text, Project& project, Residue& residue);

// --------------------------------------------------------------------------
// Saving
// --------------------------------------------------------------------------

// Produces one instrument's plugin chunk. Returning an empty vector means "this
// instrument has no state"; not setting the provider at all means "do not ask",
// and the sidecars already in the bundle are carried across untouched.
using StateProvider = std::function<std::vector<std::byte>(InstrumentId)>;

struct SaveOptions {
  // Written to `meta.created_with`. Empty keeps whatever the project already
  // carries, so that opening and saving a v0.2 project does not rewrite its
  // provenance for no reason.
  std::string created_with;

  StateProvider state_provider;

  // Where to copy existing sidecars from when `state_provider` supplies none.
  // Normally the bundle the project was loaded from; set it for Save As, or the
  // copy leaves its plugin state behind.
  std::filesystem::path copy_state_from;

  // Fault injection for the atomicity test: called after the new bundle is
  // fully staged and before it is swapped in — the exact instant at which a
  // crash must still leave the previous save intact. Never set in production.
  std::function<void()> crash_hook;
};

struct SaveReport {
  bool ok = false;
  std::string error;  // empty when ok

  size_t bytes_written = 0;
  // What was written to `state/`, so the caller can fold the new `state_ref`
  // and `state_sha256` back into the model through a command. Saving does not
  // mutate the model itself: a save is not an edit, and must not dirty the
  // undo history or the change bus.
  struct StateRecord {
    std::string state_ref;
    std::string sha256;
  };
  std::map<InstrumentId, StateRecord> state_written;
};

SaveReport saveProject(const std::filesystem::path& bundle, const Project& project,
                       const Residue& residue, const SaveOptions& options = {});

// The canonical bytes of `project.json` for this model. Byte-identical for a
// given model on any machine in any locale (docs/project-format.md §6).
std::string writeProjectJson(const Project& project, const Residue& residue,
                             const std::string& created_with = {},
                             const std::map<InstrumentId, SaveReport::StateRecord>& state = {});

// Lowercase hex SHA-256. Here rather than in a utility header because the only
// thing the model hashes is a plugin state chunk, and `state_sha256` is a field
// of this format (docs/project-format.md §5.1).
std::string sha256Hex(const std::byte* data, size_t size);
std::string sha256Hex(std::string_view text);

}  // namespace onebeat::model
