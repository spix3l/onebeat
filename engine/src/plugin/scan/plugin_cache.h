// The persistent scan cache (OB-2-02 scope §3).
//
// **Format decision, made in-ticket: a versioned flat binary file, not SQLite.**
//
// The ticket left the choice open. Flat file wins here for three reasons, and
// the reasons are worth recording because the balance changes later:
//
//   1. `PluginDescriptor` is already a padding-free POD (OB-2-01 chose fixed
//      capacity text precisely so these structs could be copied, not
//      serialised). The whole cache is therefore one header plus an array —
//      `read()` once, `write()` once. There is no ORM, no schema DDL, no query.
//   2. The access pattern is *load everything at boot, rewrite everything after
//      a scan*. That is the pattern SQLite is worst at relative to its cost:
//      500 rows is half a megabyte, read in about a millisecond.
//   3. A dependency has to pass the licence audit and be carried forever
//      (NFR-08). Adding one to avoid ~150 lines is a bad trade.
//
// **When to revisit:** FR-PLG-13's browser (Stage 7) wants search, favourites
// and tags across a library that may be tens of thousands of entries, with
// partial updates. That is a database's job, and at that point this file
// becomes a migration source rather than an embarrassment.
//
// Corruption is a first-class case, not an error path: a cache is a derived
// artefact, so anything that fails validation is discarded and rebuilt. Nothing
// here can throw or crash on hostile input — see `load()`.
#pragma once

#include <cstdint>
#include <string>
#include <vector>

#include "plugin/scan/descriptor.h"

namespace onebeat::plugin::scan {

// Bumped whenever `PluginDescriptor`'s layout changes. An older or newer file
// is not migrated — it is dropped and rescanned, which costs one scan and
// removes every migration bug that would otherwise live here forever.
//
//   1 — OB-2-02, the original layout.
//   2 — OB-2-03 added the failure block (phase, signal, exit code, retries).
//       Every v1 cache is discarded on first launch after the upgrade. That is
//       the right trade at this size: one rescan, once, against a migration
//       path that would have to be maintained forever.
inline constexpr uint32_t CacheSchemaVersion = 2;

enum class CacheLoadResult : uint8_t {
  Ok = 0,
  // No file yet. The first run and a deliberately deleted cache look identical,
  // which is intended: both mean "scan everything".
  Missing = 1,
  // The file exists but is not ours, is a different schema, is truncated, or
  // fails its checksum. Indistinguishable to the caller on purpose — every one
  // of them means the same thing: rebuild.
  Rebuilt = 2,
};

const char* cacheLoadResultName(CacheLoadResult result) noexcept;

class PluginCache {
 public:
  // ~/Library/Application Support/OneBeat/plugin-cache.bin
  static std::string defaultPath();

  explicit PluginCache(std::string path);

  // Replaces the in-memory contents. Never throws and never leaves the cache in
  // a half-loaded state: a file that fails any check yields an empty cache and
  // `Rebuilt`, and the caller carries on as though it were the first run.
  CacheLoadResult load();

  // Atomic: writes a sibling temp file, flushes it to disk, then renames over
  // the target. A crash mid-save leaves either the old cache or the new one,
  // never a truncated file — which matters because the truncated case is
  // exactly what the user would hit after a power cut, and "rebuild" is a five
  // second penalty they did not ask for.
  bool save() const;

  const std::vector<PluginDescriptor>& entries() const noexcept { return entries_; }
  size_t size() const noexcept { return entries_.size(); }

  // Rows are keyed by (path, index_in_bundle): one bundle is a factory that may
  // contain many plugins, so the path alone is not unique.
  const PluginDescriptor* find(const char* path, uint16_t index_in_bundle) const noexcept;

  // Insert or replace by that same key.
  void upsert(const PluginDescriptor& descriptor);

  // Drops every row whose path is not in `live_paths`, so a plugin the user
  // deleted stops appearing in the browser. Returns how many rows went.
  size_t retainOnly(const std::vector<std::string>& live_paths);

  void clear() noexcept { entries_.clear(); }

  const std::string& path() const noexcept { return path_; }

 private:
  std::string path_;
  std::vector<PluginDescriptor> entries_;
};

// Exposed for tests: the exact bytes `save()` writes, so a test can corrupt a
// specific field rather than a random byte and assert on the specific rejection.
struct CacheFileHeader {
  uint32_t magic;  // 'OBPC'
  uint32_t schema_version;
  uint64_t entry_count;
  uint64_t payload_checksum;  // FNV-1a 64 over the descriptor array
};

inline constexpr uint32_t CacheMagic = 0x4342504FU;  // 'OBPC' little-endian

uint64_t fnv1a64(const void* data, size_t size) noexcept;

}  // namespace onebeat::plugin::scan
