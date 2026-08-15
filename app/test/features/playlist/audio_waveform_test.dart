import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:onebeat/src/features/playlist/audio_waveform.dart';

void main() {
  test('extracts normalised peaks without retaining the audio data', () async {
    final Directory directory = await Directory.systemTemp.createTemp('onebeat-waveform-');
    addTearDown(() => directory.delete(recursive: true));
    final File file = File('${directory.path}/pulse.wav');
    await file.writeAsBytes(_monoPcm16(<int>[0, 8192, 16384, 32767, -16384, -8192, 0, 0]));

    final List<double> waveform = await loadAudioWaveform(
      file.path,
      bucketCount: 4,
    );

    expect(waveform, hasLength(4));
    expect(waveform.reduce((double a, double b) => a > b ? a : b), closeTo(1.0, 0.001));
    expect(waveform.any((double value) => value > 0.5), isTrue);
    expect(waveform.every((double value) => value >= 0 && value <= 1), isTrue);
  });

  test('invalid files produce an empty waveform', () async {
    final Directory directory = await Directory.systemTemp.createTemp('onebeat-waveform-');
    addTearDown(() => directory.delete(recursive: true));
    final File file = File('${directory.path}/not-a-wave.wav');
    await file.writeAsString('not audio');

    expect(await loadAudioWaveform(file.path), isEmpty);
  });
}

List<int> _monoPcm16(List<int> samples) {
  final List<int> data = <int>[];
  for (final int sample in samples) {
    data
      ..add(sample & 0xFF)
      ..add((sample >> 8) & 0xFF);
  }
  final int riffSize = 36 + data.length;
  return <int>[
    ...'RIFF'.codeUnits,
    ..._u32(riffSize),
    ...'WAVE'.codeUnits,
    ...'fmt '.codeUnits,
    ..._u32(16),
    ..._u16(1), // PCM
    ..._u16(1), // mono
    ..._u32(44100),
    ..._u32(88200),
    ..._u16(2),
    ..._u16(16),
    ...'data'.codeUnits,
    ..._u32(data.length),
    ...data,
  ];
}

List<int> _u16(int value) => <int>[value & 0xFF, (value >> 8) & 0xFF];

List<int> _u32(int value) => <int>[
  value & 0xFF,
  (value >> 8) & 0xFF,
  (value >> 16) & 0xFF,
  (value >> 24) & 0xFF,
];
