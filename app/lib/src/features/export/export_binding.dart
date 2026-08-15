// ExportBinding — drives the export state machine against the engine (UI-D-06).
import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';

import '../../core/engine_controller.dart' as core;
import '../../engine/engine_client.dart';
import 'export_dialog.dart';
import 'export_flow_vm.dart';
import 'export_folder_platform.dart';

class ExportBinding extends StatefulWidget {
  const ExportBinding({
    required this.client,
    required this.onClose,
    this.controller,
    this.folders = const ExportFolderPlatform(),
    this.initialFormat = ExportFormat.wav,
    this.initialSampleRate = 48000,
    this.initialDirectory,
    this.onExportStarted,
    this.onExportDone,
    super.key,
  });

  final EngineClient client;
  final VoidCallback onClose;
  final core.EngineController? controller;
  final ExportFolderPicker folders;
  final ExportFormat initialFormat;
  final int initialSampleRate;

  /// Overrides where the first export is offered. Defaults to the folder the
  /// project lives in, and to the user's Music folder for a project that has
  /// never been saved.
  final String? initialDirectory;
  final VoidCallback? onExportStarted;
  final ValueChanged<String>? onExportDone;

  @override
  State<ExportBinding> createState() => _ExportBindingState();
}

class _ExportBindingState extends State<ExportBinding> {
  // The render runs on an engine thread; this is how often the UI asks it where
  // it has got to. Fast enough for a bar that moves, cheap enough to ignore.
  static const Duration _pollInterval = Duration(milliseconds: 100); // token-lint-ok: engine poll cadence

  late ExportFormat _format;
  late int _sampleRate;
  late String _directory;

  ExportFlowVm? _overrideVm;
  Timer? _poll;
  bool _running = false;

  @override
  void initState() {
    super.initState();
    _format = widget.initialFormat;
    _sampleRate = widget.initialSampleRate;
    _directory = widget.initialDirectory ?? _defaultDirectory();
  }

  @override
  void dispose() {
    _poll?.cancel();
    // The dialog is the only thing showing a render's progress, so a render
    // must not outlive it: closing mid-export cancels rather than leaving the
    // engine bouncing with nobody watching and the transport claimed.
    if (_running) widget.client.cancelExport();
    super.dispose();
  }

  /// Beside the project if it has been saved, otherwise the user's Music
  /// folder: the two places a person looks for a bounce they just made.
  String _defaultDirectory() {
    final String projectPath = widget.client.projectPath;
    if (projectPath.isNotEmpty) {
      final String parent = File(projectPath).parent.path;
      if (Directory(parent).existsSync()) return parent;
    }
    final String? home = Platform.environment['HOME'];
    if (home != null && home.isNotEmpty) {
      final String music = '$home/Music';
      if (Directory(music).existsSync()) return music;
      return home;
    }
    return Directory.current.path;
  }

  String get _projectName {
    final String name = widget.client.projectName;
    return name.isEmpty ? 'Untitled' : name;
  }

  ExportFlowVm _buildVm() {
    if (_overrideVm != null) return _overrideVm!;
    return ExportSettingsVm(
      projectName: _projectName,
      format: _format,
      sampleRate: _sampleRate,
      destinationDirectory: _directory,
      fileName: '$_projectName.${_format.extension}',
    );
  }

  Future<void> _chooseFolder() async {
    final String? chosen = await widget.folders.pickExportFolder(directory: _directory);
    if (chosen == null || !mounted) return;
    setState(() => _directory = chosen);
  }

  void _startExport() {
    widget.onExportStarted?.call();
    try {
      widget.client.startExport(
        directory: _directory,
        format: _format,
        sampleRate: _sampleRate,
      );
    } on EngineException catch (error) {
      setState(() {
        _running = false;
        _overrideVm = ExportFailedVm(errorMessage: error.message);
      });
      return;
    }
    setState(() {
      _running = true;
      _overrideVm = const ExportProgressVm(progress: 0.0, statusText: 'Rendering audio mix…');
    });
    _poll?.cancel();
    _poll = Timer.periodic(_pollInterval, (Timer timer) => _readStatus()); // token-lint-ok: engine poll
  }

  void _readStatus() {
    if (!mounted) {
      _poll?.cancel();
      return;
    }
    final ExportStatus status = widget.client.readExportStatus();
    switch (status.state) {
      case ExportState.running:
        setState(() {
          _overrideVm = ExportProgressVm(
            progress: status.progress,
            statusText: 'Rendering audio mix…',
          );
        });
      case ExportState.done:
        _poll?.cancel();
        _running = false;
        widget.onExportDone?.call(status.path);
        setState(() {
          _overrideVm = ExportDoneVm(
            filePath: status.path,
            summaryText: '${_format.label} 24-bit · ${sampleRateLabel(_sampleRate)}',
          );
        });
      case ExportState.failed:
        _poll?.cancel();
        _running = false;
        setState(() {
          _overrideVm = ExportFailedVm(
            errorMessage: status.error.isEmpty ? 'The export did not finish.' : status.error,
          );
        });
      case ExportState.cancelled:
      case ExportState.idle:
        _poll?.cancel();
        _running = false;
        setState(() => _overrideVm = null);
    }
  }

  void _cancelExport() {
    widget.client.cancelExport();
    // Left running: the engine finishes the block it is on, deletes the partial
    // file and reports OB_EXPORT_CANCELLED, which is what returns the dialog to
    // its settings. Dropping the timer here would leave the render unwatched.
    _readStatus();
  }

  void _openFolder() {
    final ExportFlowVm vm = _buildVm();
    if (vm is! ExportDoneVm) return;
    // Reveals rather than opens: the point is to show the file where it landed,
    // not to hand it to whatever plays WAVs on this machine.
    unawaited(Process.run('open', <String>['-R', vm.filePath]));
  }

  @override
  Widget build(BuildContext context) {
    return ExportDialog(
      vm: _buildVm(),
      onClose: widget.onClose,
      onFormatChanged: (ExportFormat format) => setState(() => _format = format),
      onSampleRateChanged: (int rate) => setState(() => _sampleRate = rate),
      onChooseFolder: () => unawaited(_chooseFolder()),
      onStartExport: _startExport,
      onCancelExport: _cancelExport,
      onOpenFolder: _openFolder,
      onRetry: _startExport,
    );
  }
}
