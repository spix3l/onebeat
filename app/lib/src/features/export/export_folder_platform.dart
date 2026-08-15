// Native bridge for the "where should this export go?" panel (macOS).
//
// Shares the panels channel with the project open/save bridge: the native side
// of both is one NSOpenPanel wearing a different hat, and a second channel for
// a second panel would be two names for one seam.
import 'package:flutter/services.dart';

/// A seam, so widget tests and non-macOS hosts get a stand-in rather than a
/// missing-plug-in exception.
abstract interface class ExportFolderPicker {
  /// The folder the user chose, or null if they cancelled. [directory] is where
  /// the panel opens.
  Future<String?> pickExportFolder({String directory = ''});
}

class ExportFolderPlatform implements ExportFolderPicker {
  const ExportFolderPlatform();

  static const MethodChannel _channel = MethodChannel('onebeat/project_files');

  @override
  Future<String?> pickExportFolder({String directory = ''}) async {
    try {
      final String? chosen = await _channel.invokeMethod<String>(
        'pickExportFolder',
        <String, String>{'directory': directory},
      );
      return chosen == null || chosen.isEmpty ? null : chosen;
    } on MissingPluginException {
      // No native host — `flutter test`, or a platform without the bridge.
      return null;
    } on PlatformException {
      return null;
    }
  }
}
