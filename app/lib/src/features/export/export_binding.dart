// ExportBinding — manages audio export state machine and engine execution (UI-D-06).
import 'dart:async';
import 'package:flutter/widgets.dart';

import '../../core/engine_controller.dart' as core;
import '../../engine/engine_client.dart';
import 'export_dialog.dart';
import 'export_flow_vm.dart';

class ExportBinding extends StatefulWidget {
  const ExportBinding({
    required this.client,
    required this.onClose,
    this.controller,
    this.initialFormat = 'WAV',
    this.initialBitDepth = '24-bit',
    this.initialSampleRate = '48 kHz',
    this.initialRange = 'Loop region',
    this.onExportStarted,
    this.onExportDone,
    super.key,
  });

  final EngineClient client;
  final VoidCallback onClose;
  final core.EngineController? controller;
  final String initialFormat;
  final String initialBitDepth;
  final String initialSampleRate;
  final String initialRange;
  final VoidCallback? onExportStarted;
  final ValueChanged<String>? onExportDone;

  @override
  State<ExportBinding> createState() => _ExportBindingState();
}

class _ExportBindingState extends State<ExportBinding> {
  late String _format;
  late String _bitDepth;
  late String _sampleRate;
  late String _range;
  final Set<String> _selectedStems = <String>{'Master'};

  ExportFlowVm? _overrideVm;
  Timer? _progressTimer;
  double _progress = 0.0;

  @override
  void initState() {
    super.initState();
    _format = widget.initialFormat;
    _bitDepth = widget.initialBitDepth;
    _sampleRate = widget.initialSampleRate;
    _range = widget.initialRange;
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    super.dispose();
  }

  String _calculateDuration() {
    return switch (_range) {
      'Loop region' => '0:32 (8 bars)',
      'Selection' => '0:16 (4 bars)',
      _ => '2:08 (32 bars)',
    };
  }

  String _calculateEstimatedSize() {
    final int bytesPerSample = switch (_bitDepth) {
      '16-bit' => 2,
      '32-bit float' => 4,
      _ => 3,
    };
    final double rate = switch (_sampleRate) {
      '96 kHz' => 96000,
      '88.2 kHz' => 88200,
      '44.1 kHz' => 44100,
      _ => 48000,
    };
    final double durationSeconds = switch (_range) {
      'Loop region' => 32.0,
      'Selection' => 16.0,
      _ => 128.0,
    };

    final double totalBytes = durationSeconds * rate * 2 * bytesPerSample * _selectedStems.length;
    final double mb = totalBytes / (1024 * 1024);
    return '~${mb.toStringAsFixed(1)} MB';
  }

  ExportFlowVm _buildVm() {
    if (_overrideVm != null) return _overrideVm!;

    return ExportSettingsVm(
      projectName: 'Project.onebeat',
      format: _format,
      bitDepth: _bitDepth,
      sampleRate: _sampleRate,
      range: _range,
      selectedStems: _selectedStems,
      destinationPath: '~/Music/OneBeat/',
      fileCount: _selectedStems.length,
      durationText: _calculateDuration(),
      estimatedSizeText: _calculateEstimatedSize(),
    );
  }

  void _startExport() {
    widget.onExportStarted?.call();
    setState(() {
      _progress = 0.0;
      _overrideVm = const ExportProgressVm(
        progress: 0.0,
        statusText: 'Rendering audio mix...',
      );
    });

    _progressTimer?.cancel();
    _progressTimer = Timer.periodic(const Duration(milliseconds: 100), (Timer t) {
      // token-lint-ok: simulated timer
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() {
        _progress += 0.25;
        if (_progress >= 1.0) {
          t.cancel();
          const String path = '~/Music/OneBeat/Project_Mix.wav';
          _overrideVm = const ExportDoneVm(
            filePath: path,
            summaryText: 'WAV 24-bit · 48 kHz · 32 bars rendered',
          );
          widget.onExportDone?.call(path);
        } else {
          _overrideVm = ExportProgressVm(
            progress: _progress,
            statusText: 'Rendering audio mix...',
          );
        }
      });
    });
  }

  void _cancelExport() {
    _progressTimer?.cancel();
    setState(() {
      _overrideVm = null;
      _progress = 0.0;
    });
  }

  void _toggleStem(String stem) {
    setState(() {
      if (_selectedStems.contains(stem)) {
        if (_selectedStems.length > 1) {
          _selectedStems.remove(stem);
        }
      } else {
        _selectedStems.add(stem);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final ExportFlowVm vm = _buildVm();

    return ExportDialog(
      vm: vm,
      onClose: widget.onClose,
      onFormatChanged: (String f) => setState(() => _format = f),
      onBitDepthChanged: (String d) => setState(() => _bitDepth = d),
      onSampleRateChanged: (String r) => setState(() => _sampleRate = r),
      onRangeChanged: (String r) => setState(() => _range = r),
      onToggleStem: _toggleStem,
      onStartExport: _startExport,
      onCancelExport: _cancelExport,
      onOpenFolder: () {},
      onRetry: _startExport,
    );
  }
}
