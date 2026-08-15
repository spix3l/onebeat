// Compact waveform extraction for audio clips.
//
// The engine remains the source of truth for decoding and playback. This is a
// presentation-only reader: it scans the WAV data into a small set of peak
// values, never keeps the audio in memory, and lets the playlist render while
// the thumbnail is still loading.
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

Future<List<double>> loadAudioWaveform(
  String path, {
  int bucketCount = 96,
}) async {
  if (path.isEmpty || bucketCount <= 0) return const <double>[];

  RandomAccessFile? file;
  try {
    file = await File(path).open();
    final int fileLength = await file.length();
    final Uint8List header = await file.read(12);
    if (header.length < 12 ||
        _ascii(header, 0, 4) != 'RIFF' ||
        _ascii(header, 8, 4) != 'WAVE') {
      return const <double>[];
    }

    int? audioFormat;
    int? channels;
    int? bitsPerSample;
    int? blockAlign;
    int? dataOffset;
    int dataLength = 0;

    while (await file.position() + 8 <= fileLength) {
      final Uint8List chunk = await file.read(8);
      if (chunk.length < 8) break;
      final String id = _ascii(chunk, 0, 4);
      final int size = _u32(chunk, 4);
      final int contentOffset = await file.position();

      if (id == 'fmt ' && size >= 16) {
        final Uint8List format = await file.read(math.min(size, 40));
        if (format.length >= 16) {
          audioFormat = _u16(format, 0);
          channels = _u16(format, 2);
          blockAlign = _u16(format, 12);
          bitsPerSample = _u16(format, 14);
        }
      } else if (id == 'data') {
        dataOffset = contentOffset;
        dataLength = math.min(size, math.max(0, fileLength - contentOffset));
      }

      final int next = contentOffset + size + (size.isOdd ? 1 : 0);
      await file.setPosition(math.min(next, fileLength));
      if (dataOffset != null && audioFormat != null) break;
    }

    if (dataOffset == null ||
        audioFormat == null ||
        channels == null ||
        channels <= 0 ||
        bitsPerSample == null ||
        blockAlign == null ||
        blockAlign <= 0 ||
        dataLength <= 0) {
      return const <double>[];
    }

    final int bytesPerSample = (bitsPerSample / 8).floor();
    if (bytesPerSample <= 0 || blockAlign < bytesPerSample) {
      return const <double>[];
    }

    final int frameCount = dataLength ~/ blockAlign;
    if (frameCount <= 0) return const <double>[];

    final List<double> peaks = List<double>.filled(bucketCount, 0.0);
    await file.setPosition(dataOffset);
    const int requestedChunkBytes = 256 * 1024;
    int frame = 0;
    while (frame < frameCount) {
      final int framesToRead = math.min(
        frameCount - frame,
        math.max(1, requestedChunkBytes ~/ blockAlign),
      );
      final Uint8List bytes = await file.read(framesToRead * blockAlign);
      final int completeFrames = bytes.length ~/ blockAlign;
      if (completeFrames == 0) break;
      final ByteData data = ByteData.sublistView(bytes);
      for (int index = 0; index < completeFrames; index++) {
        final int offset = index * blockAlign;
        final double amplitude =
            _sampleAmplitude(data, offset, audioFormat, bitsPerSample);
        final int bucket = math.min(
          bucketCount - 1,
          ((frame + index) * bucketCount) ~/ frameCount,
        );
        if (amplitude > peaks[bucket]) peaks[bucket] = amplitude;
      }
      frame += completeFrames;
      if (completeFrames < framesToRead) break;
    }

    // A quiet recording should remain quiet, while ordinary files use the
    // available vertical range instead of looking like a one-pixel line.
    final double maximum = peaks.fold<double>(0.0, math.max);
    if (maximum <= 0.0001) return peaks;
    return <double>[for (final double peak in peaks) (peak / maximum).clamp(0.0, 1.0)];
  } on IOException {
    return const <double>[];
  } on FormatException {
    return const <double>[];
  } finally {
    await file?.close();
  }
}

String _ascii(Uint8List bytes, int offset, int length) =>
    String.fromCharCodes(bytes.sublist(offset, offset + length));

int _u16(Uint8List bytes, int offset) =>
    bytes[offset] | (bytes[offset + 1] << 8);

int _u32(Uint8List bytes, int offset) =>
    bytes[offset] |
    (bytes[offset + 1] << 8) |
    (bytes[offset + 2] << 16) |
    (bytes[offset + 3] << 24);

double _sampleAmplitude(
  ByteData data,
  int offset,
  int format,
  int bitsPerSample,
) {
  switch (bitsPerSample) {
    case 8:
      return ((data.getUint8(offset) - 128).abs() / 128.0).clamp(0.0, 1.0);
    case 16:
      return (data.getInt16(offset, Endian.little).abs() / 32768.0).clamp(0.0, 1.0);
    case 24:
      final int value = data.getUint8(offset) |
          (data.getUint8(offset + 1) << 8) |
          (data.getInt8(offset + 2) << 16);
      return (value.abs() / 8388608.0).clamp(0.0, 1.0);
    case 32:
      if (format == 3) {
        return data.getFloat32(offset, Endian.little).abs().clamp(0.0, 1.0);
      }
      return (data.getInt32(offset, Endian.little).abs() / 2147483648.0)
          .clamp(0.0, 1.0);
    default:
      return 0.0;
  }
}
