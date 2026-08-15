// ProjectStore tests (OB-3-05 §4).
//
// The decisions ⌘S, ⌘O and Rename make, without an engine, a native panel or a
// disk: which of save and save-as applies, what a cancelled panel means, and
// what happens to the bundle when the project is renamed.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:onebeat/src/engine/engine_client.dart';
import 'package:onebeat/src/features/project/project_files_platform.dart';
import 'package:onebeat/src/features/project/project_store.dart';

import '../../support/fake_engine_client.dart';

class _ScriptedPanels implements ProjectFilePanels {
  /// What the next panel returns. Null is a cancelled panel.
  String? openAnswer;
  String? saveAnswer;

  int openCalls = 0;
  int saveCalls = 0;
  String lastSuggestedName = '';
  String lastDirectory = '';

  @override
  Future<String?> pickProjectToOpen() async {
    openCalls++;
    return openAnswer;
  }

  @override
  Future<String?> pickProjectDestination({
    required String suggestedName,
    String directory = '',
  }) async {
    saveCalls++;
    lastSuggestedName = suggestedName;
    lastDirectory = directory;
    return saveAnswer;
  }
}

class _FakeBundles implements ProjectBundles {
  _FakeBundles([Set<String>? present]) : present = present ?? <String>{};

  final Set<String> present;
  final List<String> deleted = <String>[];
  bool deleteThrows = false;

  @override
  bool exists(String path) => present.contains(path);

  @override
  void delete(String path) {
    if (deleteThrows) {
      throw const FileSystemException('Permission denied');
    }
    deleted.add(path);
    present.remove(path);
  }
}

