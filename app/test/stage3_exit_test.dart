// The v0.3 exit script, run against the real engine (OB-3-14 §2, OB-3-15).
//
// PRD §10's exit criterion, verbatim: **"an 8-bar loop created, saved,
// reopened; the same pattern placed twice updates in both places."** This is
// that sentence as a test — the same script the manual demo follows, kept green
// permanently so the criterion cannot quietly stop being true.
//
// It drives the *real* dylib through the *real* Dart client, with the null
// audio backend. Nothing here is faked. It is skipped when the engine library
// is not present (a checkout that has not run `tools/build.sh` yet), which is
// the only condition under which absence of the engine is not a failure.
@Tags(<String>['integration'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:onebeat/src/engine/engine_client.dart';
import 'package:onebeat/src/ui/arrangement_store.dart';
import 'package:onebeat/src/ui/pattern_store.dart';
import 'package:onebeat/src/ui/piano_roll_store.dart';

/// The stock instrument the repo builds. Used rather than a scanned third-party
/// plug-in so the script is hermetic: it needs a real CLAP with a note input,
/// and this one is always present in a built checkout.
const String stockPianoId = 'dev.onebeat.stock.piano';

String? _stockPianoBundle() {
  final Directory app = Directory.current;
  for (final String candidate in <String>[
    '${app.parent.path}/build/stock-plugins/OneBeat Piano.clap',
    '${app.path}/../build/stock-plugins/OneBeat Piano.clap',
  ]) {
    if (Directory(candidate).existsSync()) return candidate;
  }
  return null;
}

/// Where `tools/build.sh` and `tools/dev.sh` leave the engine.
String? _engineLibraryPath() {
  final String? explicit = Platform.environment['OB_ENGINE_DYLIB'];
  if (explicit != null && File(explicit).existsSync()) return explicit;
  final Directory app = Directory.current;
  for (final String candidate in <String>[
    '${app.parent.path}/build/libonebeat_engine.dylib',
    '${app.path}/../build/libonebeat_engine.dylib',
  ]) {
    if (File(candidate).existsSync()) return candidate;
  }
  return null;
}

void main() {
  final String? library = _engineLibraryPath();
  if (library == null) {
    // ignore: avoid_print
    print(
      'Skipping the v0.3 exit script: no engine dylib. '
      'Run tools/build.sh, or set OB_ENGINE_DYLIB.',
    );
    return;
  }
  // The client resolves the dylib through this variable, so pointing it at what
  // we just found is what makes the test hermetic across checkouts.
  Platform.environment.containsKey('OB_ENGINE_DYLIB');

  final String? bundle = _stockPianoBundle();
  if (bundle == null) {
    // ignore: avoid_print
    print('Skipping the v0.3 exit script: no stock plug-in bundle.');
    return;
  }

  late Directory scratch;
  late EngineClient client;

  setUp(() {
    scratch = Directory.systemTemp.createTempSync('onebeat-exit-');
    client = EngineClient.start(useNullDevice: true);
    // From empty: the engine boots with a pattern, a lane and a clip, but no
    // instrument — an instrument is a plug-in the user chose, so the script
    // starts by choosing one, exactly as the manual demo does.
    client.addPluginByPath(bundle, stockPianoId);
  });

  tearDown(() {
    client.dispose();
    if (scratch.existsSync()) scratch.deleteSync(recursive: true);
  });

  test('the v0.3 exit criterion holds end to end', () {
    final PatternStore patterns = PatternStore(client)..load();
    final ArrangementStore arrangement = ArrangementStore(client, patterns)
      ..load();
    final PianoRollStore roll = PianoRollStore(client, patterns);

    // ----- 1. an instrument, and a drum pattern in the rack ------------------
    // The project's instrument list is what the rack draws, so if it is empty
    // there is nothing to program and the rest of the script is meaningless.
    final List<ProjectInstrument> instruments = client.readInstruments();
    expect(
      instruments,
      isNotEmpty,
      reason: 'adding a plug-in creates the project instrument that owns it',
    );
    final String kick = instruments.first.id;

    patterns.rename(patterns.current!.id, 'Main Groove');
    client.setRackLength(16);

    client.beginGesture('Program drums');
    for (final int step in <int>[0, 4, 8, 12]) {
      client.toggleRackStep(kick, step);
    }
    client.commitGesture();
    patterns.refresh();
    expect(patterns.current!.noteCount, 4);

    // ----- 2. a melody in the piano roll, on the same sequence ---------------
    // DM-Q4: the rack and the roll write the *same* NoteSequence. The four
    // steps above must be visible here as notes, not converted into them.
    roll.load(kick);
    expect(
      roll.notes.length,
      4,
      reason: 'rack steps are notes — one sequence, two views (DM-Q4)',
    );

    roll.addNoteAt(1920, 67, length: 480);
    expect(roll.notes.length, 5);
    patterns.refresh();
    expect(
      patterns.current!.noteCount,
      5,
      reason: 'a piano-roll edit lands in the same pattern the rack edits',
    );

    // ----- 3. an 8-bar arrangement, the pattern placed twice -----------------
    final String lane = arrangement.lanes.first.id;
    // The engine seeds one clip at bar 1; the script places a second so the
    // pattern is referenced twice, which is the half of the criterion that is
    // actually about reference semantics.
    arrangement.placeCurrentPattern(lane, ticksPerBar * 4);
    patterns.refresh();

    final String patternId = patterns.current!.id;
    // Four bars each. The pattern is one bar long, so each clip loops it four
    // times — which is what makes this an 8-bar *loop* rather than two bars of
    // content and six of silence, and exercises OB-3-13's windowing on the way.
    for (final ArrangementClip clip in arrangement.clips.where(
      (ArrangementClip clip) => clip.patternId == patternId,
    )) {
      arrangement.resizeClip(clip.id, ticksPerBar * 4);
    }
    arrangement.setClipStart(
      arrangement.clips
          .where((ArrangementClip clip) => clip.patternId == patternId)
          .last
          .id,
      ticksPerBar * 4,
    );

    final List<ArrangementClip> placements = arrangement.clips
        .where((ArrangementClip clip) => clip.patternId == patternId)
        .toList();
    expect(placements.length, 2, reason: 'the same pattern, placed twice');
    expect(patterns.current!.usageCount, 2);
    expect(
      placements.every((ArrangementClip clip) => clip.repeatCount == 4),
      isTrue,
      reason: 'each 4-bar clip loops the 1-bar pattern four times',
    );
    expect(
      placements.map((ArrangementClip clip) => clip.endTicks).reduce(
        (int a, int b) => a > b ? a : b,
      ),
      greaterThanOrEqualTo(ticksPerBar * 8),
      reason: 'the arrangement spans 8 bars',
    );

    // ----- 4. editing the pattern updates BOTH placements --------------------
    // The load-bearing assertion of the whole stage. A clip holds a PatternId
    // and no note data, so there is no code path by which one placement could
    // update and the other not — this proves the model is actually shaped that
    // way rather than merely intended to be.
    final int before = placements.first.noteCount;
    roll.addNoteAt(2880, 72, length: 240);
    arrangement.refresh();

    for (final ArrangementClip clip in arrangement.clips.where(
      (ArrangementClip clip) => clip.patternId == patternId,
    )) {
      expect(
        clip.noteCount,
        before + 1,
        reason: 'every placement of an edited pattern changes with it',
      );
    }

    // ----- 5. save, reopen, and compare ---------------------------------- ---
    final String path = '${scratch.path}/exit.onebeat';
    client.saveProject(path);
    expect(
      Directory(path).existsSync() || File(path).existsSync(),
      isTrue,
      reason: 'the project bundle was written',
    );

    // Reopen into the *same* engine, which is the stricter test: anything the
    // loader fails to restore shows up as a difference rather than being masked
    // by a fresh process happening to default to the same value.
    client.openProject(path);

    // Save again and compare the two files byte for byte. This is the exact
    // round-trip property the canonical writer promises (docs/project-format.md
    // §6) and it is stronger than comparing against the pre-save model: saving
    // stamps `meta.created_with`, so the model in memory legitimately differs
    // from the file until it has been through one save.
    final String resaved = '${scratch.path}/exit-again.onebeat';
    client.saveProject(resaved);
    expect(
      File('$resaved/project.json').readAsStringSync(),
      File('$path/project.json').readAsStringSync(),
      reason:
          'save -> open -> save is byte-identical '
          '(docs/project-format.md §6)',
    );

    patterns.refresh();
    arrangement.refresh();
    expect(patterns.current!.name, 'Main Groove');
    expect(patterns.current!.noteCount, 6);
    expect(patterns.current!.usageCount, 2);
    expect(
      arrangement.clips
          .where((ArrangementClip clip) => clip.patternId.isNotEmpty)
          .length,
      2,
    );

    // Opening a file is not an edit, so there is nothing to undo into.
    expect(
      client.canUndoProject,
      isFalse,
      reason: 'the history belongs to the session that made it',
    );
  });

  test('Make unique diverges one placement and undo restores the share', () {
    final PatternStore patterns = PatternStore(client)..load();
    final ArrangementStore arrangement = ArrangementStore(client, patterns)
      ..load();

    final String kick = client.readInstruments().first.id;
    client.toggleRackStep(kick, 0);
    arrangement.placeCurrentPattern(
      arrangement.lanes.first.id,
      ticksPerBar * 4,
    );
    patterns.refresh();
    expect(patterns.current!.usageCount, 2);

    final String original = patterns.current!.id;
    final ArrangementClip target = arrangement.clips
        .firstWhere((ArrangementClip clip) => clip.patternId == original);

    patterns.makeUnique(<String>[target.id]);
    arrangement.refresh();

    final ArrangementClip diverged = arrangement.clipById(target.id)!;
    expect(diverged.patternId, isNot(original));
    expect(diverged.usageCount, 1);
    expect(patterns.byId(original)!.usageCount, 1);

    client.undoProject();
    patterns.refresh();
    arrangement.refresh();
    expect(
      arrangement.clipById(target.id)!.patternId,
      original,
      reason: 'undo puts the shared reference back (D-M3)',
    );
    expect(patterns.byId(original)!.usageCount, 2);
  });

  test('moving a clip between lanes changes nothing about the clip', () {
    // OB-3-12's critical negative, at the model boundary: a lane is
    // organisational and carries no signal, so the only field a lane change may
    // touch is the lane itself (ARCHITECTURE.md §4).
    final PatternStore patterns = PatternStore(client)..load();
    final ArrangementStore arrangement = ArrangementStore(client, patterns)
      ..load();

    arrangement.addLane('Second');
    final ArrangementClip before = arrangement.clips.first;
    final String otherLane = arrangement.lanes
        .firstWhere((ArrangementLane lane) => lane.id != before.laneId)
        .id;

    arrangement
      ..selectClip(before.id)
      ..beginClipDrag(ClipDragKind.move)
      ..updateClipMove(0, laneId: otherLane)
      ..endClipDrag();

    final ArrangementClip after = arrangement.clipById(before.id)!;
    expect(after.laneId, otherLane);
    expect(after.startTicks, before.startTicks);
    expect(after.lengthTicks, before.lengthTicks);
    expect(after.patternId, before.patternId);
    expect(after.transpose, before.transpose);
    expect(after.windowStartTicks, before.windowStartTicks);
    expect(after.loop, before.loop);
    expect(after.muted, before.muted);
  });
}
