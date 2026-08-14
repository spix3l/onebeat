// ExportFlowVm — sealed state machine for audio export (UI-C-06 / UI-D-06).
import 'package:flutter/foundation.dart';

@immutable
sealed class ExportFlowVm {
  const ExportFlowVm();
}

@immutable
class ExportSettingsVm extends ExportFlowVm {
  const ExportSettingsVm({
    required this.projectName,
    required this.format,
    required this.bitDepth,
    required this.sampleRate,
    required this.range,
    required this.selectedStems,
    required this.destinationPath,
    required this.fileCount,
    required this.durationText,
    required this.estimatedSizeText,
  });

  final String projectName;
  final String format;
  final String bitDepth;
  final String sampleRate;
  final String range;
  final Set<String> selectedStems;
  final String destinationPath;
  final int fileCount;
  final String durationText;
  final String estimatedSizeText;

  static const List<String> formats = <String>['WAV', 'AIFF', 'FLAC', 'MP3'];
  static const List<String> bitDepths = <String>['16-bit', '24-bit', '32-bit float'];
  static const List<String> sampleRates = <String>['44.1 kHz', '48 kHz', '88.2 kHz', '96 kHz'];
  static const List<String> ranges = <String>['Whole project', 'Loop region', 'Selection'];
  static const List<String> availableStems = <String>[
    'Master',
    'Drums Bus',
    'Bass',
    'Music',
    'Vox',
    'Reverb Send',
  ];
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