void main() {
  late FakeEngineClient client;
  late _ScriptedPanels panels;
  late _FakeBundles bundles;
  late ProjectStore store;

  setUp(() {
    client = FakeEngineClient();
    panels = _ScriptedPanels();
    bundles = _FakeBundles();
    store = ProjectStore(client, panels, bundles);
  });

  group('save', () {
    test('the first save asks where, and adopts the name it was given', () async {
      panels.saveAnswer = '/Music/Night Drive.obt';

      final ProjectResult result = await store.save();

      expect(result.outcome, ProjectOutcome.done);
      expect(panels.saveCalls, 1);
      expect(panels.lastSuggestedName, 'Untitled.obt');
      expect(client.savedPath, '/Music/Night Drive.obt');
      expect(store.name, 'Night Drive');
    });

    test('later saves write in place without asking again', () async {
      panels.saveAnswer = '/Music/Night Drive.obt';
      await store.save();

      final ProjectResult result = await store.save();

      expect(result.outcome, ProjectOutcome.done);
      expect(panels.saveCalls, 1, reason: '⌘S must not re-open the panel');
      expect(client.saves, 2);
    });

    test('cancelling the panel writes nothing and is not an error', () async {
      panels.saveAnswer = null;

      final ProjectResult result = await store.save();

      expect(result.outcome, ProjectOutcome.cancelled);
      expect(result.message, isEmpty);
      expect(client.saves, 0);
    });

    test('save as offers the folder the project already lives in', () async {
      panels.saveAnswer = '/Music/A.obt';
      await store.save();
      panels.saveAnswer = '/Music/B.obt';

      await store.saveAs();

      expect(panels.lastDirectory, '/Music');
      expect(client.savedPath, '/Music/B.obt');
      expect(store.name, 'B');
    });

    test('a failed write says so and leaves the project modified', () async {
      panels.saveAnswer = '/Music/Night Drive.obt';
      client.modified = true;
      store.refresh();
      client.failure = EngineException('The disk is full.');

      final ProjectResult result = await store.save();

      expect(result.isFailure, isTrue);
      expect(result.message, contains('Night Drive.obt'));
      expect(result.message, contains('The disk is full.'));
      expect(store.modified, isTrue);
    });
  });

  group('open', () {
    test('a chosen project replaces the session', () async {
      panels.openAnswer = '/Music/Other.obt';

      final ProjectResult result = await store.open();

      expect(result.outcome, ProjectOutcome.done);
      expect(client.opens, 1);
      expect(store.modified, isFalse);
    });

    test('a file that will not load leaves the session alone', () async {
      client.failure = EngineException('version 2 was written by a newer build');
      panels.openAnswer = '/Music/Future.obt';

      final ProjectResult result = await store.open();

      expect(result.isFailure, isTrue);
      expect(result.message, contains('Future.obt'));
      expect(result.message, contains('still here'));
      expect(client.opens, 0);
    });

    test('cancelling opens nothing', () async {
      panels.openAnswer = null;

      expect((await store.open()).outcome, ProjectOutcome.cancelled);
      expect(client.opens, 0);
    });
  });

  group('rename', () {
    test('an unsaved project just takes the name', () async {
      final ProjectResult result = await store.rename('Night Drive');

      expect(result.outcome, ProjectOutcome.done);
      expect(store.name, 'Night Drive');
      expect(client.saves, 0, reason: 'renaming is not a save');
      expect(bundles.deleted, isEmpty);
    });

    test('a saved project moves its bundle, new one first', () async {
      panels.saveAnswer = '/Music/Old.obt';
      await store.save();

      final ProjectResult result = await store.rename('New');

      expect(result.outcome, ProjectOutcome.done);
      expect(store.name, 'New');
      expect(client.savedPath, '/Music/New.obt');
      expect(
        bundles.deleted,
        <String>['/Music/Old.obt'],
        reason: 'the old bundle goes only after the new one is written',
      );
    });

    test('a name already taken in that folder is refused, changing nothing', () async {
      panels.saveAnswer = '/Music/Old.obt';
      await store.save();
      bundles.present.add('/Music/Taken.obt');

      final ProjectResult result = await store.rename('Taken');

      expect(result.isFailure, isTrue);
      expect(result.message, contains('already in that folder'));
      expect(store.name, 'Old');
      expect(client.savedPath, '/Music/Old.obt');
      expect(bundles.deleted, isEmpty);
    });

    test('a rename that cannot remove the old bundle still succeeded', () async {
      panels.saveAnswer = '/Music/Old.obt';
      await store.save();
      bundles.deleteThrows = true;

      final ProjectResult result = await store.rename('New');

      expect(result.outcome, ProjectOutcome.done);
      expect(result.message, contains('Old.obt'));
      expect(client.savedPath, '/Music/New.obt');
    });

    test('names that cannot become file names are refused', () {
      expect(ProjectStore.validateName(''), isNotNull);
      expect(ProjectStore.validateName('   '), isNotNull);
      expect(ProjectStore.validateName('Drums/Bass'), isNotNull);
      expect(ProjectStore.validateName('a:b'), isNotNull);
      expect(ProjectStore.validateName('.hidden'), isNotNull);
      expect(ProjectStore.validateName('Night Drive'), isNull);
    });

    test('a refused name never reaches the engine', () async {
      final ProjectResult result = await store.rename('  ');

      expect(result.isFailure, isTrue);
      expect(store.name, 'Untitled');
    });
  });

  group('the dirty flag', () {
    test('refresh asks the engine and notifies once per change', () {
      int notifications = 0;
      store.addListener(() => notifications++);

      store.refresh();
      expect(store.modified, isFalse);
      expect(notifications, 0);

      client.modified = true;
      store.refresh();
      store.refresh();

      expect(store.modified, isTrue);
      expect(notifications, 1, reason: 'unchanged answers are not events');
    });

    test('the status line names the file and marks unsaved work', () async {
      expect(store.displayName, 'Untitled.obt');

      client.modified = true;
      store.refresh();
      expect(store.displayName, 'Untitled.obt — Edited');

      panels.saveAnswer = '/Music/Night Drive.obt';
      await store.save();
      expect(store.displayName, 'Night Drive.obt');
    });
  });
}
