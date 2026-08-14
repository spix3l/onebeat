// Store-level behaviour for PatternStore: shared-pattern notices, live usage
// counts, and Make unique diverging one placement while the rest keep sharing.
import 'package:flutter_test/flutter_test.dart';
import 'package:onebeat/src/core/pattern_store.dart';
import 'package:onebeat/src/engine/engine_client.dart';

import '../support/app_harness.dart';

void main() {
  group('the shared-pattern notice', () {
    test('appears once per pattern per session', () {
      final EditorHarness harness = EditorHarness()..seedArrangement();
      final PatternStore patterns = harness.patterns;
      expect(patterns.current!.usageCount, 2, reason: 'two clips share it');

      patterns.noteEditStarted();
      expect(patterns.notice, isNotNull);
      expect(patterns.notice!.usageCount, 2);
      expect(patterns.notice!.message, contains('used in 2 places'));

      patterns.dismissNotice();
      patterns.noteEditStarted();
      expect(
        patterns.notice,
        isNull,
        reason: 'the second edit of the same pattern must not nag',
      );
    });

    test('a pattern used once raises no notice at all', () {
      final EditorHarness harness = EditorHarness();
      harness.client.addClip('lane_a', startTicks: 0, lengthTicks: 3840);
      harness.patterns.refresh();

      harness.patterns.noteEditStarted();

      expect(harness.patterns.notice, isNull);
    });

    test('is offered with Make unique only with a clip context', () {
      final EditorHarness harness = EditorHarness()..seedArrangement();
      final PatternStore patterns = harness.patterns;

      // Reaching a pattern without going through a clip: "unique for which
      // clip?" has no answer, so the inline action is not offered.
      patterns.noteEditStarted();
      expect(patterns.notice!.canMakeUnique, isFalse);

      // A second shared pattern, reached by double-clicking one of its clips.
      // It has to be a *different* pattern: the once-per-session rule below
      // would otherwise suppress this notice entirely.
      harness.client
        ..createPattern('Chorus Drums')
        ..addClip('lane_a', startTicks: 7680, lengthTicks: 3840)
        ..addClip('lane_a', startTicks: 11520, lengthTicks: 3840);
      patterns.refresh();
      harness.arrangement.refresh();
      final String chorus = patterns.current!.id;
      final String chorusClip = harness.arrangement.clips
          .firstWhere((ArrangementClip clip) => clip.patternId == chorus)
          .id;

      patterns
        ..dismissNotice()
        ..select(chorus, fromClipId: chorusClip);
      patterns.noteEditStarted();

      expect(patterns.notice!.canMakeUnique, isTrue);
      expect(patterns.notice!.clipId, chorusClip);
    });

    test('the once-per-session rule is per pattern, not global', () {
      final EditorHarness harness = EditorHarness()..seedArrangement();
      final PatternStore patterns = harness.patterns;
      final String first = patterns.current!.id;

      patterns.noteEditStarted();
      expect(patterns.notice, isNotNull);
      patterns.dismissNotice();

      harness.client
        ..createPattern('Chorus Drums')
        ..addClip('lane_a', startTicks: 7680, lengthTicks: 3840)
        ..addClip('lane_a', startTicks: 11520, lengthTicks: 3840);
      patterns.refresh();

      patterns.noteEditStarted();
      expect(
        patterns.notice,
        isNotNull,
        reason: 'a different shared pattern deserves its own warning',
      );
      expect(patterns.hasWarnedAbout(first), isTrue);
    });

    test('usage counts are live rather than cached', () {
      final EditorHarness harness = EditorHarness()..seedArrangement();
      expect(harness.patterns.current!.usageCount, 2);

      harness.arrangement
        ..selectClip(harness.arrangement.clips.first.id)
        ..deleteSelection();

      expect(harness.patterns.current!.usageCount, 1);
    });
  });

  group('Make unique', () {
    test('diverges the chosen clip and leaves the other sharing', () {
      final EditorHarness harness = EditorHarness()..seedArrangement();
      harness.client.addNote('inst_a', 0, 240, 60, velocity: 9000);
      harness.patterns.refresh();

      final List<ArrangementClip> before = harness.arrangement.clips;
      final String firstClip = before[0].id;
      final String secondClip = before[1].id;
      final String originalPattern = before[0].patternId;

      harness.patterns.makeUnique(<String>[firstClip]);
      harness.arrangement.refresh();

      final ArrangementClip first = harness.arrangement.clipById(firstClip)!;
      final ArrangementClip second = harness.arrangement.clipById(secondClip)!;
      expect(first.patternId, isNot(originalPattern));
      expect(second.patternId, originalPattern);
      expect(first.name, 'Verse Drums 2');
      expect(first.noteCount, second.noteCount, reason: 'the clone copied notes');

      // Editing the clone must not reach the original.
      harness.patterns.select(first.patternId);
      harness.client.addNote('inst_a', 1920, 240, 72, velocity: 9000);
      harness.arrangement.refresh();
      expect(
        harness.arrangement.clipById(firstClip)!.noteCount,
        harness.arrangement.clipById(secondClip)!.noteCount + 1,
      );
    });

    test('one clone serves a whole multi-clip selection', () {
      final EditorHarness harness = EditorHarness()..seedArrangement();
      final List<String> ids = harness.arrangement.clips
          .map((ArrangementClip clip) => clip.id)
          .toList();

      harness.patterns.makeUnique(ids);
      harness.arrangement.refresh();

      final Set<String> patternIds = harness.arrangement.clips
          .map((ArrangementClip clip) => clip.patternId)
          .toSet();
      expect(patternIds.length, 1, reason: 'both clips share the one clone');
      expect(harness.patterns.patterns.length, 2);
    });
  });
}
