#include "core/transport.h"
#include "doctest.h"

using onebeat::core::Transport;

TEST_SUITE("unit") {
  TEST_CASE("Transport starts stopped at zero") {
    Transport transport;
    transport.prepare(48000.0, 120.0);
    CHECK_FALSE(transport.playing());
    CHECK(transport.positionFrames() == 0);
    CHECK(transport.tempo() == doctest::Approx(120.0));
  }

  TEST_CASE("A tempo change keeps the musical position continuous") {
    Transport transport;
    transport.prepare(48000.0, 120.0);
    transport.seekBeats(8.0);
    const double before = transport.timeMap().framesToBeats(transport.positionFrames());
    CHECK(before == doctest::Approx(8.0));

    transport.setTempo(174.0);
    const double after = transport.timeMap().framesToBeats(transport.positionFrames());
    CHECK(after == doctest::Approx(8.0).epsilon(0.0001));
    // Same musical place, different sample position: the mapping moved, not the music.
    CHECK(transport.positionFrames() != 48000 * 4);
  }

  TEST_CASE("framesUntilLoopWrap stops exactly at the loop end") {
    Transport transport;
    transport.prepare(48000.0, 120.0);
    transport.setLoop(0.0, 4.0, true);  // 4 beats = 96000 frames at 120 BPM
    transport.seekFrames(95900);
    CHECK(transport.framesUntilLoopWrap(512) == 100);
    transport.seekFrames(96000);
    CHECK(transport.framesUntilLoopWrap(512) == 0);

    transport.setLoop(0.0, 4.0, false);
    CHECK(transport.framesUntilLoopWrap(512) == 512);
  }

  TEST_CASE("Seeking clamps at zero and loop bounds are validated") {
    Transport transport;
    transport.prepare(48000.0, 120.0);
    transport.seekFrames(-100);
    CHECK(transport.positionFrames() == 0);

    transport.setLoop(4.0, 2.0, true);  // end before start: rejected, kept as-is
    CHECK(transport.loopStartBeats() == doctest::Approx(0.0));
    CHECK(transport.loopEndBeats() == doctest::Approx(16.0));
  }

}  // TEST_SUITE
