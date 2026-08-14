// The widget-test harness for the editor screens.
//
// Wires the fake seam to real stores and real widgets, so a test drives the
// same code the app does — the only substitution is the engine itself.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onebeat/src/core/action_registry.dart';
import 'package:onebeat/src/core/pattern_store.dart';
import 'package:onebeat/src/design/tokens.dart';
import 'package:onebeat/src/features/piano_roll/piano_roll_binding.dart';
import 'package:onebeat/src/features/piano_roll/piano_roll_store.dart'
    hide ticksPerBar, ticksPerQuarter, GridChoice;
import 'package:onebeat/src/features/playlist/playlist_binding.dart';
import 'package:onebeat/src/features/playlist/playlist_store.dart';

import 'fake_engine_client.dart';

/// Wraps a widget in the minimum real app chrome: the token theme and a
/// directionality. Deliberately not `MaterialApp` — the app has no Material in
/// it, and a test that added some would be testing a different widget tree.
Widget wrapForTest(Widget child, {Size size = const Size(1200, 800)}) {
  return Directionality(
    textDirection: TextDirection.ltr,
    child: OneBeatTheme(
      tokens: OneBeatTokens.dark(),
      child: MediaQuery(
        data: MediaQueryData(size: size),
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: size.width,
            height: size.height,
            // The shell sits on the deep surface, so the harness does too —
            // otherwise a golden's unpainted regions read as white and hide
            // whether the widget actually covers its own bounds.
            child: ColoredBox(
              color: OneBeatTokens.dark().color.surfaceDeep,
              // The real app's `WidgetsApp` provides the root `Overlay` that
              // dropdown menus and popovers render into; mirror it here so a
              // binding test can open one without a missing-overlay assert.
              child: Overlay(
                initialEntries: <OverlayEntry>[
                  OverlayEntry(builder: (BuildContext context) => child),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// Loads the app's two real font families into the test binding.
Future<void> loadAppFonts() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  const Map<String, String> families = <String, String>{
    'Archivo': '../third_party/fonts/archivo/Archivo[wdth,wght].ttf',
    'MartianMono':
        '../third_party/fonts/martian_mono/MartianMono[wdth,wght].ttf',
  };
  for (final MapEntry<String, String> family in families.entries) {
    final FontLoader loader = FontLoader(family.key)
      ..addFont(
        File(family.value).readAsBytes().then(ByteData.sublistView),
      );
    await loader.load();
  }
}

/// Pumps [child] in the app chrome at a window of [size].
Future<void> pumpForTest(
  WidgetTester tester,
  Widget child, {
  Size size = const Size(1200, 800),
}) async {
  final double ratio = tester.view.devicePixelRatio;
  tester.view.physicalSize = Size(size.width * ratio, size.height * ratio);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(wrapForTest(child, size: size));
}

class EditorHarness {
  EditorHarness() {
    patterns = PatternStore(client)..load();
    pianoRoll = PianoRollStore(client, patterns);
    arrangement = ArrangementStore(client, patterns)..load();
  }

  final FakeEngineClient client = FakeEngineClient();
  late final PatternStore patterns;
  late final PianoRollStore pianoRoll;
  late final ArrangementStore arrangement;

  /// A run of `count` sixteenths on one instrument, walking up a scale.
  void seedNotes(String instrumentId, {int count = 4}) {
    for (int index = 0; index < count; index++) {
      client.addNote(
        instrumentId,
        index * (ticksPerQuarter ~/ 4),
        ticksPerQuarter ~/ 4,
        60 + index,
        velocity: 9000,
      );
    }
    pianoRoll.load(instrumentId);
    patterns.refresh();
  }

  /// Two lanes and two clips, both referencing the one pattern — the fixture
  /// the usage count, instance highlighting and Make unique tests need.
  void seedArrangement() {
    client
      ..createLane('Drums')
      ..addClip('lane_a', startTicks: 0, lengthTicks: 3840)
      ..addClip('lane_a', startTicks: 3840, lengthTicks: 3840);
    arrangement.refresh();
    patterns.refresh();
  }

  Widget buildPianoRoll() => PianoRollBinding(client: client);

  Widget buildArrangement() => PlaylistBinding(client: client);
}

/// Key used to locate a control associated with a specific action ID in tests.
Key actionKey(String actionId) => ValueKey<String>('action:$actionId');

/// Asserts that all actions in [area] have visible controls with corresponding keys.
void expectAreaReachable(ActionArea area) {
  for (final UiAction action in ActionRegistry.forArea(area)) {
    if (action.id.isEmpty) continue;
    expect(
      find.byKey(actionKey(action.id)),
      findsAtLeastNWidgets(1),
      reason: 'Action ${action.id} in area ${area.label} must be reachable',
    );
  }
}
