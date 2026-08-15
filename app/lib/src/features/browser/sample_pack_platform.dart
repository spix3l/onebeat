// Native bridge for sample pack folders and direct audio-file drops (macOS).
import 'package:flutter/services.dart';

class AudioFileDrop {
  const AudioFileDrop({
    required this.paths,
    required this.x,
    required this.y,
  });

  final List<String> paths;
  final double x;
  final double y;
}

class SamplePackPlatform {
  static const MethodChannel _channel = MethodChannel('onebeat/sample_packs');

  Future<String?> pickFolder() async {
    try {
      return await _channel.invokeMethod<String>('pickSampleFolder');
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  Future<List<String>> loadFolders() async {
    try {
      final List<Object?> result =
          await _channel.invokeListMethod<Object?>('loadSampleFolders') ??
          const <Object?>[];
      return result.whereType<String>().toList(growable: false);
    } on MissingPluginException {
      return const <String>[];
    } on PlatformException {
      return const <String>[];
    }
  }

  Future<void> saveFolders(Iterable<String> paths) async {
    try {
      await _channel.invokeMethod<void>('saveSampleFolders', <String>[
        ...paths,
      ]);
    } on MissingPluginException {
      // Widget tests and non-macOS hosts have no native picker.
    } on PlatformException {
      // A failed preference write must not interrupt editing.
    }
  }

  /// Which browser rows the user has opened or closed, by row id. Only rows
  /// that were toggled appear; everything else keeps the panel's own default.
  Future<Map<String, bool>> loadBrowserExpansion() async {
    try {
      return await _channel.invokeMapMethod<String, bool>(
            'loadBrowserExpansion',
          ) ??
          const <String, bool>{};
    } on MissingPluginException {
      return const <String, bool>{};
    } on PlatformException {
      return const <String, bool>{};
    }
  }

  Future<void> saveBrowserExpansion(Map<String, bool> expansion) async {
    try {
      await _channel.invokeMethod<void>('saveBrowserExpansion', expansion);
    } on MissingPluginException {
      // Widget tests and non-macOS hosts have no preference store.
    } on PlatformException {
      // A failed preference write must not interrupt editing.
    }
  }

  void setDropHandler({
    required ValueChanged<List<String>> onFolders,
    required ValueChanged<AudioFileDrop> onAudioFiles,
  }) {
    _channel.setMethodCallHandler((MethodCall call) async {
      final Object? argument = call.arguments;
      if (call.method == 'samplePackFoldersDropped' && argument is List<Object?>) {
        onFolders(argument.whereType<String>().toList(growable: false));
      } else if (call.method == 'audioFilesDropped' &&
          argument is Map<Object?, Object?>) {
        final List<String> paths =
            (argument['paths'] as List<Object?>?)?.whereType<String>().toList() ??
            const <String>[];
        final double x = (argument['x'] as num?)?.toDouble() ?? 0;
        final double y = (argument['y'] as num?)?.toDouble() ?? 0;
        if (paths.isNotEmpty) {
          onAudioFiles(AudioFileDrop(paths: paths, x: x, y: y));
        }
      }
      return null;
    });
  }

  void clearDropHandler() {
    _channel.setMethodCallHandler(null);
  }
}
