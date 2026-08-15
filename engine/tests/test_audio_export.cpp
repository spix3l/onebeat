// Audio export: the writer, the resampler, and a whole song rendered to disk.
#include <cmath>
#include <cstdint>
#include <filesystem>
#include <string>
#include <vector>

#include "core/audio_export.h"
#include "core/wav_loader.h"
#include "doctest.h"
#include "test_helpers.h"

namespace {

std::string scratchPath(const std::string& name) {
  const std::filesystem::path directory = std::filesystem::temp_directory_path() / "onebeat-export";
  std::error_code ignored;
  std::filesystem::create_directories(directory, ignored);
  return (directory / name).string();
}

std::vector<uint8_t> readBytes(const std::string& path) {
  std::vector<uint8_t> bytes;
  std::FILE* file = std::fopen(path.c_str(), "rbe");
  if (file == nullptr) return bytes;
  uint8_t buffer[4096];
  size_t read = 0;
  while ((read = std::fread(buffer, 1, sizeof(buffer), file)) > 0) {
    bytes.insert(bytes.end(), buffer, buffer + read);
  }
  std::fclose(file);
  return bytes;
}

std::string tagAt(const std::vector<uint8_t>& bytes, size_t offset) {
  if (bytes.size() < offset + 4) return {};
  return std::string(reinterpret_cast<const char*>(bytes.data() + offset), 4);
}

uint32_t littleAt(const std::vector<uint8_t>& bytes, size_t offset, int width) {
  uint32_t value = 0;
  for (int index = width - 1; index >= 0; --index) {
    value = (value << 8) | bytes[offset + static_cast<size_t>(index)];
  }
  return value;
}

uint32_t bigAt(const std::vector<uint8_t>& bytes, size_t offset, int width) {
  uint32_t value = 0;
  for (int index = 0; index < width; ++index) {
    value = (value << 8) | bytes[offset + static_cast<size_t>(index)];
  }
  return value;
}

}  // namespace

TEST_SUITE("unit") {
  TEST_CASE("A written WAV has a 24-bit stereo header and the frames it was given") {
    const std::string path = scratchPath("writer.wav");
    onebeat::core::AudioFileWriter writer;
    std::string error;
    REQUIRE_MESSAGE(writer.open(path, onebeat::core::ExportFormat::Wav, 44100, error), error);

    const std::vector<float> left(100, 0.5F);
    const std::vector<float> right(100, -0.5F);
    REQUIRE(writer.write(left.data(), right.data(), 100, error));
    REQUIRE_MESSAGE(writer.close(error), error);

    const std::vector<uint8_t> bytes = readBytes(path);
    REQUIRE(bytes.size() == 44U + (100U * 6U));
    CHECK(tagAt(bytes, 0) == "RIFF");
    CHECK(tagAt(bytes, 8) == "WAVE");
    CHECK(littleAt(bytes, 4, 4) == 36U + 600U);
    CHECK(littleAt(bytes, 22, 2) == 2);      // channels
    CHECK(littleAt(bytes, 24, 4) == 44100);  // sample rate
    CHECK(littleAt(bytes, 34, 2) == 24);     // bits
    CHECK(littleAt(bytes, 40, 4) == 600U);   // data bytes

    // 0.5 at 24-bit full scale, little-endian.
    const uint32_t first = littleAt(bytes, 44, 3);
    CHECK(first == static_cast<uint32_t>(std::lround(0.5 * 8388607.0)));

    std::error_code ignored;
    std::filesystem::remove(path, ignored);
  }

  TEST_CASE("A written AIFF carries its rate as an 80-bit extended float") {
    const std::string path = scratchPath("writer.aiff");
    onebeat::core::AudioFileWriter writer;
    std::string error;
    REQUIRE_MESSAGE(writer.open(path, onebeat::core::ExportFormat::Aiff, 44100, error), error);
    const std::vector<float> silence(64, 0.0F);
    REQUIRE(writer.write(silence.data(), silence.data(), 64, error));
    REQUIRE_MESSAGE(writer.close(error), error);

    const std::vector<uint8_t> bytes = readBytes(path);
    REQUIRE(bytes.size() == 54U + (64U * 6U));
    CHECK(tagAt(bytes, 0) == "FORM");
    CHECK(tagAt(bytes, 8) == "AIFF");
    CHECK(tagAt(bytes, 12) == "COMM");
    CHECK(bigAt(bytes, 20, 2) == 2);   // channels
    CHECK(bigAt(bytes, 22, 4) == 64);  // frames
    CHECK(bigAt(bytes, 26, 2) == 24);  // bits
    // 44100 == 0xAC44 * 2^-... : exponent 0x400E with the leading bit explicit.
    CHECK(bigAt(bytes, 28, 2) == 0x400E);
    CHECK(bigAt(bytes, 30, 2) == 0xAC44);
    CHECK(tagAt(bytes, 38) == "SSND");

    std::error_code ignored;
    std::filesystem::remove(path, ignored);
  }

  TEST_CASE("A cancelled export leaves nothing behind") {
    const std::string path = scratchPath("abandoned.wav");
    onebeat::core::AudioFileWriter writer;
    std::string error;
    REQUIRE(writer.open(path, onebeat::core::ExportFormat::Wav, 48000, error));
    const std::vector<float> silence(16, 0.0F);
    REQUIRE(writer.write(silence.data(), silence.data(), 16, error));
    writer.abandon();
    CHECK_FALSE(std::filesystem::exists(path));
  }

  TEST_CASE("Matching rates bypass the resampler sample for sample") {
    onebeat::core::SincResampler resampler(48000.0, 48000.0);
    CHECK(resampler.bypassed());

    const std::vector<float> input{0.1F, -0.2F, 0.3F, -0.4F};
    std::vector<float> left;
    std::vector<float> right;
    resampler.process(input.data(), input.data(), 4, left, right);
    resampler.flush(left, right);
    REQUIRE(left.size() == 4);
    for (size_t index = 0; index < input.size(); ++index) {
      CHECK(left[index] == input[index]);
    }
  }

  TEST_CASE("Resampling a sine keeps its level and its length") {
    constexpr double InputRate = 48000.0;
    constexpr double OutputRate = 44100.0;
    constexpr int Frames = 48000;
    std::vector<float> tone(static_cast<size_t>(Frames));
    for (int frame = 0; frame < Frames; ++frame) {
      const double phase =
          2.0 * 3.14159265358979323846 * 440.0 * (static_cast<double>(frame) / InputRate);
      tone[static_cast<size_t>(frame)] = static_cast<float>(0.5 * std::sin(phase));
    }

    onebeat::core::SincResampler resampler(InputRate, OutputRate);
    CHECK_FALSE(resampler.bypassed());
    std::vector<float> left;
    std::vector<float> right;
    // In blocks, because that is how the exporter feeds it.
    for (int offset = 0; offset < Frames; offset += 512) {
      const int frames = std::min(512, Frames - offset);
      resampler.process(tone.data() + offset, tone.data() + offset, frames, left, right);
    }
    resampler.flush(left, right);

    // One second in, one second out, to within the filter's half-window.
    CHECK(static_cast<double>(left.size()) == doctest::Approx(OutputRate).epsilon(0.001));
    float peak = 0.0F;
    // Skips the ramp at either end, where the window is still filling.
    for (size_t index = 64; index + 64 < left.size(); ++index) {
      peak = std::max(peak, std::abs(left[index]));
    }
    CHECK(peak == doctest::Approx(0.5F).epsilon(0.02));
  }
}

