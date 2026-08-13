#include <atomic>
#include <chrono>
#include <thread>
#include <vector>

#include "core/rt/mpsc_ring.h"
#include "core/rt/publisher.h"
#include "core/rt/rt.h"
#include "core/rt/rt_log.h"
#include "core/rt/spsc_ring.h"
#include "doctest.h"

using onebeat::rt::MpscRing;
using onebeat::rt::NonRealtimeMutable;
using onebeat::rt::RtLog;
using onebeat::rt::SpscRing;

namespace {
struct Message {
  int producer;
  int value;
};
}  // namespace

TEST_SUITE("unit") {
  TEST_CASE("SPSC ring is bounded and never grows") {
    SpscRing<int, 4> ring;
    CHECK(ring.tryPush(1));
    CHECK(ring.tryPush(2));
    int value = 0;
    CHECK(ring.tryPop(value));
    CHECK(value == 1);
    CHECK(ring.tryPop(value));
    CHECK(value == 2);
    CHECK_FALSE(ring.tryPop(value));
  }

  TEST_CASE("MPSC ring reports full instead of blocking") {
    MpscRing<Message, 4> ring;
    for (int index = 0; index < 4; ++index) {
      CHECK(ring.tryPush(Message{0, index}));
    }
    CHECK_FALSE(ring.tryPush(Message{0, 99}));  // full: the caller drops and counts

    Message out{};
    CHECK(ring.tryPop(out));
    CHECK(out.value == 0);
    CHECK(ring.tryPush(Message{0, 4}));
  }

  TEST_CASE("MPSC ring loses nothing under concurrent producers") {
    constexpr int Producers = 4;
    constexpr int PerProducer = 2000;
    MpscRing<Message, 1024> ring;
    std::atomic<int> received{0};
    std::atomic<bool> done{false};
    std::vector<int> counts(Producers, 0);

    std::thread consumer([&] {
      Message message{};
      for (;;) {
        if (ring.tryPop(message)) {
          ++counts[static_cast<size_t>(message.producer)];
          received.fetch_add(1);
        } else if (done.load()) {
          break;  // producers finished and the ring has drained
        }
      }
    });

    std::vector<std::thread> producers;
    producers.reserve(Producers);
    for (int producer = 0; producer < Producers; ++producer) {
      producers.emplace_back([&, producer] {
        for (int index = 0; index < PerProducer; ++index) {
          while (!ring.tryPush(Message{producer, index})) {
            std::this_thread::yield();
          }
        }
      });
    }
    for (std::thread& thread : producers) {
      thread.join();
    }
    done.store(true);
    consumer.join();

    CHECK(received.load() == Producers * PerProducer);
    for (const int count : counts) {
      CHECK(count == PerProducer);
    }
  }

  TEST_CASE("RT log drops rather than blocks, and counts what it dropped") {
    RtLog log;
    for (size_t index = 0; index < RtLog::Capacity + 64; ++index) {
      log.log(onebeat::rt::LogLevel::Info, onebeat::rt::RtMessage::Xrun, 1, 2);
    }
    CHECK(log.droppedCount() > 0);

    onebeat::rt::RtLogRecord record{};
    REQUIRE(log.pop(record));
    char formatted[128];
    RtLog::format(record, formatted, sizeof(formatted));
    CHECK(std::string(formatted).find("xrun") != std::string::npos);
  }

  TEST_CASE("Published objects are retired, not freed, until the audio thread has moved on") {
    NonRealtimeMutable<int> published;
    published.publish(std::make_unique<int>(1));
    CHECK(*published.acquire() == 1);

    published.publish(std::make_unique<int>(2));
    CHECK(*published.acquire() == 2);
    CHECK(published.retiredCount() == 1);

    // While the audio thread is running, one block is not enough: the block that
    // was in flight at publish time may still hold the old pointer.
    published.beginBlock();
    published.collect(/*rt_running=*/true);
    CHECK(published.retiredCount() == 1);

    published.beginBlock();
    published.collect(/*rt_running=*/true);
    CHECK(published.retiredCount() == 0);
  }

  TEST_CASE("Retired objects are freed immediately when the audio thread is stopped") {
    NonRealtimeMutable<int> published;
    published.publish(std::make_unique<int>(1));
    published.publish(std::make_unique<int>(2));
    published.collect(/*rt_running=*/false);
    CHECK(published.retiredCount() == 0);
  }

  TEST_CASE("The monotonic clock advances and never goes backwards") {
    const uint64_t first = onebeat::rt::monotonicNanos();
    uint64_t previous = first;
    for (int index = 0; index < 1000; ++index) {
      const uint64_t now = onebeat::rt::monotonicNanos();
      CHECK(now >= previous);
      previous = now;
    }
    CHECK(previous >= first);
  }

}  // TEST_SUITE
