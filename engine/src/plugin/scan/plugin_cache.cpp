#include "plugin/scan/plugin_cache.h"

#include <cerrno>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <system_error>

namespace onebeat::plugin::scan {
namespace {

static_assert(sizeof(CacheFileHeader) == 24, "the cache header is written as raw bytes");
static_assert(std::has_unique_object_representations_v<CacheFileHeader>,
              "padding in the header would be written uninitialised");

// A cache larger than this is not a cache, it is a corrupt length field. The
// bound exists so that a garbage `entry_count` cannot make us try to allocate
// petabytes before we have checked anything else — validation has to survive
// hostile input, and "allocate first, validate second" is how that goes wrong.
// 200,000 plugins is roughly 400× the 500 NFR-04 asks about.
constexpr uint64_t MaxCacheEntries = 200000;
#if defined(_WIN32)
constexpr const char* ReadMode = "rb";
constexpr const char* WriteMode = "wb";
#else
constexpr const char* ReadMode = "rbe";
constexpr const char* WriteMode = "wbe";
#endif

// Fixed-capacity text arrives from disk with no guarantee of a terminator. Every
// consumer of a descriptor treats these as C strings, so a missing NUL is a read
// off the end of the struct — the one memory-safety hazard in a POD cache.
template <size_t Capacity>
void terminate(FixedText<Capacity>& text) noexcept {
  text.value[Capacity - 1] = '\0';
}

template <typename Enum>
void clampEnum(Enum& value, Enum max_valid) noexcept {
  using Underlying = std::underlying_type_t<Enum>;
  if (static_cast<Underlying>(value) > static_cast<Underlying>(max_valid)) {
    value = static_cast<Enum>(0);
  }
}

// Everything a corrupt-but-checksum-valid row could do to us. The checksum
// catches accidental damage; this catches a file someone edited on purpose, and
// costs a few hundred nanoseconds per row.
void sanitize(PluginDescriptor& descriptor) noexcept {
  terminate(descriptor.id);
  terminate(descriptor.name);
  terminate(descriptor.vendor);
  terminate(descriptor.version);
  terminate(descriptor.path);
  terminate(descriptor.feature_text);
  clampEnum(descriptor.format, PluginFormat::AudioUnit);
  clampEnum(descriptor.outcome, ScanOutcome::TimedOut);
  clampEnum(descriptor.failure_phase, ScanPhase::Done);
}

// Small RAII wrapper so the several early returns below cannot leak a FILE*.
class FileHandle {
 public:
  FileHandle(const char* path, const char* mode) noexcept : file_(std::fopen(path, mode)) {}
  ~FileHandle() {
    if (file_ != nullptr) {
      std::fclose(file_);
    }
  }
  FileHandle(const FileHandle&) = delete;
  FileHandle& operator=(const FileHandle&) = delete;

  FILE* get() const noexcept { return file_; }
  explicit operator bool() const noexcept { return file_ != nullptr; }

  // Hands ownership back so the caller can check the close() return value, which
  // is the only place a buffered write reports ENOSPC.
  bool closeChecked() noexcept {
    FILE* file = file_;
    file_ = nullptr;
    return file == nullptr || std::fclose(file) == 0;
  }

