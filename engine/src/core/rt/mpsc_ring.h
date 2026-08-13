// Bounded, lock-free, allocation-free ring for POD messages.
//
// Vyukov's bounded MPMC queue. We use it for the engine -> UI event channel:
// producers are the audio thread and the worker threads, the consumer is the
// UI thread draining once per frame. Push is safe from a [[clang::nonblocking]]
// context: no allocation, no lock, bounded retries.
#pragma once

#include <atomic>
#include <cstddef>
#include <cstdint>
#include <type_traits>

#include "core/rt/rt.h"

namespace onebeat::rt {

template <typename T, size_t Capacity>
class MpscRing {
  static_assert(std::is_trivially_copyable_v<T>, "RT queues carry POD only");
  static_assert((Capacity & (Capacity - 1)) == 0, "Capacity must be a power of two");

 public:
  MpscRing() noexcept {
    for (size_t i = 0; i < Capacity; ++i) {
      cells_[i].sequence.store(i, std::memory_order_relaxed);
    }
    enqueue_pos_.store(0, std::memory_order_relaxed);
    dequeue_pos_.store(0, std::memory_order_relaxed);
  }

  MpscRing(const MpscRing&) = delete;
  MpscRing& operator=(const MpscRing&) = delete;

  // Any thread, including the audio thread. Returns false when full; the caller
  // decides whether to drop and count (we always do — blocking is not an option).
  bool tryPush(const T& value) noexcept OB_NONBLOCKING {
    Cell* cell = nullptr;
    size_t pos = enqueue_pos_.load(std::memory_order_relaxed);
    for (;;) {
      cell = &cells_[pos & Mask];
      const size_t seq = cell->sequence.load(std::memory_order_acquire);
      const auto diff = static_cast<intptr_t>(seq) - static_cast<intptr_t>(pos);
      if (diff == 0) {
        if (enqueue_pos_.compare_exchange_weak(pos, pos + 1, std::memory_order_relaxed)) {
          break;
        }
      } else if (diff < 0) {
        return false;  // full
      } else {
        pos = enqueue_pos_.load(std::memory_order_relaxed);
      }
    }
    cell->data = value;
    cell->sequence.store(pos + 1, std::memory_order_release);
    return true;
  }

  // Single consumer only.
  bool tryPop(T& out) noexcept OB_NONBLOCKING {
    Cell* cell = nullptr;
    size_t pos = dequeue_pos_.load(std::memory_order_relaxed);
    for (;;) {
      cell = &cells_[pos & Mask];
      const size_t seq = cell->sequence.load(std::memory_order_acquire);
      const auto diff = static_cast<intptr_t>(seq) - static_cast<intptr_t>(pos + 1);
      if (diff == 0) {
        if (dequeue_pos_.compare_exchange_weak(pos, pos + 1, std::memory_order_relaxed)) {
          break;
        }
      } else if (diff < 0) {
        return false;  // empty
      } else {
        pos = dequeue_pos_.load(std::memory_order_relaxed);
      }
    }
    out = cell->data;
    cell->sequence.store(pos + Mask + 1, std::memory_order_release);
    return true;
  }

  static constexpr size_t capacity() noexcept { return Capacity; }

 private:
  static constexpr size_t Mask = Capacity - 1;

  struct alignas(64) Cell {
    std::atomic<size_t> sequence{0};
    T data{};
  };

  Cell cells_[Capacity];
  alignas(64) std::atomic<size_t> enqueue_pos_{0};
  alignas(64) std::atomic<size_t> dequeue_pos_{0};
};

}  // namespace onebeat::rt
