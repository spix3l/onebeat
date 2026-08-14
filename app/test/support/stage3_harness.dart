// The widget-test harness for the Stage 3 editors (OB-3-14 §1).
//
// Wires the fake seam to real stores and real widgets, so a test drives the
// same code the app does — the only substitution is the engine itself.
import 'package:flutter/widgets.dart';
import 'package:onebeat/src/design/tokens.dart';
import 'package:onebeat/src/ui/arrangement.dart';
import 'package:onebeat/src/ui/chrome.dart';
import 'package:onebeat/src/ui/engine_controller.dart' show WorkspaceView;
import 'package:onebeat/src/ui/arrangement_store.dart';
import 'package:onebeat/src/ui/pattern_store.dart';
import 'package:onebeat/src/ui/piano_roll.dart';
import 'package:onebeat/src/ui/piano_roll_store.dart';

import 'fake_stage3_client.dart';

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
              child: child,
            ),
          ),
        ),
      ),
    ),
  );
}

class Stage3Harness {
  Stage3Harness() {
    patterns = PatternStore(client)..load();
    pianoRoll = PianoRollStore(client, patterns);
    arrangement = ArrangementStore(client, patterns)..load();
  }

  final FakeStage3Client client = FakeStage3Client();
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

  Widget buildPianoRoll() => _PianoRollHost(harness: this);

  Widget buildArrangement() => _ArrangementHost(harness: this);
}

/// The editors take an `EngineController` only for the snapshot and the
/// transport. Tests that do not need either get these thin hosts, which supply
/// a stationary playhead — a moving one would make goldens flaky.
class _PianoRollHost extends StatelessWidget {
  const _PianoRollHost({required this.harness});

  final Stage3Harness harness;

  @override
  Widget build(BuildContext context) => PianoRollSurface(
    store: harness.pianoRoll,
    patterns: harness.patterns,
    positionTicks: 0,
  );
}

class _ArrangementHost extends StatelessWidget {
  const _ArrangementHost({required this.harness});

  final Stage3Harness harness;

  @override
  Widget build(BuildContext context) => ArrangementSurface(
    store: harness.arrangement,
    patterns: harness.patterns,
    positionTicks: 0,
    onOpenPattern: (_, _) {},
  );
}


/// The shell's chrome, assembled from the *same* widgets the shell uses.
///
/// Deliberately not a copy of the top bar: a reachability test that checked a
/// lookalike would keep passing while the real chrome lost a control. What it
/// leaves out is only the parts that need a live engine — the meter and the
/// clock — because neither carries an action.
class ShellChromeForTest extends StatelessWidget {
  const ShellChromeForTest({
    required this.patterns,
    required this.activeView,
    super.key,
  });

  final PatternStore patterns;
  final WorkspaceView activeView;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        DestinationRail(
          destinations: const <RailDestination>[
            RailDestination(
              actionId: 'view.playlist',
              glyph: '▤',
              label: 'Playlist',
              view: WorkspaceView.arrangement,
            ),
            RailDestination(
              actionId: 'view.channels',
              glyph: '▥',
              label: 'Channels',
              view: WorkspaceView.rack,
            ),
            RailDestination(
              actionId: 'view.pianoRoll',
              glyph: '♪',
              label: 'Piano',
              view: WorkspaceView.pianoRoll,
            ),
          ],
          activeView: activeView,
          onSelectView: (_) {},
        ),
        TransportCluster(
          playing: false,
          canUndo: true,
          canRedo: true,
          onTogglePlay: () {},
          onUndo: () {},
          onRedo: () {},
          onReturnToZero: () {},
        ),
        SearchAffordance(onTap: () {}),
      ],
    );
  }
}
