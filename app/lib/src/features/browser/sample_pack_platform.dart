// Native bridge for sample pack folders (macOS).
import 'package:flutter/services.dart';

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

  void setFolderDropHandler(ValueChanged<List<String>> onDrop) {
    _channel.setMethodCallHandler((MethodCall call) async {
      if (call.method != 'samplePackFoldersDropped') return null;
      final Object? argument = call.arguments;
      if (argument is List<Object?>) {
        onDrop(argument.whereType<String>().toList(growable: false));
      }
      return null;
    });
  }

  void clearFolderDropHandler() {
    _channel.setMethodCallHandler(null);
  }
}
