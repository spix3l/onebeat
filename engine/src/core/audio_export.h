// Rendering a project to an audio file (EPIC-4).
//
// Two halves, deliberately separate:
//   - the *writer* and the *resampler*, which know nothing about the engine and
//     are unit-testable on their own;
//   - `exportSong`, which drives Engine::process faster than real time.
//
// The render goes through Engine::process and nothing else, which is the same
// guarantee the offline test driver gives (FR-ENG-06): what is written is what
// the device would have played, not a second mixing path that can drift from it.
#pragma once

#include <atomic>
#include <cstdint>
#include <cstdio>
#include <string>
#include <vector>

namespace onebeat::core {

class Engine;

// What the UI can pick. Both are uncompressed 24-bit PCM: the depth is not a
// user-facing choice because 24-bit is the only one that is right for a master
// nobody is going to re-render.
enum class ExportFormat : uint8_t { Wav = 0, Aiff = 1 };

// Streaming writer for stereo 24-bit PCM. Header sizes are patched in `close`
// because the frame count is only known once the tail has finished ringing.
class AudioFileWriter {
 public:
  AudioFileWriter() = default;
  ~AudioFileWriter();

  AudioFileWriter(const AudioFileWriter&) = delete;
  AudioFileWriter& operator=(const AudioFileWriter&) = delete;
  AudioFileWriter(AudioFileWriter&&) = delete;
  AudioFileWriter& operator=(AudioFileWriter&&) = delete;

  bool open(const std::string& path, ExportFormat format, int sample_rate, std::string& error);
  // Planar in, interleaved out. Samples outside [-1, 1) are clipped rather than
  // wrapped: a wrap turns an overshoot into a click loud enough to damage
  // speakers, and clipping is what every other DAW writes.
  bool write(const float* left, const float* right, int frames, std::string& error);
  bool close(std::string& error);
  // Closes and deletes the partial file. A cancelled export must not leave
  // something behind that looks like a finished render.
  void abandon();

  uint64_t framesWritten() const { return frames_written_; }

 private:
  std::FILE* file_ = nullptr;
  std::string path_;
  ExportFormat format_ = ExportFormat::Wav;
  int sample_rate_ = 48000;
  uint64_t frames_written_ = 0;
  std::vector<uint8_t> bytes_;
};

// Streaming windowed-sinc sample-rate conversion, stereo.
//
// Only needed when the user asks for a rate the device is not running at. When
// the rates match this is a memcpy — which matters, because it means the common
// case is bit-identical to what the engine rendered.
class SincResampler {
 public:
  SincResampler(double input_rate, double output_rate);

  bool bypassed() const { return bypassed_; }

  // Consumes one input block and appends every output sample whose filter
  // window is now complete. Output is planar, appended to the given vectors.
  void process(const float* left, const float* right, int frames, std::vector<float>& out_left,
               std::vector<float>& out_right);
  // Pushes silence through so the last real samples reach the output.
  void flush(std::vector<float>& out_left, std::vector<float>& out_right);

 private:
  // Half-width of the filter. 16 taps either side of the fractional position is
  // the usual transparency/cost trade-off for an offline bounce.
  static constexpr int Taps = 16;

  void produce(std::vector<float>& out_left, std::vector<float>& out_right);
  void trim();

  double ratio_ = 1.0;   // input frames consumed per output frame
  double cutoff_ = 1.0;  // normalised to the input rate; < 1 when downsampling
  bool bypassed_ = true;
  // Input history. `origin_` is the absolute input index of history_[0], so
  // `position_` stays absolute and does not have to be rebased on every trim.
  std::vector<float> history_left_;
  std::vector<float> history_right_;
  int64_t origin_ = 0;
  int64_t received_ = 0;
  double position_ = 0.0;
};

// Everything the caller decides about one render. Lengths are in frames at the
// *engine's* rate; `sample_rate` is the rate of the file being written, and the
// two differ exactly when the resampler is doing something.
struct SongExportRequest {
  std::string path;
  ExportFormat format = ExportFormat::Wav;
  int sample_rate = 48000;
  int64_t length_frames = 0;
  // Rendered past the end so a release tail, a reverb or a long sample is not
  // cut off mid-decay.
  int64_t tail_frames = 0;
};

// Shared with whoever is watching: the exporter writes `fraction`, the UI reads
// it and may set `cancel` at any point.
struct SongExportProgress {
  std::atomic<double> fraction{0.0};
  std::atomic<bool> cancel{false};
};

// Renders the project the engine currently holds, from frame 0, into a file.
//
// Blocking, and not callable from the audio thread: it stops the device, takes
// the render path over for the duration, and restarts the device afterwards.
// The transport is left stopped at the position it started from; restoring the
// loop region is the caller's business, because the loop is the model's to
// decide and not the exporter's to remember.
bool exportSong(Engine& engine, const SongExportRequest& request, SongExportProgress& progress,
                std::string& error);

}  // namespace onebeat::core
