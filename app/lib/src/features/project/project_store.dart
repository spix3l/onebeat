// ProjectStore — New/Open/Save/Save As/Rename, and the dirty flag (OB-3-05 §4).
//
// The engine owns the model and the file format; this owns the *decisions* a
// user makes about them: which of ⌘S and Save As applies, what a cancelled
// panel means, and what happens to the bundle on disk when a project is
// renamed. It is deliberately separable from the shell so those decisions are
// tested without an engine, a dylib or a native panel.
//
// Two rules run through all of it:
//
//   1. **A failed action changes nothing.** The engine leaves the open project
//      untouched when a load fails, and every path here that can fail is
//      ordered so the previous state survives it.
//   2. **The new bundle exists before the old one goes.** Rename saves to the
//      new name and only then removes what it replaced, so an interruption
//      leaves two projects rather than none.
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../engine/engine_client.dart';
import 'project_files_platform.dart';

/// What an action did. `cancelled` is not a failure — dismissing a panel is a
/// legitimate answer and must not produce an error message.
enum ProjectOutcome { done, cancelled, failed }

@immutable
class ProjectResult {
  const ProjectResult(this.outcome, [this.message = '']);

  const ProjectResult.done([String message = '']) : this(ProjectOutcome.done, message);
  const ProjectResult.cancelled() : this(ProjectOutcome.cancelled);
  const ProjectResult.failed(String message) : this(ProjectOutcome.failed, message);

  final ProjectOutcome outcome;

  /// User-facing, in the wording of `docs/errors.md`: what happened, and what
  /// the user can do about it. Empty for a plain success.
  final String message;

  bool get isFailure => outcome == ProjectOutcome.failed;
}

/// The bundle operations rename needs. A seam so the rename logic is tested
/// without touching a real disk.
abstract interface class ProjectBundles {
  bool exists(String path);
  void delete(String path);
}

class SystemProjectBundles implements ProjectBundles {
  const SystemProjectBundles();

  @override
  bool exists(String path) => Directory(path).existsSync() || File(path).existsSync();

  @override
  void delete(String path) => Directory(path).deleteSync(recursive: true);
}

class ProjectStore extends ChangeNotifier {
  /// The panels and the bundle operations are positional and defaulted so a
  /// test can substitute both without the engine or a real disk.
  ProjectStore(
    this._client, [
    this._panels = const ProjectFilePlatform(),
    this._bundles = const SystemProjectBundles(),
  ]);

  final ProjectFileClient _client;
  final ProjectFilePanels _panels;
  final ProjectBundles _bundles;

  bool _modified = false;
  String _message = '';

  /// The user-facing project name. Not the file name: an unsaved project has a
  /// name and no path.
  String get name => _client.projectName;

  /// The bundle on disk, empty until the project has been saved once.
  String get path => _client.projectPath;

  bool get hasFile => path.isNotEmpty;

  /// True when the project differs from what is on disk. Refreshed by
  /// [refresh]; reading it never walks the project.
  bool get modified => _modified;

  /// The last thing worth telling the user, or empty.
  String get message => _message;

  /// What the status bar shows: `Night Drive.obt` once saved, the project name
  /// before that, with an edited marker while there is something to save.
  String get displayName {
    final String base = hasFile ? _fileName(path) : '$name.$projectExtension';
    return _modified ? '$base — Edited' : base;
  }

  /// Re-asks the engine whether anything has changed. Called on a cadence the
  /// user notices rather than every frame: answering walks the project.
  void refresh() {
    final bool next = _client.isProjectModified;
    if (next == _modified) return;
    _modified = next;
    notifyListeners();
  }

  void clearMessage() {
    if (_message.isEmpty) return;
    _message = '';
    notifyListeners();
  }

  /// Starts a clean project after the shell has handled any save prompt.
  ProjectResult newProject() {
    try {
      _client.newProject();
    } on EngineException catch (error) {
      return _report(ProjectResult.failed('The new project could not be created. ${error.message}'));
    }
    _modified = false;
    return _report(const ProjectResult.done('Started a new project.'));
  }

  /// ⌘S. Writes in place, or asks where to write the first time.
  Future<ProjectResult> save() async {
    if (!hasFile) return saveAs();
    return _report(_write(path));
  }

  /// ⇧⌘S. Always asks, and adopts the chosen name as the project's own so the
  /// title and the file cannot disagree.
  Future<ProjectResult> saveAs() async {
    final String? destination = await _panels.pickProjectDestination(
      suggestedName: '$name.$projectExtension',
      directory: hasFile ? _parentOf(path) : '',
    );
    if (destination == null) return _report(const ProjectResult.cancelled());

    final String chosen = _projectNameOf(destination);
    if (chosen.isNotEmpty && chosen != name) {
      try {
        _client.setProjectName(chosen);
      } on EngineException {
        // Keeping the old name is harmless; failing the save over it is not.
      }
    }
    return _report(_write(destination));
  }

