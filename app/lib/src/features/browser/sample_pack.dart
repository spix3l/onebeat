// Sample pack models and filesystem scanning for the browser (UI-D-10).
import 'dart:io';

import 'package:flutter/foundation.dart';

/// One audio file that can be dragged from a sample pack into the rack.
@immutable
class SampleAsset {
  const SampleAsset({
    required this.id,
    required this.name,
    required this.path,
  });

  final String id;
  final String name;
  final String path;
}

/// A validated folder and the audio assets directly or recursively beneath it.
@immutable
class SamplePack {
  const SamplePack({
    required this.path,
    required this.name,
    required this.assets,
  });

  final String path;
  final String name;
  final List<SampleAsset> assets;
}

/// Scans only formats the current engine can decode. Keeping this list at the
/// import boundary prevents the browser from offering files that will fail when
/// they are dropped into a rack.
class SamplePackScanner {
  static const Set<String> supportedExtensions = <String>{'wav'};

  static Future<SamplePack?> scan(String path) async {
    final Directory root = Directory(path);
    if (!await root.exists()) return null;

    try {
      final List<File> files = <File>[];
      await for (final FileSystemEntity entry
          in root.list(recursive: true, followLinks: false)) {
        if (entry is! File) continue;
        final String extension = _extension(entry.path);
        if (supportedExtensions.contains(extension)) files.add(entry);
      }
      files.sort((File a, File b) => a.path.compareTo(b.path));
      if (files.isEmpty) return null;

      final String packName = _basename(root.path);
      return SamplePack(
        path: root.path,
        name: packName.isEmpty ? root.path : packName,
        assets: <SampleAsset>[
          for (final File file in files)
            SampleAsset(
              id: 'sample:${file.path}',
              name: _basename(file.path),
              path: file.path,
            ),
        ],
      );
    } on FileSystemException {
      return null;
    }
  }

  static String _extension(String path) {
    final int dot = path.lastIndexOf('.');
    return dot < 0 ? '' : path.substring(dot + 1).toLowerCase();
  }

  static String _basename(String path) {
    final String normalized = path.replaceAll('\\', '/');
    final String withoutTrailing = normalized.endsWith('/')
        ? normalized.substring(0, normalized.length - 1)
        : normalized;
    final int slash = withoutTrailing.lastIndexOf('/');
    return slash < 0 ? withoutTrailing : withoutTrailing.substring(slash + 1);
  }
}
