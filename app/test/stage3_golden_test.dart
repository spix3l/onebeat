// Per-theme goldens for the token-critical Stage 3 surfaces (OB-3-14 §1).
//
// The point of a golden here is not "the pixels are correct" — it is that a
// change to a token, a painter or a layout shows up as a reviewable image
// rather than as nothing at all. The playhead is stationary in these fixtures
// so the images are deterministic.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onebeat/src/ui/arrangement.dart';
import 'package:onebeat/src/ui/piano_roll.dart';
import 'package:onebeat/src/ui/piano_roll_store.dart';

import 'support/stage3_harness.dart';

void main() {
  // Real fonts: block glyphs measure nothing like Archivo or MartianMono.
  setUpAll(loadAppFonts);

  testWidgets('piano roll surface matches the dark token system', (
    WidgetTester tester,
  ) async {
    final Stage3Harness harness = Stage3Harness();
    // A phrase with varied velocity and length: velocity shades the note fill,
    // so a flat fixture would not catch a change to that ramp.
    const List<List<int>> phrase = <List<int>>[
      <int>[0, 480, 60, 14000],
      <int>[480, 240, 63, 9000],
      <int>[720, 240, 67, 5000],
      <int>[960, 960, 70, 16000],
      <int>[1920, 480, 65, 11000],
      <int>[2400, 240, 62, 7000],
      <int>[2880, 960, 58, 12000],
    ];
    for (final List<int> note in phrase) {
      harness.client.addNote(
        'inst_a',
        note[0],
        note[1],
        note[2],
        velocity: note[3],
      );
    }
    harness.pianoRoll
      ..load('inst_a')
      ..setScale(MusicalScale.all[2], 0)
      ..panTo(0, 74);
    harness.pianoRoll.selectOnly(harness.pianoRoll.notes[3]);

    await pumpForTest(
      tester,
      harness.buildPianoRoll(),
      size: const Size(900, 560),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(PianoRollSurface),
      matchesGoldenFile('goldens/piano_roll_dark.png'),
    );
  });

  testWidgets('arrangement surface matches the dark token system', (
    WidgetTester tester,
  ) async {
    final Stage3Harness harness = Stage3Harness()..seedArrangement();
    // One transposed, windowed, non-looping clip and one plain one: the clip
    // face draws a transpose badge and a hold-off marker, and both are things
    // a token or painter change can quietly break.
    final String first = harness.arrangement.clips.first.id;
    harness.arrangement
      ..setClipTranspose(first, 3)
      ..setClipWindowStart(first, 480)
      ..selectClip(first);
    for (int index = 0; index < 6; index++) {
      harness.client.addNote('inst_a', index * 480, 240, 60 + index);
    }
    harness.arrangement.refresh();

    await pumpForTest(
      tester,
      harness.buildArrangement(),
      size: const Size(1200, 460),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(ArrangementSurface),
      matchesGoldenFile('goldens/arrangement_dark.png'),
    );
  });
}
