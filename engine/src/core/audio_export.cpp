#include "core/audio_export.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstring>
#include <filesystem>

#include "core/audio_buffer.h"
#include "core/engine.h"
#include "core/rt/rt.h"
#include "core/transport.h"

namespace onebeat::core {
namespace {

constexpr int32_t FullScale24 = 8388607;  // 2^23 - 1

void appendLittle(std::vector<uint8_t>& bytes, uint32_t value, int width) {
  for (int index = 0; index < width; ++index) {
    bytes.push_back(static_cast<uint8_t>((value >> (8 * index)) & 0xFFU));
  }
}

void appendBig(std::vector<uint8_t>& bytes, uint32_t value, int width) {
  for (int index = width - 1; index >= 0; --index) {
    bytes.push_back(static_cast<uint8_t>((value >> (8 * index)) & 0xFFU));
  }
}

void appendTag(std::vector<uint8_t>& bytes, const char* tag) {
  for (int index = 0; index < 4; ++index) {
    bytes.push_back(static_cast<uint8_t>(tag[index]));
  }
}

// AIFF stores its sample rate as an 80-bit IEEE 754 extended float, which is
// the one thing in the format that cannot be written by staring at a hex dump.
void appendExtended80(std::vector<uint8_t>& bytes, double value) {
  int exponent = 0;
  const double mantissa = std::frexp(value, &exponent);  // value = mantissa * 2^exponent
  const auto biased = static_cast<uint16_t>(exponent - 1 + 16383);
  // Extended precision carries its leading bit explicitly, so scaling the
  // [0.5, 1) mantissa by 2^64 lands it exactly in a 64-bit fraction field.
  const auto fraction = static_cast<uint64_t>(std::ldexp(mantissa, 64));
  bytes.push_back(static_cast<uint8_t>((biased >> 8) & 0xFFU));
  bytes.push_back(static_cast<uint8_t>(biased & 0xFFU));
  for (int index = 7; index >= 0; --index) {
    bytes.push_back(static_cast<uint8_t>((fraction >> (8 * index)) & 0xFFU));
  }
}

int32_t toPcm24(float sample) {
  const double clamped = std::clamp(static_cast<double>(sample), -1.0, 1.0);
  const double scaled = clamped * static_cast<double>(FullScale24);
  return static_cast<int32_t>(std::lround(scaled));
}

// Normalised sinc, windowed with a Blackman window over the filter's support.
double windowedSinc(double offset, double cutoff) {
  constexpr double Pi = 3.14159265358979323846;
  const double support = 16.0;  // must match SincResampler::Taps
  if (std::abs(offset) > support) return 0.0;
  const double argument = Pi * cutoff * offset;
  const double sinc = std::abs(argument) < 1.0e-9 ? 1.0 : std::sin(argument) / argument;
  const double normalised = (offset + support) / (2.0 * support);
  const double window =
      0.42 - (0.5 * std::cos(2.0 * Pi * normalised)) + (0.08 * std::cos(4.0 * Pi * normalised));
  return sinc * window;
}

}  // namespace

// ---------------------------------------------------------------------------
// AudioFileWriter
// ---------------------------------------------------------------------------

AudioFileWriter::~AudioFileWriter() {
  if (file_ != nullptr) {
    std::fclose(file_);
    file_ = nullptr;
  }
}

bool AudioFileWriter::open(const std::string& path, ExportFormat format, int sample_rate,
                           std::string& error) {
  if (file_ != nullptr) {
    error = "a file is already open";
    return false;
  }
  if (sample_rate <= 0) {
    error = "invalid sample rate";
    return false;
  }
#if defined(_WIN32)
  file_ = std::fopen(path.c_str(), "wb");
#else
  file_ = std::fopen(path.c_str(), "wbe");
#endif
  if (file_ == nullptr) {
    error = "could not create " + path;
    return false;
  }
  path_ = path;
  format_ = format;
  sample_rate_ = sample_rate;
  frames_written_ = 0;

  // Placeholder sizes; `close` patches them once the length is known.
  std::vector<uint8_t> header;
  if (format_ == ExportFormat::Wav) {
    const uint32_t byte_rate = static_cast<uint32_t>(sample_rate_) * 2U * 3U;
    appendTag(header, "RIFF");
    appendLittle(header, 0, 4);
    appendTag(header, "WAVE");
    appendTag(header, "fmt ");
    appendLittle(header, 16, 4);
    appendLittle(header, 1, 2);  // PCM
    appendLittle(header, 2, 2);  // stereo
    appendLittle(header, static_cast<uint32_t>(sample_rate_), 4);
    appendLittle(header, byte_rate, 4);
    appendLittle(header, 6, 2);   // block align: 2 channels * 3 bytes
    appendLittle(header, 24, 2);  // bits per sample
    appendTag(header, "data");
    appendLittle(header, 0, 4);
  } else {
    appendTag(header, "FORM");
    appendBig(header, 0, 4);
    appendTag(header, "AIFF");
    appendTag(header, "COMM");
    appendBig(header, 18, 4);
    appendBig(header, 2, 2);  // channels
    appendBig(header, 0, 4);  // frame count
    appendBig(header, 24, 2);
    appendExtended80(header, static_cast<double>(sample_rate_));
    appendTag(header, "SSND");
    appendBig(header, 8, 4);
    appendBig(header, 0, 4);  // offset
    appendBig(header, 0, 4);  // block size
  }
  if (std::fwrite(header.data(), 1, header.size(), file_) != header.size()) {
    error = "could not write the header of " + path;
    abandon();
    return false;
  }
  return true;
}

bool AudioFileWriter::write(const float* left, const float* right, int frames, std::string& error) {
  if (file_ == nullptr) {
    error = "no file is open";
    return false;
  }
  if (frames <= 0) return true;

  bytes_.clear();
  bytes_.reserve(static_cast<size_t>(frames) * 6U);
  const bool little_endian = format_ == ExportFormat::Wav;
  for (int frame = 0; frame < frames; ++frame) {
    const std::array<int32_t, 2> samples{toPcm24(left[frame]), toPcm24(right[frame])};
    for (const int32_t sample : samples) {
      const auto bits = static_cast<uint32_t>(sample);
      if (little_endian) {
        appendLittle(bytes_, bits, 3);
      } else {
        appendBig(bytes_, bits, 3);
      }
    }
  }
  if (std::fwrite(bytes_.data(), 1, bytes_.size(), file_) != bytes_.size()) {
    error = "could not write audio to " + path_;
    return false;
  }
  frames_written_ += static_cast<uint64_t>(frames);
  return true;
}

bool AudioFileWriter::close(std::string& error) {
  if (file_ == nullptr) {
    error = "no file is open";
    return false;
  }
  const auto data_bytes = static_cast<uint32_t>(frames_written_ * 6U);
  std::vector<uint8_t> patch;
  bool ok = true;
  if (format_ == ExportFormat::Wav) {
    patch.clear();
    appendLittle(patch, 36U + data_bytes, 4);
    ok = ok && std::fseek(file_, 4, SEEK_SET) == 0 &&
         std::fwrite(patch.data(), 1, patch.size(), file_) == patch.size();
    patch.clear();
    appendLittle(patch, data_bytes, 4);
    ok = ok && std::fseek(file_, 40, SEEK_SET) == 0 &&
         std::fwrite(patch.data(), 1, patch.size(), file_) == patch.size();
  } else {
    patch.clear();
    appendBig(patch, 46U + data_bytes, 4);
    ok = ok && std::fseek(file_, 4, SEEK_SET) == 0 &&
         std::fwrite(patch.data(), 1, patch.size(), file_) == patch.size();
    patch.clear();
    appendBig(patch, static_cast<uint32_t>(frames_written_), 4);
    ok = ok && std::fseek(file_, 22, SEEK_SET) == 0 &&
         std::fwrite(patch.data(), 1, patch.size(), file_) == patch.size();
    patch.clear();
    appendBig(patch, 8U + data_bytes, 4);
    ok = ok && std::fseek(file_, 42, SEEK_SET) == 0 &&
         std::fwrite(patch.data(), 1, patch.size(), file_) == patch.size();
  }
  const bool flushed = std::fclose(file_) == 0;
  file_ = nullptr;
  if (!ok || !flushed) {
    error = "could not finalise " + path_;
    return false;
  }
  return true;
}

void AudioFileWriter::abandon() {
  if (file_ != nullptr) {
    std::fclose(file_);
    file_ = nullptr;
  }
  if (path_.empty()) return;
  std::error_code ignored;
  std::filesystem::remove(path_, ignored);
  path_.clear();
  frames_written_ = 0;
}

// ---------------------------------------------------------------------------
// SincResampler
// ---------------------------------------------------------------------------

SincResampler::SincResampler(double input_rate, double output_rate) {
  if (!(input_rate > 0.0) || !(output_rate > 0.0)) return;
  if (std::abs(input_rate - output_rate) < 1.0e-9) return;
  bypassed_ = false;
  ratio_ = input_rate / output_rate;
  // Downsampling has to band-limit to the *output* Nyquist or it folds; going
  // up needs no extra filtering, so the cutoff stays at the input Nyquist.
  cutoff_ = std::min(1.0, output_rate / input_rate);
}

void SincResampler::process(const float* left, const float* right, int frames,
                            std::vector<float>& out_left, std::vector<float>& out_right) {
  if (frames <= 0) return;
  if (bypassed_) {
    out_left.insert(out_left.end(), left, left + frames);
    out_right.insert(out_right.end(), right, right + frames);
    return;
  }
  history_left_.insert(history_left_.end(), left, left + frames);
  history_right_.insert(history_right_.end(), right, right + frames);
  received_ += frames;
  produce(out_left, out_right);
  trim();
}

void SincResampler::flush(std::vector<float>& out_left, std::vector<float>& out_right) {
  if (bypassed_) return;
  const std::vector<float> silence(static_cast<size_t>(Taps) + 1U, 0.0F);
  process(silence.data(), silence.data(), static_cast<int>(silence.size()), out_left, out_right);
}

void SincResampler::produce(std::vector<float>& out_left, std::vector<float>& out_right) {
  while (true) {
    const auto centre = static_cast<int64_t>(std::floor(position_));
    // The window reaches `Taps` samples past the centre, so an output can only
    // be finished once that much input has arrived.
    if (centre + Taps >= received_) return;
    const double fraction = position_ - static_cast<double>(centre);
    double sum_left = 0.0;
    double sum_right = 0.0;
    for (int tap = -Taps + 1; tap <= Taps; ++tap) {
      const int64_t index = centre + tap;
      if (index < origin_ || index >= received_) continue;
      const double weight = windowedSinc(static_cast<double>(tap) - fraction, cutoff_);
      const auto slot = static_cast<size_t>(index - origin_);
      sum_left += weight * static_cast<double>(history_left_[slot]);
      sum_right += weight * static_cast<double>(history_right_[slot]);
    }
    out_left.push_back(static_cast<float>(sum_left * cutoff_));
    out_right.push_back(static_cast<float>(sum_right * cutoff_));
    position_ += ratio_;
  }
}

void SincResampler::trim() {
  // Compacting on every block would make this a memmove per block; a slack of
  // one large block keeps it to an occasional one.
  constexpr int64_t Slack = 4096;
  const int64_t keep_from = static_cast<int64_t>(std::floor(position_)) - Taps;
  if (keep_from <= origin_ + Slack) return;
  const auto drop = static_cast<size_t>(keep_from - origin_);
  history_left_.erase(history_left_.begin(), history_left_.begin() + static_cast<long>(drop));
  history_right_.erase(history_right_.begin(), history_right_.begin() + static_cast<long>(drop));
  origin_ = keep_from;
}

// ---------------------------------------------------------------------------
// exportSong
// ---------------------------------------------------------------------------

bool exportSong(Engine& engine, const SongExportRequest& request, SongExportProgress& progress,
                std::string& error) {
  const int64_t total_frames = request.length_frames + request.tail_frames;
  if (total_frames <= 0) {
    error = "there is nothing to export: the project is empty";
    return false;
  }

  AudioFileWriter writer;
  if (!writer.open(request.path, request.format, request.sample_rate, error)) return false;

  // The device and this thread would otherwise both be inside process().
  const bool was_running = engine.isRunning();
  if (was_running) engine.stop();

  Transport& transport = engine.offlineTransport();
  const int64_t resume_position = transport.positionFrames();
  const double loop_start = transport.loopStartBeats();
  const double loop_end = transport.loopEndBeats();
  const bool loop_enabled = transport.loopEnabled();

  // A render is the whole song once through, so the loop region — the thing
  // that makes playback repeat eight bars forever — has to be out of the way.
  transport.setLoop(loop_start, loop_end, false);
  transport.seekFrames(0);
  transport.play();
  ob_command metronome{};
  metronome.type = OB_CMD_SET_METRONOME;
  metronome.i64_a = 0;
  engine.postCommand(metronome);

  rt::enableFlushToZero();

  // The engine's own block size, not a size of our choosing: every plug-in was
  // activated for exactly this many frames and the channel scratch is sized for
  // it, so a larger block here would render straight past the end of both.
  const int block_frames = engine.config().block_frames > 0 ? engine.config().block_frames : 512;
  std::vector<float> left(static_cast<size_t>(block_frames), 0.0F);
  std::vector<float> right(static_cast<size_t>(block_frames), 0.0F);
  std::array<float*, 2> planes{left.data(), right.data()};
  SincResampler resampler(engine.config().sample_rate, static_cast<double>(request.sample_rate));
  std::vector<float> out_left;
  std::vector<float> out_right;

  bool ok = true;
  bool cancelled = false;
  int64_t rendered = 0;
  while (rendered < total_frames) {
    if (progress.cancel.load(std::memory_order_relaxed)) {
      cancelled = true;
      break;
    }
    const auto frames = static_cast<int>(std::min<int64_t>(block_frames, total_frames - rendered));
    ProcessContext context;
    context.output = AudioBufferView(planes.data(), 2, frames);
    context.num_frames = frames;
    context.host_time_ns = rt::monotonicNanos();
    context.stream_time_frames = static_cast<uint64_t>(rendered);
    engine.process(context);

    out_left.clear();
    out_right.clear();
    resampler.process(left.data(), right.data(), frames, out_left, out_right);
    if (!writer.write(out_left.data(), out_right.data(), static_cast<int>(out_left.size()),
                      error)) {
      ok = false;
      break;
    }
    rendered += frames;
    progress.fraction.store(static_cast<double>(rendered) / static_cast<double>(total_frames),
                            std::memory_order_relaxed);
  }

  if (ok && !cancelled) {
    out_left.clear();
    out_right.clear();
    resampler.flush(out_left, out_right);
    ok = writer.write(out_left.data(), out_right.data(), static_cast<int>(out_left.size()), error);
  }

  // Whatever happened to the render, the session goes back to where it was.
  transport.stop();
  transport.seekFrames(resume_position);
  transport.setLoop(loop_start, loop_end, loop_enabled);
  ob_command silence{};
  silence.type = OB_CMD_ALL_NOTES_OFF;
  engine.postCommand(silence);

  if (cancelled) {
    writer.abandon();
    error = "export cancelled";
  } else if (!ok) {
    writer.abandon();
  } else {
    ok = writer.close(error);
    if (!ok) writer.abandon();
  }

  if (was_running) {
    std::string restart_error;
    if (!engine.start(restart_error) && ok) {
      // The file is written; say so, and let the device error travel with it.
      error = "exported, but the audio device did not restart: " + restart_error;
    }
  }
  return ok && !cancelled;
}

}  // namespace onebeat::core
