// Native bridge for the project open/save panels (macOS).
//
// A `.obt` project is a *directory* that Finder shows as one file (ADR-004 §3,
// `LSTypeIsPackage`). That is why this cannot be a generic file picker: the
// open panel has to treat packages as files so the user picks the bundle rather
// than wandering into `state/`, and the save panel has to append `.obt` itself
// so a project can never be written to a name Finder will not open.
import 'package:flutter/services.dart';

/// The project bundle extension, without the dot. One definition, because a
/// second one would eventually disagree with the Info.plist.
const String projectExtension = 'obt';

/// Everything the store needs from the platform, as a seam: widget tests and
/// non-macOS hosts get a stand-in rather than a missing plug-in exception.
abstract interface class ProjectFilePanels {
  /// The bundle the user chose to open, or null if they cancelled.
  Future<String?> pickProjectToOpen();

  /// Where to write, or null if they cancelled. The returned path always ends
  /// in `.$projectExtension`.
  Future<String?> pickProjectDestination({
    required String suggestedName,
    String directory = '',
  });
}

class ProjectFilePlatform implements ProjectFilePanels {
  const ProjectFilePlatform();

  static const MethodChannel _channel = MethodChannel('onebeat/project_files');

  @override
  Future<String?> pickProjectToOpen() async {
    try {
      return await _channel.invokeMethod<String>('pickProjectToOpen');
    } on MissingPluginException {
      // No native host — `flutter test`, or a platform without the bridge.
      return null;
    } on PlatformException {
      return null;
    }
  }

  @override
  Future<String?> pickProjectDestination({
    required String suggestedName,
    String directory = '',
  }) async {
    try {
      final String? chosen = await _channel.invokeMethod<String>('pickProjectDestination', <String, String>{
        'suggestedName': suggestedName,
        'directory': directory,
      });
      if (chosen == null || chosen.isEmpty) return null;
      // Belt and braces: NSSavePanel appends the extension for us, but a user
      // who types `Track.obt.obt` or edits the field in an unusual way must
      // still end up with one bundle called `Track.obt`.
      return chosen.endsWith('.$projectExtension') ? chosen : '$chosen.$projectExtension';
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }
}
