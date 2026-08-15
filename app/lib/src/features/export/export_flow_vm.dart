// ExportFlowVm — sealed state machine for audio export (UI-C-06 / UI-D-06).
import 'package:flutter/foundation.dart';

import '../../engine/engine_client.dart' show ExportFormat;

/// The rates the dialog offers, in hertz. The engine renders at whatever the
/// device is running at and converts on the way out, so any of these is
/// available whatever the audio hardware is doing.
const List<int> exportSampleRates = <int>[44100, 48000, 88200, 96000];

/// `48000` -> `48 kHz`, `44100` -> `44.1 kHz`.
String sampleRateLabel(int hertz) {
  final double kilohertz = hertz / 1000;
  final String text = kilohertz == kilohertz.roundToDouble()
      ? kilohertz.toStringAsFixed(0)
      : kilohertz.toStringAsFixed(1);
  return '$text kHz';
}

@immutable
sealed class ExportFlowVm {
  const ExportFlowVm();
}

/// What the dialog asks for, and nothing else: a format, a rate, and a folder.
///
/// Bit depth, range and stems used to live here. They were choices the engine
/// could not honour — every export was the whole song, at 24-bit, of the master
/// — so the dialog was describing a render nobody was performing.
@immutable
class ExportSettingsVm extends ExportFlowVm {
  const ExportSettingsVm({
    required this.projectName,
    required this.format,
    required this.sampleRate,
    required this.destinationDirectory,
    required this.fileName,
  });

  final String projectName;
  final ExportFormat format;
  final int sampleRate;

  /// The folder the file will be written into.
  final String destinationDirectory;

  /// What the file will be called there, extension included. The engine picks
  /// the final name — it will not overwrite an earlier export — so this is the
  /// name a first export gets.
  final String fileName;

  static const List<ExportFormat> formats = ExportFormat.values;
  static const List<int> sampleRates = exportSampleRates;
}

@immutable
class ExportProgressVm extends ExportFlowVm {
  const ExportProgressVm({
    required this.progress,
    required this.statusText,
  });

  final double progress;
  final String statusText;
}

@immutable
class ExportDoneVm extends ExportFlowVm {
  const ExportDoneVm({
    required this.filePath,
    required this.summaryText,
  });

  final String filePath;
  final String summaryText;
}

@immutable
class ExportFailedVm extends ExportFlowVm {
  const ExportFailedVm({
    required this.errorMessage,
  });

  final String errorMessage;
}
