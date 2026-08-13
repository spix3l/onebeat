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

  // The path list is only meaningful for "could not find it anywhere". A
  // version mismatch already names the file it found, so appending an empty
  // "Looked in:" heading to that message is noise in a string a user reads.
  @override
  String toString() =>
      searchedPaths.isEmpty
          ? message
          : '$message\nLooked in:\n${searchedPaths.map((String p) => '  $p').join('\n')}';
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
    _checkAbiVersion(bindings, path);
    return bindings;
  }
  throw EngineLoadException(
    'The OneBeat audio engine could not be found. Build it with '
    '`tools/build.sh` and start the app again.',
    candidates,
  );
}

/// The client refuses to run against an ABI it cannot use, with a clear message
/// rather than a crash three calls later (ADR-002 §1).
void _checkAbiVersion(OneBeatBindings bindings, String path) {
  final int packed = bindings.ob_abi_version();
  final int major = (packed >> 16) & 0xFF;
  final int minor = (packed >> 8) & 0xFF;
  final int patch = packed & 0xFF;

  if (major != expectedAbiMajor) {
    throw EngineLoadException(
      'This build of OneBeat needs engine ABI $expectedAbiMajor.x but found '
      '$major.$minor.$patch at $path. Rebuild the engine with `tools/build.sh`.',
      const <String>[],
    );
  }

  // The minor check is what catches a *stale* engine, and it is worth having
  // because the symptom without it is terrible: the app loads, runs, and then
  // dies on the first call to a function the old dylib does not export —
  // "Failed to lookup symbol 'ob_engine_plugin_cache_load'", from inside a
  // widget build, with nothing pointing at the real cause. Minor versions are
  // additive (ADR-002 §8), so a *newer* engine is fine; an older one is not.
  if (minor < expectedAbiMinor) {
    throw EngineLoadException(
      'The engine at $path is ABI $major.$minor.$patch, but this build of the '
      'app was generated against $expectedAbiMajor.$expectedAbiMinor and calls '
      'functions that version does not have. It is a stale build rather than a '
      'broken one: rebuild with `tools/build.sh`.',
      const <String>[],
    );
  }
}

/// Kept in step with OB_ABI_VERSION_MAJOR/MINOR in engine/src/abi/onebeat_abi.h.
/// Bump the minor here in the same change that bumps it there — that pairing is
/// what makes a stale dylib a clear message instead of a missing symbol.
const int expectedAbiMajor = 1;
const int expectedAbiMinor = 2;