TEST_SUITE("engine") {
  TEST_CASE("Exporting renders the song through Engine::process into a playable file") {
    auto engine = onebeat::tests::makeOfflineEngine();
    REQUIRE(engine != nullptr);
    // Four notes at 120 bpm: two seconds of arrangement.
    engine->publishSchedule(onebeat::testing::makeGridSchedule(4, 60, 48000.0, 1.0, 120.0));

    onebeat::core::SongExportRequest request;
    request.path = scratchPath("song.wav");
    request.sample_rate = 48000;
    request.length_frames = 96000;
    request.tail_frames = 24000;
    onebeat::core::SongExportProgress progress;
    std::string error;
    REQUIRE_MESSAGE(onebeat::core::exportSong(*engine, request, progress, error), error);
    CHECK(progress.fraction.load() == doctest::Approx(1.0));

    std::string load_error;
    const auto decoded = onebeat::core::loadAudioFile(request.path, load_error);
    REQUIRE_MESSAGE(decoded != nullptr, load_error);
    CHECK(decoded->channels == 2);
    CHECK(decoded->sample_rate == doctest::Approx(48000.0));
    CHECK(decoded->frames == 120000);
    float peak = 0.0F;
    for (const float sample : decoded->samples) peak = std::max(peak, std::abs(sample));
    CHECK(peak > 0.05F);

    // The transport is where it was: an export is not a playback.
    CHECK_FALSE(engine->transportForTests().playing());
    CHECK(engine->transportForTests().positionFrames() == 0);

    std::error_code ignored;
    std::filesystem::remove(request.path, ignored);
  }

  TEST_CASE("Exporting at another rate writes that rate, and cancelling deletes the file") {
    auto engine = onebeat::tests::makeOfflineEngine();
    REQUIRE(engine != nullptr);
    engine->publishSchedule(onebeat::testing::makeGridSchedule(4, 60, 48000.0, 1.0, 120.0));

    onebeat::core::SongExportRequest request;
    request.path = scratchPath("song-44.wav");
    request.sample_rate = 44100;
    request.length_frames = 48000;
    request.tail_frames = 0;
    onebeat::core::SongExportProgress progress;
    std::string error;
    REQUIRE_MESSAGE(onebeat::core::exportSong(*engine, request, progress, error), error);

    std::string load_error;
    const auto decoded = onebeat::core::loadAudioFile(request.path, load_error);
    REQUIRE_MESSAGE(decoded != nullptr, load_error);
    CHECK(decoded->sample_rate == doctest::Approx(44100.0));
    CHECK(static_cast<double>(decoded->frames) == doctest::Approx(44100.0).epsilon(0.01));
    std::error_code ignored;
    std::filesystem::remove(request.path, ignored);

    onebeat::core::SongExportRequest cancelled = request;
    cancelled.path = scratchPath("cancelled.wav");
    cancelled.length_frames = int64_t{48000} * 30;
    onebeat::core::SongExportProgress stopping;
    stopping.cancel.store(true);
    CHECK_FALSE(onebeat::core::exportSong(*engine, cancelled, stopping, error));
    CHECK(error == "export cancelled");
    CHECK_FALSE(std::filesystem::exists(cancelled.path));
  }
}