  /// ⌘O. A load that fails leaves the session exactly as it was, which is why
  /// this can offer to try again rather than having to warn beforehand.
  Future<ProjectResult> open() async {
    final String? chosen = await _panels.pickProjectToOpen();
    if (chosen == null) return _report(const ProjectResult.cancelled());
    try {
      _client.openProject(chosen);
    } on EngineException catch (error) {
      return _report(
        ProjectResult.failed(
          '“${_fileName(chosen)}” could not be opened, so the project you had '
          'open is still here. ${error.message}',
        ),
      );
    }
    _modified = _client.isProjectModified;
    return _report(ProjectResult.done('Opened “${_fileName(chosen)}”.'));
  }

  /// Renames the project, and the bundle with it.
  ///
  /// The name in `project.json` and the name in Finder are one thing to a user,
  /// so they move together: the project is written under the new name and the
  /// bundle it replaces is removed afterwards. A project that has never been
  /// saved just takes the name — there is no file to move yet.
  Future<ProjectResult> rename(String requested) async {
    final String wanted = requested.trim();
    final String? problem = validateName(wanted);
    if (problem != null) return _report(ProjectResult.failed(problem));
    if (wanted == name && !hasFile) return _report(const ProjectResult.done());

    if (!hasFile) {
      try {
        _client.setProjectName(wanted);
      } on EngineException catch (error) {
        return _report(ProjectResult.failed(error.message));
      }
      notifyListeners();
      return _report(
        ProjectResult.done('Renamed to “$wanted”. It is saved on first save.'),
      );
    }

    final String previous = path;
    final String destination = '${_parentOf(previous)}/$wanted.$projectExtension';
    if (destination != previous && _bundles.exists(destination)) {
      return _report(
        ProjectResult.failed(
          'A project called “$wanted” is already in that folder. Choose '
          'another name, or rename the other project first.',
        ),
      );
    }

    try {
      _client.setProjectName(wanted);
    } on EngineException catch (error) {
      return _report(ProjectResult.failed(error.message));
    }

    final ProjectResult written = _write(destination);
    if (written.isFailure) return _report(written);

    if (destination != previous) {
      try {
        _bundles.delete(previous);
      } on FileSystemException catch (error) {
        // The rename itself worked — the project is now the bundle at the new
        // name. Saying so is more useful than pretending it failed.
        return _report(
          ProjectResult.done(
            'Renamed to “$wanted”. The old bundle “${_fileName(previous)}” is '
            'still on disk: ${error.message}',
          ),
        );
      }
    }
    return _report(ProjectResult.done('Renamed to “$wanted”.'));
  }

  /// Why [candidate] is not a usable project name, or null when it is.
  ///
  /// `/` and `:` are the two characters macOS will not let a file carry, and a
  /// project name becomes a file name on the next save. Rejecting them here
  /// beats a save that fails later for a reason the user cannot see.
  static String? validateName(String candidate) {
    final String trimmed = candidate.trim();
    if (trimmed.isEmpty) return 'A project needs a name.';
    if (trimmed.contains('/') || trimmed.contains(':')) {
      return 'A project name cannot contain “/” or “:”.';
    }
    if (trimmed.startsWith('.')) {
      return 'A project name cannot start with a dot.';
    }
    return null;
  }

  ProjectResult _write(String destination) {
    try {
      _client.saveProject(destination);
    } on EngineException catch (error) {
      return ProjectResult.failed(
        'The project could not be saved to “${_fileName(destination)}”. '
        '${error.message}',
      );
    }
    _modified = false;
    return ProjectResult.done('Saved “${_fileName(destination)}”.');
  }

  ProjectResult _report(ProjectResult result) {
    if (result.message != _message) {
      _message = result.message;
    }
    notifyListeners();
    return result;
  }

  static String _fileName(String path) {
    final int slash = path.lastIndexOf('/');
    return slash < 0 ? path : path.substring(slash + 1);
  }

  static String _parentOf(String path) {
    final int slash = path.lastIndexOf('/');
    return slash <= 0 ? '/' : path.substring(0, slash);
  }

  /// `…/Night Drive.obt` → `Night Drive`.
  static String _projectNameOf(String path) {
    final String file = _fileName(path);
    return file.endsWith('.$projectExtension') ? file.substring(0, file.length - projectExtension.length - 1) : file;
  }
}
