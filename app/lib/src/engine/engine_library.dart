// Locating and opening the engine dylib.
//
// Three resolution steps, in order, each with a reason:
//   1. OB_ENGINE_DYLIB      — an explicit override, used by tests and CI.
//   2. the app bundle       — Contents/Frameworks/, how a shipped build works.
//   3. the repository build — engine build output, how `flutter run` works
//                             during development before packaging exists.
//
// Bundling and signing the dylib into a distributable .app is Stage 2 work
// (OB-2-06); v0.1 runs from a development build and says so out loud.
import 'dart:ffi';
import 'dart:io';

import 'generated/onebeat_bindings.dart';

/// Thrown when the engine cannot be loaded at all. The message is written to be
/// shown to a person (FR-UX-12): what happened, and what to do about it.
class EngineLoadException implements Exception {
  EngineLoadException(this.message, this.searchedPaths);

  final String message;
  final List<String> searchedPaths;

  @override
  String toString() =>
      '$message\nLooked in:\n${searchedPaths.map((String p) => '  $p').join('\n')}';
}

const String _libraryFileName = 'libonebeat_engine.dylib';

List<String> _candidatePaths() {
  final List<String> candidates = <String>[];

  final String? override = Platform.environment['OB_ENGINE_DYLIB'];
  if (override != null && override.isNotEmpty) {
    candidates.add(override);
  }

  final Directory executableDir = File(Platform.resolvedExecutable).parent;
  candidates.add('${executableDir.path}/../Frameworks/$_libraryFileName');

  // Development: walk up from the working directory looking for the engine
  // build output, so `flutter run` from app/ or from the repository root works.
  Directory dir = Directory.current;
  for (int depth = 0; depth < 4; depth++) {
    candidates.add('${dir.path}/build/$_libraryFileName');
    candidates.add('${dir.path}/build/RelWithDebInfo/$_libraryFileName');
    dir = dir.parent;
  }
  return candidates;
}

/// Opens the engine and checks the ABI major version before anything else runs.
OneBeatBindings openEngineLibrary() {
  final List<String> candidates = _candidatePaths();
  for (final String path in candidates) {
    if (!File(path).existsSync()) {
      continue;
    }
    final OneBeatBindings bindings = OneBeatBindings(DynamicLibrary.open(path));
    _checkAbiVersion(bindings);
    return bindings;
  }
  throw EngineLoadException(
    'The OneBeat audio engine could not be found. Build it with '
    '`tools/build.sh` and start the app again.',
    candidates,
  );
}

/// The client refuses to run against a different ABI major version, with a
/// clear message rather than a crash three calls later (ADR-002 §1).
void _checkAbiVersion(OneBeatBindings bindings) {
  final int packed = bindings.ob_abi_version();
  final int major = (packed >> 16) & 0xFF;
  final int minor = (packed >> 8) & 0xFF;
  final int patch = packed & 0xFF;
  if (major != expectedAbiMajor) {
    throw EngineLoadException(
      'This build of OneBeat needs engine ABI $expectedAbiMajor.x but found '
      '$major.$minor.$patch. Rebuild the engine with `tools/build.sh`.',
      const <String>[],
    );
  }
}

/// Kept in step with OB_ABI_VERSION_MAJOR in engine/src/abi/onebeat_abi.h.
const int expectedAbiMajor = 1;