 private:
  FILE* file_ = nullptr;
};

}  // namespace

uint64_t fnv1a64(const void* data, size_t size) noexcept {
  const auto* bytes = static_cast<const unsigned char*>(data);
  uint64_t hash = 0xCBF29CE484222325ULL;
  for (size_t i = 0; i < size; ++i) {
    hash ^= bytes[i];
    hash *= 0x100000001B3ULL;
  }
  return hash;
}

const char* cacheLoadResultName(CacheLoadResult result) noexcept {
  switch (result) {
    case CacheLoadResult::Ok:
      return "ok";
    case CacheLoadResult::Missing:
      return "missing";
    case CacheLoadResult::Rebuilt:
      return "rebuilt";
  }
  return "unknown";
}

std::string PluginCache::defaultPath() {
  const char* home = std::getenv("HOME");
  const std::string base = home != nullptr ? std::string(home) : std::string("/tmp");
  return base + "/Library/Application Support/OneBeat/plugin-cache.bin";
}

PluginCache::PluginCache(std::string path) : path_(std::move(path)) {}

CacheLoadResult PluginCache::load() {
  entries_.clear();

  FileHandle file(path_.c_str(), ReadMode);
  if (!file) {
    return errno == ENOENT ? CacheLoadResult::Missing : CacheLoadResult::Rebuilt;
  }

  CacheFileHeader header{};
  if (std::fread(&header, sizeof(header), 1, file.get()) != 1) {
    return CacheLoadResult::Rebuilt;
  }
  if (header.magic != CacheMagic || header.schema_version != CacheSchemaVersion) {
    return CacheLoadResult::Rebuilt;
  }
  if (header.entry_count > MaxCacheEntries) {
    return CacheLoadResult::Rebuilt;
  }

  std::vector<PluginDescriptor> loaded(static_cast<size_t>(header.entry_count));
  if (header.entry_count > 0) {
    if (std::fread(loaded.data(), sizeof(PluginDescriptor), loaded.size(), file.get()) !=
        loaded.size()) {
      return CacheLoadResult::Rebuilt;  // truncated
    }
  }

  // A trailing byte means the file is not what it claims to be, and the cheapest
  // way that happens is a schema change that forgot to bump the version.
  if (std::fgetc(file.get()) != EOF) {
    return CacheLoadResult::Rebuilt;
  }

  const uint64_t checksum = loaded.empty()
                                ? fnv1a64("", 0)
                                : fnv1a64(loaded.data(), loaded.size() * sizeof(PluginDescriptor));
  if (checksum != header.payload_checksum) {
    return CacheLoadResult::Rebuilt;
  }

  for (PluginDescriptor& descriptor : loaded) {
    sanitize(descriptor);
  }
  entries_ = std::move(loaded);
  return CacheLoadResult::Ok;
}

bool PluginCache::save() const {
  std::error_code code;
  const std::filesystem::path target(path_);
  std::filesystem::create_directories(target.parent_path(), code);

  // A sibling, so the rename below is within one filesystem and therefore
  // atomic. A temp file in /tmp would make it a copy, which is not.
  const std::string temp_path = path_ + ".tmp";

  {
    FileHandle file(temp_path.c_str(), WriteMode);
    if (!file) {
      return false;
    }

    CacheFileHeader header{};
    header.magic = CacheMagic;
    header.schema_version = CacheSchemaVersion;
    header.entry_count = entries_.size();
    header.payload_checksum =
        entries_.empty() ? fnv1a64("", 0)
                         : fnv1a64(entries_.data(), entries_.size() * sizeof(PluginDescriptor));

    if (std::fwrite(&header, sizeof(header), 1, file.get()) != 1) {
      std::filesystem::remove(temp_path, code);
      return false;
    }
    if (!entries_.empty() && std::fwrite(entries_.data(), sizeof(PluginDescriptor), entries_.size(),
                                         file.get()) != entries_.size()) {
      std::filesystem::remove(temp_path, code);
      return false;
    }
    if (!file.closeChecked()) {
      std::filesystem::remove(temp_path, code);
      return false;
    }
  }

  std::filesystem::rename(temp_path, target, code);
  if (code) {
    std::filesystem::remove(temp_path, code);
    return false;
  }
  return true;
}

const PluginDescriptor* PluginCache::find(const char* path,
                                          uint16_t index_in_bundle) const noexcept {
  if (path == nullptr) {
    return nullptr;
  }
  for (const PluginDescriptor& descriptor : entries_) {
    if (descriptor.index_in_bundle == index_in_bundle &&
        std::strcmp(descriptor.path.text(), path) == 0) {
      return &descriptor;
    }
  }
  return nullptr;
}

void PluginCache::upsert(const PluginDescriptor& descriptor) {
  for (PluginDescriptor& existing : entries_) {
    if (existing.index_in_bundle == descriptor.index_in_bundle &&
        std::strcmp(existing.path.text(), descriptor.path.text()) == 0) {
      existing = descriptor;
      return;
    }
  }
  entries_.push_back(descriptor);
}

size_t PluginCache::retainOnly(const std::vector<std::string>& live_paths) {
  const size_t before = entries_.size();
  std::vector<PluginDescriptor> kept;
  kept.reserve(entries_.size());
  for (const PluginDescriptor& descriptor : entries_) {
    for (const std::string& live : live_paths) {
      if (live == descriptor.path.text()) {
        kept.push_back(descriptor);
        break;
      }
    }
  }
  entries_ = std::move(kept);
  return before - entries_.size();
}

}  // namespace onebeat::plugin::scan
