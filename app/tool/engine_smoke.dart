// A headless smoke test of the whole boundary, from Dart (OB-1-10 §5).
//
// Runs the real EngineClient against the null backend, so CI exercises the FFI
// path — commands in, snapshots out, events drained — without audio hardware.
//
//   dart run tool/engine_smoke.dart [seconds]
//
// Exit code 0 means: the engine started, the pattern played, the transport
// advanced, levels moved, and no dropouts or errors were reported.
import 'dart:io';

import 'package:onebeat/src/engine/engine_client.dart';

Future<void> main(List<String> arguments) async {
  final double seconds = arguments.isEmpty ? 3.0 : double.parse(arguments.first);

  final EngineClient client = EngineClient.start(useNullDevice: true, blockFrames: 128);
  client.startAudio();
  client.setStepPattern(<int>[127, 0, 60, 0, 100, 0, 60, 40, 127, 0, 60, 0, 100, 30, 60, 0]);
  client.play();

  double loudestPeak = 0;
  int maxVoices = 0;
  int reads = 0;
  final List<String> errors = <String>[];
  EngineSnapshot snapshot = const EngineSnapshot.empty();

  final DateTime until = DateTime.now().add(
    Duration(milliseconds: (seconds * 1000).round()),
  );
  while (DateTime.now().isBefore(until)) {
    // ~120 Hz, the rate the UI reads at.
    await Future<void>.delayed(const Duration(milliseconds: 8));
    snapshot = client.readSnapshot();
    reads++;
    if (snapshot.peakLeft > loudestPeak) {
      loudestPeak = snapshot.peakLeft;
    }
    if (snapshot.activeVoices > maxVoices) {
      maxVoices = snapshot.activeVoices;
    }
    for (final EngineEvent event in client.pollEvents()) {
      if (event.isError) {
        errors.add(event.text);
      }
    }
  }

  stdout
    ..writeln('device            ${client.deviceName}')
    ..writeln('reads             $reads')
    ..writeln('position          ${snapshot.positionFrames} frames '
        '(${snapshot.bar}.${snapshot.beat}.${snapshot.tick})')
    ..writeln('schedule events   ${snapshot.scheduleEventCount}')
    ..writeln('loudest peak      ${loudestPeak.toStringAsFixed(3)}')
    ..writeln('max voices        $maxVoices')
    ..writeln('xruns             ${snapshot.xrunCount}')
    ..writeln('errors            ${errors.isEmpty ? 'none' : errors.join('; ')}');

  // The export path, end to end: the same engine, the same schedule, written to
  // a real file through the ABI. A smoke test that stopped at the snapshot
  // would have passed all the way through the months when export did nothing.
  final Directory exportFolder = Directory.systemTemp.createTempSync('onebeat-smoke-export');
  client.startExport(directory: exportFolder.path, format: ExportFormat.wav, sampleRate: 48000);
  ExportStatus export = client.readExportStatus();
  final DateTime exportDeadline = DateTime.now().add(const Duration(seconds: 60));
  while (export.state == ExportState.running && DateTime.now().isBefore(exportDeadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
    export = client.readExportStatus();
  }
  final int exportedBytes =
      export.path.isNotEmpty && File(export.path).existsSync() ? File(export.path).lengthSync() : 0;

  stdout
    ..writeln('export state      ${export.state.name}')
    ..writeln('export file       ${export.path}')
    ..writeln('export bytes      $exportedBytes');

  client.dispose();
  exportFolder.deleteSync(recursive: true);

  final List<String> failures = <String>[
    if (export.state != ExportState.done) 'the export did not finish: ${export.error}',
    // 44 bytes of header and nothing else is an export that wrote silence-free
    // nothing; a second of stereo 24-bit is ~288 KB.
    if (exportedBytes < 100000) 'the exported file is too small to hold the render',
    if (snapshot.scheduleEventCount != 20) 'the schedule did not reach the engine',
    if (snapshot.positionFrames <= 0) 'the transport did not advance',
    if (loudestPeak <= 0.05) 'the pattern produced no audible output',
    if (maxVoices <= 0) 'no sampler voice was ever triggered',
    if (errors.isNotEmpty) 'engine reported errors',
  ];

  if (failures.isNotEmpty) {
    stderr.writeln('SMOKE TEST FAILED: ${failures.join(', ')}');
    exit(1);
  }
  stdout.writeln('Smoke test passed.');
}
