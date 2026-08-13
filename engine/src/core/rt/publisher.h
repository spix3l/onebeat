// NonRealtimeMutable<T>: the publish/retire pattern, once, for everything the
// audio thread reads but never writes (OB-1-06 §3, OB-1-07 §2/§3).
//
// A writer thread builds a *complete, immutable* T off the audio thread and
// publishes it with a single release store. The audio thread does exactly one
// acquire load per block and then reads the object without any synchronisation.
// Superseded objects are retired and freed on a non-RT thread.
//
// Reclamation proof (the thing that makes this safe without RCU machinery):
//
//   The audio thread runs one block at a time. At the top of block N it does
//   `beginBlock()` (fetch_add on `rt_epoch_`, giving the value N) and *then*
//   loads the pointer. `publish()` stores the new pointer and only afterwards
//   reads `rt_epoch_` as R, recording it on the retired object.
//
//   Any load that returned the old pointer happened before the store to
//   `current_` (coherence order), which happened before the read of R.
//   Therefore that load's block had already done its fetch_add before R was
//   read, so its block index is <= R. Blocks are sequential on one thread, so
//   once `rt_epoch_` reaches R + 2 every block with index <= R has finished and
//   the old pointer is unreachable. If the audio thread is not running at all,
//   nothing can be holding a pointer, and retired objects are freed at once.
#pragma once

#include <atomic>
#include <cstdint>
#include <memory>
#include <mutex>
#include <vector>

#include "core/rt/rt.h"

namespace onebeat::rt {

template <typename T>
class NonRealtimeMutable {
 public:
  NonRealtimeMutable() = default;
  ~NonRealtimeMutable() {
    // Destruction happens after the device is stopped and joined.
    delete current_.load(std::memory_order_acquire);
    std::lock_guard<std::mutex> lock(retired_mutex_);
    retired_.clear();
  }

  NonRealtimeMutable(const NonRealtimeMutable&) = delete;
  NonRealtimeMutable& operator=(const NonRealtimeMutable&) = delete;

  // Audio thread, once per block, before reading. Not optional: reclamation
  // correctness depends on the epoch advancing exactly once per block.
  void beginBlock() noexcept OB_NONBLOCKING { rt_epoch_.fetch_add(1, std::memory_order_acq_rel); }

  // Audio thread. One acquire load per block; the returned object is immutable
  // and stays valid for the whole block.
  const T* acquire() const noexcept OB_NONBLOCKING {
    return current_.load(std::memory_order_acquire);
  }

  // Any non-RT thread. Takes ownership. The previously published object is
  // retired, not freed.
  void publish(std::unique_ptr<T> next) {
    T* const previous = current_.exchange(next.release(), std::memory_order_acq_rel);
    generation_.fetch_add(1, std::memory_order_release);
    if (previous == nullptr) {
      return;
    }
    const uint64_t retire_epoch = rt_epoch_.load(std::memory_order_acquire);
    std::lock_guard<std::mutex> lock(retired_mutex_);
    retired_.push_back(Retired{std::unique_ptr<T>(previous), retire_epoch});
  }

  // Non-RT reclamation thread. Frees everything the audio thread provably can
  // no longer observe. `rt_running` false means no callback can hold anything.
  size_t collect(bool rt_running) {
    const uint64_t epoch = rt_epoch_.load(std::memory_order_acquire);
    std::vector<std::unique_ptr<T>> doomed;
    {
      std::lock_guard<std::mutex> lock(retired_mutex_);
      for (auto it = retired_.begin(); it != retired_.end();) {
        if (!rt_running || epoch >= it->epoch + 2) {
          doomed.push_back(std::move(it->object));
          it = retired_.erase(it);
        } else {
          ++it;
        }
      }
    }
    return doomed.size();  // frees on the way out, outside the lock
  }

  size_t retiredCount() const {
    std::lock_guard<std::mutex> lock(retired_mutex_);
    return retired_.size();
  }

  uint64_t generation() const noexcept { return generation_.load(std::memory_order_acquire); }
  uint64_t epoch() const noexcept { return rt_epoch_.load(std::memory_order_acquire); }

 private:
  struct Retired {
    std::unique_ptr<T> object;
    uint64_t epoch;
  };

  alignas(64) std::atomic<T*> current_{nullptr};
  alignas(64) std::atomic<uint64_t> rt_epoch_{0};
  std::atomic<uint64_t> generation_{0};
  mutable std::mutex retired_mutex_;
  std::vector<Retired> retired_;
};

}  // namespace onebeat::rt
