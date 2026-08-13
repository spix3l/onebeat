#include <cmath>

#include "core/time_map.h"
#include "doctest.h"

using onebeat::core::TimeMap;

TEST_SUITE("unit") {
  TEST_CASE("TimeMap round-trips beats and frames across every supported rate") {
    for (const double rate : {44100.0, 48000.0, 88200.0, 96000.0}) {
      for (const double tempo : {20.0, 90.0, 120.0, 174.0, 300.0, 999.0}) {
        const TimeMap map(rate, tempo);
        for (const double beats : {0.0, 1.0, 4.0, 16.5, 128.25, 1024.0}) {
          const int64_t frames = map.beatsToFrames(beats);
          // Round-trip is exact to within the half-sample the rounding allows.
          CHECK(std::abs(map.framesToBeats(frames) - beats) < (1.0 / map.framesPerBeat()));
        }
      }
    }
  }

  TEST_CASE("TimeMap clamps tempo to the documented 20..999 range") {
    TimeMap map(48000.0, 120.0);
    map.setTempo(0.0);
    CHECK(map.tempo() == doctest::Approx(20.0));
    map.setTempo(5000.0);
    CHECK(map.tempo() == doctest::Approx(999.0));
    map.setTempo(174.0);
    CHECK(map.tempo() == doctest::Approx(174.0));
  }

  TEST_CASE("Musical position is 1-based bars and beats with 960 PPQN ticks") {
    const TimeMap map(48000.0, 120.0);  // one beat = 24000 frames
    auto position = map.musicalPosition(0);
    CHECK(position.bar == 1);
    CHECK(position.beat == 1);
    CHECK(position.tick == 0);

    position = map.musicalPosition(24000 * 4);  // exactly bar 2
    CHECK(position.bar == 2);
    CHECK(position.beat == 1);
    CHECK(position.tick == 0);

    position = map.musicalPosition((24000 * 5) + 12000);  // bar 2, beat 2, half beat
    CHECK(position.bar == 2);
    CHECK(position.beat == 2);
    CHECK(position.tick == 480);
  }

  TEST_CASE("Frames per beat matches the arithmetic definition") {
    const TimeMap map(48000.0, 120.0);
    CHECK(map.framesPerBeat() == doctest::Approx(24000.0));
    CHECK(map.framesToSeconds(48000) == doctest::Approx(1.0));
  }

}  // TEST_SUITE
