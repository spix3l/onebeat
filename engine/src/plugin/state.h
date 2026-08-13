// Opaque state chunks (OB-2-01 scope §5, groundwork for FR-PLG-08).
//
// A plugin's state is a byte blob the host must never interpret. That is not a
// simplification, it is the requirement: FR-PLG-10 says a project must open and
// keep its state when the plugin is *missing*, which is only possible if the
// host stores the blob without understanding it, and FR-PLG-08 says vendor
// chunks survive a round trip intact.
//
// Streams rather than a returned buffer, because plugin states run to megabytes
// (sampler content, convolution IRs) and both CLAP and VST3 hand them over
// incrementally. The host chooses where the bytes land — memory now, the project
// bundle in Stage 3.
#pragma once

#include <cstddef>
#include <cstdint>
#include <cstring>
#include <vector>

namespace onebeat::plugin {

// [main-thread] Allocation and I/O are expected here; this never runs on the
// audio thread, and a plugin that saves state from process() is broken.
class StateWriter {
 public:
  virtual ~StateWriter() = default;
  // Returns false on a short write; the caller must abandon the save. Partial
  // state is worse than no state — it loads as garbage rather than failing.
  virtual bool write(const void* data, size_t size) = 0;
};

class StateReader {
 public:
  virtual ~StateReader() = default;
  // Returns the number of bytes actually read; 0 means end of stream.
  virtual size_t read(void* data, size_t size) = 0;
  virtual size_t remaining() const = 0;
};

// The in-memory implementations. Tests use them, and so does the missing-plugin
// placeholder (FR-PLG-10), which holds a state it cannot give to anyone yet.
class MemoryStateWriter final : public StateWriter {
 public:
  bool write(const void* data, size_t size) override {
    const auto* bytes = static_cast<const uint8_t*>(data);
    buffer_.insert(buffer_.end(), bytes, bytes + size);
    return true;
  }

  const std::vector<uint8_t>& bytes() const noexcept { return buffer_; }

 private:
  std::vector<uint8_t> buffer_;
};

class MemoryStateReader final : public StateReader {
 public:
  explicit MemoryStateReader(std::vector<uint8_t> bytes) : buffer_(std::move(bytes)) {}

  size_t read(void* data, size_t size) override {
    const size_t available = buffer_.size() - position_;
    const size_t copied = size < available ? size : available;
    if (copied > 0) {
      std::memcpy(data, buffer_.data() + position_, copied);
      position_ += copied;
    }
    return copied;
  }

  size_t remaining() const override { return buffer_.size() - position_; }

 private:
  std::vector<uint8_t> buffer_;
  size_t position_ = 0;
};

}  // namespace onebeat::plugin
